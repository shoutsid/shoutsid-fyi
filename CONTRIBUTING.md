# Contributing

Thanks for taking the time to look at this repository.

`shoutsid.fyi` is a personal portfolio and blog. It is **source-available, not
open source**: the code and content are published for inspection, and all
rights are reserved. That shapes what contributions are useful.

## What is welcome

- **Corrections to factual claims** — a project description, a date, a role, a
  link or a technical statement that is wrong.
- **Broken links** — especially a URL that has rotted since it was published.
- **Accessibility issues** — keyboard navigation, contrast, semantics, reduced
  motion, screen-reader output.
- **Bugs** in the application, the CLI, the container setup or the
  documentation.
- **Security reports** — privately, following [SECURITY.md](SECURITY.md). Do
  not open a public issue for a vulnerability.

## What is not solicited

- Feature pull requests that add a CMS, comments, analytics, a JavaScript
  framework, a database or a contact form. The site's constraints are
  deliberate; see [Architecture](docs/architecture.md).
- Rewrites of the visual design or the copy.
- Content that conflicts with [Editorial rules](docs/editorial.md), including
  usage numbers, revenue figures, benchmarks or adjectives such as
  "production-grade".
- Dependency updates without a reason tied to a bug, a security advisory or a
  maintained runtime.

If you are unsure whether something is in scope, open an issue with the
question before writing code.

## Before you open an issue

1. Read the [documentation index](docs/README.md), especially
   [Troubleshooting](docs/troubleshooting.md).
2. Search existing issues.
3. For a bug, collect the output of:

   ```bash
   bin/site version
   bin/site check
   ```

   and, if the problem is at the edge, `bin/site tunnel status`.

Redact `CF_TUNNEL_TOKEN`, `CF_API_TOKEN` and every value from `.env` before
posting. Never paste a tunnel token into an issue.

## Development setup

The short version:

```bash
bin/site setup
bin/site build
bin/site up --no-tunnel
bin/site verify
bin/site check
```

Ruby is optional on the host. If a matching Ruby 3.3.12 with the locked gems is
installed, `check`, `test` and `lint` run on it; otherwise they run in the dev
container. See [Getting started](docs/getting-started.md).

## The gate

Every change must pass:

```bash
bin/site check
```

That runs the environment round-trip, StandardRB and the full RSpec suite. If
the change touches `config/puma.rb`, the Dockerfile or a Compose file, also run:

```bash
bin/site build
bin/site up --no-tunnel
bin/site verify
```

The suite never binds a socket, so only `verify` proves the container serves the
site. For an external link change, run `bin/site links` as well.

## Content changes

Content is data, not markup. Read [Content authoring](docs/content.md) for the
schema and [Editorial rules](docs/editorial.md) for what may be claimed.

In particular:

- A project's `status` is a claim, not a label of convenience.
- A figure must come from the running service or be labelled as a drawing.
- A demo is a command and the output it actually produced.
- A claim that cannot be reproduced, or pointed at, is rewritten or removed.

## Pull requests

A good pull request:

- addresses one problem;
- explains **why** the change is needed, not only what changed;
- includes a test when the change fixes a bug or adds an invariant;
- keeps the existing structure, naming and comment style;
- passes `bin/site check`;
- does not add a dependency without a reason in the description.

Use the pull request template. Small, focused changes are easier to review than
a mixed cleanup.

### By submitting a contribution

You confirm that:

- you have the right to submit the work; and
- you grant James Summerill a perpetual, worldwide, non-exclusive, royalty-free
  licence to use, modify, distribute and sublicense the contribution as part of
  this repository, under the terms in [LICENSE](LICENSE).

Do not submit code, images or text you do not have the right to contribute.

## Style

Ruby uses [StandardRB](https://github.com/standardrb/standard); there is no
style configuration file. Bash and YAML follow the conventions already in the
repository: comments explain a decision that is not obvious, and a guard exists
because the failure it prevents is real.

Documentation uses plain Markdown, one sentence per line where practical, and
links rather than duplicated explanations.

## Code of conduct

Participation is covered by the [Code of Conduct](CODE_OF_CONDUCT.md). Be
direct about the work and courteous to the person.
