# Security policy

## Supported versions

The only supported version is the one currently deployed at
<https://shoutsid.fyi>. The repository does not maintain release branches.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Email **jsummerill.ltd@gmail.com** with the subject line
`SECURITY: shoutsid.fyi`.

Include:

- what the issue is and where it is;
- the steps to reproduce it;
- the impact you believe it has;
- any logs, requests or screenshots that help (redact secrets);
- how you would like to be credited, if at all.

You will receive an acknowledgement as soon as practical, normally within five
working days. This is a personal project rather than a staffed product, so
timelines are best effort; you will be told if a fix is going to take longer
than that.

Please give a reasonable window to investigate and deploy a fix before
disclosing the issue publicly. There is no bug bounty.

## Scope

In scope:

- the application in this repository;
- the deployed site at `shoutsid.fyi` and `www.shoutsid.fyi`;
- the container, Compose and CLI configuration in this repository.

Out of scope:

- Cloudflare's own infrastructure and services;
- other projects on other hostnames (for example `webcap.shoutsid.fyi` and
  `agents.shoutsid.fyi`), which have their own repositories and policies;
- findings that require a compromised host, a compromised Docker daemon or
  physical access;
- missing security headers that are already set (check the response first);
- automated scanner output without a demonstrated impact.

## Security posture

The design reduces the attack surface rather than relying on a web application
firewall:

- **No write path.** There is no database, no session, no login, no file upload
  and no user-submitted text.
- **No inbound port.** The container binds to loopback; the public edge is an
  outbound Cloudflare Tunnel.
- **Unprivileged runtime.** The app runs as uid 10001 with no shell and no home
  directory.
- **Read-only root filesystem.** The only writable path is a 16 MB `tmpfs` for
  `/tmp`.
- **No capabilities.** All capabilities are dropped and `no-new-privileges` is
  set.
- **Strict headers.** Every generated page carries a restrictive CSP,
  `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, a referrer policy
  and a permissions policy.
- **No secrets in layers.** `.env` is excluded from the Docker build context and
  reaches the container through `env_file`.
- **Pinned base images.** Ruby and `cloudflared` are pinned by digest.
- **Content is reviewed input.** Markdown is committed to this repository and
  reviewed like code; no user-supplied content is rendered.

## What to expect

- Acknowledged: normally within five working days.
- Assessment: whether the report is in scope and what the impact is.
- Fix: deployed to the live site, with a note in the repository where useful.
- Credit: offered unless you prefer otherwise.

Thank you for reporting privately.
