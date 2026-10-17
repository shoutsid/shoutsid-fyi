# Working on shoutsid-fyi

A Sinatra portfolio site with its content in YAML and Markdown, deployed in a
hardened container behind a Cloudflare Tunnel. Read this before changing
anything: most of the traps below cost a container restart to discover, and two
of them shipped as live bugs before they were found.

## The gate

```bash
bin/site check                   # config round-trip + lint + full suite
bin/site test spec/app_spec.rb   # one file; args go straight to rspec
bin/site lint                    # standardrb only
bin/site verify                  # every page 200, bad path 404, over real HTTP
bin/site links                   # every external URL in config/ still resolves
bin/site build && bin/site up --no-tunnel && bin/site verify
```

`check` is the contract. Never report a change as done without it. It runs
against the working tree rather than a copy of it, so it always tests what is on
disk.

**No Docker is involved in that path.** `check|test|lint` run on the host Ruby
whenever it matches the Gemfile pin and has the locked gems, and on this machine
that is every run: no image build, no mount, no daemon. The dev image is the
fallback for a machine without that Ruby, not the way these commands run. Read
the run's own line — `host Ruby <version> — no container` means the fast path,
and its absence is the only case where the container is worth thinking about.

`verify` is the one that catches what the suite cannot: the suite drives the app
through Rack and therefore never binds a socket, opens a real port or runs the
container's own healthcheck. Run it after any change to `config/puma.rb`, the
Dockerfile or the compose files.

`links` is the same idea one step further out: it probes every external URL in
`config/` and `content/`, which is the one class of claim nothing else here
checks. `verify` can only see this site and the suite has no network, so a link
to somebody else's service is invisible to both — a card marked `live`
advertised API docs at a path that service has never served, and every other
check passed while it 404ed. It needs the network, which is why it is a
subcommand rather than a step inside `check`.

The runtime is chosen rather than configured: `check|test|lint` use the host
Ruby when it is the version the Gemfile pins and the locked gems are installed,
and a container otherwise. `--host` and `--docker` force the choice. Ruby is
still not *required* on the host — the container path is the fallback and needs
nothing installed — but installing `ruby 3.3.12` (this machine uses RVM) and
running `bundle install` once turns a multi-minute, Docker-dependent wait into
about two seconds. See the trap about the runtime.

## Where things live

| Path | Responsibility |
|---|---|
| `app.rb` | Routes, helpers, error handlers, security headers. Thin by design: it reads content and renders it. |
| `lib/content.rb` | The only reader of `config/*.yml` and `content/blog/`. Normalises every record and defines `validate!`. |
| `lib/markdown.rb` | The one Kramdown configuration. |
| `lib/cache_policy.rb` | The one `Cache-Control` policy, applied as middleware. It cannot be a `before` filter — see the trap about static files. |
| `config/*.yml` | All prose and all claims, including page and section copy in `pages.yml`. Templates must not contain any — `site_integrity_spec.rb` fails on a literal run of six or more words in a template. |
| `views/` | ERB. `layout.erb` plus one template per route, partials under `partials/`. |
| `public/` | CSS, JS, favicon, `robots.txt`, `llms.txt`, the social preview `og.png`, and the case-study figures: `screenshots/` for captures of the running services, `diagrams/` for authored drawings. Served directly, no asset pipeline. |
| `spec/` | Routes, content invariants, whole-site integrity, response headers and the contrast of the palette. |
| `bin/site` | The CLI. Every documented operation is a subcommand; nothing is documented as "run X then Y". |
| `bin/cf-setup.sh` | One-time Cloudflare tunnel and DNS provisioning. |
| `bin/healthcheck.rb` | The container healthcheck, referenced by the Dockerfile. |
| `docker-compose.yml` | The site, and an optional `dev` service. |
| `docker-compose.tunnel.yml` | The `cloudflared` overlay. |

## Invariants the tests enforce

- **Every project's `status` is in `Content::STATUSES`.** The badge label, the
  tooltip and the callout style all derive from it, so an unknown status is a
  startup failure, not a fallback badge.
- **Slugs are unique** across projects and across posts.
- **At least one project is `featured`**, and at least one project is `live`,
  one is `public` and one is `research` — the homepage has sections that render
  nothing if those disappear.
- **Every link in `config/` resolves.** Profile links are absolute (`https?://`
  or `mailto:`); links to pages on this site are root-relative and must start
  with `/`. `validate!` checks both at boot, and `site_integrity_spec` follows
  every one of them — which is why the optional `link` on an experience role is
  a path rather than a URL. A link meant to open the evidence should not be able
  to send the reader off the site.
