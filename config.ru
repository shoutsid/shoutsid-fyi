# frozen_string_literal: true

# Rack entrypoint. `rackup` (or `puma -c config/puma.rb`) loads this file,
# which is the only place that decides what the server runs.
require_relative "app"

run ShoutsidFyi::App
