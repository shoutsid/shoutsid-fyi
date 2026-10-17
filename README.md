# shoutsid.fyi

The portfolio site for James Summerill — Ruby on Rails and backend systems,
with independent work in local AI and model-training research.

A Sinatra app with its content in YAML and Markdown, shipped in a pinned,
unprivileged, read-only container, published through a Cloudflare Tunnel.

- **Live:** <https://shoutsid.fyi>
- **Stack:** Ruby 3.3, Sinatra 4, Puma, Kramdown — no database, no write path
- **Public edge:** a dedicated Cloudflare Tunnel; the app's port is bound to
  loopback and is not reachable from the network directly

---

## Requirements

Nothing but Docker. Ruby is **not** required on the host — a machine with no
Ruby at all runs everything in a container.

On this machine the tests do not start a container: `check`, `test` and `lint`
run on the host Ruby when it matches the `Gemfile` pin and the locked gems are
installed, and that is the fast path — see
[Optional: a host Ruby](#optional-a-host-ruby-for-speed) below. The container is
the fallback for when it does not, and it is where `shell` and `dev` always run.
A run says which it used: `host Ruby <version> — no container` is the host path.

File sharing matters only on the container path. There the dev image carries no
source and the working tree is mounted over `/app`, so the project directory has
to be on Docker Desktop's file-sharing list (**Settings → Resources → File
sharing**). `build`, `up`, `verify` and `deploy` mount nothing at all.

| Tool | Version | Why |
|---|---|---|
| Docker Engine / Desktop | with the `compose` plugin | builds and runs everything |
| `curl`, `python3` | any recent | used by `bin/site verify` and `bin/cf-setup.sh` |
| A Cloudflare API token | once only | to create the tunnel and DNS records |
| Ruby (optional) | the version `Gemfile` pins | makes `check` about 2s instead of Docker-dependent |

### Optional: a host Ruby, for speed

`check`, `test` and `lint` use the host Ruby when it is the version the `Gemfile`
pins and the locked gems are installed, and a container otherwise. Both paths run
the same suite; the host one skips a container start that has been measured on
this machine at anything from 2 to 288 seconds.

```bash
# RVM, which is what this machine uses. libyaml is built into ~/.rvm/usr first
# because the content layer is YAML and psych needs its C extension.
rvm pkg install libyaml
rvm install 3.3.12 --with-libyaml-dir="$HOME/.rvm/usr"
bundle install
```

None of this is required, and none of it is taken on faith: the version is read
from the `Gemfile` rather than assumed, `bundle check` has to pass, and any
difference falls back to the container. `build`, `up`, `verify` and `deploy`
never read the working tree and need neither a host Ruby nor file sharing.

---

## Quick start

```bash
git clone <this repo> shoutsid-fyi
cd shoutsid-fyi

bin/site setup          # creates .env from .env.example
bin/site build          # builds the production image
bin/site up --no-tunnel # starts the site on http://127.0.0.1:3010
bin/site verify         # checks every page actually renders
bin/site check          # linter + full test suite
```

That is the whole local loop. `--no-tunnel` is the default for `up`, so no
Cloudflare credentials are needed to run or test the site.

### Why port 3010

Inside the container the app always listens on **3000**. On the host it is
published on **3010** (`HOST_PORT` in `.env`), because this machine already
runs Gitea on 3000 and `docker compose up` failing with "port is already
allocated" is a poor first-run experience. Change `HOST_PORT` if 3010 is taken.

---

## Deploying to shoutsid.fyi

The public edge is a Cloudflare Tunnel. The app is never exposed directly, so
there is no inbound port to open, no certificate to renew and no reverse proxy
to keep patched.

### 1. One-time: provision the tunnel (needs a Cloudflare API token)

Create a custom API token at **Cloudflare dashboard → My Profile → API Tokens →
Create Custom Token** with exactly these permissions:

| Scope | Permission |
|---|---|
| Account | Cloudflare Tunnel | Edit |
| Zone | DNS | Edit |
| Zone | Zone | Read |

`shoutsid.fyi` must already be delegated to Cloudflare (its nameservers are
`liv.ns.cloudflare.com` and `pablo.ns.cloudflare.com`).

```bash
CF_API_TOKEN=<token> bin/site cf-setup           # dry run first if you like:
CF_API_TOKEN=<token> bin/site cf-setup --dry-run
```

This is idempotent and safe to re-run. It:

1. verifies the token and resolves the zone and account;
2. creates a dedicated tunnel named `shoutsid-fyi` (or reuses it);
3. sets the tunnel's remotely-managed ingress for `shoutsid.fyi` and
   `www.shoutsid.fyi`, forwarding to `http://web:3000` on the compose network;
