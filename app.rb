# frozen_string_literal: true

require "sinatra/base"
require "json"
require_relative "lib/cache_policy"
require_relative "lib/content"
require_relative "lib/markdown"

# The portfolio site served at https://shoutsid.fyi.
#
# The app is deliberately thin: it reads structured content (see lib/content.rb)
# and renders it. There is no database, no session and no write path, so the
# whole surface is a handful of GET routes over data committed to the
# repository. That is what makes it safe to run read-only and unprivileged in a
# container behind a tunnel.
module ShoutsidFyi
  class App < Sinatra::Base
    # One source of truth for the version, and it is the deployment's: `.env`
    # carries APP_VERSION and reaches the container through `env_file`, so the
    # number `bin/site version` prints and the number /healthz reports cannot
    # disagree. They did — the constant here was 0.1.0 while .env said whatever
    # it said, and nothing read the file's copy at all.
    VERSION = ENV.fetch("APP_VERSION", "0.1.0")

    # Number of seconds the process has been up, without a global.
    BOOTED_AT = Time.now.to_i

    # The badge a project's status renders as. Declared at class level rather
    # than inside `helpers do ... end`: a constant assignment inside a block is
    # a dynamic-constant-assignment SyntaxError, and this is the kind of thing
    # that only shows up when the file is first loaded.
    STATUS_LABELS = {
      "live" => "Live",
      "public" => "Public repo",
      "research" => "Research",
      "in-progress" => "In progress"
    }.freeze

    # The caveat shown under a badge, and in a tooltip on a card. One place, so
    # a research card cannot be labelled as though it shipped.
    STATUS_HINTS = {
      "live" => "Deployed and publicly reachable.",
      "public" => "Source available on GitHub.",
      "research" => "Experimental, ongoing investigation — not a demonstrated result.",
      "in-progress" => "Work in progress; no demo published yet."
    }.freeze

    configure do
      set :root, File.expand_path(__dir__)
      set :views, File.join(root, "views")
      set :public_folder, File.join(root, "public")
      set :environment, ENV.fetch("RACK_ENV", "production").to_sym

      # Escaping is on (Erubi's option is `escape`, not `escape_html` — Tilt
      # passes template options straight through to Erubi::Engine). So `<%= %>`
      # is safe by default and anything that is already markup has to say so
      # with `<%== %>`. The layout and the two partials it renders are the only
      # places that do; see the note above `yield` in views/layout.erb.
      #
      # This setting is only meaningful because `erubi` is a direct dependency
      # in the Gemfile: without it Tilt falls back to stdlib ERB, which ignores
      # the option and does not support `<%==` at all.
      set :erb, escape: true

      # A broken template or content file should be a 500 and a log line, not
      # a stack trace rendered into the page. Errors are raised in development
      # (below) so that a failure is impossible to miss.
      set :show_exceptions, false
      set :raise_errors, false
      set :dump_errors, true

      # The suite and the container start both refuse to run on content that
      # does not satisfy lib/content.rb's invariants. Failing at boot is the
      # point: a missing tagline should stop a deploy, not blank a card.
      Content.validate! unless environment == :test
    end

    configure :development do
      set :show_exceptions, true
      set :raise_errors, true
    end

    # ------------------------------------------------------------ middleware

    # The cache policy is middleware, not a filter: Sinatra serves a static file
    # before its before-filters run, so a filter would set no header on the very
    # responses the policy is for. See lib/cache_policy.rb.
    use CachePolicy

    before do
      headers(
        "Content-Security-Policy" =>
          "default-src 'self'; base-uri 'none'; form-action 'none'; " \
          "frame-ancestors 'none'; object-src 'none'; img-src 'self' data:; " \
          "style-src 'self'; script-src 'self'; font-src 'self'; " \
          "connect-src 'self'",
        "X-Content-Type-Options" => "nosniff",
        "X-Frame-Options" => "DENY",
        "Referrer-Policy" => "strict-origin-when-cross-origin",
        "Permissions-Policy" => "geolocation=(), microphone=(), camera=(), interest-cohort=()"
      )
    end

    # ---------------------------------------------------------------- routes

    get "/" do
      # The same grouping `/work` renders, and the same order inside it, so the
      # two pages cannot disagree about which projects are prominent. They did,
      # and the reviewer noticed: the homepage led with Rails while `/work` put
      # four other projects ahead of it.
      #
      # Research sits in its own section rather than beside a deployed service
      # on purpose: a card in the first grid reads as a shipped product, and the
      # ACT hypothesis has not been demonstrated.
      @main = Content.projects_in_section("main")
      @systems = Content.projects_in_section("systems")
      @others = Content.projects_in_section("archive")
      @posts = Content.posts.first(2)
      @roles = Content.experience.first(2)
      @title = nil
      @description = Content.profile["summary"]
      erb :index
    end

    get "/about" do
      @title = "About"
      @description = Content.profile["summary"]
      @roles = Content.experience
      @education = Content.education
      @skills = Content.skills
      erb :about
    end

    get "/work" do
      @title = "Work"
      @description = Content.pages.dig("work", "description")
      @main = Content.projects_in_section("main")
      @systems = Content.projects_in_section("systems")
      @archive = Content.projects_in_section("archive")
      erb :work
    end

    get "/work/:slug" do
      @project = Content.project(params["slug"])
      halt 404 unless @project
      @title = @project["title"]
      @description = @project["summary"]
      erb :project
    end

    get "/blog" do
      @title = "Blog"
      @description = Content.pages.dig("blog", "description")
      @posts = Content.posts
      erb :blog
    end

    # Declared before `/blog/:slug` on purpose: Sinatra matches routes in
    # declaration order, so a `:slug` route registered first would swallow
    # `feed.xml` and serve a 404 for the feed.
    get "/blog/feed.xml" do
      content_type "application/atom+xml; charset=utf-8"
      @posts = Content.posts.first(20)
      erb :feed, layout: false
    end

    get "/blog/:slug" do
      @post = Content.post(params["slug"])
      halt 404 unless @post
      @title = @post.title
      @description = @post.summary
      erb :post
    end

    get "/contact" do
      @title = "Contact"
      @description = Content.pages.dig("contact", "description")
      erb :contact
    end

    # A CV generated from the same content store as every other page, so it
    # cannot disagree with the site. Print it from the browser to save a PDF.
    get "/cv" do
      @title = "CV"
      @description = Content.pages.dig("cv", "description")
      @roles = Content.experience
      @education = Content.education
      @skills = Content.skills
      @selected = Content.projects.select { |p| p["status"] == "live" || (p["featured"] && p["status"] == "public") }
      erb :cv
    end

    # The container healthcheck's target. Kept truthful — it reports the same
    # content store the pages read, so a container that cannot read its own
    # content is reported unhealthy rather than serving empty cards.
    get "/healthz" do
      content_type :json
      JSON.generate(
        status: "ok",
        service: "shoutsid-fyi",
        version: VERSION,
        uptime_seconds: Time.now.to_i - BOOTED_AT,
        projects: Content.projects.length,
        posts: Content.posts.length
      )
    end

    get "/sitemap.xml" do
      content_type "application/xml"
      @urls = ["/", "/about", "/work", "/blog", "/contact", "/cv"] +
        Content.projects.map { |p| "/work/#{p["slug"]}" } +
        Content.posts.map(&:url)
      erb :sitemap, layout: false
    end

    # --------------------------------------------------------------- errors

    not_found do
      @title = "Not found"
      @description = "That page does not exist."
      erb :"errors/404"
    end

    error do
      @title = "Something went wrong"
      @description = "An unexpected error occurred."
      status 500
      erb :"errors/500"
    end

    # -------------------------------------------------------------- helpers

    helpers do
      def profile = Content.profile

      def site_url = profile.dig("site", "url") || "https://shoutsid.fyi"

      def nav_items
        [
          {label: "Home", path: "/"},
          {label: "About", path: "/about"},
          {label: "Work", path: "/work"},
          {label: "Blog", path: "/blog"},
          {label: "Contact", path: "/contact"},
          {label: "CV", path: "/cv"}
        ]
      end

      def profile_links = Array(profile["links"])

      # `mailto:` should not open a new tab and does not want `noopener`; an
      # external http(s) link should. One predicate, used by every link
      # rendering, so the two do not drift apart per template.
      def external_link?(url) = url.to_s.match?(%r{\Ahttps?://})

      def current_path = @request_path ||= request.path_info

      # `/work/act` should light up the "Work" nav item, which means matching on
      # the first segment rather than on equality.
      def nav_active?(path)
        return current_path == "/" if path == "/"
        current_path == path || current_path.start_with?("#{path}/")
      end

      def page_title
        return profile["site"]["title"] if @title.nil?
        "#{@title} — #{profile["name"]}"
      end

      def page_description
        @description || profile["summary"]
      end

      def canonical_url
        "#{site_url}#{current_path}"
      end

      # Rendered as a badge on every project card. The label a status shows is
      # decided in exactly one place so a "Research" project cannot be labelled
      # "Live" on a page that reuses the card.
      def status_label(status) = STATUS_LABELS.fetch(status, status)

      def status_hint(status) = STATUS_HINTS.fetch(status, "")

      # Versioned same-origin asset URL. The query string is part of the cache
      # key at the CDN, so a changed file is a new URL and a stale edge copy can
      # never shadow it — and it is what lets lib/cache_policy.rb answer with a
      # year of immutability, because the file's own digest is the key. Sinatra's
      # static server ignores the query, so the unversioned path keeps working
      # (the suite relies on that for /css/site.css and friends); that path is
      # served revalidating rather than immutable, for the same reason.
      def asset_path(name) = "/#{name}?v=#{Content.asset_digest(name)}"

      # Page copy, read from config/pages.yml. A template renders these
      # sentences; it does not carry any of its own — see that file for why.
      def page_copy(section, key) = Content.pages.dig(section, key).to_s

      # The optional {label, path} rendered beside a page's copy.
      def page_link(section, key) = Content.pages.dig(section, key) || {}

      def markdown(source) = Markdown.render(source)

      def format_tags(tags) = Array(tags).join(", ")

      # Card copy is a paragraph in the content file and a one- or two-line
      # teaser in the grid. Trimming on a word boundary keeps a card from
      # ending mid-word, which reads as a bug rather than as an excerpt.
      def excerpt(text, limit: 180)
        flat = text.to_s.gsub(/\s+/, " ").strip
        return flat if flat.length <= limit

        trimmed = flat[0, limit].sub(/\s+\S*\z/, "")
        "#{trimmed}…"
      end
    end

    def self.production? = environment == :production
  end
end
