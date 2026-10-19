# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) for its
`APP_VERSION` value.

## Unreleased

### Added

- A complete documentation set under `docs/`: getting started, configuration,
  architecture, content authoring, deployment, testing, troubleshooting and a
  documentation index.
- Repository policies: contributing guide, security policy, code of conduct,
  changelog, license and GitHub issue/PR templates.
- A rewritten README oriented around the project's design principles, quick
  start, command reference and documentation map.

### Changed

- Documentation now separates the project overview from long-form reference
  material, so the README can be read in a few minutes and the detail remains
  available where it is needed.
- The license is stated explicitly as all rights reserved.

## 0.1.0 — 2026-10-17

### Added

- Sinatra application with content-driven routes for the homepage, About, Work,
  project case studies, blog, contact and a generated CV.
- YAML content store for profile, projects, experience and page copy, validated
  at boot.
- Markdown blog with YAML front matter, tags, drafts, reading time and an Atom
  feed.
- Project case studies with status badges, stack lists, screenshots/diagrams and
  reproducible demo blocks.
- Sitemap, `robots.txt`, `llms.txt`, canonical URLs, Open Graph metadata and a
  social preview image.
- Digest-versioned assets with a conditional cache policy.
- Strict security headers, including a restrictive Content Security Policy.
- Multi-stage Dockerfile with pinned base images, a non-root runtime, a
  read-only root filesystem and an in-image healthcheck.
- Docker Compose stack with an optional Cloudflare Tunnel overlay.
- `bin/site` CLI for setup, build, run, deploy, tunnel management, health,
  HTTP verification and external link checking.
- RSpec suite covering routes, content invariants, site integrity and the test
  harness, with StandardRB as the linter.
- Host/container runtime selection for the test suite, with a dev image that
  carries gems and no source.
