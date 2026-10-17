---
title: How this site is built
date: 2026-10-11
summary: >
  A Sinatra app with its content in YAML, shipped in a pinned, unprivileged,
  read-only container and published through a Cloudflare tunnel. The short
  version of why each of those was the boring choice.
tags: [sinatra, docker, cloudflare]
---

This is a portfolio, so it has no login, no database and no write path. Every
page is a GET over data committed to the repository. Given that, the
interesting decisions are not about features — they are about making the thing
cheap to run and hard to get subtly wrong.

## Content is data, not markup

Everything the site says about me lives in `config/*.yml` and `content/blog/*.md`.
The templates read records; they do not contain claims.

That sounds like ceremony for a personal site, and for one page it would be. It
earns its place once the same project appears in three places — a homepage
card, the work index, and its own page — and the badge that says **Research**
must not say **Live** on one of them. The status is written once, in one file,
and the label, the caveat underneath it and the styling all derive from it. The
suite then refuses to start on a project whose status is not in the known set,
which is the part that actually prevents the mistake: a typo in a status string
is a build failure, not a blank card nobody notices for a month.

## A container that cannot surprise you

The image is built in two stages: one installs gems, the other copies them onto
a clean base. The runtime layer runs as a non-root user, has a read-only root
filesystem with `tmpfs` for `/tmp`, drops all Linux capabilities, and carries
its own `HEALTHCHECK` so the check cannot drift away from the image that is
supposed to satisfy it.

Two of those matter more than they look. A read-only root filesystem turns
"the app quietly started writing to disk" from a slow surprise into an immediate,
loud failure — for a site whose entire job is to render text, nothing should be
writing anything. And pinning the base image by digest means a rebuild next
month is the same image, rather than whatever `ruby:3.3-slim` happens to point
at that day.

## One way in

The host port is bound to loopback. The only public path is a Cloudflare
Tunnel, run as its own container in the same compose file, holding a single
scoped token and nothing else. There is no inbound port open, no certificate to
renew and no reverse proxy to configure — which is the whole reason the tunnel
is there rather than a VM with nginx and certbot.

## A CLI rather than a wiki page

Deployment is `bin/site`, which has one subcommand per thing I actually do:
`build`, `up`, `deploy`, `logs`, `health`, `verify`, `check`, `tunnel`. The
point is not convenience — it is that the deploy command in my shell history
and the one in the README are the same command, so the documented steps cannot
be the ones that stopped working.

The one-time edge setup is separate, because it needs a Cloudflare API token
and only ever runs once: `bin/cf-setup.sh` creates the tunnel, writes its
ingress rules, creates the DNS records for the apex and `www`, and puts the
token in `.env`. Everything else is repeatable without it.
