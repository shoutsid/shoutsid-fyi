# Getting started

This page takes a clean checkout to a running site and a passing gate. It also
lists every command the project exposes.

## Requirements

| Requirement | Notes |
|---|---|
| Docker Engine or Docker Desktop | With the Compose v2 plugin (`docker compose version` must work) |
| `curl` | Used by `verify`, `deploy` and the health checks |
| `python3` | Used by `bin/cf-setup.sh` to parse Cloudflare API responses |
| A Cloudflare API token | Only for the one-time tunnel setup; not needed for local work |
| Ruby 3.3.12 | Optional. Makes `check`, `test` and `lint` fast; the container is the fallback |

Nothing else is installed on the host, and Ruby is not required at all. The
suite runs in the dev image on a machine with no Ruby.

## First run

```bash
git clone https://github.com/shoutsid/shoutsid-fyi.git
cd shoutsid-fyi

bin/site setup          # copies .env.example to .env (mode 600)
bin/site build          # builds the production image
bin/site up --no-tunnel # starts the site on http://127.0.0.1:3010
bin/site verify         # every page must render, a bad path must 404
bin/site check          # StandardRB + the full RSpec suite
```

`bin/site setup` is safe to re-run: it never overwrites an existing `.env`.
`bin/site up` defaults to `--no-tunnel`, so no Cloudflare credentials are needed
for local development. The first `build` is the slow step; later builds reuse
the layer cache.

The site is then available at **<http://127.0.0.1:3010>**.

### Why the host port is 3010

Inside the container the app always listens on `3000`. On the host it is
published on `3010` by default because 3000 is commonly already occupied (this
machine runs Gitea there). `HOST_PORT` in `.env` changes it; the container port
does not move.

## The two runtimes

`check`, `test` and `lint` choose where to run:

| Runtime | When it is selected | What it needs |
|---|---|---|
| **Host** | The host Ruby is exactly the `Gemfile` version and `bundle check` passes | Ruby 3.3.12 and the locked gems |
| **Container** | Anything else, or `--docker` | Docker; the dev image; a mounted working tree |

A host run prints `host Ruby 3.3.12 — no container`. A fallback container run
prints a warning naming the Ruby it wanted and how to switch. Both run the same
suite.

### The fast host path

```bash
# RVM, which is what this machine uses. The content layer is YAML, so psych
# needs libyaml's C extension.
rvm pkg install libyaml
rvm install 3.3.12 --with-libyaml-dir="$HOME/.rvm/usr"
bundle install

bin/site check
```

Ruby is still not a requirement: any mismatch — version, gems, `bundle check` —
falls back to the container.

### The container path

The dev image contains the Ruby toolchain and the locked gems, and deliberately
**no source**. The working tree is mounted over `/app` at run time, so the code
under test is always the code on disk. Editing a template, spec or post never
invalidates the image.

On Docker Desktop the project directory must be on the file-sharing list
(**Settings → Resources → File sharing**). This affects `shell`, `dev` and any
`check|test|lint` run that uses the container. It does **not** affect `build`,
`up`, `verify` or `deploy`, which mount nothing.

The dev image is rebuilt only when its build inputs change: `Dockerfile`,
`Gemfile`, `Gemfile.lock` and `.dockerignore`, hashed into
`.dev-image-digest`. Use `--rebuild` to force a rebuild and `--no-build` to
trust the image already present.

## Development server

```bash
bin/site dev      # http://127.0.0.1:3011
```

`bin/site dev` runs Puma with `RACK_ENV=development` and a writable mount of the
working tree, so content edits take effect on the next request. It needs Docker
and file sharing; it is not part of the deploy path.

## Command reference

Run `bin/site help` for the same list on the command line.

### Setup

| Command | What it does |
|---|---|
| `help` | Prints the full command reference. |
| `setup` | Copies `.env.example` to `.env` (mode 600). Safe to re-run; never overwrites. |
| `cf-setup [--dry-run]` | One-time Cloudflare tunnel and DNS provisioning. Requires `CF_API_TOKEN`. |
| `lock` | Regenerates `Gemfile.lock` in a container and copies it out. |
| `version` | Prints the site name and `APP_VERSION`. |

### Build and run

| Command | What it does |
|---|---|
| `build [--no-cache]` | Builds the production image. |
| `up [--tunnel\|--no-tunnel] [--build]` | Starts the site, optionally with the tunnel, then waits for health. |
| `down [--volumes]` | Stops the stack. `--volumes` also removes named volumes. |
| `restart` | Restarts the running stack and waits for health. |
| `ps` | Shows container status. |
| `logs [service]` | Follows logs; `web` and `cloudflared` are the useful services. |
| `health` | Prints the app's `/healthz` response. |

### Deploy and edge

| Command | What it does |
|---|---|
| `deploy [--no-tunnel] [--no-build]` | Build, start, wait for health, verify locally, then verify publicly. |
| `tunnel up\|down\|restart\|logs\|status` | Manages the `cloudflared` container alone. |

### Verification

| Command | What it does |
|---|---|
| `verify [--local\|--public]` | Every page must return 200, a bad path must return 404, and the homepage must name James Summerill. |
| `links` | Probes every external URL in `config/` and `content/`. Requires the network. |
| `check [--host\|--docker] [--rebuild\|--no-build]` | **The gate:** environment round-trip, StandardRB and the full suite in one invocation. |
| `test [rspec args]` | Runs the suite. Arguments go straight to `rspec`. |
| `lint [standardrb args]` | Runs the linter. Arguments go straight to `standardrb`. |

`check`, `test` and `lint` all accept `--host`, `--docker`, `--rebuild` and
`--no-build`. See [Testing](testing.md#where-it-runs).

### Interactive

| Command | What it does |
|---|---|
| `shell` | A shell in the dev image, with the working tree mounted. |
| `dev` | Development Puma server with content and template reload on port 3011, with a writable mount. |

## What to run before calling a change finished

```bash
bin/site check
```

That is the contract. `check` runs:

1. an environment round-trip check, comparing every `.env` key the CLI reads
   against the file byte for byte;
2. `standardrb`;
3. the full RSpec suite.

Lint and the suite share one boot, and lint runs first, so a style failure does
not wait on the tests. If a change touches `config/puma.rb`, the Dockerfile or
the Compose files, also run:

```bash
bin/site build && bin/site up --no-tunnel && bin/site verify
```

The suite never binds a socket, so only `verify` proves the container actually
serves the site.

## Next steps

- [Configuration](configuration.md) — change ports, version, threads or the
  tunnel token.
- [Content authoring](content.md) — add a project or a post.
- [Architecture](architecture.md) — understand the request path.
- [Deployment](deployment.md) — publish it.
