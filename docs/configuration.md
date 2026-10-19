# Configuration

Configuration is deliberately small: one `.env` file on the host, environment
variables passed through Compose, and a handful of settings read by the app and
the CLI.

## The `.env` file

`.env.example` is the template and is tracked. `.env` is local, is created by
`bin/site setup`, is written with mode `600`, and is listed in `.gitignore` and
`.dockerignore`. It must never be committed or copied into an image layer.

```bash
bin/site setup   # copies .env.example to .env, never overwriting
```

### How `bin/site` reads it

`bin/site` does not source `.env`. Sourcing would execute arbitrary code from
the file and export every variable it contains. Instead it reads the file line
by line and exports an **allowlist** of keys:

```text
HOST_PORT  DEV_PORT  PUBLIC_URL  APP_VERSION  PUMA_THREADS  CF_TUNNEL_TOKEN  CF_ZONE
```

A key not on that list is invisible to every subcommand, no matter what the file
says. Add new keys to both `.env.example` and the list in `load_env`.

Values are split on the **first** `=` only, and the remainder is kept verbatim.
This matters for base64 tunnel tokens: `IFS='=' read -r key value` strips a
trailing delimiter, which silently shortened a token ending in `=`. The
`check` command's environment round-trip compares every allowlisted key present
in the file against the raw value byte for byte and fails on any drift. It
prints lengths, never values.

## Variables

### Host and runtime

| Variable | Default | Used by | Purpose |
|---|---|---|---|
| `HOST_PORT` | `3010` | Compose, `bin/site` | Host loopback port for the production container. Inside the container the app is always on 3000. |
| `DEV_PORT` | `3011` | Compose, `bin/site dev` | Host loopback port for the development server. |
| `APP_VERSION` | `0.1.0` | App, `bin/site version` | The version reported by `/healthz` and printed by the CLI. One value, read from the environment. |
| `PUBLIC_URL` | `https://shoutsid.fyi` | `bin/site deploy\|verify` | The public origin checked by `deploy` and `verify --public`. Optional; not present in `.env.example`. |
| `PUMA_THREADS` | `5` | `config/puma.rb` | Puma thread count in the container. |
| `WEB_CONCURRENCY` | `0` | `config/puma.rb` | Puma worker count. `0` keeps a single process; a positive value enables preloading. |
| `PORT` | `3000` | `config/puma.rb` | Container-internal listening port, set by Compose. Do not publish this. |
| `RACK_ENV` | `production` | App, Compose | Runtime environment. Compose sets `production` for `web` and `development` for `dev`. |

### Cloudflare

| Variable | Required | Purpose |
|---|---|---|
| `CF_TUNNEL_TOKEN` | For tunnel deploys | The remotely-managed tunnel credential. Written by `bin/cf-setup.sh`; stored only in `.env`. The tunnel overlay marks it required, so Compose refuses to start the tunnel without it. |
| `CF_API_TOKEN` | `cf-setup` only | A scoped Cloudflare API token used **once** to create the tunnel and DNS records. It is not written to `.env` and is not available to the container. |
| `CF_ZONE` | No | Zone name used by `cf-setup`; defaults to `shoutsid.fyi`. Also allowlisted in `bin/site`. |
| `CF_TUNNEL_NAME` | No | Tunnel name used by `cf-setup`; defaults to `shoutsid-fyi`. |
| `CF_HOSTS` | No | Space-separated hostnames to serve; defaults to the apex and `www`. |
| `CF_ORIGIN` | No | Tunnel origin; defaults to `http://web:3000` on the Compose network. |

`CF_TUNNEL_TOKEN` is the only secret in `.env`. `CF_API_TOKEN` is an operator
credential for provisioning and should be short-lived or revoked after setup.

### Secret handling

- `.env` is created with mode `600` and is ignored by Git.
- `.env` is excluded from the Docker build context, so a `COPY` cannot pick it
  up.
- The running container receives variables through Compose `env_file`, not
  through a layer.
- The tunnel overlay contains the `:?` requirement, not the base Compose file.
  Compose interpolates a whole file before applying profiles; a required
  variable in the base file would break every command until the tunnel had been
  provisioned, including `docker compose build`.
- `bin/site` checks for the tunnel token itself and names the fix
  (`bin/site cf-setup` or `--no-tunnel`) instead of passing Compose's
  interpolation error through.

## Compose settings

`docker-compose.yml` sets the production runtime:

| Setting | Value | Reason |
|---|---|---|
| Published port | `127.0.0.1:${HOST_PORT}:3000` | Loopback only. The public path is the tunnel, never a published port. |
| Root filesystem | `read_only: true` | The app writes nothing; a write is a loud failure. |
| `/tmp` | `tmpfs`, 16 MB | The only writable path. |
| Capabilities | `cap_drop: [ALL]` | No capability the app needs. |
| Privileges | `no-new-privileges: true` | Prevents privilege gain through setuid binaries. |
| Memory | `256m` | A small, read-mostly site. |
| CPUs | `0.5` | Enough for template rendering; prevents runaway use. |
| Restart policy | `unless-stopped` | Survives a host reboot. |
| Logging | 10 MB × 3 files | Bounded logs; an unbounded log is a slow disk-full outage. |

The `dev` service is behind the `dev` profile and is not part of a normal
deploy. It publishes `127.0.0.1:${DEV_PORT}:3000` and runs Puma with
`RACK_ENV=development`.

## Application settings

### Puma

`config/puma.rb` reads `PORT`, `RACK_ENV`, `PUMA_THREADS` and
`WEB_CONCURRENCY`. It does not configure a pidfile or log file: the container
is the unit of lifecycle, logs go to stdout, and the root filesystem is
read-only.

**Do not call both `port` and `bind`.** `port` already binds `0.0.0.0`; a second
`bind "tcp://0.0.0.0:3000"` is a second listener on the same socket and Puma
dies at startup with `EADDRINUSE`. The test suite cannot see this because
`rack-test` never binds a socket.

### Version

`APP_VERSION` is read once, in `app.rb`, and reported by `/healthz`. The
deployment value comes from `.env`; the same fallback default appears in
`app.rb`, `bin/site` and `.env.example`, and `spec/harness_spec.rb` fails if
those three disagree.

To ship a new version, update `.env` (the deployed value) and `.env.example`
(what a new checkout gets). If the fallback itself changes, update `app.rb` and
`bin/site` with it.

### Content validation

The app validates its content store at boot in every environment except `test`.
The suite sets `RACK_ENV=test` so it can construct deliberately broken content
and assert on `Content.validate!` directly. Do not move that validation into a
request.

## Changing the hostname or zone

`cf-setup` reads `CF_ZONE`, `CF_TUNNEL_NAME`, `CF_HOSTS` and `CF_ORIGIN` from
the environment. For a different site:

```bash
CF_ZONE=example.com \
CF_TUNNEL_NAME=example-fyi \
CF_HOSTS="example.com www.example.com" \
CF_API_TOKEN=<token> \
bin/site cf-setup --dry-run
```

Run it once with `--dry-run` to inspect the planned tunnel, ingress and DNS
changes, then without it to apply them. Update `PUBLIC_URL` in `.env` and the
site URL in `config/profile.yml` if the public origin changes; the sitemap,
feed, canonical URLs and social metadata derive from the profile.
