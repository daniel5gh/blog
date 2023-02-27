---
layout: post
title:  "Reviving the Blog"
date:   2023-02-26 00:00:00
categories: blog
tags: git gitlab github ci/cd nginx zfs podman docker
---

## Introduction

High time to revive the blog!

I didn't have the source in git, and there was only a manual "deployment" in place. As
the first post after the revival, I'll document the improvement process. This post will
cover:

 * Moving of GitLab instance
 * Automatic mirroring from GitLab to GitHub
 * CI/CD pipeline on GitLab to build and create a release for the blog

## Moving and removing public access from my GitLab instance 

I have locked down my self-hosted GitLab instance from the public, because I am not comfortable
staying on top of each and every security issue and I have gotten some abuse mails
in the past because some people scanning the internet for vulnerable instances thought my instance
had issues. There have been some serious security issues, [some](https://www.rapid7.com/blog/post/2021/11/01/gitlab-unauthenticated-remote-code-execution-cve-2021-22205-exploited-in-the-wild/)
[of](https://about.gitlab.com/blog/2022/04/07/updates-regarding-spring-rce-vulnerabilities/)
[them](https://duckduckgo.com/?q=gitlab+CVE+RCE&ia=web) allowing RCE and GitLab has
become quite popular so people are actively hunting for vulnerable instances.

The Omnibus docker container I was running had a volume bind mount. To move the instance, all I
did was stopping the container on the source machine. I was then using `rsync` transferring
everything over to the target machine, both the contents of the persistent volumes and the
`docker-compose.yml`.

On the target machine I had decided to run `podman` instead of `docker`, and while not
strictly needed, I did rename the docker compose file to `compose.yml`. After updating
the `volumes` section to match the new situation, I was all done:

```yaml
version: '2'

services:
  gitlab:
    #image: gitlab/gitlab-ce:11.11.0-ce.0
    #image: gitlab/gitlab-ce:12.10.14-ce.0
    #image: gitlab/gitlab-ce:13.0.0-ce.0
    #image: gitlab/gitlab-ce:13.3.2-ce.0
    #image: gitlab/gitlab-ce:13.9.4-ce.0
    #image: gitlab/gitlab-ce:13.9.6-ce.0
    #image: gitlab/gitlab-ce:13.12.15-ce.0
    #image: gitlab/gitlab-ce:14.0.12-ce.0
    #image: gitlab/gitlab-ce:14.1.8-ce.0
    #image: gitlab/gitlab-ce:14.5.2-ce.0
    #image: gitlab/gitlab-ce:14.7.3-ce.0
    #image: gitlab/gitlab-ce:14.8.2-ce.0
    #image: docker.io/gitlab/gitlab-ce:14.9.0-ce.0
    #image: docker.io/gitlab/gitlab-ce:14.9.5-ce.0
    #image: docker.io/gitlab/gitlab-ce:14.10.5-ce.0
    #image: docker.io/gitlab/gitlab-ce:15.0.3-ce.0
    #image: docker.io/gitlab/gitlab-ce:15.3.3-ce.0
    #image: docker.io/gitlab/gitlab-ce:15.3.5-ce.0
    #image: docker.io/gitlab/gitlab-ce:15.4.0-ce.0
    #image: docker.io/gitlab/gitlab-ce:15.7.1-ce.0
    #image: docker.io/gitlab/gitlab-ce:15.7.2-ce.0
    image: docker.io/gitlab/gitlab-ce:15.8.3-ce.0
    #image: gitlab/gitlab-ce:14.10.2-ce.0
    hostname: git.example.com
    domainname: example.com
    container_name: gitlab
    ports:
      - "8222:22"
      - "8700:80"
    volumes:
      - /var/lib/pv/gitlab/data:/var/opt/gitlab
      - /var/lib/pv/gitlab/logs:/var/log/gitlab
      - /var/lib/pv/gitlab/config/ssh_host_ecdsa_key:/etc/gitlab/ssh_host_ecdsa_key:ro
      - /var/lib/pv/gitlab/config/ssh_host_ecdsa_key.pub:/etc/gitlab/ssh_host_ecdsa_key.pub:ro
      - /var/lib/pv/gitlab/config/ssh_host_ed25519_key:/etc/gitlab/ssh_host_ed25519_key:ro
      - /var/lib/pv/gitlab/config/ssh_host_ed25519_key.pub:/etc/gitlab/ssh_host_ed25519_key.pub:ro
      - /var/lib/pv/gitlab/config/ssh_host_rsa_key:/etc/gitlab/ssh_host_rsa_key:ro
      - /var/lib/pv/gitlab/config/ssh_host_rsa_key.pub:/etc/gitlab/ssh_host_rsa_key.pub:ro
      - /var/lib/pv/gitlab/config/gitlab-secrets.json:/etc/gitlab/gitlab-secrets.json
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://git.example.com'
        nginx['listen_port'] = 80
        nginx['listen_https'] = false
        nginx['real_ip_trusted_addresses'] = [ '10.0.0.0/8' ]
        nginx['real_ip_header'] = 'X-Forwarded-For'
        nginx['real_ip_recursive'] = 'on'
        gitlab_rails['gitlab_ssh_host'] = 'git.example.com'
        gitlab_rails['gitlab_email_from'] = 'gitlab@example.com'
        gitlab_rails['gitlab_shell_ssh_port'] = 8222
        gitlab_rails['smtp_enable'] = true
        gitlab_rails['smtp_address'] = "exim"
        gitlab_rails['smtp_port'] = 25
        user['git_user_email'] = "gitlab@example.com"
        sidekiq['concurrency'] = 1
        prometheus['enable'] = true
        prometheus['monitor_kubernetes'] = false
        grafana['enable'] = true
        grafana['gitlab_application_id'] = 'redacted'
        grafana['gitlab_secret'] = 'redacted'
    restart: always
    depends_on:
      - exim
    shm_size: '256m'
    # leaving out the exim service
```

I like to keep track of which versions I have been running and I think this is a good place to do that.

I changed from using a copy of `gitlab.rb` in favor of `GITLAB_OMNIBUS_CONFIG` environment because
configuring through environment variables is much more flexible. One mistake I made which did take me
a while to figure out was that I had an equals sign in `external_url = 'https://git.example.com'` and
that caused gitlab to not configure itself properly behind the HTTPS reverse proxy. I didn't notice
any errors and that `external_url` line appeared to be ignored. Gitlab was able to figure out the hostname
I would guess using `X-Forwarded` or `Host` headers, but it thought it was on `http`.

Symptoms were that the clone url on repo pages used `http://`, gitlab runners failing to pull properly
and the releases API thoroughly confusing `release-cli`. All that even though there is an HTTP redirect
returned, but I remember there
was [something with PUT and POST while redirects are in play](https://softwareengineering.stackexchange.com/questions/99894/why-doesnt-http-have-post-redirect)
.
Wish I had saved the specific error messages, because I did find some people having the same issues,
but nobody had posted a cause or solution.

For a few days I did workaround some issues by explicitly specifying the *Custom Git clone URL for HTTP(S)*
in the global admin settings. I knew this was not a proper fix, but I was stuck. While this did let me
get past the gitlab runner's pulling issue, the `release-cli` was not using the same environment
vars that are used for cloning.

The mounted volumes are all on a ZFS dataset which I created with:

```bash
zfs create rpool/var/lib/pv/gitlab
```

Finally, the way I locked down this instance from the public is by only allowing specific IPs on the 
NGINX reverse proxy:

```nginx
server {
    listen 443 http2 ssl;
    listen [::]:443 http2 ssl;
    server_name git.example.com;

    include /etc/nginx/conf.d/ssl_params;
    include /etc/nginx/conf.d/common_locations;

    # Default is HTTP/1, keepalive is only enabled in HTTP/1.1
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    chunked_transfer_encoding off;

    client_max_body_size 0;
    
    proxy_buffering off;
    proxy_request_buffering off;

    location / {
        # location 1
        allow x.x.x.x;
        # location 2
        allow x.x.x.x;
        # public ips of the box running the GitLab Instance
        allow x:x:x:x::1;
        allow x.x.x.x;
        # internal, podman network is in this range
        allow 10.0.0.0/8;

        deny all;

        proxy_pass http://localhost:8700;
        proxy_set_header Host              $host;
        proxy_set_header X-Real-IP         $remote_addr;
        proxy_set_header X-Forwarded-By    $server_addr:$server_port;
        proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-SSL   on;

        proxy_connect_timeout 300;
    }
}
```

## Automatic mirroring from GitLab to GitHub

After finding the source to the Jekyll blog, I created a new repo on my GitLab instance. 

Since I locked down this GitLab instance from the public, I decided I want to mirror some
public repos to GitHub to still have them be available.

This was easy to set up. I followed [the instructions](https://docs.gitlab.com/ee/user/project/repository/mirror/push.html#set-up-a-push-mirror-from-gitlab-to-github)
from the GitLab docs.

Firstly I created target repo on GitHub and a **Personal Access Token** on the [developer settings](https://github.com/settings/tokens?type=beta)
section. I chose to the new *fine-grained* option. The options I selected are:

* **Only select repositories** and I selected the newly created `daniel5gh/blog` repo and I will add others to this as
  needed
* **Read and Write Contents**
* **Read Only Metadata** (selected by default and mandatory)

Selected a lifetime, generated the token and stored it in a secure location. 

Then on GitLab I set up push mirroring. Under **Mirroring Repositories** in the project's repository settings
filled out the URL field. It was important to include the username, because without it GitLab will try
to push anonymously. I used `https://daniel5gh@github.com/daniel5gh/blog.git`, mirror direction `push` and
entered the *Personal Access Token* as password.

Not selecting *Keep divergent refs* because I will not have any divergent refs on the target.

Behold the mirrored repo for this blog: [https://github.com/daniel5gh/blog](https://github.com/daniel5gh/blog)

## CI/CD pipeline on GitLab to build and create a release for the blog

I'll go over the CI/CD setup section by section:

```yaml
image: docker.io/ruby:3.1
```

Jekyll is a ruby project, so we select this image as the main image for the jobs. The
`docker.io` usually is omitted, but I have configured `podman` to not have any `unqualified-search-registries`
(in `/etc/containers/registries.conf`) so I need to be specific. It was required
to add `allowed_images = ["docker.io/*:*", "registry.gitlab.com/gitlab-org/*:*"]` to the
gitlab running config files.

```yaml
variables:
  JEKYLL_ENV: production
  LC_ALL: C.UTF-8

setvars:
  stage: .pre
  script:
    - |
      if [[ -n $CI_COMMIT_TAG ]]; then
        echo "VERSION=$CI_COMMIT_TAG" >> version.env
      else
        echo "VERSION=$CI_COMMIT_REF_SLUG-$CI_COMMIT_SHORT_SHA" >> version.env
      fi
      source version.env
      echo "TARBAL_FILENAME=blog-$VERSION.tar.bz2" >> version.env
    - cat version.env
  artifacts:
    reports:
      dotenv: version.env
```

Here I set up global env variables in the first stage, which are then available
in all subsequents stages and jobs. The `dotenv` report artifact is responsible for
loading these variables in those jobs.

When the length of string `CI_COMMIT_TAG` is non-zero, it means this pipeline runs
after a git tag has been created. In this case I want the `VERSION` to be that tag name.
A git ref can have multiple tags, I don't know what the contents of `CI_COMMIT_TAG` is
in that case, maybe space separated tags. I'm willing to take this risk and I will be
sure to quote any usage of `VERSION`.

In all other cases the `VERSION` will consist of the git ref slug and short sha, for
example: `master-d381768f`. Because it specifically says slug in the gitlab predefined
variable, I am assuming no spaces can be in there.

Lastly I want to define a tarball filename here, so I can use it in both the build and
release jobs. Because it uses the `VERSION`, which is chosen conditionally,
we'll have to source it into the env first.

`cat version.env` is just there for verbosity.

```yaml
build:
  stage: build
  script:
    - gem install bundler
    - bundle install
    - bundle exec jekyll build -d blog
    - tar cjvf "$TARBAL_FILENAME" ./blog
    - echo "DOWNLOAD_LINK=$CI_JOB_URL/artifacts/raw/$TARBAL_FILENAME?inline=false" >> download.env
    - cat download.env
  artifacts:
    paths:
      - "*.bz2"
    reports:
      dotenv: download.env
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_COMMIT_TAG
```

There are two things happening in the build job, building and packaging of the Jekyll site, and
secondly we are adding another environment var for the job artifact's download link. 

The build and `tar.bz2` creation is straightforward. The tarball gets uploaded as an artifact to
the build job. This build job's ID is encoded in `CI_JOB_URL` and it is specific for this 
exact build job. The next job which is for release will have another ID.

Because the release job has another ID we have to store the `DOWNLOAD_LINK` in this job. I chose
for the raw link, because I want to easily download the latest release with `curl` when deploying.
Without the raw part in the URL, we'd be presented the artifact download or preview page.

Lastly the `rules` are to run this job only if a commit is made to the default branch or when a
tag has been created, or both.

```yaml
release_job:
  stage: deploy
  image: registry.gitlab.com/gitlab-org/release-cli:latest
  rules:
    - if: $CI_COMMIT_TAG                 # Run this job when a tag is created
  script:
    - echo "running release_job"
  release:                               # See https://docs.gitlab.com/ee/ci/yaml/#release for available properties
    tag_name: $CI_COMMIT_TAG
    name: 'Release $CI_COMMIT_TAG'
    description: 'Release created for version $VERSION.'
    assets:
      links:
        - name: '$TARBAL_FILENAME'
          url: '$DOWNLOAD_LINK'
```

The release job uses the `release-cli` command line tool. I followed the instructions on the
GitLab [documentation](https://docs.gitlab.com/ee/user/project/releases/release_cicd_examples.html)
on how to use the `release` and the only thing that was missing there was how to get the link to an artifact
built in a prior job of this pipeline. I chose to store the link to the download in an environment
variable at `DOWNLOAD_LINK` and this seems to work out fine.

I did wonder how `release-cli` knows where to connect to and what defaults to use, but apparently
this is just picking it up from the predefined `CI_` environment variables.

## Conclusion

Finally, another blog post after a short 8-year break. I figured to make it a bit meta by
having the topic on the blog itself and how I revived it. One part is missing, which is how I am
deploying the automatically built tarballs. This is not automatic yet, and I will have to think
about how I want to do that. It'll be a topic in another post. I don't yet know if I want to push
it from my CI/CD pipeline, because then I'll need to have some credentials on there. Pulling it
from a cron job on the target box could also work, but is a bit lame I think.

Other ideas for topics include some research and maybe implementation of a commenting system. I
want the blog te remain a static HTML site, so that'll be interesting. And I am also working
again on a tower defense game, this time using [Bevy Engine](https://bevyengine.org) in rust
and I want to share my learnings on Entity Component Systems which I think are super cool. For
The game I'll also be using AI art generation and maybe ChatGPT to help me with some story elements!
