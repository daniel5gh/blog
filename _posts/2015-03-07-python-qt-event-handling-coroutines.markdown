---
layout: single
title:  "Python Qt and Coroutines"
date:   2015-03-07 00:00:00
categories: coding
tags: python generator qt
---

## Introduction

When running tasks asynchronously often you find yourself in a web of callback
handlers. This blog entry tries to explore the idea of using python generators
as coroutines to solve this using python 2.7.

### An example of the problem we want to solve

```python
def handle_click(self):
    # done callback
    def done(result):
        # notify the parent thread we have  a result
        # emit a qt signal with a QueuedConnection so we can
        # handle the result in the GUI thread
        pass

    # Do some async work like a web request or a file load.
    self.start_async_work(on_done=done)
```

This code is hard to read, hard to write and hard to maintain. Testing this
is not very trivial. This example also has no exception handling whatsoever.

This looks like a mess already and I even left out all the plumbing needed to have
a slot on the GUI thread to handle the result.

### Wouldn't this be cool?

```python
@coroutine
def handle_click(self):
    task1 = AsyncTask(self.worker, 66)
    try:
        val1 = yield task1
        # add result to a text box, or some other operation that
        # needs to be done on the GUI thread. In this example we
        # just print
        print("task1 returned: {0}".format(val1))
    except ASyncException as e:
        print("Async task failed with {0}".format(repr(e)))
```

(hint: yes)

We can give an `ASyncTask` a callable, `*args` and `**kwargs`. When constructing
a new task it will fire off a `QThread` that runs this callable immediately in the
background and returns quickly.

Then we use `yield` to suspend this coroutine and to pass the now running task
to the coroutine decorator code. This decorator is responsible for registering
a callback on the task and to send results from the task back to us in the
coroutine. We need the results to be sent in on the GUI thread as well. And to
make matters really interesing it may not block the GUI thread.

If we can manage this we get very natural sequential looking code that is easy to
ready, write and maintain, and all this while it's not blocking the GUI thread.

## What's out there already

I have seen the presentations of [David Beazley][1] which really inspired me to
pursue this solution. Here I've seen some usage of python 3's `Future` and got
a peek at python 3's `asyncio`.

This ActiveState [recipe][2] provides a very neat way of communicating with
a parent thread using a custom [QEvent][3] and `QtGui.QApplication.postEvent`
to post it back to the parent on the GUI thread.
We will be using its `CallbackEvent` class to get callbacks from async tasks
back on our GUI thread.

A [Stackoverflow][4] post that offers a very similar solution to what I had in
mind. I used it as a basis and improved it with a lot of comments and corner
case handling like exceptions in worker thread propagation to coroutine among
various other additions.

I am also inspired by C# [async and await][5] keywords.

## The ASyncTask class

Simplified version of the `ASyncTask`. Refer to the code for the complete thing.

```python
class AsyncTask(QtCore.QObject):
    def __init__(self, func, *args, **kwargs):
        # ...
        self.finished_callback = None
        self._worker_thread = RunThreadCallback(
            self, self.func, self.on_finished, *self.args, **self.kwargs)
        self._worker_thread.start()

    def customEvent(self, event):
        # ... checking event type
        event.callback()

    def on_finished(self, result):
        # ... called from GUI thread
        func = partial(self.finished_callback, result)
        QTimer.singleShot(0, func)
        self._worker_thread.quit()
        self._worker_thread.wait()
```

At this point it is important to understand that we can provide this class with
a function and arguments which it will run on our behalf in a `QThread`. When the
`QThread` is done the `finished_callback` we gave it will be run on the GUI thread.

The `RunThreadCallback` is a `QThread` that uses `CallbackEvent` from the ActiveState
[recipe][2] to have the callback run on the GUI thread. This alone is great already, but we
can do more, buckle up!

## Coroutine Decorator a.k.a. The Magic

This decorator can only be used on functions that use the `yield AsyncTask` pattern.

The `execute` function defined in the decorator will get `AsyncTask` objects
from the decorated generator function and register `execute` itself again to be
called when the task is complete. It will also explicitly call
the finished handler if the task is already complete when it's yielded.

### Gory details

```python
def coroutine(func):
    def wrapper(*args, **kwargs):
        def execute(gen, input_=None):
            if isinstance(gen, types.GeneratorType):
```

Let's go over this `execute` function. This function can be a bit tricky to wrap
your head around. Notice that it has an optional `input_`
argument. This argument changes the behavior drastically.

When no input is given, we will make the coroutine advance to the first yield
and receive an `AsyncTask` from it.

```python
                # no input given
if not input_:
    # the co routine yields an AsyncTask
    task = next(gen)
```