- **Every post has a title, a summary and a non-empty body**, and posts are
  sorted newest first.
- **Every internal link on every page resolves**, and every asset the layout
  references is served. This is the test that catches a deleted route or a
  renamed stylesheet.
- **Every response declares a cache policy.** A digest-versioned asset URL is
  answered `public, immutable, max-age=31536000`; the same file at its
  unversioned path revalidates, because Sinatra's static server ignores the
  query string and that URL does not identify its content; the other files under
  `public/` get an hour; generated responses — pages, the feed, the sitemap,
  `/healthz` — revalidate. `site_integrity_spec.rb` asserts each class, and that
  the digest in the layout is the digest of the file on disk.
- **Every text colour clears WCAG AA (4.5:1)** on every surface it is used on, in
  both themes, and the two dark palettes — the stored-theme attribute and the
  no-JavaScript media query — are byte-for-byte the same map. Computed from the
  tokens in `site_integrity_spec.rb`, so a palette edit has to clear the bar
  rather than be trusted. `--text-faint` measured 3.08:1 before this existed, on
  the small mono labels and post dates it is used for.
- **`/healthz` reports the content it can actually read** — the number of
  projects and posts must match the loaded content, so an empty content store
  cannot be reported as healthy.
- **Every page has a title, a meta description and a canonical URL.**
- **Every case-study figure exists on disk.** A `screenshots` entry carries a
  `label`, a `path` under `public/` and a non-empty `alt`; `lib/content.rb`
  refuses to boot if the file is not there, and `site_integrity_spec.rb`
  re-checks it from the rendered page. A figure that 404s is worse here than a
  broken image elsewhere, because it is the part of the page a reader is
  supposed to be able to check for themselves.
- **Templates carry no prose of their own.** The sentences describing a
  section live in `config/pages.yml` and are rendered with `page_copy`. This
  is checked, because the intention alone did not hold: eight templates had
  prose in them, and the homepage went on advertising "two public engineering
  projects" after a third was added.
- **Escaping is on.** `spec/app_spec.rb` renders "Languages & frameworks" from
  the toolkit and asserts `Languages &amp; frameworks`, which is the canary that
  proves the template engine is escaping.
- **One grouping, so the two pages cannot disagree.** `section` on each project
  is `main`, `systems` or `archive`; the homepage and `/work` both render those
  three from `Content.projects_in_section`, and a project with a section nobody
  renders — or a content file with nothing in `main` — is a boot failure rather
  than a card that silently never appears. There is deliberately no second
  ordering list: a separate `homepage_order` is how the pages drifted, with
  Rails second on the homepage and fifth on `/work`. Order within a section is
  file order, so `config/projects.yml` is kept grouped by section and each
  group in the order it should render. `spec/content_spec.rb` covers the
  grouping and the validation, `spec/app_spec.rb` pins the order both pages
  actually render, and the two must agree — a reorder of the file moved Rails
  once, which is why the position is pinned rather than left to a comment.
- **Raw output is deliberate and narrow.** `<%== %>` appears in exactly three
  places: `views/layout.erb` for `yield` and the two partials, and
  `views/post.erb` for rendered Markdown. Everywhere else uses `<%= %>`, which
  escapes. Adding a fourth is a decision, not a convenience.

## Traps that cost real time

- **An ERB comment ends at the FIRST closing delimiter it contains, so a
  comment may never quote the tag syntax.** Writing
  `<%# ... the escaped-output tag, `<%= %>` ... %>` truncates the comment at the
  nested delimiter and renders the remainder of the sentence as visible page
  text. It shipped that way once. Describe tags in prose; never write the
  delimiter characters inside a comment. `spec/site_integrity_spec.rb` now
  walks every page asserting the body contains no `<%` or `%>`, which is the
  check that was missing — the page was a healthy 200 with the right content
  and a sentence of Ruby comment in the middle of it.
- **Both theme icons live in the markup; CSS does the swapping.** The toggle
  shows the theme it will switch *to* (moon in light, sun in dark). Because the
  swap is pure CSS, it is correct at first paint and with JavaScript disabled —
  so if you add an icon, add its `prefers-color-scheme` rule too, or the
  no-JavaScript case falls back to showing both.
- **`erubi` must stay in the Gemfile, or escaping silently stops working.**
  Sinatra depends on Tilt, and Tilt only registers `Tilt::ErubiTemplate` when
  `erubi` can be loaded — otherwise it falls back to stdlib ERB. That fallback
  changes two things without any error: `set :erb, escape: true` stops escaping
  anything, and `<%== %>` becomes a *compile* error (`unexpected '='`) rather
  than raw output. Both were live bugs here. If templates start rendering
  unescaped, check `Tilt["erb"]` before anything else.
