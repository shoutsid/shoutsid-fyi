# frozen_string_literal: true

# Whole-site checks.
#
# These are the ones a per-route test cannot make: a page can be a healthy 200
# while linking at a page that no longer exists, and an asset can be referenced
# by every template while 404ing for every visitor. Both are invisible from a
# single response.
RSpec.describe "site integrity" do
  # Every page a visitor (or a crawler) can reach without guessing. `/cv` is
  # here for the same reason the rest are: it is in the nav and the sitemap, so
  # it is a page the site claims to serve, and every whole-site check below has
  # to cover it. It was missing when it was added, which meant the newest page
  # was the only one with no link, title, canonical or template-leak check.
  def all_pages
    ["/", "/about", "/work", "/blog", "/contact", "/cv"] +
      ShoutsidFyi::Content.projects.map { |p| "/work/#{p["slug"]}" } +
      ShoutsidFyi::Content.posts.map(&:url)
  end

  def internal_links(html)
    html.scan(/href="(\/[^"#?]*)/).flatten.uniq
  end

  def stylesheet
    File.read(File.join(ShoutsidFyi::Content::ROOT, "public", "css", "site.css"))
  end

  it "resolves every internal link found on every page" do
    broken = []

    all_pages.each do |page|
      get page
      expect(last_response.status).to eq(200), "expected #{page} to be 200"

      internal_links(last_response.body).each do |link|
        get link
        next if last_response.status == 200

        broken << "#{page} links to #{link}, which returned #{last_response.status}"
      end
    end

    expect(broken).to be_empty, "broken internal links:\n#{broken.join("\n")}"
  end

  it "serves every asset the layout references" do
    %w[/css/site.css /js/theme-boot.js /js/site.js /favicon.svg /og.png].each do |asset|
      get asset

      expect(last_response.status).to eq(200), "expected #{asset} to be 200"
    end
  end

  # Case-study figures are the one thing on the site a reader cannot judge from
  # the text, so an image that does not load is worse here than elsewhere. The
  # content loader checks the paths it is given; this checks what a page emits.
  it "serves every image the pages reference" do
    broken = []

    all_pages.each do |page|
      get page
      last_response.body.scan(/<img[^>]+src="(\/[^"]+)"/).flatten.uniq.each do |src|
        get src.split("?").first
        broken << "#{page} references #{src}, which returned #{last_response.status}" unless last_response.status == 200
      end
    end

    expect(broken).to be_empty, "unserved images:\n#{broken.join("\n")}"
  end

  it "sets a title and a meta description on every page" do
    all_pages.each do |page|
      get page

      expect(last_response.body).to match(%r{<title>[^<]+\n?\s*[^<]*</title>}),
        "expected #{page} to have a title"
      expect(last_response.body).to include('name="description" content="'),
        "expected #{page} to have a meta description"
    end
  end

  it "gives every page a canonical URL on the public domain" do
    all_pages.each do |page|
      get page

      expect(last_response.body).to include(%(rel="canonical" href="https://shoutsid.fyi#{page}"))
    end
  end

  it "marks the current section in the navigation" do
    get "/work"

    expect(last_response.body).to match(/aria-current="page"[^>]*>Work|Work<\/a>/)
    expect(last_response.body).to include('aria-current="page"')
  end

  it "selects exactly one theme from either the stored value or the OS" do
    # The stylesheet defines the dark palette twice — once behind
    # [data-theme="dark"] and once behind the prefers-color-scheme media query
    # for the no-JavaScript case — and both blocks must agree, or the page
    # changes appearance when a visitor without JavaScript toggles nothing.
    css = stylesheet

    expect(css).to include(":root[data-theme=\"dark\"]")
    expect(css).to include("@media (prefers-color-scheme: dark)")
    expect(css).to include(":root:not([data-theme=\"light\"])")
  end

  # An ERB comment ends at the FIRST closing delimiter it contains, so a
  # comment that quotes the tag syntax truncates itself and spills its
  # remainder onto the page as visible text. That shipped once: every other
  # test passed while the homepage rendered a sentence of Ruby comment. This
  # is the check that was missing, and it covers every page.
  it "never leaks template syntax into a rendered page" do
    leaked = []

    all_pages.each do |page|
      get page
      leaked << page if last_response.body.include?("<%") || last_response.body.include?("%>")
    end

    expect(leaked).to be_empty, "template syntax leaked into: #{leaked.join(", ")}"
  end

  it "never leaks a template comment's text into a rendered page" do
    leaked = []

    all_pages.each do |page|
      get page
      leaked << page if last_response.body.match?(/print the markup as text|Rendered with locals/)
    end

    expect(leaked).to be_empty, "comment text leaked into: #{leaked.join(", ")}"
  end

  # The blog section was renamed and its index heading changed from "Notes".
  # This walks every page *and* the machine-readable summary, because the one
  # surviving "Notes" heading after the rename was in public/llms.txt — a file
  # no rendered-page test looks at.
  it "has no heading named Notes anywhere" do
    offenders = []

    all_pages.each do |page|
      get page
      offenders << page if last_response.body.match?(%r{<h[1-6][^>]*>\s*Notes\s*<}i)
    end

    llms = File.read(File.join(ShoutsidFyi::Content::ROOT, "public", "llms.txt"))
    offenders << "public/llms.txt" if llms.match?(/^#+\s*Notes\b/i)

    expect(offenders).to be_empty, "a heading named Notes is still present in: #{offenders.join(", ")}"
  end

  # The architecture says `config/` holds the prose and the templates render
  # it. That was true of the design and false of the code: eight templates
  # carried sentences describing content, and one of them advertised "a
  # deployed service and two public engineering projects" after a third
  # repository had been added. A rule nothing checks is a preference, so this
  # checks it: a literal run of six or more words in a template is prose, and
  # prose belongs in config/pages.yml where it can be read beside the data it
  # describes.
  it "keeps prose out of the templates" do
    offenders = []

    Dir.glob(File.join(ShoutsidFyi::Content::ROOT, "views", "**", "*.erb")).sort.each do |path|
      # Stripping happens across the whole file, not per line, because both a
      # block ERB tag and a multi-line SVG element span lines: the theme
      # toggle's opening tag runs for six, so a per-line pass leaves its
      # `viewBox` attributes looking like prose. Replacing each match with
      # spaces rather than deleting it keeps every line number honest.
      blank = ->(match) { match.gsub(/[^\n]/, " ") }
      source = File.read(path).gsub(/<%.*?%>/m, &blank).gsub(/<[^>]*>/m, &blank)

      source.each_line.with_index(1) do |line, number|
        words = line.split
        next if words.length < 6

        offenders << "#{path.sub("#{ShoutsidFyi::Content::ROOT}/", "")}:#{number} " \
                     "(#{words.length} words): #{words.join(" ")[0, 64]}"
      end
    end

    expect(offenders).to be_empty, "template prose belongs in config/pages.yml:\n#{offenders.join("\n")}"
  end

  it "ships both theme icons in the markup" do
    get "/"

    expect(last_response.body).to include("theme-toggle-icon-moon")
    expect(last_response.body).to include("theme-toggle-icon-sun")
  end

  it "swaps the toggle icon per theme, including with no JavaScript" do
    css = stylesheet

    expect(css).to include(":root[data-theme=\"dark\"] .theme-toggle-icon-sun")
    expect(css).to include(":root[data-theme=\"dark\"] .theme-toggle-icon-moon")
    expect(css).to include(":root:not([data-theme=\"light\"]) .theme-toggle-icon-sun")
  end

  it "loads the theme before the stylesheet so there is no flash of the wrong theme" do
    get "/"
    body = last_response.body

    script_at = body.index("theme-boot.js")
    css_at = body.index("site.css")

    expect(script_at).not_to be_nil
    expect(css_at).not_to be_nil
    expect(script_at).to be < css_at
  end

  # The digest in the asset URL is half of a cache-busting scheme; the response
  # header is the other half, and it is the half that fails silently. The app
  # declared no Cache-Control at all until this was written, so Cloudflare
  # supplied four hours of its own on every asset while `asset_digest` built a
  # new URL per revision that nothing was permitted to keep.
  describe "cache policy" do
    def digest_of(name)
      Digest::MD5.file(File.join(ShoutsidFyi::Content::ROOT, "public", name)).hexdigest[0, 8]
    end

    it "version-stamps every asset the layout references with that file's digest" do
      get "/"

      %w[css/site.css js/site.js js/theme-boot.js].each do |name|
        expect(last_response.body).to include("/#{name}?v=#{digest_of(name)}"),
          "the layout must reference #{name} at the digest of the file on disk"
      end
    end

    it "lets a digest-versioned asset be kept for a year, immutably" do
      %w[css/site.css js/site.js js/theme-boot.js].each do |name|
        get "/#{name}?v=#{digest_of(name)}"

        expect(last_response.status).to eq(200)
        expect(last_response.headers["cache-control"]).to eq("public, immutable, max-age=31536000"),
          "#{name} is content-addressed, so every hop may keep it"
      end
    end

    # The static server ignores the query string: `/css/site.css?v=old` answers
    # with today's file. Promising a year of immutability for a URL that does
    # not identify its content would be the one thing this header must never do.
    it "does not promise immutability for a URL that does not identify its content" do
      ["/css/site.css", "/css/site.css?v=00000000"].each do |path|
        get path

        expect(last_response.status).to eq(200)
        expect(last_response.headers["cache-control"]).to eq("public, no-cache")
      end
    end

    it "gives files whose URL cannot change with their content a short TTL" do
      %w[/og.png /favicon.svg /robots.txt /llms.txt /screenshots/webcap.png
        /diagrams/rails-outbox.svg].each do |path|
        get path

        expect(last_response.status).to eq(200)
        expect(last_response.headers["cache-control"]).to eq("public, max-age=3600")
      end
    end

    it "revalidates pages, the feed, the sitemap and the health check" do
      ["/", "/about", "/work", "/blog/feed.xml", "/sitemap.xml", "/healthz", "/nope"].each do |path|
        get path

        expect(last_response.headers["cache-control"]).to eq("public, no-cache"),
          "#{path} is generated, so it must be revalidated rather than guessed at"
      end
    end
  end

  # Colour is content too. A grey that fails WCAG AA is invisible to the reader
  # who needed the contrast, and nothing about it fails a render test — so the
  # ratios are computed from the tokens rather than eyeballed, and the next
  # palette edit has to clear the bar instead of being trusted.
  describe "colour contrast" do
    def palette(scope)
      css = stylesheet
      block =
        case scope
        when :light then css[/^:root \{(.*?)^\}/m, 1]
        when :dark_attribute then css[/^:root\[data-theme="dark"\] \{(.*?)^\}/m, 1]
        when :dark_system then css[/^@media \(prefers-color-scheme: dark\) \{(.*?)^\}/m, 1]
        end

      expect(block).not_to be_nil, "expected #{scope} to define a palette"
      block.scan(/(--[a-z-]+):\s*(#[0-9a-f]{6})/i).to_h
    end

    def relative_luminance(hex)
      channels = hex.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) / 255.0 }
      channels = channels.map { |c| (c <= 0.04045) ? c / 12.92 : (((c + 0.055) / 1.055)**2.4) }
      (0.2126 * channels[0]) + (0.7152 * channels[1]) + (0.0722 * channels[2])
    end

    def contrast(front, back)
      # `sort` is ascending, so the smaller luminance is the darker colour.
      darker, lighter = [relative_luminance(front), relative_luminance(back)].sort
      (lighter + 0.05) / (darker + 0.05)
    end

    # WCAG AA for normal-size text. The small mono labels and post dates are
    # normal size, and they are the reason this is 4.5 rather than the 3.0 that
    # non-text UI is allowed.
    def minimum_ratio = 4.5

    it "keeps every text token legible on every surface, in both themes" do
      {light: :light, dark: :dark_attribute}.each do |theme, scope|
        tokens = palette(scope)

        %w[--text --text-muted --text-faint --accent].each do |token|
          %w[--bg --bg-elevated --bg-subtle].each do |surface|
            ratio = contrast(tokens.fetch(token), tokens.fetch(surface))

            expect(ratio).to be >= minimum_ratio,
              "#{theme} #{token} on #{surface} is #{ratio.round(2)}:1, " \
              "below the #{minimum_ratio}:1 floor for normal-size text"
          end
        end
      end
    end

    it "keeps every project status badge legible on its own fill" do
      %w[live public research in-progress].each do |status|
        %i[light dark_attribute].each do |scope|
          tokens = palette(scope)
          ratio = contrast(tokens.fetch("--status-#{status}"), tokens.fetch("--status-#{status}-soft"))

          expect(ratio).to be >= minimum_ratio,
            "#{scope} badge #{status} is #{ratio.round(2)}:1 on its own background"
        end
      end
    end

    # The dark palette is written twice — once behind the stored-theme attribute
    # and once behind the media query for the no-JavaScript case — and the
    # stylesheet's own comment claims the two cannot drift. They can: they are
    # two literal copies. This is what makes the claim true.
    it "defines the same palette in the stored-theme attribute and the media query" do
      expect(palette(:dark_attribute)).to eq(palette(:dark_system))
    end
  end
end
