# frozen_string_literal: true

require "digest"
require "yaml"
require "date"
require "time"
require_relative "markdown"

module ShoutsidFyi
  # Everything the site says about James lives here, as data.
  #
  # Content is data rather than ERB so that the templates cannot disagree with
  # each other: the homepage, the work index and a project page all render the
  # same `Project` record, and a claim appears once in one file. It also means
  # the copy is reviewable and diffable without reading markup, which matters
  # because the portfolio's whole point is that its claims are evidence-based.
  module Content
    # Raised when a content file is structurally wrong. Deliberately raised at
    # boot in production (see `App.configure`) rather than swallowed: a
    # malformed project should stop the container, not serve a page with a
    # blank card on it.
    class Error < StandardError; end

    ROOT = File.expand_path("..", __dir__)
    CONFIG_DIR = File.join(ROOT, "config")
    BLOG_DIR = File.join(ROOT, "content", "blog")

    # The status a project can carry. The set is closed so that the badge
    # rendered for it is exhaustive: an unknown status is a content bug, not a
    # fallback badge.
    STATUSES = %w[live public research in-progress].freeze

    # The page sections, in the order they render. Both the homepage and `/work`
    # group their cards by this, so the two pages cannot disagree about which
    # projects are prominent. They did disagree while `/work` rendered file
    # order and the homepage had an ordering list of its own: a reorder of one
    # file moved the Rails case study on both pages, which is what made the
    # problem visible.
    SECTIONS = %w[main systems archive].freeze

    # The page copy every page reads, and therefore the keys a missing entry
    # would render as an empty paragraph. Checked at boot like everything else
    # in `validate!`, so a deleted key is a startup failure rather than a
    # heading with nothing under it.
    PAGES_REQUIRED = {
      # Rendered by both pages, and therefore stated once.
      "shared" => %w[systems_note more_note],
      "home" => %w[featured_note experience_note],
      "work" => %w[description intro],
      "blog" => %w[description intro],
      "about" => %w[experience_note],
      "contact" => %w[description where_note],
      "cv" => %w[description download_label projects_note projects_note_print],
      "errors" => %w[not_found server_error]
    }.freeze

    # A markdown post under content/blog/. Constructed with keywords only
    # (see `load_post`), which needs no `keyword_init` on Ruby 3.2+.
    Post = Struct.new(:slug, :title, :date, :summary, :tags, :draft, :body) do
      def url = "/blog/#{slug}"

      def date_display = date.strftime("%-d %B %Y")

      def iso_date = date.strftime("%Y-%m-%d")

      def reading_minutes = [(body.to_s.split.length / 220.0).ceil, 1].max

      def html = Markdown.render(body)

      def draft? = !!draft
    end

    module_function

    # ---------------------------------------------------------------- public

    def profile
      cached(:profile, profile_path) { read_yaml(profile_path) }
    end

    # Page-level prose. Read here rather than written in a template so that a
    # sentence describing the content sits beside the content it describes.
    def pages
      cached(:pages, pages_path) { read_yaml(pages_path) }
    end

    def projects
      cached(:projects, projects_path) do
        Array(read_yaml(projects_path)["projects"]).map { |raw| normalize_project(raw) }
      end
    end

    def featured_projects
      projects.select { |p| p["featured"] }
    end

    def other_projects
      projects.reject { |p| p["featured"] }
    end

    # The projects in one section, in file order. `config/projects.yml` is kept
    # ordered by section, so within a section this is the order the content file
    # states — and there is only one of those.
    def projects_in_section(section)
      projects.select { |p| p["section"] == section }
    end

    def project(slug)
      projects.find { |p| p["slug"] == slug }
    end

    def experience
      cached(:experience, experience_path) { Array(read_yaml(experience_path)["roles"]) }
    end

    def education
      cached(:education, experience_path) { Array(read_yaml(experience_path)["education"]) }
    end

    def skills
      cached(:skills, experience_path) { Array(read_yaml(experience_path)["skills"]) }
    end

    # Newest first. Drafts are included only when asked for, so production
    # never serves one and the suite can still assert that a draft is
    # well-formed.
    def posts(include_drafts: false)
      # `sort_by` is not stable in Ruby, and two posts can share a date — the
      # first pair that did produced an order that was arbitrary but consistent,
      # which is the kind of thing that changes under an unrelated edit and gets
      # blamed on that edit. The slug breaks the tie so the order is defined.
      all = raw_posts.sort_by { |post| [post.date, post.slug] }.reverse
      include_drafts ? all : all.reject(&:draft?)
    end

    def post(slug, include_drafts: false)
      posts(include_drafts: include_drafts).find { |p| p.slug == slug }
    end

    def tags
      posts.flat_map(&:tags).tally.sort_by { |name, count| [-count, name] }
    end

    # Short content hash of a file under public/, for cache-busting asset
    # URLs: a new deploy with changed CSS or JS is a new URL, so a CDN edge
    # holding yesterday's copy can never serve it for today's page. Memoised
    # on the file's mtime, so an edit in development takes effect on the next
    # request without a restart.
    def asset_digest(name)
      path = File.join(ROOT, "public", name)
      cached(:"asset_#{name}", path) { Digest::MD5.file(path).hexdigest[0, 8] }
    end

    # ----------------------------------------------------------- validation

    # Everything the suite and the production boot both insist on. Returns
    # nothing and raises `Error` on the first problem, naming the file it came
    # from — a content bug reported as "project 3 is missing a summary" is
    # actionable, one reported as a 500 on `/work` is not.
    def validate!
      profile = self.profile
      # `seeking` is in this list because the hero and the contact page both
      # render it: a missing one used to leave a blank invitation rather than
      # a build failure.
      %w[name role tagline summary seeking].each do |key|
        raise Error, "config/profile.yml: missing #{key}" if blank?(profile[key])
      end
      links = profile["links"]
      unless links.is_a?(Array) && !links.empty?
        raise Error, "config/profile.yml: missing links (expected a list of {label, url})"
      end

      links.each do |link|
        url = link["url"].to_s
        unless url.match?(%r{\A(https?://|mailto:)})
          raise Error, "config/profile.yml: link #{link["label"].inspect} is not a URL (#{url.inspect})"
        end
      end

      slugs = projects.map { |p| p["slug"] }
      duplicates = slugs.tally.select { |_, count| count > 1 }.keys
      raise Error, "config/projects.yml: duplicate slug(s) #{duplicates.join(", ")}" if duplicates.any?

      raise Error, "config/projects.yml: no featured projects" if featured_projects.empty?

      projects.each do |project|
        %w[slug title tagline summary].each do |key|
          raise Error, "config/projects.yml: #{project["slug"].inspect} missing #{key}" if blank?(project[key])
        end
        unless STATUSES.include?(project["status"])
          raise Error, "config/projects.yml: #{project["slug"]} has unknown status #{project["status"].inspect} " \
                       "(known: #{STATUSES.join(", ")})"
        end
        # A project with no section, or a section nobody renders, is a card
        # silently missing from both pages.
        unless SECTIONS.include?(project["section"])
          raise Error, "config/projects.yml: #{project["slug"]} has section #{project["section"].inspect}, " \
                       "which is not one of #{SECTIONS.join(", ")}"
        end
        Array(project["links"]).each do |link|
          url = link["url"].to_s
          raise Error, "config/projects.yml: #{project["slug"]} link #{link["label"].inspect} is not a URL" unless url.match?(%r{\Ahttps?://})
        end

        # A demo is rendered as a command and its output, so all three parts
        # have to be there for it to mean anything.
        if project["demo"]
          %w[title request response].each do |key|
            raise Error, "config/projects.yml: #{project["slug"]} demo is missing #{key}" if blank?(project["demo"][key])
          end
        end

        # A figure pointing at a file that is not there renders as a broken
        # image on a page whose entire argument is that its claims are checkable.
        project["screenshots"].each do |shot|
          %w[label path alt].each do |key|
            raise Error, "config/projects.yml: #{project["slug"]} screenshot is missing #{key}" if blank?(shot[key])
          end
          raise Error, "config/projects.yml: #{project["slug"]} screenshot path must start with / (got #{shot["path"].inspect})" unless shot["path"].start_with?("/")

          asset = File.join(ROOT, "public", shot["path"].delete_prefix("/"))
          raise Error, "config/projects.yml: #{project["slug"]} screenshot #{shot["path"]} is not a file under public/" unless File.file?(asset)
        end
      end

      # The social preview image is referenced by the layout on every page, so
      # its absence is the same class of bug as a figure with no file.
      unless File.file?(File.join(ROOT, "public", "og.png"))
        raise Error, "public/og.png is missing — the layout references it as the social preview image"
      end

      PAGES_REQUIRED.each do |section, keys|
        raise Error, "config/pages.yml: missing the #{section.inspect} section" unless pages[section].is_a?(Hash)

        keys.each do |key|
          raise Error, "config/pages.yml: missing #{section}.#{key}" if blank?(pages[section][key])
        end
      end

      link = pages.dig("home", "experience_link")
      unless link.is_a?(Hash) && link["path"].to_s.start_with?("/")
        raise Error, "config/pages.yml: home.experience_link needs a {label, path} whose path starts with /"
      end

      post_slugs = posts(include_drafts: true).map(&:slug)
      post_duplicates = post_slugs.tally.select { |_, count| count > 1 }.keys
      raise Error, "content/blog: duplicate slug(s) #{post_duplicates.join(", ")}" if post_duplicates.any?

      posts(include_drafts: true).each do |post|
        raise Error, "content/blog/#{post.slug}.md: missing title" if blank?(post.title)
        raise Error, "content/blog/#{post.slug}.md: missing summary" if blank?(post.summary)
        raise Error, "content/blog/#{post.slug}.md: empty body" if blank?(post.body)
      end

      # These lists are printed item by item by the templates, so an entry that
      # parsed as a mapping reaches the page as a Ruby hash inspect. The
      # project lists are normalised through `scalar_list` above; the
      # experience and skills files are read raw, so they are checked here.
      experience.each do |role|
        scalar_list(role["highlights"], "config/experience.yml: #{role["title"].inspect} highlights")

        # An optional link out of the entry, in the same shape as
        # home.experience_link: a path on this site, not a URL, because its job
        # is to open the evidence rather than send the reader away from it. A
        # typo here would be a broken link on /about and /cv, so it is a boot
        # failure like every other link in config.
        link = role["link"]
        next if link.nil?

        unless link.is_a?(Hash) && link["path"].to_s.start_with?("/")
          raise Error, "config/experience.yml: #{role["title"].inspect} link needs a {label, path} whose path starts with /"
        end
      end

      skills.each do |group|
        scalar_list(group["items"], "config/experience.yml: #{group["group"].inspect} items")
      end

      # A section that nothing belongs to renders as a heading with no cards
      # under it. The first section is the page's reason for existing, so it is
      # required in the same spirit as `featured` above.
      raise Error, "config/projects.yml: no projects in the main section" if projects_in_section("main").empty?

      true
    end

    # Drops the memo table. Only the suite needs this; the process caches for
    # its lifetime otherwise.
    def reset!
      @cache = {}
      true
    end

    # ------------------------------------------------------------- internals

    def profile_path = File.join(CONFIG_DIR, "profile.yml")
    def projects_path = File.join(CONFIG_DIR, "projects.yml")
    def experience_path = File.join(CONFIG_DIR, "experience.yml")
    def pages_path = File.join(CONFIG_DIR, "pages.yml")

    def blank?(value) = value.nil? || value.to_s.strip.empty?

    # A list of plain scalars — highlights, technologies, tags. Every one of
    # them is looped over by a template that prints the item directly, so an
    # item that is not a scalar has nowhere to go but the page.
    #
    # The trap this exists for: an unquoted `: ` inside a block-sequence entry
    # — `- Verification is executable: two services...` — turns that entry into
    # a *mapping*, not a string. Coerced with `to_s` it renders as a Ruby hash
    # inspect, so the card read `{"Verification is executable"=>"two
    # services run"}`. Raising here instead of coercing makes that a startup
    # failure, which is the same rule the status check follows: a content bug
    # stops the boot rather than reaching a page. Quote the entry to fix it.
    def scalar_list(value, context)
      Array(value).each_with_index.map { |item, index| scalar(item, "#{context}[#{index}]") }
    end

    # One plain scalar, strict for the same reason as the list above.
    def scalar(value, context)
      unless value.nil? || value.is_a?(String) || value.is_a?(Numeric)
        raise Error, "#{context}: expected a plain string, got #{value.class} — " \
                     "quote the entry if it contains \": \" " \
                     "(#{value.inspect[0, 60]})"
      end
      value.to_s
    end

    # Memoised on (path, mtime). In production the file never changes, so this
    # is one stat per request; in development it means an edit takes effect on
    # the next refresh without restarting the server.
    def cached(key, path)
      mtime = File.mtime(path)
      entry = (@cache ||= {})[key]
      return entry[:value] if entry && entry[:mtime] == mtime

      value = yield
      @cache[key] = {mtime: mtime, value: value}
      value
    end

    def read_yaml(path)
      raise Error, "missing content file: #{path}" unless File.file?(path)
      YAML.safe_load_file(path, permitted_classes: [Date, Time], aliases: true) || {}
    rescue Psych::SyntaxError => e
      raise Error, "#{path}: #{e.message}"
    end

    # A project is normalised once, here, so templates can assume the shape.
    # `links` is always an array (`{label, url}`) and `stack` always a list,
    # which is what lets `views/partials/project_card.erb` be a loop rather
    # than a chain of null checks. `demo` is an optional documented
    # request/response example (`{title, request, response}`); it is nil when
    # the project has none, so only project pages that carry one render it.
    def normalize_project(raw)
      demo = raw["demo"]
      {
        "slug" => raw["slug"].to_s,
        "title" => raw["title"].to_s,
        "status" => raw["status"].to_s,
        "tagline" => raw["tagline"].to_s,
        "summary" => raw["summary"].to_s,
        "year" => raw["year"].to_s,
        "featured" => !!raw["featured"],
        "section" => raw["section"].to_s,
        "highlights" => scalar_list(raw["highlights"], "config/projects.yml: #{raw["slug"]} highlights"),
        "notes" => raw["notes"].to_s,
        "stack" => scalar_list(raw["stack"], "config/projects.yml: #{raw["slug"]} stack"),
        "links" => Array(raw["links"]).map { |link| {"label" => link["label"].to_s, "url" => link["url"].to_s} },
        # A documented example needs all three parts to be worth rendering, and
        # each is coerced strictly for the reason above: an unquoted ": " in a
        # request line is a mapping, not a command.
        "demo" => normalize_demo(raw["slug"], demo),
        "screenshots" => normalize_screenshots(raw["slug"], raw["screenshots"])
      }
    end

    # Captured pages, shown as figures on the project page. Each one is a
    # {label, path, alt}: the label is the caption, the path is a file this
    # site serves, and the alt is the description a reader who cannot see it
    # gets instead — which is the whole content of the figure for them, so it
    # is required rather than optional.
    def normalize_screenshots(slug, shots)
      Array(shots).map.with_index do |shot, index|
        unless shot.is_a?(Hash)
          raise Error, "config/projects.yml: #{slug} screenshots[#{index}] is not a {label, path, alt} mapping"
        end

        {
          "label" => scalar(shot["label"], "config/projects.yml: #{slug} screenshots[#{index}] label"),
          "path" => scalar(shot["path"], "config/projects.yml: #{slug} screenshots[#{index}] path"),
          "alt" => scalar(shot["alt"], "config/projects.yml: #{slug} screenshots[#{index}] alt")
        }
      end
    end

    def normalize_demo(slug, demo)
      return nil unless demo.is_a?(Hash)

      {
        "title" => scalar(demo["title"], "config/projects.yml: #{slug} demo title"),
        "request" => scalar(demo["request"], "config/projects.yml: #{slug} demo request"),
        "response" => scalar(demo["response"], "config/projects.yml: #{slug} demo response")
      }
    end

    # Keyed on the directory's own mtime rather than each file's: adding or
    # removing a post moves the directory, and editing one moves the file. Two
    # stats beats one stat per post, and this directory will never be large.
    def raw_posts
      cached(:posts, BLOG_DIR) do
        Dir.glob(File.join(BLOG_DIR, "*.md")).sort.filter_map { |path| load_post(path) }
      end
    end

    # `YYYY-MM-DD-a-slug.md` -> slug `a-slug`, date from the filename unless the
    # front matter overrides it. The filename carries the date because it keeps
    # the directory listing in reading order; the front matter carries it too
    # because that is what the page displays.
    def load_post(path)
      raw = File.read(path)
      front, body = split_front_matter(raw, path)
      filename = File.basename(path, ".md")
      slug = filename.sub(/\A\d{4}-\d{2}-\d{2}-/, "")

      date =
        if front["date"]
          parse_date(front["date"], path)
        elsif (match = filename.match(/\A(\d{4}-\d{2}-\d{2})-/))
          Date.parse(match[1])
        else
          raise Error, "#{path}: no date in filename or front matter"
        end

      Post.new(
        slug: slug,
        title: front["title"].to_s,
        date: date,
        summary: front["summary"].to_s,
        tags: scalar_list(front["tags"], "#{path}: tags"),
        draft: front.fetch("draft", false),
        body: body.strip
      )
    end

    FRONT_MATTER = /\A---\s*\n(.*?)\n---\s*\n/m

    def split_front_matter(raw, path)
      match = raw.match(FRONT_MATTER)
      raise Error, "#{path}: missing YAML front matter (--- ... ---)" unless match

      front = YAML.safe_load(match[1], permitted_classes: [Date, Time], aliases: true) || {}
      raise Error, "#{path}: front matter is not a mapping" unless front.is_a?(Hash)

      [front, raw[match[0].length..]]
    rescue Psych::SyntaxError => e
      raise Error, "#{path}: #{e.message}"
    end

    def parse_date(value, path)
      return value if value.is_a?(Date)
      return value.to_date if value.is_a?(Time)
      Date.parse(value.to_s)
    rescue ArgumentError
      raise Error, "#{path}: unparseable date #{value.inspect}"
    end
  end
end