- **An asset is served before the `before` filters run, so a filter cannot set a
  header on one.** Sinatra's `dispatch!` calls `static!` first and the served
  file halts, which means a header set in `before` lands on every page and no
  asset — the exact wrong half, and invisibly, because both answer 200 either
  way. That is how this site shipped with no `Cache-Control` on its CSS at all
  while Cloudflare supplied four hours of its own, and why the policy lives in
  middleware (`lib/cache_policy.rb`) instead. `set :static_cache_control` is the
  other hook, but it takes one fixed value and this policy is conditional on the
  digest in the URL. (`X-Content-Type-Options` does reach assets — that comes
  from `Rack::Protection`, which is also middleware.)
- **The escaping option is `escape`, not `escape_html`.** Tilt passes template
  options straight to `Erubi::Engine`, whose option is `escape`. `escape_html`
  is accepted and ignored.
- **`config/puma.rb` must not call both `port` and `bind`.** `port` already
  binds `0.0.0.0`, so an additional `bind "tcp://0.0.0.0:3000"` is a second
  listener on the same socket and Puma dies at startup with `EADDRINUSE`. The
  suite cannot see this — rack-test never binds — so it only appears when the
  container runs.
- **`input: "GFM"` needs the `kramdown-parser-gfm` gem.** It is a separate gem,
  and without it the *first request to a post* raises "kramdown has no parser to
  handle the specified input format: GFM" — a 500 on every post page, not a
  silent fallback to plain Markdown.
- **A required variable (`:?`) belongs in the tunnel overlay, not the base
  compose file.** Compose interpolates the whole file before applying profiles,
  so a `:?` on `CF_TUNNEL_TOKEN` in `docker-compose.yml` makes *every* command
  fail until the tunnel is provisioned — including `docker compose build` and
  `bin/site check`. `bin/site` additionally checks the token itself so the error
  names the fix rather than showing an interpolation message.
- **On the container path the dev image carries the gems and no source.**
  `shell`, `dev`, and any `check|test|lint` run that fell back to the container
  or was forced with `--docker`, bind-mount the working tree over `/app`, so
  what runs is what is on disk and editing source can never require a rebuild.
  The image is rebuilt only when its build inputs change — `Dockerfile`,
  `Gemfile`, `Gemfile.lock`, `.dockerignore`, hashed into `.dev-image-digest` —
  and `--rebuild` forces one, `--no-build` trusts the image present.
  Baking the source in made every edit invalidate a layer, so each edit bought
  either a rebuild or a suite testing a tree that no longer existed. Removing
  the source removes the choice; do not put a `COPY . .` back into the `dev`
  stage. The mount is required rather than an optimisation, which is why the
  container path needs Docker Desktop's file sharing — and why the host path,
  which mounts nothing and builds nothing, needs none of it.

  This listing `check|test|lint` as commands that use the dev image is what made
  a run of `check` look like it had to be containerised. It does not: on the
  host Ruby there is no image in the picture at all. The distinction is worth
  keeping straight, because reaching for `--docker` to "make it real" is the
  opposite of what a fast, equivalent runtime is for.
- **A run that did not mount the tree must not look like a pass.** `rspec`
  exits 0 printing "0 examples, 0 failures" — which is exactly what an empty
  `/app` produces, and with no source in the image there is nothing to fall
  back on. So `bin/site` refuses to start unless `/app/app.rb` exists, and
  `spec_helper` sets `fail_if_no_examples`. Both exist for this one failure
  mode; neither is redundant with the other.
- **`check` runs the linter and the suite as one invocation.** Two invocations
  cost two starts and two bundler boots, and the second proved nothing the first
  had not. Lint still runs first, so a style failure does not wait on the tests.
  Expect one timing line, `Lint and test`, not two.
- **The container start is the slow part, which is why a host runtime exists.**
  The suite does about 0.7s of work and the linter about 1.2s. Starting a
  container for it has been measured on this machine at 2s, 23s, 39s, 135s and
  288s for the same image — the variance is Docker's, not the project's. So
  `check|test|lint` prefer a host Ruby that matches the Gemfile pin exactly and
  has the locked gems (`bundle check`), and fall back to the container on any
  difference. The version is read from the Gemfile rather than assumed, because
  a host Ruby that differs from the container's is a second environment quietly
  pretending to be the first.
- **`bin/site` sets RVM's paths; it must not source `~/.rvm/scripts/rvm`.**
  Sourcing it installs `cd` hooks that are not `set -u` clean, and a hook that
  fails takes the `bundle check` probe down with it — which reads as "no host
  Ruby here", so every run quietly chose the container while appearing to have
  made a considered decision. Setting the bin and gem paths is the whole of what
  is needed and cannot fail that way.
