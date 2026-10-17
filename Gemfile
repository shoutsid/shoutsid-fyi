# frozen_string_literal: true

source "https://rubygems.org"

# Pinned to the version baked into the runtime image (see Dockerfile). A
# mismatch between Gemfile and image is a confusing boot failure rather than
# a clear one, so the constraint is stated here and nowhere else.
ruby "3.3.12"

# The web framework. Sinatra 4 is Rack 3 only, which is why `rackup` and
# `puma` are explicit rather than pulled in transitively.
gem "sinatra", "~> 4.1"

# The application server. Puma is what the container's CMD runs.
gem "puma", "~> 6.5"

# `rackup` supplies the Rack 3 config-file loader that `config.ru` needs when
# Sinatra is used as a library (Sinatra::Base) rather than in classic mode.
gem "rackup", "~> 2.2"

# Markdown for the blog. Kramdown is pure Ruby, so the runtime
# image needs no compiler toolchain — a native extension here would mean
# shipping build-essential in the final layer.
gem "kramdown", "~> 2.5"

# Kramdown's GFM parser is a separate gem. Without it, `input: "GFM"` in
# lib/markdown.rb raises "kramdown has no parser to handle the specified input
# format" the first time a post is rendered — a 500 on every post page, not a
# silent fallback.
gem "kramdown-parser-gfm", "~> 1.1"

# Required explicitly, not pulled in transitively. Sinatra depends on Tilt,
# and Tilt only registers its Erubi template when `erubi` can be loaded —
# otherwise it falls back to stdlib ERB, which *silently* changes two things:
# `set :erb, escape: true` stops escaping anything, and `<%== %>` becomes a
# compile error instead of raw output. Both were live bugs in this app until
# the fallback was tracked down, so the dependency is stated here rather than
# left to chance.
gem "erubi", "~> 1.13"

group :development, :test do
  gem "rspec", "~> 3.13"
  # Drives the app through Rack without binding a socket, so the suite never
  # depends on a port being free.
  gem "rack-test", "~> 2.2"
  # The one linter. Standard has no configuration file on purpose: a style
  # argument is not worth a diff, and an unconfigurable linter cannot drift.
  gem "standard", "~> 1.4"
end
