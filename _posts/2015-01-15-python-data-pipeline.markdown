---
layout: post
title:  "Data pipelines with python generators"
date:   2015-01-15 00:00:00
categories: python generator
---

## Introduction

When you need to process a large amount of data, chaining [python generators][1]
is a nice way to set up processing pipelines. Advantage of this method are
that you have fine-grained control over memory usage, and it provides an
easy way of defining the pipelines.

At the end of this post we can define pipelines as follows:

{% highlight python %}
pijp = [
    open_file_node(mode='rt', encoding='utf8'),
    parse_csv_node,
    make_upper_node,
    print_line_node,
]
{% endhighlight %}

## The codes

Let's walk through the different parts of the code. It is assumed you are
familiar with [python generators][1].

We start with importing `csv` and `itertools`. The `itertools` module is
not used in the example code included in this post, but it provides some
very nice utilities. 

{% highlight python %}
import csv
import itertools

__author__ = 'daniel'
{% endhighlight %}

### A basic processing node

I chose to call each of the processing steps a Node. We start with
implementing a No Operation node to demonstrate the simplest node.

The generator iterates over the input data and yields each item 
unmodified.

{% highlight python %}
def null_node(data):
    """Does nothing, a null operation.

    :param data: Any iterable
    :type data: iterable
    :return: the input
    :rtype: generator
    """
    for datum in data:
        yield datum
{% endhighlight %}

Running this:

{% highlight python %}
In [3]: null_node(range(10))
Out[3]: <generator object null_node at 0x1227d20>

In [4]: list(_)
Out[4]: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
{% endhighlight %}

Debug printing is usually very annoying an inefficient, but we all do it
from time to time right? In any case it makes a nice example for a
processing node that as [side-effect][2] has an output to `stdout`.

{% highlight python %}
def debug_node(data):
    """Print input and output. Yield unmodified.

    :param data:
    :return:
    """
    for datum in data:
        print("{0} yielded {1}".format(data, datum))
        yield datum
{% endhighlight %}

Running this:

{% highlight python %}
In [10]: list(debug_node(range(10)))
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 0
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 1
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 2
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 3
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 4
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 5
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 6
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 7
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 8
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9] yielded 9
Out[10]: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9]

{% endhighlight %}

### A node to split an iterable into chunks

When inserting data into a database it is efficient to do this multiple
rows at a time. Let's make a node that makes chunks of size 3. Larger
chunks are more realistic, but for demonstration purpose we use a small
size. 

{% highlight python %}
def chunk_gen(data):
    data = iter(data)  # so we can pass in any iterator or sequence and `next()` it
    chunk = []
    try:
        while True:
            for i in range(3):
                chunk.append(next(data))
            yield chunk
            chunk.clear()
    except StopIteration:
        if chunk:
            yield chunk
{% endhighlight %}

{% highlight python %}
In [19]: list(chunk_gen(range(10)))
Out[19]: [[0, 1, 2], [3, 4, 5], [6, 7, 8], [9]]
{% endhighlight %}

### Static config values on a node

How cool would it be if we can configure these nodes at pipeline definition
time? We would need some place to store this information. Maybe a class could 
work, passing configuration values to the constructor and a method for the
actual generator. I haven't tried this, another option is to take advantage
of [closures][3]:

{% highlight python %}
def make_chunks_node(size=100):
    """Chunks the data stream.

    With size of 2: (1,2,3,4,5) -> ((1,2),(3,4),(5))
    Example of a node that reduces data.

    Useful for database inserts.
    :param size: Chunk size
    :return:
    :rtype: generator
    """

    # we love closures, use it to store size

    def chunk_gen(data):
        data = iter(data)
        chunk = []
        try:
            while True:
                for i in range(size):
                    chunk.append(next(data))
                yield chunk
                chunk.clear()
        except StopIteration:
            if chunk:
                yield chunk

    return chunk_gen
{% endhighlight %}

This allows us to make the following construction, we pass the config
value to the method that returns the actual generator:
    
{% highlight python %}
In [35]: gen = make_chunks_node(2)

In [36]: list(gen(range(10)))
Out[36]: [[0, 1], [2, 3], [4, 5], [6, 7], [8, 9]]
{% endhighlight %}

### More nodes

Other examples of nodes are:

 * `open_file_node`, takes an iterable of filenames and yields file-like objects
 * `parse_csv_node`, takes an iterable of text lines and yields data rows
 * `make_upper_node`, takes an iterable of iterables and yields lists for each
   inner iterable with their items uppercased
 * `print_line_node`, same as debug node without printing the source

{% highlight python %}
def open_file_node(mode='r', encoding=None):
    """Opens given file names given on input and yields file like objects
    """

    def gen_open_file_node(file_names):
        for fn in file_names:
            with open(fn, mode=mode, encoding=encoding) as fo:
                yield fo
    return gen_open_file_node


