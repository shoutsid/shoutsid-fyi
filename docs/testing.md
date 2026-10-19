# Testing

The project has one gate and two outer checks. The gate is `bin/site check`;
the outer checks are `bin/site verify` and `bin/site links`, which need a
running site and the network respectively.

## The gate

```bash
bin/site check
```

`check` runs three things in one invocation:

1. **Environment round-trip** — every `.env` key the CLI reads is compared
   against the raw file byte for byte. This exists because a parser bug once
   shortened a base64 tunnel token by one character, and the only symptom was
   `cloudflared` refusing to start.
2. **StandardRB** — the linter, with no configuration file.
3. **RSpec** — the full suite.

Lint and the suite share one boot, and lint runs first, so a style failure does
not wait on the tests. A change is not finished until `check` passes.

## Where it runs

`check`, `test` and `lint` choose a runtime:

| Runtime | Condition | Notes |
|---|---|---|
| Host | The host Ruby is exactly the `Gemfile` version and `bundle check` passes | Prints `host Ruby <version> — no container` |
| Container | Anything else, or `--docker` | Uses the dev image with the working tree mounted read-only |

The host path exists because the suite takes under a second while a container
start has been measured at anything from 2 to 288 seconds on the same machine.
The container path is the reproducible one and needs no host Ruby.

Force the choice with `--host` or `--docker`. `--rebuild` forces a dev image
rebuild; `--no-build` trusts the image present.

### The dev image and the mount

The dev image carries the Ruby toolchain and the locked gems, and deliberately
**no source**. `check`, `test`, `lint` and `shell` mount the working tree over
`/app`, read-only for the suite. Editing a template, spec or post does not
invalidate the image.

The image is rebuilt only when its build inputs change — `Dockerfile`,
`Gemfile`, `Gemfile.lock`, `.dockerignore` — hashed into `.dev-image-digest`.
On Docker Desktop the project directory must be on the file-sharing list.

## Test layers

| File | What it covers |
|---|---|
| `spec/app_spec.rb` | Routes and rendered responses: every page, project, post, feed, sitemap, health endpoint, 404 and security headers; escaping; section order on both pages |
| `spec/content_spec.rb` | Content loading and validation, including the failure cases: unknown status, duplicate slug, no featured project, wrong section, bad link, missing figure, post with no summary |
| `spec/site_integrity_spec.rb` | Whole-site integrity: internal links, assets, titles, descriptions, canonical URLs, template prose, cache policy, digest correctness, palette contrast, no leaked template syntax |
| `spec/harness_spec.rb` | The test arrangement itself: the dev image has no source, the runtime image does, every code-running command uses one mount, an empty run cannot pass, the link checker is documented, the version has one source, the suite reads UTF-8 |

`spec/spec_helper.rb` sets `RACK_ENV=test` **before** requiring the app, so
boot-time content validation is skipped and deliberately broken content can be
constructed in tests. The suite drives the app through Rack with `rack-test`,
so it never binds a socket and never depends on a free port.

## What the integrity tests enforce

These are the invariants worth knowing before changing content or templates:

- Every internal link found on every rendered page resolves.
- Every asset the layout references is served.
- Every page has a title, a meta description and a canonical URL.
- Every project's `status` is in `Content::STATUSES`; the badge label, tooltip
  and callout style all derive from it.
- Slugs are unique across projects and across posts.
- At least one project is featured, one is live, one is public and one is
  research; the homepage has sections that render nothing if those disappear.
- Every post has a title, a summary and a non-empty body; posts sort newest
  first.
- Every case-study figure exists on disk.
- Every response declares a cache policy, and the digest in the layout is the
  digest of the file on disk.
- Every text colour clears WCAG AA (4.5:1) on every surface it is used on, in
  both themes, and the two dark palettes are byte-for-byte identical.
- No template contains a literal run of six or more words.
- No rendered page leaks `<%` or `%>` from a broken ERB comment.
- `/healthz` reports the content actually loaded.

## The harness guards

Three guards exist because the arrangement can fail in a way that looks like
success:

1. **No mount, no run.** With no source in the image, a failed mount leaves an
   empty `/app`. `bin/site` refuses to start unless `/app/app.rb` is present.
2. **No examples is not a pass.** `rspec` with no spec files exits 0 reporting
   "0 examples, 0 failures". `spec_helper` sets `fail_if_no_examples`.
3. **The host path sets a UTF-8 locale.** The container pins `LANG=C.UTF-8`;
   the content layer depends on it, and under US-ASCII the em dashes in
   `config/experience.yml` raise "invalid byte sequence in US-ASCII". `bin/site`
   sets the locale, and `harness_spec` asserts the encoding.

## Verification beyond the suite

```bash
bin/site verify [--local|--public]
bin/site links
```

`verify` is the only check that exercises a real socket, the container and the
tunnel. It requests:

```text
/  /about  /work  /blog  /contact  /cv  /healthz
/sitemap.xml  /blog/feed.xml  /robots.txt  /llms.txt
```

and one path that must return 404. It also asserts that the homepage names
James Summerill, because a 200 with an empty body is the failure a status code
alone cannot catch.

`links` extracts every `http(s)://` URL from `config/` and `content/`, dedupes
them, and probes each one with a `GET` (some hosts answer 405 to `HEAD`). It
needs the network, which is why it is a subcommand rather than a step in
`check`. A dead link on a live project is a claim the rest of the suite cannot
see.

## Adding a test

- Put route-level tests in `spec/app_spec.rb`, content/validation tests in
  `spec/content_spec.rb`, and site-wide invariants in
  `spec/site_integrity_spec.rb`.
- `rack-test` helpers (`get`, `last_response`) are included globally.
- Content is memoised. If a test changes files or stubs the loader, call
  `ShoutsidFyi::Content.reset!` between examples.
- A test that only checks a file's text should say which file and which rule,
  so the failure names the fix.
- Do not weaken a guard to make a test pass. The harness tests describe the
  arrangement that makes the other tests trustworthy.

## Style

Ruby files use [StandardRB](https://github.com/standardrb/standard). There is no
style configuration file on purpose: a style argument is not worth a diff, and
an unconfigurable linter cannot drift.

```bash
bin/site lint                 # whole project
bin/site lint lib/content.rb  # one file
```

## Continuous integration

The project has no hosted CI configuration in the repository. A CI job needs
only:

```bash
ruby 3.3.12
bundle install
bin/site check --host
```

`--host` makes the runtime explicit and fails if the pinned Ruby or the locked
gems are missing, rather than silently falling back to a container. If a job
touches `config/puma.rb`, the Dockerfile or the Compose files, it should also
build and run the site:

```bash
bin/site setup
bin/site build
bin/site up --no-tunnel
bin/site verify
```

`verify` is the step that catches a container that builds but does not serve.

## Common failures

| Symptom | Cause | Fix |
|---|---|---|
| `0 examples, 0 failures` | The working tree was not mounted | Check Docker file sharing; the runner should have refused with a message first |
| `invalid byte sequence in US-ASCII` | No UTF-8 locale on the host path | Use `bin/site check`, which sets it, or `LANG=C.UTF-8 bundle exec rspec` |
| `config: ... does not round-trip` | `.env` parsing changed or a value contains an unsupported form | Compare the key's length in `.env` and in the CLI; the usual cause is a dropped trailing `=` |
| `check` took minutes and named a container | The host Ruby was missing, the wrong version or missing gems | `bundle install`, or use `--host` to see the exact failure |
| A template-prose test fails | A sentence was written into a view | Move it to `config/pages.yml` and render it with `page_copy` |

See [Troubleshooting](troubleshooting.md) for runtime and deployment issues.
