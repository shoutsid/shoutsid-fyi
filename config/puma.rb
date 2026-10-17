# frozen_string_literal: true

# Puma configuration. Read by `bundle exec puma -C config/puma.rb` (the
# container's CMD) and by `bin/site dev`.
#
# This is a small, read-mostly site: content is parsed once and cached, so the
# work per request is template rendering. Threads therefore buy more than
# processes here, and cluster mode would multiply the content cache for no
# gain — hence one process by default.
#
# NOTE (necessary): `port` already binds 0.0.0.0, so an explicit
# `bind "tcp://0.0.0.0:3000"` alongside it is a *second* listener on the same
# socket, and Puma dies at startup with EADDRINUSE. The suite cannot see this
# because rack-test never binds a socket; it only shows up when the container
# actually runs.

port ENV.fetch("PORT", 3000).to_i

environment ENV.fetch("RACK_ENV", "production")

threads_count = Integer(ENV.fetch("PUMA_THREADS", 5))
threads threads_count, threads_count

workers Integer(ENV.fetch("WEB_CONCURRENCY", 0))
preload_app! if ENV.fetch("WEB_CONCURRENCY", "0").to_i.positive?

# A worker stuck for a minute is not going to answer; recycling it is cheaper
# than a healthcheck that flaps.
worker_timeout 60 if respond_to?(:worker_timeout)

# No pidfile and no log files: the container is the unit of lifecycle, logs go
# to stdout for the json-file driver, and the root filesystem is read-only
# (see docker-compose.yml) so there is nowhere to write one anyway.
