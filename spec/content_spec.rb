# frozen_string_literal: true

RSpec.describe ShoutsidFyi::Content do
  # The invariants, checked against the real content committed to the
  # repository. This is the test that fails when a new project is added with a
  # status nobody handles, or a post is committed without a summary — the two
  # mistakes that would otherwise render as a blank card on a live page.
  describe ".validate!" do
    it "passes on the content in this repository" do
      expect(described_class.validate!).to be(true)
    end

    it "rejects a project whose status is not in the known set" do
      allow(described_class).to receive(:projects).and_return(
        [project("rogue", status: "shipped")]
      )

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /unknown status "shipped"/)
    end

    it "rejects two projects sharing a slug" do
      allow(described_class).to receive(:projects).and_return(
        [project("same"), project("same")]
      )

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /duplicate slug/)
    end

    it "rejects a featured set with nothing in it" do
      allow(described_class).to receive(:projects).and_return(
        [project("only", featured: false)]
      )

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /no featured projects/)
    end

    # `section` decides which group a project appears in, on both pages. A value
    # nobody renders is a card silently missing from both, which is the quiet
    # kind of wrong this file turns into a boot error.
    it "rejects a project whose section is not one of the rendered ones" do
      allow(described_class).to receive(:projects).and_return([project("rogue", section: "sidebar")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /section "sidebar"/)
    end

    it "rejects a project with no section at all" do
      allow(described_class).to receive(:projects).and_return([project("bare", section: "")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /section ""/)
    end

    it "rejects a content file with nothing in the main section" do
      allow(described_class).to receive(:projects).and_return([project("only", section: "archive")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /no projects in the main section/)
    end

    # The optional link on an experience role is a path, like home.experience_link
    # and unlike the profile's links. A URL there would take the reader off the
    # page the link exists to support, and a typo would be a broken link on
    # /about and /cv rather than a boot failure.
    it "rejects an experience role link that leaves the site" do
      roles = described_class.experience.dup
      roles[1] = roles[1].merge("link" => {"label" => "Elsewhere", "path" => "https://example.com/x"})
      allow(described_class).to receive(:experience).and_return(roles)

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /link needs a \{label, path\}/)
    end

    it "rejects a project link that is not a URL" do
      allow(described_class).to receive(:projects).and_return(
        [project("bad-link", links: [{"label" => "GitHub", "url" => "github.com/x"}])]
      )

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /is not a URL/)
    end

    # An unquoted `: ` inside a YAML block-sequence entry turns that entry
    # into a mapping rather than a string. Coerced with `to_s` it reaches the
    # page as a Ruby hash inspect: the agents.shoutsid.fyi card read
    # `{"Verification is executable"=>"two services run..."}`. This asserts
    # the coercion refuses instead, so the mistake stops the boot.
    it "rejects a highlight that parsed as a mapping rather than a string" do
      raw = project_hash("trap", highlights: [{"Verification is executable" => "two services run"}])

      expect { described_class.normalize_project(raw) }
        .to raise_error(described_class::Error, /expected a plain string, got Hash/)
    end

    it "rejects a stack entry that parsed as a mapping rather than a string" do
      raw = project_hash("trap", stack: [{"C++" => "CMake"}])

      expect { described_class.normalize_project(raw) }
        .to raise_error(described_class::Error, /expected a plain string, got Hash/)
    end

    it "rejects an experience highlight that parsed as a mapping" do
      allow(described_class).to receive(:experience).and_return(
        [{"title" => "T", "highlights" => [{"led" => "a team"}]}]
      )
      allow(described_class).to receive(:projects).and_return([project("ok")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /expected a plain string, got Hash/)
    end

    it "rejects a skills entry that parsed as a mapping" do
      allow(described_class).to receive(:skills).and_return(
        [{"group" => "G", "items" => [{"Ruby" => "Rails"}]}]
      )
      allow(described_class).to receive(:projects).and_return([project("ok")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /expected a plain string, got Hash/)
    end

    it "rejects a post with no summary" do
      post = described_class::Post.new(
        slug: "no-summary", title: "T", date: Date.today, summary: "",
        tags: [], draft: false, body: "body"
      )
      allow(described_class).to receive(:posts).and_return([post])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /missing summary/)
    end
  end

  describe ".profile" do
    it "carries the fields the templates depend on" do
      profile = described_class.profile

      expect(profile["name"]).to eq("James Summerill")
      expect(profile["headline"]).not_to be_empty
      expect(profile["summary"]).not_to be_empty
      expect(profile["links"]).not_to be_empty
      expect(profile.dig("site", "url")).to start_with("https://")
    end

    it "offers an email link that is a mailto" do
      email_links = described_class.profile["links"].select { |l| l["label"] == "Email" }

      expect(email_links.length).to eq(1)
      expect(email_links.first["url"]).to start_with("mailto:")
    end
  end

  # Page copy lives in config/pages.yml so that a sentence describing the
  # content sits beside it. A missing key would render as a heading with
  # nothing under it, so the set is closed and checked at boot.
  describe ".pages" do
    it "carries every key the pages read" do
      described_class::PAGES_REQUIRED.each do |section, keys|
        expect(described_class.pages[section]).to be_a(Hash), "#{section} section"

        keys.each do |key|
          value = described_class.pages.dig(section, key)
          expect(value).not_to be_nil, "#{section}.#{key}"
          expect(value.to_s.strip).not_to be_empty, "#{section}.#{key}"
        end
      end
    end

    it "gives the hero link a path on this site" do
      link = described_class.pages.dig("home", "experience_link")

      expect(link["label"]).not_to be_empty
      expect(link["path"]).to start_with("/")
    end

    # Built by removing one section from the real file rather than stubbing an
    # empty hash. The empty hash made this test depend on which section happens
    # to be checked first, and it failed the moment `shared` was added above
    # `home` — naming a section the test had not removed.
    it "rejects a missing page copy section" do
      broken = described_class.pages.except("home")
      allow(described_class).to receive(:pages).and_return(broken)
      allow(described_class).to receive(:projects).and_return([project("ok")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /missing the "home" section/)
    end

    it "rejects a page copy file with no sections at all" do
      allow(described_class).to receive(:pages).and_return({})
      allow(described_class).to receive(:projects).and_return([project("ok")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /missing the "shared" section/)
    end

    it "rejects a hero link that points off the site" do
      broken = described_class.pages.dup
      broken["home"] = broken["home"].merge(
        "experience_link" => {"label" => "Elsewhere", "path" => "https://example.com/about"}
      )
      allow(described_class).to receive(:pages).and_return(broken)
      allow(described_class).to receive(:projects).and_return([project("ok")])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /path starts with \//)
    end
  end

  # The grouping both pages render. One field, so the homepage and `/work`
  # cannot disagree about which projects are prominent — which they did while
  # `/work` rendered file order and the homepage had an ordering list of its
  # own. A reviewer caught it: the homepage led with Rails, `/work` put four
  # projects ahead of it.
  describe ".projects_in_section" do
    it "orders the sections the way both pages render them" do
      expect(described_class::SECTIONS).to eq(%w[main systems archive])
    end

    # The four a Rails reader should meet first, in this order: the architecture
    # case study, the two deployed services, then the public agent tooling that
    # carries the AI-with-verification argument.
    it "leads with the Rails work, the deployed services and the public agent tooling" do
      expect(described_class.projects_in_section("main").map { |p| p["slug"] })
        .to eq(%w[rails-modular-monolith webcap agents-fyi local-coder])
    end

    it "keeps the systems work and the research out of the first grid" do
      expect(described_class.projects_in_section("systems").map { |p| p["slug"] })
        .to eq(%w[act evo16 planetary-matrix])
    end

    it "puts every project in exactly one section" do
      grouped = described_class::SECTIONS.flat_map do |section|
        described_class.projects_in_section(section).map { |p| p["slug"] }
      end

      expect(grouped.sort).to eq(described_class.projects.map { |p| p["slug"] }.sort)
    end

    it "drops a project that no section claims" do
      allow(described_class).to receive(:projects).and_return([project("stray", section: "")])

      expect(described_class::SECTIONS.flat_map { |s| described_class.projects_in_section(s) }).to be_empty
    end
  end

  describe ".projects" do
    it "normalises every project into the shape the templates read" do
      described_class.projects.each do |project|
        expect(project["slug"]).to match(/\A[a-z0-9-]+\z/)
        expect(project).to include("title", "status", "tagline", "summary", "links", "stack", "highlights", "screenshots")
        expect(project["links"]).to be_an(Array)
        expect(project["stack"]).to be_an(Array)
      end
    end

    # The page-visible consequence, asserted against the real content: every
    # item a template prints directly has to be a string, not a mapping that
    # `to_s` would turn into a hash inspect.
    it "has only plain strings in every list a template loops over" do
      described_class.projects.each do |project|
        expect(project["highlights"]).to all(be_a(String)), "#{project["slug"]} highlights"
        expect(project["stack"]).to all(be_a(String)), "#{project["slug"]} stack"
      end

      described_class.experience.each do |role|
        expect(Array(role["highlights"])).to all(be_a(String)), "#{role["title"]} highlights"
      end

      described_class.skills.each do |group|
        expect(Array(group["items"])).to all(be_a(String)), "#{group["group"]} items"
      end

      described_class.posts.each do |post|
        expect(post.tags).to all(be_a(String)), "#{post.slug} tags"
      end
    end

    it "uses only known statuses" do
      statuses = described_class.projects.map { |p| p["status"] }.uniq
      expect(statuses - described_class::STATUSES).to be_empty
    end

    it "has at least one deployed project and at least one experimental one" do
      statuses = described_class.projects.map { |p| p["status"] }

      expect(statuses).to include("live", "public", "research")
    end

    # A documented example is a command and its output, so all three parts have
    # to be present for it to be worth rendering.
    it "gives every documented example a title, a request and a response" do
      described_class.projects.select { |p| p["demo"] }.each do |project|
        expect(project["demo"]["title"]).not_to be_empty, "#{project["slug"]} demo title"
        expect(project["demo"]["request"]).not_to be_empty, "#{project["slug"]} demo request"
        expect(project["demo"]["response"]).not_to be_empty, "#{project["slug"]} demo response"
      end
    end

    it "rejects a demo field that parsed as a mapping" do
      raw = project_hash("trap").merge(
        "demo" => {"title" => {"a" => "b"}, "request" => "cmd", "response" => "out"}
      )

      expect { described_class.normalize_project(raw) }
        .to raise_error(described_class::Error, /expected a plain string, got Hash/)
    end

    it "rejects a demo that is missing its response" do
      raw = project_hash("trap").merge(
        "demo" => {"title" => "t", "request" => "cmd", "response" => "  "}
      )
      allow(described_class).to receive(:projects).and_return([described_class.normalize_project(raw)])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /demo is missing response/)
    end

    # A figure whose file is not there renders as a broken image, on a page
    # whose whole argument is that its claims can be checked. The loader
    # refuses to boot rather than let that reach a reader.
    it "gives every screenshot a label, an alt, and a path to a file this site serves" do
      described_class.projects.each do |project|
        project["screenshots"].each do |shot|
          expect(shot["label"]).not_to be_empty, "#{project["slug"]} label"
          expect(shot["alt"]).not_to be_empty, "#{project["slug"]} alt"
          expect(shot["path"]).to start_with("/"), "#{project["slug"]} path"

          asset = File.join(described_class::ROOT, "public", shot["path"].delete_prefix("/"))
          expect(File.file?(asset)).to be(true), "#{project["slug"]} points at #{shot["path"]}, which is not a file"
        end
      end
    end

    it "rejects a screenshot whose file is missing" do
      raw = project_hash("trap").merge(
        "screenshots" => [{"label" => "l", "path" => "/screenshots/not-there.png", "alt" => "a"}]
      )
      allow(described_class).to receive(:projects).and_return([described_class.normalize_project(raw)])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /is not a file under public\//)
    end

    it "rejects a screenshot hosted somewhere else" do
      raw = project_hash("trap").merge(
        "screenshots" => [{"label" => "l", "path" => "https://example.com/x.png", "alt" => "a"}]
      )
      allow(described_class).to receive(:projects).and_return([described_class.normalize_project(raw)])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /path must start with \//)
    end

    it "rejects a screenshot with no alt text" do
      raw = project_hash("trap").merge(
        "screenshots" => [{"label" => "l", "path" => "/screenshots/webcap.png", "alt" => ""}]
      )
      allow(described_class).to receive(:projects).and_return([described_class.normalize_project(raw)])

      expect { described_class.validate! }
        .to raise_error(described_class::Error, /screenshot is missing alt/)
    end

    it "finds a project by slug" do
      expect(described_class.project("webcap")["title"]).to eq("Webcap")
    end

    it "returns nil for a slug that does not exist" do
      expect(described_class.project("nope")).to be_nil
    end
  end

  describe ".posts" do
    it "is sorted newest first" do
      dates = described_class.posts.map(&:date)
      expect(dates).to eq(dates.sort.reverse)
    end

    it "gives every post a slug, a title, a summary and a body" do
      described_class.posts.each do |post|
        expect(post.slug).to match(/\A[a-z0-9-]+\z/)
        expect(post.title).not_to be_empty
        expect(post.summary).not_to be_empty
        expect(post.body).not_to be_empty
        expect(post.date).to be_a(Date)
      end
    end

    it "excludes drafts by default and includes them on request" do
      allow(described_class).to receive(:raw_posts).and_return(
        [
          described_class::Post.new(slug: "live", title: "Live", date: Date.today,
            summary: "s", tags: [], draft: false, body: "b"),
          described_class::Post.new(slug: "hidden", title: "Hidden", date: Date.today,
            summary: "s", tags: [], draft: true, body: "b")
        ]
      )

      expect(described_class.posts.map(&:slug)).to eq(["live"])
      expect(described_class.posts(include_drafts: true).map(&:slug)).to contain_exactly("live", "hidden")
    end

    it "renders markdown to HTML" do
      expect(described_class.posts.first.html).to include("<p>")
    end
  end

  describe ".experience" do
    it "is in reverse-chronological order, starting with the current period" do
      roles = described_class.experience

      expect(roles.first["current"]).to be(true)
      expect(roles.first["period"]).to match(/present/i)
    end

    it "gives every role a title, company and period" do
      described_class.experience.each do |role|
        expect(role["title"]).not_to be_empty
        expect(role["company"]).not_to be_empty
        expect(role["period"]).not_to be_empty
      end
    end

    # Four entries whose dates interleaved with clixifix, with the overlap
    # explained by a one-line note on the page. One employer is one entry; the
    # phases are what the note was trying to say, so they are what this pins —
    # including the engagement type, which is per phase and not per entry: two
    # contracts, then a full-time return.
    it "presents the City Electrical Factors work as one entry, typed by phase" do
      roles = described_class.experience.select { |role| role["company"] == "City Electrical Factors" }
      phases = roles.first["highlights"].select { |item| item.start_with?("Phase") }

      expect(roles.length).to eq(1)
      expect(roles.first["period"]).to include("contract, then full time")
      expect(phases.length).to eq(3)
      expect(phases[0]).to include("(contract)")
      expect(phases[1]).to include("(contract)")
      expect(phases[2]).to include("(full time)")
    end

    # The project list was repeated here as well as under Work, which put four
    # projects in front of the Rails history and let /about disagree with /work
    # about what had shipped.
    it "keeps the career break to its summary and defers the projects to /work" do
      brk = described_class.experience.first

      expect(brk["highlights"]).to be_empty
      expect(brk["link"]["path"]).to eq("/work")
    end

    it "links the Rails upgrade work to the post that writes it up" do
      cef = described_class.experience.find { |role| role["company"] == "City Electrical Factors" }

      expect(cef["link"]["path"]).to eq("/blog/upgrading-a-production-rails-application")
    end
  end

  # A project record in the shape `normalize_project` reads: raw scalars,
  # before normalisation. The failure cases that exercise the loader's own
  # coercion go through this one, so a bad list entry is refused for the
  # reason a real content file would be.
  def project_hash(slug, highlights: [], stack: [])
    {
      "slug" => slug,
      "title" => slug.capitalize,
      "status" => "live",
      "section" => "main",
      "tagline" => "tagline",
      "summary" => "summary",
      "year" => "2026",
      "featured" => true,
      "highlights" => highlights,
      "notes" => "",
      "stack" => stack,
      "links" => []
    }
  end

  # A project record shaped like the loader's output, for the failure cases
  # above. Building it here rather than from a fixture file keeps the failure
  # mode explicit: this is a project that could not have come out of
  # normalisation, which is the point.
  def project(slug, status: "live", featured: true, links: [], section: "main")
    {
      "slug" => slug,
      "title" => slug.capitalize,
      "status" => status,
      "section" => section,
      "tagline" => "tagline",
      "summary" => "summary",
      "year" => "2026",
      "featured" => featured,
      "highlights" => [],
      "notes" => "",
      "stack" => [],
      "links" => links,
      # `validate!` iterates these two, so a hand-built record has to carry them
      # as well as a normalised one does.
      "screenshots" => [],
      "demo" => nil
    }
  end
end