4. creates proxied CNAME records for the apex and `www` pointing at
   `<tunnel-id>.cfargotunnel.com`;
5. writes `CF_TUNNEL_TOKEN` into `.env` (mode 600).

**Why a dedicated tunnel rather than a hostname on the existing `webcap`
tunnel:** `webcap.shoutsid.fyi` is served by a tunnel run from the host under
its own cron watchdog. Joining it would make this site's uptime a function of
that project's process. One tunnel per site means one site's watchdog cannot
take the other down.

### 2. Every deploy

```bash
bin/site deploy
```

Builds the image, starts the site and the tunnel, waits for the container's own
healthcheck, then verifies every page locally and again through
`https://shoutsid.fyi`. If the public check does not pass within 60 seconds it
says so and leaves the local site running — a newly created DNS record can take
a few minutes to resolve.

Other ways in:

```bash
bin/site deploy --no-build     # restart without rebuilding
bin/site deploy --no-tunnel    # local only
bin/site tunnel status         # is the tunnel container up, and what is it saying?
bin/site tunnel logs           # follow the tunnel
```

---

## CLI reference

`bin/site help` prints this too.

| Command | What it does |
|---|---|
| `setup` | Copies `.env.example` to `.env` (mode 600). Safe to re-run; never overwrites. |
| `cf-setup` | One-time Cloudflare tunnel + DNS provisioning. Needs `CF_API_TOKEN`. |
| `lock` | Regenerates `Gemfile.lock` in a container and copies it out. |
| `build [--no-cache]` | Builds the production image. |
| `up [--tunnel\|--no-tunnel] [--build]` | Starts the site, optionally with the tunnel. |
| `down [--volumes]` | Stops the stack. |
| `restart` | Restarts and waits for health. |
| `ps` / `logs [service]` | Container status and logs. |
| `deploy [--no-tunnel] [--no-build]` | Build → start → health → verify local and public. |
| `tunnel up\|down\|restart\|logs\|status` | Manages the `cloudflared` container alone. |
| `health` | Prints the app's `/healthz` response. |
| `verify [--local\|--public]` | Every page must be 200, a bad path must be 404, and the homepage must name the subject. |
| `check` | **The gate:** `standardrb` plus the whole RSpec suite, as one invocation. |
| `test [args]` / `lint [args]` | The suite or the linter alone. |
| `shell` | A shell in the dev image, over the mounted working tree. |
| `dev` | Live-reload server (a writable mount; same file-sharing requirement). |

`check`, `test` and `lint` take `--host` or `--docker` to force where they run,
and `--rebuild` / `--no-build` to control the dev image.
| `version` | Prints the site name and `APP_VERSION`. |

---

## Architecture

```
.
├── app.rb                  Sinatra app: routes, helpers, error handlers
├── config.ru               Rack entrypoint
├── lib/
│   ├── content.rb          loads and validates all content (the only reader of config/)
│   └── markdown.rb         the one Kramdown configuration
├── config/
│   ├── profile.yml         identity, links, principles
│   ├── projects.yml        every project card and case study
│   ├── experience.yml      roles, education, skills
│   ├── pages.yml           page and section prose
│   └── puma.rb             server configuration
├── content/blog/*.md       posts, YAML front matter + Markdown
├── views/                  ERB templates (layout, pages, partials, errors)
├── public/                 CSS, JS, favicon, robots.txt, llms.txt
│   ├── og.png              the social preview image, checked at boot
│   ├── screenshots/        captures of the running services
│   └── diagrams/           authored drawings, labelled as drawings
├── spec/                   RSpec: routes, content invariants, site integrity
├── bin/
│   ├── site                the CLI
│   ├── cf-setup.sh         Cloudflare provisioning
│   └── healthcheck.rb      container healthcheck
├── Dockerfile              base / lock / dev / build / runtime stages
├── docker-compose.yml      the site (+ an optional dev service)
└── docker-compose.tunnel.yml   the Cloudflare Tunnel overlay
```

### Content is data

Everything the site says lives in `config/*.yml` and `content/blog/*.md`.
Templates read records; they do not contain claims — including the sentences
that describe a section, which live in `config/pages.yml` and are rendered
through `page_copy`. `spec/site_integrity_spec.rb` fails on a template that
carries a literal run of six or more words, so the rule is enforced rather
than merely intended.

That one is worth stating plainly, because the intention alone did not hold.
Eight templates carried prose of their own, and the homepage advertised "a
deployed service and two public engineering projects" for a while after a
third repository was added — a sentence describing the content was in no
position to be checked against it.

