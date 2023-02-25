export JEKYLL_VERSION=4
docker run --rm \
  --volume="$PWD:/srv/jekyll:Z" \
  -it jekyll/builder:$JEKYLL_VERSION \
  jekyll build
