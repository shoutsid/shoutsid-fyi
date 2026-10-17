# syntax=docker/dockerfile:1

# The base image is pinned by digest, not by tag. `ruby:3.3-slim` is a moving
# target — a rebuild in six months would silently pick up a different build of
# Ruby — and for an app whose whole job is to render the same pages, a rebuild
# that changes the runtime is a variable with no upside. The tag is kept in the
# reference only so a human reading the file knows what the digest is meant to
# be. Bump it deliberately: `docker buildx imagetools inspect ruby:3.3-slim`.
ARG RUBY_IMAGE=ruby:3.3-slim@sha256:47b93492bc6afc708dc4f2478c7f1867725c64b3bf43b94ea1bad2dac0314f02

# ---------------------------------------------------------------- base
FROM ${RUBY_IMAGE} AS base
ENV LANG=C.UTF-8 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    BUNDLE_RETRY=3 \
    BUNDLE_DISABLE_SHARED_GEMS=true
WORKDIR /app

# ---------------------------------------------------------------- lock
# Resolves Gemfile into a Gemfile.lock and nothing else. `bin/site lock` builds
# this target and copies the file out, which is how the lockfile gets generated
# without a bind mount (bind mounts need Docker Desktop's file sharing, builds
# do not).
FROM base AS lock
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*
COPY Gemfile ./
RUN bundle lock --update

# ---------------------------------------------------------------- dev
# Everything the suite needs to run, and deliberately no source. `bin/site
# check|test|lint|shell` mount the working tree over /app, so the code under
# test is read from disk at run time.
#
# Baking the source in was the old arrangement, and it had a cost with no
# upside: any edit to any file invalidated the layer, so the tree and the image
# could disagree, and every edit paid for a rebuild to keep them from doing so.
# With no source in the image there is nothing for an edit to invalidate and
# nothing for the image to fall out of step with — and a run whose mount did
# not take effect finds an empty /app and stops, instead of passing against a
# tree that no longer exists.
#
# Gems are the expensive part of this image and they change only when the
# Gemfile does, so it is also the only thing a rebuild now has to redo.
FROM base AS dev
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git curl \
    && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle install
ENV RACK_ENV=development
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

# -------------------------------------------------------------- build
# Production gems only. C sources and object files are removed after install:
# they are build inputs, not runtime ones, and puma is the only extension here.
FROM base AS build
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential git \
    && rm -rf /var/lib/apt/lists/*
COPY Gemfile Gemfile.lock ./
RUN bundle config set --local without "development:test" \
    && bundle install \
    && rm -rf /usr/local/bundle/cache \
    && find /usr/local/bundle -name "*.c" -type f -delete \
    && find /usr/local/bundle -name "*.o" -type f -delete

# -------------------------------------------------------------- runtime
# From the same pinned digest as `base`, but with nothing installed in it: the
# compiler that built puma's extension is not in this layer.
FROM ${RUBY_IMAGE} AS runtime

ENV LANG=C.UTF-8 \
    RACK_ENV=production \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test \
    BUNDLE_FROZEN=true \
    PORT=3000

WORKDIR /app

# A system user with no shell and no home directory of its own. The container
# has no reason to be root: the app binds 3000, reads its own files and writes
# nothing.
RUN groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid app --home-dir /app --shell /usr/sbin/nologin app

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=app:app . .

USER app

EXPOSE 3000

# The healthcheck lives in the image rather than in docker-compose.yml so it
# cannot drift away from the image it is meant to describe: anything running
# this image gets the same check, including a bare `docker run`.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD ["ruby", "bin/healthcheck.rb"]

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
