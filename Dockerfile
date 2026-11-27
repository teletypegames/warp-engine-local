# syntax=docker/dockerfile:1.7
# The local WarpEngine: one container, one port, SQLite and the files in /data.
#
#   docker build -t warp-engine-local .
#
# Against an engine checkout instead of the released gem:
#   docker build --build-context engine=../warp_engine --build-arg WARP_ENGINE_PATH=/warp_engine -t warp-engine-local .
FROM scratch AS engine

FROM ruby:3.4-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  build-essential git libyaml-dev pkg-config curl \
  && rm -rf /var/lib/apt/lists/*

ARG WARP_ENGINE_VERSION="~> 6.0"
ARG WARP_ENGINE_PATH=""
ENV RAILS_ENV=production \
    WARP_DATA=/data \
    PORT=7470 \
    WARP_ENGINE_VERSION=${WARP_ENGINE_VERSION} \
    WARP_ENGINE_PATH=${WARP_ENGINE_PATH}

COPY --from=engine . /warp_engine/

WORKDIR /app
COPY host_app/Gemfile ./
RUN bundle install --jobs 4 && rm -rf /usr/local/bundle/cache

COPY host_app/ ./
RUN WARP_DATA=/tmp/build-data WARP_ADMIN=1 bin/rails assets:precompile && rm -rf /tmp/build-data tmp/cache

VOLUME /data
EXPOSE 7470
ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