- **The host runtime must set a UTF-8 locale.** The Dockerfile sets
  `LANG=C.UTF-8` and the app depends on it: `lib/content.rb` matches UTF-8
  content with a regex, and under Ruby's US-ASCII default the em dashes in
  `config/experience.yml` raise "invalid byte sequence in US-ASCII". Without the
  locale, 35 examples fail on the host that pass in the container — so `bin/site`
  sets it whenever the caller's locale is not already UTF-8, and `harness_spec`
  asserts the encoding so the next person sees the cause rather than 35 reds.
- **The production path must never bind-mount the working tree.** `web` uses
  named volumes and `env_file` (read by the host CLI), so `bin/site
  build|up|verify|deploy` works even where the project directory is not shared
  with Docker. `shell`, `dev` and any container-path `check|test|lint` do mount
  it, and so do need file sharing — but a bind mount added to the deploy path
  would make `bin/site deploy` fail on exactly the machines that cannot mount.
- **`.env` is in `.dockerignore`.** Secrets reach the container through
  `env_file`, never through a layer. If you add a `COPY` that could pick up
  `.env`, stop.
- **Content validation runs at boot in every environment except `test`.** The
  suite sets `RACK_ENV=test` so it can build deliberately broken content and
  assert on `validate!` directly. Do not move that check into a request.
- **`GET /blog/feed.xml` must be declared before `GET /blog/:slug`.**
  Sinatra matches in declaration order, so a `:slug` route registered first
  swallows `feed.xml` and serves a 404 for the feed.
- **The blog lives at `/blog`.** It was called `/writing` and the directory
  `content/writing/`; both were renamed. A test asserts the old path 404s, so a
  half-finished rename fails rather than leaving two live URLs for one section.
  `Post#url`, the nav label, the feed's `<id>` and self-link, the sitemap, the
  layout's alternate link and `bin/site verify` all derive from that route and
  must move together.
- **`HOST_PORT` defaults to 3010, not 3000.** This host runs Gitea on 3000. The
  container-internal port is always 3000; only the published port differs.
- **`load_env` must not split `.env` with `IFS='=' read -r key value`.** Bash
  strips a trailing delimiter, so a base64 tunnel token ending in `=` came back
  one character short — 180 chars in `.env`, 179 exported. Everything upstream
  looked correct (valid token, right scopes, right account) and `cloudflared`
  simply refused to start, with nothing in any log pointing at the value. Read
  the whole line and split with `${line%%=*}` / `${line#*=}` instead.
  `verify_env_roundtrip` in `bin/site check` now compares every key the CLI
  reads against the file byte for byte and fails on any drift; it prints
  lengths, never values, because one of those keys is a secret.
- **A second `cloudflared` registered against the same tunnel breaks the site
  intermittently, not completely.** Requests are load-balanced across every
  connector, so a stray connector — a leftover `docker run` probe, say, sitting
  on the default `bridge` network where `web` does not resolve — produces roughly
  every other request 502ing while the good connector serves the rest. It looks
  like flakiness, a race or a slow app, and it is none of those. Check
  `GET /accounts/{acct}/cfd_tunnel/{id}/connections`: exactly one is correct.
  A stopped connector lingers there until Cloudflare's heartbeat timeout, so
  confirm the count drops to 1 rather than assuming `docker rm` was enough.
- **Never pipe `curl` straight into `grep -q` in a health check.** `grep -q`
  exits at the first match, closing the pipe with the body still in flight, and
  `curl` then fails with `(23) Failure writing output to destination` — reported
  as the content check failing, i.e. as the site being wrong. It is invisible
  over loopback, where the whole body arrives before `grep` can exit, and
  reproducible through the tunnel, which is the only place the check runs for
  real. Buffer the body first, then match it.

## Claims discipline

This is a portfolio whose entire argument is that its claims are evidence-based.
Before adding any prose, read `docs/editorial.md`. In short: no usage, revenue
or benchmark numbers that are not reproducible and published here; mark every
project with its status; and never describe the research project as though the
hypothesis had been demonstrated.

A figure is a claim too, so the same rule governs the case studies. A `demo`
block is a command and the output it actually produced — run, not quoted from a
project's own documentation — a capture is taken from the running service, and
a drawing is labelled as a drawing rather than as a screenshot. Where a run also
failed, the failure stays in rather than being trimmed to a clean number,
because a portfolio that publishes only its green runs is making the same claim
these projects exist to distrust.
