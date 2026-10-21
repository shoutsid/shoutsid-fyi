# frozen_string_literal: true

require "cgi"

RSpec.describe ShoutsidFyi::App do
  describe "GET /" do
    before { get "/" }

    it "is a success" do
      expect(last_response.status).to eq(200)
    end

    it "names the engineer it is about" do
      expect(last_response.body).to include("James Summerill")
    end

    it "shows the status badge for a live project and a research one" do
      expect(last_response.body).to include("badge-live")
      expect(last_response.body).to include("badge-research")
    end

    it "separates research from shipped work" do
      expect(last_response.body).to include("Experimental")
    end

    # The grid leads with the Rails work. The roles being applied for are Rails
    # roles, and that entry is the one showing an established background applied
    # to architecture rather than described in the abstract — Webcap is the
    # stronger product, but it is not the pitch. A reorder of
    # config/projects.yml moved this once already, which is why the position is
    # pinned here rather than left to a comment asking politely.
    it "leads the work grid with the Rails work and then Webcap" do
      grid = last_response.body[/Selected work.*?Engineering experience/m]

      expect(grid).not_to be_nil, "expected a Selected work section"
      expect(grid.scan(%r{<h3 class="card-title">\s*<a href="/work/([a-z0-9-]+)"}m).flatten)
        .to start_with("rails-modular-monolith", "webcap")
    end

    it "renders the grid from the same section `/work` leads with" do
      grid = last_response.body[/Selected work.*?Engineering experience/m]

      expect(grid.scan(%r{<h3 class="card-title">\s*<a href="/work/([a-z0-9-]+)"}m).flatten)
        .to eq(ShoutsidFyi::Content.projects_in_section("main").map { |p| p["slug"] })
    end

    # The pitch used to appear only in the closing call to action, six sections
    # below the projects. For a reader deciding whether to keep reading, that
    # is the wrong end of the page.
    # Sharing this site on LinkedIn rendered a bare link, because there was no
    # image. It is the one place the site is seen by people who have not chosen
    # to visit it.
    it "carries a social preview image rather than a bare link" do
      expect(last_response.body).to include(%(property="og:image" content="https://shoutsid.fyi/og.png"))
      expect(last_response.body).to include(%(property="og:image:width" content="1200"))
      expect(last_response.body).to include(%(property="og:image:height" content="630"))
      expect(last_response.body).to include(%(property="og:image:alt"))
      expect(last_response.body).to include(%(name="twitter:card" content="summary_large_image"))
    end

    it "states what he is looking for in the hero" do
      hero = last_response.body[%r{<p class="hero-seeking">.*?</p>}m]

      expect(hero).not_to be_nil, "expected a hero-seeking block on the homepage"

      seeking = ShoutsidFyi::Content.profile["seeking"].to_s.gsub(/\s+/, " ").strip
      expect(hero.gsub(/\s+/, " ")).to include(seeking[0, 60])
    end
  end

  describe "GET /about" do
    before { get "/about" }

    it "is a success" do
      expect(last_response.status).to eq(200)
    end

    it "lists the most recent role and the earliest one" do
      expect(last_response.body).to include("City Electrical Factors")
      expect(last_response.body).to include("Green Gorilla Apps")
    end

    it "renders the toolkit groups" do
      expect(last_response.body).to include("Languages &amp; frameworks")
    end

    # Four overlapping entries explained by a one-line note became one entry
    # labelled by phase. The phases are the point of the merge, so they are what
    # this pins rather than the presence of the company name.
    it "presents the City Electrical Factors work as one entry, typed by phase" do
      body = last_response.body

      # Counted by the markup that renders a company rather than by the name:
      # the section note names the employer too, so a plain string count measures
      # the note instead of the number of entries.
      expect(body.scan(%(class="role-company">City Electrical Factors)).length).to eq(1)
      expect(body).to include("October 2019 — October 2024 (contract, then full time)")
      expect(body.scan(/Phase \d/).length).to eq(3)
      # Two contracts and one full-time phase. Measured on the rendered page so
      # the engagement type cannot be lost in a reword of the YAML.
      expect(body.scan("(contract)").length).to eq(2)
      expect(body).to include("(full time)")
    end

    it "links that entry to the write-up rather than leaving it as bullets" do
      expect(last_response.body)
        .to include(%(href="/blog/upgrading-a-production-rails-application"))
    end

    it "links the career break to the work section instead of listing projects" do
      expect(last_response.body).to include(%(href="/work">Selected independent work))
    end
  end

  describe "GET /work" do
    it "lists every project" do
      get "/work"

      expect(last_response.status).to eq(200)
      ShoutsidFyi::Content.projects.each do |project|
        expect(last_response.body).to include(project["title"])
      end
    end

    # This page and the homepage grid read the same field, so a reader cannot be
    # told one thing here and another there. They used to differ: the homepage
    # led with Rails and this page put four other projects ahead of it.
    it "leads with the same projects the homepage does, in the same order" do
      get "/work"

      first_grid = last_response.body.split("Research and Experimental Systems").first

      expect(first_grid.scan(%r{<h3 class="card-title">\s*<a href="/work/([a-z0-9-]+)"}m).flatten)
        .to eq(ShoutsidFyi::Content.projects_in_section("main").map { |p| p["slug"] })
    end

    it "puts the systems work and research in their own labelled section, after the work" do
      get "/work"

      body = last_response.body
      expect(body).to include("Research and Experimental Systems")
      # Bounded at both ends, because the archive grid renders after this one
      # and would otherwise be counted as part of it.
      systems = body.split("Research and Experimental Systems").last.split("More projects").first

      expect(systems.scan(%r{<h3 class="card-title">\s*<a href="/work/([a-z0-9-]+)"}m).flatten)
        .to eq(ShoutsidFyi::Content.projects_in_section("systems").map { |p| p["slug"] })
    end
  end

  describe "GET /work/:slug" do
    it "serves a page for every project in the content" do
      ShoutsidFyi::Content.projects.each do |project|
        get "/work/#{project["slug"]}"

        expect(last_response.status).to eq(200), "expected /work/#{project["slug"]} to be 200"
        expect(last_response.body).to include(project["title"])
      end
    end

    it "links a project's write-ups by the post's own title and URL" do
      get "/work/rails-modular-monolith"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("The outbox is a table, not a library")
      expect(last_response.body).to include(%(href="/blog/the-outbox-is-a-table-not-a-library"))
    end

    it "states the caveat on the research project rather than presenting it as shipped" do
      get "/work/act"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("not a demonstrated result")
      expect(last_response.body).not_to include("badge-live")
    end

    it "is a 404 for a slug that does not exist" do
      get "/work/definitely-not-a-project"

      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /blog" do
    before { get "/blog" }

    it "is a success" do
      expect(last_response.status).to eq(200)
    end

    it "lists every published post" do
      ShoutsidFyi::Content.posts.each do |post|
        expect(last_response.body).to include(post.title)
      end
    end

    it "heads the page Posts, not Notes" do
      expect(last_response.body).to include("<h1>Posts</h1>")
      expect(last_response.body).not_to match(%r{>\s*Notes\s*<})
    end

    it "is reachable at /blog and not at the old /writing path" do
      # The section was renamed; nothing should still be served from the old
      # route, or the rename is only half done.
      get "/writing"

      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /blog/:slug" do
    it "serves a page for every post" do
      ShoutsidFyi::Content.posts.each do |post|
        get post.url

        expect(last_response.status).to eq(200), "expected #{post.url} to be 200"
        expect(last_response.body).to include(post.title)
      end
    end

    it "renders the markdown body as HTML" do
      post = ShoutsidFyi::Content.posts.first
      get post.url

      expect(last_response.body).to include("<h2")
    end

    it "is a 404 for a post that does not exist" do
      get "/blog/not-a-post"

      expect(last_response.status).to eq(404)
    end
  end

  describe "GET /blog/feed.xml" do
    before { get "/blog/feed.xml" }

    it "is an Atom feed, not a post" do
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("atom+xml")
    end

    it "contains an entry for each published post" do
      ShoutsidFyi::Content.posts.each do |post|
        expect(last_response.body).to include(post.title)
      end
    end

    it "points entries at the canonical site URL" do
      expect(last_response.body).to include("https://shoutsid.fyi/blog/")
    end
  end

  describe "GET /contact" do
    before { get "/contact" }

    it "is a success" do
      expect(last_response.status).to eq(200)
    end

    it "offers a mailto and an external profile" do
      expect(last_response.body).to include("mailto:")
      expect(last_response.body).to include("github.com/shoutsid")
    end

    # This page used to describe the team being hoped for. What a recruiter
    # opens the contact page to find out is whether he is available, for what
    # and where — so the lede is the offer, and it is the same string the hero
    # renders.
    it "states an availability offer rather than a preference" do
      expect(last_response.body).to include("Available for senior backend and Rails engineering roles")
      expect(last_response.body).to include("remote or hybrid")
    end
  end

  describe "GET /cv" do
    before { get "/cv" }

    it "is a success" do
      expect(last_response.status).to eq(200)
    end

    # The CV is the artifact a recruiter actually reads, so the case study has
    # to be reachable from it and not only from /about.
    it "links the Rails upgrade write-up from the experience entry" do
      expect(last_response.body)
        .to include(%(href="/blog/upgrading-a-production-rails-application"))
    end

    it "carries the availability line" do
      expect(last_response.body).to include("Available for senior backend and Rails engineering roles")
    end

    it "carries the current city" do
      expect(last_response.body).to include("Hartlepool, County Durham")
    end

    # The point of generating the CV from the content store is that it cannot
    # disagree with the rest of the site. If a role is on About it is on the
    # CV, because both read the same record — so this asserts the join rather
    # than a list of strings copied into a second document.
    #
    # Compared against the unescaped body on purpose: the content contains an
    # ampersand ("Career break & independent technical projects") and the
    # template escapes it, so the raw string is not what the browser receives.
    # Escaping has its own canary test; re-stating the rule here would make
    # this test fail for a reason that has nothing to do with the join.
    it "carries every role the content store holds" do
      body = CGI.unescapeHTML(last_response.body)

      ShoutsidFyi::Content.experience.each do |role|
        expect(body).to include(role["title"])
        expect(body).to include(role["company"])
      end
    end

    it "carries the toolkit and the education entries" do
      expect(last_response.body).to include("Languages &amp; frameworks")
      ShoutsidFyi::Content.education.each do |entry|
        expect(last_response.body).to include(entry["qualification"])
      end
    end

    it "does not publish a phone number" do
      # The old CV carries one. Publishing it to the open web is a decision,
      # not a side effect of adding a page, so its absence is asserted.
      expect(last_response.body).not_to match(/\+\d{2}[\d\s]{7,}/)
    end

    it "offers the print action as a button, not a link to nowhere" do
      # It was an anchor to "#", which goes nowhere with JavaScript disabled.
      # Printing is an action, so the element is a button.
      expect(last_response.body).to include(%(<button type="button" class="print-button" data-print>))
      expect(last_response.body).not_to include(%(<a href="#" data-print>))
    end

    # A PDF cannot follow "under Work" and cannot click a label, so the two
    # outputs deliberately differ: web-only pointers carry `no-print`, the
    # contact line carries the bare address, and the note is replaced rather
    # than hidden. The print stylesheet is what acts on these; the classes are
    # the contract between it and the template.
    it "marks the parts the paper version leaves out or replaces" do
      expect(last_response.body).to include(%(class="cv-contact-link no-print"))
      expect(last_response.body).to include(%(data-print-url="github.com/shoutsid"))
      expect(last_response.body).to include(%(class="role-link no-print"))
      expect(last_response.body).to include(%(class="section-note print-only"))
    end
  end

  describe "GET /healthz" do
    before { get "/healthz" }

    it "is JSON" do
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("json")
    end

    it "reports the content it can actually read" do
      payload = JSON.parse(last_response.body)

      expect(payload["status"]).to eq("ok")
      expect(payload["projects"]).to eq(ShoutsidFyi::Content.projects.length)
      expect(payload["posts"]).to eq(ShoutsidFyi::Content.posts.length)
      expect(payload["uptime_seconds"]).to be_a(Integer)
    end

    # The version used to be a literal here while `bin/site version` printed
    # whatever APP_VERSION said, and nothing read the file's copy — so the two
    # could disagree and neither would notice. bin/site exports APP_VERSION, so
    # a run through the CLI checks the wiring; a bare rspec falls back to the
    # same default the CLI does.
    it "reports the version the deployment declares" do
      payload = JSON.parse(last_response.body)

      expect(payload["version"]).to eq(ShoutsidFyi::App::VERSION)
      expect(payload["version"]).to eq(ENV.fetch("APP_VERSION", "0.1.0"))
    end
  end

  describe "GET /sitemap.xml" do
    before { get "/sitemap.xml" }

    it "is XML listing the project and post URLs" do
      expect(last_response.status).to eq(200)
      expect(last_response.headers["content-type"]).to include("xml")
      expect(last_response.body).to include("/work/webcap")
      expect(last_response.body).to include("/blog/")
    end
  end

  describe "GET /robots.txt" do
    it "points crawlers at the sitemap" do
      get "/robots.txt"

      expect(last_response.status).to eq(200)
      expect(last_response.body).to include("Sitemap: https://shoutsid.fyi/sitemap.xml")
    end
  end

  describe "a path that does not exist" do
    before { get "/nope" }

    it "is a 404 with the site's own page" do
      expect(last_response.status).to eq(404)
      expect(last_response.body).to include("does not exist")
      expect(last_response.body).to include("James Summerill")
    end
  end

  describe "security headers" do
    # Every route class, not just the homepage. The headers come from one
    # `before` block, and the way that block goes missing is a refactor that
    # leaves the suite green because only `/` was ever checked. The generated
    # documents are the ones worth checking twice: a JSON or XML response is a
    # response too, and the 404 is a page crawlers keep.
    def every_route
      ["/", "/about", "/work", "/blog", "/contact", "/cv", "/work/act",
        "/blog/feed.xml", "/sitemap.xml", "/healthz", "/nope"]
    end

    it "sends a restrictive content security policy on every response" do
      every_route.each do |path|
        get path
        csp = last_response.headers["content-security-policy"]

        expect(csp).to include("default-src 'self'"), "expected #{path} to send a CSP"
        expect(csp).to include("frame-ancestors 'none'")
        # No inline scripts are allowed, which is why the theme lives in
        # public/js/ and not in a <script> block.
        expect(csp).to include("script-src 'self'")
        expect(csp).not_to include("unsafe-inline")
      end
    end

    it "sends the other hardening headers on every response" do
      every_route.each do |path|
        get path

        expect(last_response.headers["x-content-type-options"]).to eq("nosniff")
        expect(last_response.headers["x-frame-options"]).to eq("DENY")
        expect(last_response.headers["referrer-policy"]).to eq("strict-origin-when-cross-origin")
        expect(last_response.headers["permissions-policy"]).to include("geolocation=()", "camera=()")
      end
    end

    # The one header that cannot come from the filter, because Sinatra serves a
    # static file before its before-filters run: it arrives from
    # Rack::Protection's middleware instead. Asserted on an asset for that
    # reason — it is the header that stops a mistyped content type being sniffed
    # into something executable, and assets are where that matters.
    it "sends nosniff on static assets too" do
      %w[/css/site.css /js/site.js /og.png].each do |asset|
        get asset

        expect(last_response.status).to eq(200)
        expect(last_response.headers["x-content-type-options"]).to eq("nosniff")
      end
    end
  end

  describe "escaping" do
    it "escapes an ampersand in the toolkit rather than emitting raw markup" do
      # "Languages & frameworks" is the canary: it proves the ERB escape
      # setting is on, because the source string contains a bare ampersand.
      get "/about"

      expect(last_response.body).to include("Languages &amp; frameworks")
    end
  end
end