This matters for one specific reason: the same project appears on the homepage,
in the work index and on its own page, and the badge that says **Research** must
not say **Live** on one of them. The status is written once, and the badge
label, the caveat under it and the callout styling all derive from that one
value. `lib/content.rb` also refuses to load an unknown status, so the mistake
is a startup failure rather than a blank card nobody notices.

Adding a project means editing `config/projects.yml` — there is no template to
touch:

```yaml
- slug: my-project
  title: My project
  status: live          # live | public | research | in-progress
  featured: true
  year: "2026"
  tagline: One line.
  summary: >
    A paragraph.
  highlights:
    - What it does.
  notes: >
    Status and caveats, rendered in a callout.
  stack: [Ruby, Postgres]
  links:
    - label: GitHub
      url: https://github.com/...
```

Both of the following are optional, and both are about giving a reader
something to inspect rather than another paragraph. A figure is a claim, so a
capture must come from the running service, a drawing must say it is a drawing,
and the loader refuses to boot if the file is not on disk:

```yaml
  screenshots:
    - label: The landing page, captured from the running service.
      path: /screenshots/my-project.png
      alt: "The landing page: a headline, a curl example and a pricing table."

  demo:
    title: The endpoint, called live
    request: curl "https://my-project.example/v1/thing"
    response: |-
      200 {"ok":true,"version":"1"}
```

The homepage's "Selected work" grid and `/work`'s first grid are the *same*
group, read from one field on each project:

```yaml
- slug: webcap
  section: main        # main | systems | archive
```

`main` is the curated first grid on both pages, `systems` is the "Research and
Experimental Systems" section, and `archive` is "More projects". One field
rather than a separate ordering list, because a second list is exactly how the
two pages drifted apart once: the homepage led with Rails while `/work` had
four projects ahead of it, so the same project read as prominent on one page and
incidental on the other. A section nobody renders, or a content file with
nothing in `main`, is a boot failure rather than a card that silently never
appears. Order within a section is file order, so `config/projects.yml` is kept
grouped by section, each group in the order it should render.

### Docker

- **Pinned by digest.** `ruby:3.3-slim@sha256:…` and
  `cloudflare/cloudflared@latest@sha256:…`. A rebuild in six months is the same
  image, not whatever the tag happens to point at.
- **Multi-stage.** The compiler that builds Puma's extension is in the build
  stage, not the runtime layer. The runtime image has no `gcc`.
- **Unprivileged.** Runs as uid 10001 with no shell and no home directory.
- **Read-only root filesystem** with a 16 MB `tmpfs` for `/tmp`; all
  capabilities dropped and `no-new-privileges` set. The app writes nothing, so
  any attempt to write is an immediate, loud failure.
- **Healthcheck in the image**, not in Compose, so it cannot drift from the
  image it describes. `bin/healthcheck.rb` asks `/healthz`, which reads the
  same content store the pages read.

### Why the tunnel is a separate Compose file

`docker-compose.tunnel.yml` is layered on only when the tunnel is wanted:

```bash
docker compose -f docker-compose.yml \
               -f docker-compose.tunnel.yml up -d
```

Its `CF_TUNNEL_TOKEN` is marked required (`:?`), so Compose refuses to start the
tunnel without one instead of launching something that cannot connect. Keeping
that in an overlay rather than the base file means the hard failure does not
also block `docker compose build`, `bin/site check` or any local command before
the tunnel has been provisioned.

### Security headers

Every response carries a strict CSP (`default-src 'self'`, `script-src 'self'`,
`frame-ancestors 'none'`), `X-Content-Type-Options`, `X-Frame-Options` and a
referrer policy. Because the CSP allows no inline scripts, the theme is set by
an external `/js/theme-boot.js` — loaded before the stylesheet so the first
paint is already in the right palette.

---

## Content and editorial rules

Claims on this site must be evidence-based. The rules are in
[`docs/editorial.md`](docs/editorial.md); the short version:

- Lead with software engineering; AI is a differentiator, not the whole identity.
- Mark every project **Live**, **Public repo**, **Research** or **In progress**.
- No usage, revenue or benchmark numbers unless they are reproducible and
  published here.
- Give each major project something to inspect: a capture of the running
  service, a diagram of the architecture, or a command and the output it
  actually produced. If a run also failed, the failure is published with it.
- Personal circumstances behind the career break are not published; the
  technical work during it is.

## Testing

```bash
bin/site check     # config round-trip + lint + full suite
bin/site test      # suite only
bin/site lint      # standardrb only
```

The suite's example count is deliberately not quoted here. It was, and it went
stale twice in one afternoon: a number in prose is one more thing to keep in
step with the code, and the copy that goes stale is the one a reader trusts.

