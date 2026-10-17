# frozen_string_literal: true

require "rack/utils"
require_relative "content"

module ShoutsidFyi
  # The site's `Cache-Control` policy, applied to every response.
  #
  # This is middleware rather than a `before` filter for one reason, and it is
  # not a preference: Sinatra serves a static file *before* its before-filters
  # run (`dispatch!` calls `static!` first, and the served file halts). A filter
  # therefore sets a header on every page and on none of the assets — the exact
  # wrong half, and invisibly so, because both answer 200 either way. That is how
  # this site shipped with no `Cache-Control` on its CSS at all while Cloudflare
  # supplied four hours of its own. Middleware wraps the app, so it sees the
  # static responses too. (`X-Content-Type-Options` reaches the assets by the
  # same route, from Rack::Protection.)
  #
  # The rule follows from how the URL is built. `asset_path` puts the file's own
  # digest in the query string, so a revision is a new URL and every hop may keep
  # it for a year. Everything else under `public/` is served at a URL that does
  # not identify its content, so it gets an hour. Generated responses revalidate:
  # a portfolio that gets corrected is one whose corrections should be visible.
  class CachePolicy
    YEAR = 31_536_000
    HOUR = 3600

    # The two directories `asset_path` is called for.
    VERSIONED_ASSET = %r{\A/(?:css|js)/[\w.-]+\z}
    STATIC_DIRECTORY = %r{\A/(?:css|js|screenshots|diagrams)/}
    STATIC_ROOT_FILES = %w[/favicon.svg /og.png /robots.txt /llms.txt].freeze

    def initialize(app)
      @app = app
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers["cache-control"] ||= policy_for(env)

      [status, headers, body]
    end

    private

    def policy_for(env)
      path = env["PATH_INFO"].to_s

      if VERSIONED_ASSET.match?(path)
        versioned?(env, path) ? "public, immutable, max-age=#{YEAR}" : "public, no-cache"
      elsif STATIC_DIRECTORY.match?(path) || STATIC_ROOT_FILES.include?(path)
        "public, max-age=#{HOUR}"
      else
        "public, no-cache"
      end
    end

    # A year and `immutable` only when the URL carries the digest of the bytes
    # about to be served. Sinatra's static server ignores the query string, so
    # `/css/site.css?v=old` answers with today's file — and a year of
    # immutability for a URL that does not identify its content is the one thing
    # this header must never promise. A stale or absent digest revalidates
    # instead, which is correct for it and cheap for us.
    def versioned?(env, path)
      name = path.delete_prefix("/")
      return false unless File.file?(File.join(Content::ROOT, "public", name))

      Rack::Utils.parse_query(env["QUERY_STRING"].to_s)["v"] == Content.asset_digest(name)
    end
  end
end
