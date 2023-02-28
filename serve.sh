export JEKYLL_VERSION=4
docker run --rm \
  --volume="$PWD:/srv/jekyll:Z" \
  --publish 4000:4000 \
  jekyll/jekyll:$JEKYLL_VERSION \
  jekyll serve --drafts
