#!/usr/bin/env ruby
# frozen_string_literal: true

# Container healthcheck.
#
# A file rather than a one-liner in the Dockerfile: this is the check that
# decides whether the tunnel's `depends_on: service_healthy` gate lets traffic
# through, so it should be readable and testable rather than an escaped string
# inside a JSON array.
#
# It asks the app's own `/healthz`, which reads the same content store the
# pages read — so a container that has lost its content is reported unhealthy
# instead of quietly serving empty cards.

require "net/http"

port = ENV.fetch("PORT", "3000")
uri = URI("http://127.0.0.1:#{port}/healthz")

begin
  response = Net::HTTP.start(
    uri.host,
    uri.port,
    open_timeout: 3,
    read_timeout: 3
  ) { |http| http.get(uri.path) }

  exit(response.is_a?(Net::HTTPSuccess) ? 0 : 1)
rescue StandardError => e
  warn("healthcheck: #{e.class}: #{e.message}")
  exit 1
end
