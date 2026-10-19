# Troubleshooting

Start with the command that names the failing layer:

```bash
bin/site check          # code, content and configuration
bin/site health         # the app's own view of itself
bin/site verify         # real HTTP through the app
bin/site tunnel status  # the public edge
bin/site links          # somebody else's service
```

## Local runtime

### `port is already allocated` on `bin/site up`

Something on the host owns `HOST_PORT` (default 3010). Find it and either stop
it or change the port:

```bash
ss -ltnp | grep :3010
# edit HOST_PORT in .env, then:
bin/site up --no-tunnel
```

The container-internal port is always 3000; only the published port changes.

### `check`, `shell` or `dev` cannot see the working tree

The container path mounts the project directory over `/app`; the dev image
contains no source. Docker Desktop only mounts directories on its file-sharing
list.

Add the project in **Docker Desktop → Settings → Resources → File sharing** and
restart Docker. Restarting Docker restarts every container on the machine,
including other projects' tunnels, so do it when that is acceptable.

The production path (`build`, `up`, `verify`, `deploy`) mounts nothing and is
unaffected.

### `check` took minutes and said it was using a container

It chose the container because the host Ruby was missing, the wrong version, or
missing the locked gems. The run prints a warning naming the Ruby it wanted.

```bash
bundle install
# or force the diagnosis:
bin/site check --host
```

A host run should print `host Ruby 3.3.12 — no container`. Its absence is the
explanation for the slower path.

### `invalid byte sequence in US-ASCII` from `lib/content.rb`

Ruby is reading content as US-ASCII because no UTF-8 locale is set. The
container pins `LANG=C.UTF-8`; `bin/site` sets it for the host path. This
normally appears only when `rspec` is run directly:

```bash
LANG=C.UTF-8 bundle exec rspec
```

### The dev image keeps rebuilding

It should rebuild only when `Dockerfile`, `Gemfile`, `Gemfile.lock` or
`.dockerignore` changes. Those inputs are hashed into `.dev-image-digest`.
Editing source, specs or content does not invalidate anything.

Use `--rebuild` to force a build and `--no-build` to trust the image present.

### The suite reports `0 examples, 0 failures`

That is not a pass. It means the run found no specs, usually because the
working tree was not mounted. The CLI has a guard for this and should fail with
a message about `/app/app.rb`; `spec_helper` also sets `fail_if_no_examples`.

If you see the message without the guard, run `bin/site check` rather than
calling `rspec` directly, and check Docker file sharing.

## Content

### A content file stops the container at boot

That is deliberate. `lib/content.rb` validates the whole store and names the
file and record:

```text
config/projects.yml: my-project has unknown status "shipping" (known: live, public, research, in-progress)
```

Fix the value; do not move the check into a request.

### A list item renders as `{"some key"=>"some value"}`

An unquoted `: ` inside a YAML list item turned it into a mapping. Quote the
entry:

```yaml
highlights:
  - "Verification is executable: two services run beside the miner."
```

The loader rejects this at boot now, so the hash should never reach a page.

### A screenshot or diagram is missing

A `screenshots` entry needs `label`, `path` and `alt`, and `path` must name a
real file under `public/`:

```yaml
screenshots:
  - label: The landing page, captured from the running service.
    path: /screenshots/my-project.png
    alt: "A description of what the figure shows."
```

A figure that 404s is treated as a content bug, not a missing image.

### A project is not on the homepage

Check `section`. The homepage and `/work` render `main`, `systems` and
`archive` from that one field. A project with a section nobody renders is a boot
failure; a project in `archive` renders in the last group, not the first.

### A post 404s or the feed is empty

- The filename must be `YYYY-MM-DD-slug.md`.
- Front matter must be delimited by `---` and include `title` and `summary`.
- `draft: true` hides a post from production and the feed, but it still has to
  validate.
- The feed route is declared before `/blog/:slug`; if you add routes, keep
  `/blog/feed.xml` first.

## Deployment

### A new page or post 404s after a deploy

The production image bakes in the source, so a stale image runs stale content.
Rebuild:

```bash
bin/site build
# or:
bin/site deploy
```

### The public URL does not answer

If the local site is healthy, the problem is the edge:

```bash
bin/site tunnel status
bin/site tunnel logs
bin/site verify --local
```

Check DNS:

```bash
dig +short shoutsid.fyi
dig +short www.shoutsid.fyi
```

Both should return Cloudflare addresses. A newly created record can take a few
minutes to resolve.

### The tunnel will not start

The overlay marks `CF_TUNNEL_TOKEN` required, so Compose refuses to launch a
tunnel without one. The CLI checks first and names the fix:

```bash
CF_API_TOKEN=<token> bin/site cf-setup   # provision or rewrite the token
# or run without the tunnel:
bin/site up --no-tunnel
```

If the token is present but `cloudflared` rejects it, re-run `cf-setup` to fetch
a fresh token. Do not hand-edit or trim it: a base64 token can end in `=`, and
the CLI preserves the whole value.

### Every other request returns 502

Suspect a second `cloudflared` registered against the same tunnel. Requests are
load-balanced across all connectors, so one bad connector produces intermittent
failures rather than a total outage — it can look like flakiness, a race or a
slow app.

Check the tunnel's connections:

```text
GET /accounts/{account_id}/cfd_tunnel/{tunnel_id}/connections
```

Exactly one is correct. A stopped connector lingers until Cloudflare's
heartbeat timeout, so confirm the count drops to one rather than assuming
`docker rm` was enough.

### The container is unhealthy

```bash
bin/site ps
bin/site logs web
bin/site health
```

`/healthz` reports the version and the number of projects and posts it can
read. If it cannot read the content store, the container is unhealthy by
design rather than serving empty pages.

### `deploy` succeeds locally but the public check times out

This is usually DNS propagation rather than the app:

- `bin/site health` and `bin/site verify --local` already passed.
- `bin/site tunnel status` shows the connector.
- `dig` shows the proxied CNAME.
- Retry `bin/site verify --public` after a few minutes.

`deploy` deliberately leaves the local site running in this case.

## Security and headers

### A strict CSP blocks an inline script or style

The policy allows no inline scripts or styles. Put JavaScript in `public/js/`
and load it with `asset_path`, and keep styles in `public/css/site.css`. The
theme boot script is external for this reason and is loaded before the
stylesheet so the first paint is correct.

### Assets are cached for a year after a change

Only URLs carrying the **current** digest get the immutable policy. The layout
builds those URLs with `asset_path`; a file edited on disk changes its digest
and therefore its URL. A URL with a stale or missing digest revalidates.

If a stale asset persists at the same URL, check that the page is using
`asset_path` rather than a hard-coded path.

## For maintainers

Two failure modes are worth remembering because they look like something else:

- **Never pipe `curl` straight into `grep -q` in a health check.** `grep -q`
  exits at the first match and closes the pipe with the body still in flight;
  `curl` then fails with `(23) Failure writing output to destination`, which is
  reported as the content check failing. It is invisible over loopback and
  reproducible through the tunnel. Buffer the body, then match it.
- **A green run that tested nothing is the failure mode to guard against.**
  Empty `/app`, no spec files and `rspec` exits 0. The mount guard and
  `fail_if_no_examples` exist for that one outcome; do not remove either to
  simplify a script.

## Collecting diagnostics

For a bug report, include:

```bash
bin/site version
bin/site ps
bin/site health
bin/site check
```

and, for an edge problem, `bin/site tunnel status` with the log lines. Redact
`CF_TUNNEL_TOKEN`, `CF_API_TOKEN` and any value from `.env` before posting.