On the other hand when `input_` is given the input holds
the result of our `ASyncTask` (more on how this works this
in a sec, get ready for a blown mind). This result can either
be an `Exception` type or the actual result from the task.
In the case of an exception we rethrow it as an `ASyncException`
in the decorated generator, where it will be raised
on the yield statement. In the other case when we do get a
successful result we send it into the decorated generator
which then continues execution. This will result in either
a `StopIteration` or a new yielded `ASyncTask`.

```python
                # input_ given
else:
try:
    if isinstance(input_, Exception):
        task = gen.throw(ASyncException, input_)
    else:
        task = gen.send(input_)
except StopIteration as e:
    return
```

Recap, no `input_` given advances to the first yield and `input_` given
sends (or throws) results into the decorated generator, making it
continue after the yield giving us the next yielded task or
a `StopIteration`.

In either case (when we got input or not) the decorated generator
has yielded an `ASyncTask`. This task is given a `finished_callback` that
consists of, and this is where minds get blown if they weren't
already, a partial function that is made up of ourselves (`execute`)
and the decorated generator as first argument. When it's called by the
task the second argument will be the tasks result.

```python
                # In either case we get a task from the coroutine
if isinstance(task, AsyncTask):
    # the partial `func(*a, **kw)` calls `execute(gen, *a, **kw)`
    partial_func = partial(execute, gen)
    task.finished_callback = partial_func
    if task.finished and not task.finished_cb_ran:
        # explicitly call if the task is already finished
        task.on_finished(task.result)
else:
    raise Exception("Using yield is only supported with AsyncTasks.")
            else:
                # obviously, this must not happen
                raise Exception("Head Asplode.")
```

Pause for a minute and think about this.

Realize that this `finished_callback` has our generator and that the `execute` function
returns quickly after setting the callback resuming Qt's normal event loop.

So what happens when the task calls the `finished_callback`? It
calls the partial with the tasks result. This is equivalent to:
`execute(gen, the_tasks_result`), this is important to realize to be
able to understand why we can yield multiple times.

If you go to the full code and look for where the `finished_callback` is called from.
You can see it is called
from the `on_finished` callback of the custom callback event on the
`ASyncTask`. This means that we (the `execute` function) get called on the
GUI thread by Qt's event dispatching! This time with the optional `input_` argument and of
course the generator. This happens to be exactly what we need to continue the coroutine where it
got suspended on the yield. Because we have the `input_` argument, this `execute` call will now
send or throw the result. Both send and throw on a generator
returns the next yielded task. And this new task eventually makes Qt call us (the `execute` function) with
`input_` again and so the chain continues until a `StopIteration` is thrown,
i.e. no more tasks are yielded from the coroutine.

How is that for some flow control bending!? (did I mention minds as well?)

Lastly we have this piece of decorator code that is actually called when the decorated function is called.
For example as a result of a button click.

```python
        #
# when Qt calls this wrapper function, `func` holds
# the decorated function. When called it returns our
# coroutine as a generator, and it doesn't execute anything yet.
generator = func(*args, **kwargs)
# Then execute is called without input_ argument so the coroutine
# will advance to the first yield and it also registers `execute`
# itself as a callback on task, so we get called *again*, but this
# time with an input_ argument (the task result).
execute(generator)
    return wrapper
```

To recap (again, to try to wrap heads around this), we get called without
`input_` once as a result of a call to the decorated generator. For
example as a connected slot on a clicked signal of a button.

We get called with `input_` by Qt via the `CallbackEvent` after the task
is done running. The beauty of this is ofcourse that this allows us to
continue the coroutine on the GUI thread!

*NB*
When the decorated generator continues it can either yield
another task or return in which case it raises `StopIteration`. Be careful
when you fire up multiple tasks before yielding them, in this case you have
to make sure to wrap each yield in their own try except block.


## Conclusion and Future

Chaining coroutines is not trivial without python 3's `yield from`. It can probably be
done, but I will have to think about it some more. I'm not sure if it will be worth the effort.

The way I propagate the `Exceptions` is not good enough, we loose all stacktrace information.
This needs to be improved before I consider using this code. Without it, it is near to
impossible to debug any unexpected exceptions.

Another question I have not answered here is how to write unit test for both the
coroutine framework itself and also the decorated coroutines.

Check out the [GitHub][daniel-gh]s for codes.

[daniel-gh]:   https://github.com/daniel5gh/
[1]: http://www.dabeaz.com/
[2]: http://code.activestate.com/recipes/578634-pyqt-pyside-thread-safe-callbacks-main-loop-integr/
[3]: http://doc.qt.io/qt-5/qevent.html
[4]: http://stackoverflow.com/questions/24689800/async-like-pattern-in-pyqt-or-cleaner-background-call-pattern
[5]: https://msdn.microsoft.com/en-us/library/hh156528.aspx