def parse_csv_node(csv_data):
    """Parse CSV rows from input data

    :param csv_data: file like object containing CSV
    :return: CSV rows as lists
    :rtype: generator
    """
    for csv_datum in csv_data:
        reader = csv.reader(csv_datum)
        for row in reader:
            yield row


def make_upper_node(rows):
    """Example of a 1 to 1 processing node

    :param rows:
    :return:
    """
    for row in rows:
        yield [x.upper() for x in row]
        # yield (x.upper() for x in row)


def print_line_node(lines):
    """Print the input and yield unmodified

    :param lines:
    :return:
    :rtype: generator
    """
    for line in lines:
        print(line)
        yield line
{% endhighlight %}

## Chaining generators

Now we have some nodes, we need to have a way to chain them all together.
The following method does that by accepting a list of nodes and a source
iterable. The source is passed to the first generator in the nodes list. The 
generator returned by the first node is then passed as an argument to the next
node and so on until there are no more nodes in the list. Finally, the generator
returned by the last node is returned. Iterating this last generator sets the
whole pipeline in motion.

{% highlight python %}
def make_pipe(source, nodes):
    """Chain all nodes and return the last

    Make a combined generator where the source is passed to
    the first generator in nodes. The generator returned by it
    is then passed on the the next node, etc.

    :param source:
    :param nodes:
    :return: combined, chained generator
    :rtype: generator
    """
    gen = source
    for node in nodes:
        gen = node(gen)
    return gen
{% endhighlight %}

## Defining pipelines

Putting it all together we get something like this:

{% highlight python %}
if __name__ == '__main__':
    # define pipeline
    pijp = [
        make_chunks_node(10),
        print_line_node,
    ]
    # make a pipe generator
    pipe = make_pipe(range(100), pijp)
    # consume all
    list(pipe)

    pijp = [
        debug_node,
        open_file_node(mode='rt', encoding='utf8'),
        debug_node,
        parse_csv_node,
        debug_node,
        make_upper_node,
        debug_node,
        print_line_node,
    ]

    list(make_pipe(['test1.csv', 'test2.csv'], pijp))
{% endhighlight %}

{% highlight python %}
[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]
[10, 11, 12, 13, 14, 15, 16, 17, 18, 19]
[20, 21, 22, 23, 24, 25, 26, 27, 28, 29]
[30, 31, 32, 33, 34, 35, 36, 37, 38, 39]
[40, 41, 42, 43, 44, 45, 46, 47, 48, 49]
[50, 51, 52, 53, 54, 55, 56, 57, 58, 59]
[60, 61, 62, 63, 64, 65, 66, 67, 68, 69]
[70, 71, 72, 73, 74, 75, 76, 77, 78, 79]
[80, 81, 82, 83, 84, 85, 86, 87, 88, 89]
[90, 91, 92, 93, 94, 95, 96, 97, 98, 99]
['test1.csv', 'test2.csv'] yielded test1.csv
<generator object gen_open_file_node at 0x0000000003CF8F30> yielded <_io.TextIOWrapper name='test1.csv' mode='rt' encoding='utf8'>
<generator object parse_csv_node at 0x0000000003D29240> yielded ['HEADER1', 'HEADER2']
<generator object make_upper_node at 0x0000000003D29F30> yielded ['HEADER1', 'HEADER2']
['HEADER1', 'HEADER2']
<generator object parse_csv_node at 0x0000000003D29240> yielded ['data11', 'data 92']
<generator object make_upper_node at 0x0000000003D29F30> yielded ['DATA11', 'DATA 92']
['DATA11', 'DATA 92']
...
['test1.csv', 'test2.csv'] yielded test2.csv
<generator object gen_open_file_node at 0x0000000003CF8F30> yielded <_io.TextIOWrapper name='test2.csv' mode='rt' encoding='utf8'>
<generator object parse_csv_node at 0x0000000003D29240> yielded ['HEADER3', 'HEADER4']
<generator object make_upper_node at 0x0000000003D29F30> yielded ['HEADER3', 'HEADER4']
['HEADER3', 'HEADER4']
...
{% endhighlight %}

## Conclusion and Future

I like the result of this experiment. Although I didn't take care of any
exception handling nor did I try to use for something serious I think this
can work. One thing I am not sure about is something like progress reporting.
If each node knows beforehand how many items it will be processing, they can 
know their own percentage, but how to communicate that. A callable that is 
passed in with the source iterable perhaps...

Nodes can also be used to partition data, like `make_chunk_node`, and fire
off tasks to be processed in parallel. After jobs become ready, the result
can be yielded.

Probably more cool stuff possible!

Check out the [GitHub][daniel-gh]s for codes.

[daniel-gh]:   https://github.com/daniel5gh/
[1]: https://wiki.python.org/moin/Generators
[2]: http://en.wikipedia.org/wiki/Side_effect_(computer_science)
[3]: http://en.wikipedia.org/wiki/Closure_(computer_programming)