`check`, `test` and `lint` run against the working tree: on the host when a
matching Ruby is installed, otherwise in a container with the tree bind-mounted
read-only over `/app`. `shell` is always the container, over that same mount.
Which one is used, and why, is under
[Optional: a host Ruby](#optional-a-host-ruby-for-speed) above.

The dev image holds the Ruby toolchain and the locked gems and nothing else, so
editing a template, a spec or a post invalidates nothing and triggers no
rebuild. Only the build inputs — `Dockerfile`, `Gemfile`, `Gemfile.lock`,
`.dockerignore` — are hashed into `.dev-image-digest`, and only a change there
forces a build. `--rebuild` forces one anyway, `--no-build` trusts the image
already present.

Lint and the suite run as a single invocation, so they share one boot. Lint runs
first, so a style failure does not wait on the tests. `--host` and `--docker`
force where they run.

Two guards exist because this arrangement can fail in a way that looks like
success. With no source in the image, a run that failed to mount sees an empty
`/app` — and `rspec` with no spec files exits 0 reporting "0 examples, 0
failures". `bin/site` refuses to run unless `/app/app.rb` is present, and
`spec_helper` sets `fail_if_no_examples`, so a suite that ran nothing fails
instead of passing without having tested anything.

A third guard covers the host path. The container pins `LANG=C.UTF-8` and the
content layer depends on it — under Ruby's US-ASCII default the em dashes in
`config/experience.yml` raise "invalid byte sequence in US-ASCII" and 35
examples fail with nothing pointing at the cause. `bin/site` sets the locale
whenever the caller's is not already UTF-8, and `harness_spec` asserts the
encoding so the next person sees the reason rather than 35 reds.

`check` first compares every `.env` key the CLI reads against the file itself
(a parser that silently mangles a secret is otherwise only visible as a
`cloudflared` that will not start). It then runs the suite, which covers four
things:

- **Routes** — every page, every project, every post, plus 404s, the Atom feed,
  the sitemap, `/healthz` and the security headers.
- **Content invariants** — the same checks the app makes at boot, driven
  directly, including the failure cases (unknown status, duplicate slug, no
  featured project, a link that is not a URL, a post with no summary).
- **Site integrity** — every internal link found on every page resolves, every
  asset the layout references is served, every page has a title, a description
  and a canonical URL, and no page leaks template syntax or comment text into
  its rendered output. That last one exists because a truncated ERB comment
  did exactly that while every other test passed.
- **The harness** — that the dev image is built from the gems and no source,
  that every command which runs code goes through the one mount, and that a run
  which collected no examples cannot exit 0. These describe the arrangement that
  runs the other three, and each of them failed as a *green run* before it was
  fixed — which is why they are asserted rather than trusted.

Ruby files use [standard](https://github.com/standardrb/standard); there is no
style configuration file, deliberately.

---

## Troubleshooting

**`port is already allocated` on `bin/site up`** — something on the host owns
`HOST_PORT`. Find it (`ss -ltnp | grep :3010`) and change `HOST_PORT` in `.env`.

**A new page 404s after a deploy** — the production image bakes in the source,
so a stale image runs stale content. `bin/site build` (or `bin/site deploy`,
which builds first).

**The public URL does not answer** — the local site being healthy means the
problem is the edge:

```bash
bin/site tunnel status
bin/site tunnel logs
```

A newly created DNS record can take a few minutes to resolve. Verify the
records with `dig +short shoutsid.fyi` and `dig +short www.shoutsid.fyi`; both
should return Cloudflare addresses.

**`bin/site shell`, `bin/site dev`, or a `check|test|lint` run that fell back to
the container cannot see the working tree** — the container path bind-mounts the
project directory over `/app`, and Docker Desktop only mounts directories on its
file-sharing list. Add it in **Docker Desktop → Settings → Resources → File
sharing** and restart Docker. The host path mounts nothing, and the production
path (`build`, `up`, `verify`, `deploy`) mounts nothing and is unaffected.

**`check` took minutes and said nothing about a container** — it chose the
container because the host Ruby was missing, the wrong version, or without the
locked gems. `bin/site check` prints `host Ruby <version> — no container` when it
uses the host, so the absence of that line is the explanation. Run
`bundle install`, or see [Optional: a host Ruby](#optional-a-host-ruby-for-speed).

**`invalid byte sequence in US-ASCII` from `lib/content.rb`** — Ruby is reading
the content as US-ASCII because no UTF-8 locale is set. The container pins
`LANG=C.UTF-8`; `bin/site` sets it for the host path, so this only appears when
rspec is run directly from a shell without one. Run `LANG=C.UTF-8 bundle exec
rspec` to confirm.

**Ruby is not installed on this host** — by design. `bin/site check` runs the
suite in the dev image; `bin/site shell` gives you a prompt in it.
