# Content authoring

All substantive copy and every claim lives in `config/*.yml` and
`content/blog/*.md`. Templates contain no claims of their own. This page
documents the schema, the validation rules, and the evidence requirements for a
figure or a demo.

Before writing prose, read [Editorial rules](editorial.md). The rules are short
and they govern what may be claimed.

## Content map

| File | Contains | Rendered by |
|---|---|---|
| `config/profile.yml` | Identity, links, summary, availability, principles | Every page, contact, CV |
| `config/projects.yml` | Project cards and case studies | Homepage, `/work`, `/work/:slug`, CV |
| `config/experience.yml` | Roles, education, toolkit | `/about`, `/cv` |
| `config/pages.yml` | Page and section prose | Every page |
| `content/blog/*.md` | Posts | `/blog`, `/blog/:slug`, feed |

All of these are loaded through `lib/content.rb`. A malformed file is a boot
failure, not a missing section on a page.

## Validation

`Content.validate!` runs at boot in every environment except `test`. It raises
`ShoutsidFyi::Content::Error` with the file and record it came from, so a
content bug names the fix rather than surfacing as a blank card.

The suite runs the same validation and also asserts many of its failure cases
directly. The important rules:

- Required profile fields: `name`, `role`, `tagline`, `summary`, `seeking`, and
  a non-empty `links` list of `{label, url}`.
- Profile links must be absolute (`https?://` or `mailto:`).
- Project slugs are unique; post slugs are unique.
- Every project has `slug`, `title`, `tagline`, `summary`, a known `status` and
  a known `section`.
- At least one project has `featured: true`, and at least one project is in
  `main`.
- Project links must be `https?://`.
- A `demo` has non-empty `title`, `request` and `response`.
- A `screenshots` entry has `label`, `path` and `alt`; `path` starts with `/`
  and names a file under `public/`.
- Every required page-copy key exists and is non-empty.
- Every post has a `title`, `summary` and non-empty body.
- List entries are scalars. An unquoted `: ` inside a list item turns it into a
  mapping; the loader refuses it rather than letting a Ruby hash reach the page.

## `profile.yml`

| Key | Type | Purpose |
|---|---|---|
| `name` | string | Used in page titles and the homepage |
| `role` | string | Professional role |
| `tagline` | string | Short identity line |
| `headline` | string | The `<h1>` on the homepage |
| `location` | string | Full location |
| `short_location` | string | Dateline form |
| `email` | string | Contact address; also used by the CV |
| `summary` | string | Hero lede and About opener |
| `seeking` | string | Availability, rendered on the hero, contact page and CV |
| `links` | list | `{label, url}`, absolute; a `cv: false` entry is omitted from the printed CV contact line |
| `site` | map | `url`, `title`, `description`; canonical URLs, feed and social metadata derive from here |
| `principles` | list | `{title, body}` for "How I work" |

Adding a link means adding it to `profile.links`; validation rejects anything
that is not an absolute URL or `mailto:`.

## `projects.yml`

Each entry is one project. It appears as a card on the homepage and `/work`,
and as a case study at `/work/<slug>`.

| Key | Required | Type | Notes |
|---|---|---|---|
| `slug` | yes | string | Unique; the URL segment |
| `title` | yes | string | Card and page title |
| `status` | yes | enum | `live`, `public`, `research`, `in-progress` |
| `featured` | no | boolean | At least one project overall must be featured; a featured public project is included in the CV |
| `section` | yes | enum | `main`, `systems`, `archive` |
| `year` | no | string | Display year or range |
| `tagline` | yes | string | One-line card subtitle |
| `summary` | yes | string | Paragraph on the card and case study |
| `highlights` | no | list of strings | Capabilities or engineering facts |
| `notes` | no | string | Status and caveats, rendered in a callout |
| `stack` | no | list of strings | Technologies |
| `links` | no | list of `{label, url}` | Absolute URLs |
| `screenshots` | no | list | See below |
| `demo` | no | map | See below |

### Statuses

The label, the tooltip and the callout style all derive from `status`. An
unknown status is a boot failure, not a fallback badge.

| Status | Label | Meaning |
|---|---|---|
| `live` | Live | Deployed and publicly reachable at a URL you can visit |
| `public` | Public repo | Source on GitHub and readable |
| `research` | Research | Ongoing investigation with a stated hypothesis; not a demonstrated result |
| `in-progress` | In progress | Work exists; no demo yet |

Read [Editorial rules](editorial.md) before changing a status. "Research" is
never rendered beside a deployed service in the first grid, and its callout
repeats what has not been shown.

### Sections

`section` is the only grouping field. Both the homepage and `/work` render the
same three groups in the same order, and order within a group is file order.

| Section | Renders as | Intended content |
|---|---|---|
| `main` | Selected work (first grid) | Deployed services and public engineering repositories |
| `systems` | Systems work and ongoing research | Research and experimental systems |
| `archive` | More projects | Archived and in-progress work |

Keep `config/projects.yml` grouped by section, each group in the order it should
render. There is deliberately no second ordering list: a separate homepage
order is how the two pages drifted once.

### Screenshots and diagrams

A figure is a claim. A capture must come from the running service; a drawing
must be labelled as a drawing. Both live under `public/` and both carry a
caption and alt text.

```yaml
screenshots:
  - label: The landing page, captured from the running service.
    path: /screenshots/my-project.png
    alt: "The landing page: a headline, a curl example and a pricing table."
```

| Key | Meaning |
|---|---|
| `label` | The visible caption |
| `path` | Root-relative path under `public/` |
| `alt` | The description a reader who cannot see the figure gets |

`lib/content.rb` refuses to boot if the file is missing, and
`site_integrity_spec.rb` re-checks it from the rendered page.

### Demos

A demo is a command and the output it actually produced, run against the live
service or a clean build — not a quotation from another project's
documentation.

```yaml
demo:
  title: The endpoint, called live
  request: curl "https://my-project.example/v1/thing"
  response: |-
    200 {"ok":true,"version":"1"}
```

All three fields are required. If a run also failed, the failure stays in
rather than being trimmed to a clean number.

## `experience.yml`

### Roles

```yaml
roles:
  - title: Ruby on Rails Engineer
    company: Example Ltd
    period: October 2019 — October 2024
    location: County Durham, United Kingdom
    summary: >
      A paragraph describing the work and the scope.
    link:
      label: The upgrade path, written up on the blog
      path: /blog/upgrading-a-production-rails-application
    highlights:
      - "A concrete engineering fact."
    current: false
    personal: false
```

| Key | Notes |
|---|---|
| `title`, `company`, `period`, `location`, `summary` | Rendered as written |
| `link` | Optional `{label, path}`; `path` must start with `/`, because the link opens evidence on this site rather than sending the reader away |
| `highlights` | Optional list of strings; rendered in order |
| `current` | Marks the current entry |
| `personal` | Marks independent work rather than employment |

### Education and skills

```yaml
education:
  - qualification: BSc (Hons) Computer Science
    institution: Example University
    period: "2005 — 2008"

skills:
  - group: Languages & frameworks
    items: [Ruby, Rails, SQL]
```

`items` is a list of plain strings. Quote an entry containing `: `.

## `pages.yml`

Page and section copy is data. Templates render it through `page_copy`, which
is why a sentence describing the content can be checked against the content.

```yaml
shared:
  systems_note: >-
    A sentence used by both the homepage and the work index.
  more_note: >-
    Another shared note.

home:
  featured_note: >-
    A sentence for the first grid.
  experience_note: >-
    A sentence for the experience section.
  experience_link:
    label: Full history and how I work
    path: /about

work:
  description: >-
    Meta description for /work.
  intro: >-
    The page introduction.
```

Required keys are declared in `Content::PAGES_REQUIRED` and checked at boot.
`home.experience_link` must be `{label, path}` with a root-relative path.

The `errors` section holds the 404 and 500 copy. The `cv` section holds the
download label and the two project notes (screen and print).

## Blog posts

A post is a Markdown file in `content/blog/` named:

```text
YYYY-MM-DD-a-slug.md
```

The date in the filename is used unless front matter overrides it. The slug is
the filename without the date prefix; it becomes `/blog/<slug>`.

```markdown
---
title: A title
date: 2026-10-19
summary: >
  One or two sentences used on the index, in the feed and as the meta
  description.
tags: [rails, architecture]
draft: false
---

The body, in GitHub-flavoured Markdown.
```

| Key | Required | Notes |
|---|---|---|
| `title` | yes | Post title |
| `summary` | yes | Index, feed and meta description |
| `date` | no | Defaults to the filename date; `YYYY-MM-DD` |
| `tags` | no | List of strings; must be quoted if an entry contains `: ` |
| `draft` | no | `true` keeps it out of production listings and the feed |

Posts are sorted newest first, with the slug breaking ties. Reading time is
computed at 220 words per minute. Drafts are still validated, so a broken draft
fails the suite rather than surprising you when it is published.

Markdown is rendered by the single configuration in `lib/markdown.rb` (GFM
input, auto IDs, no syntax highlighter). Raw HTML is allowed because content is
committed and reviewed; there is no user-submitted text on the site.

## Figures, demos and evidence

The site's argument is that its claims can be checked. A case study should give
a reader something to inspect:

1. a capture of the running service, or
2. an authored diagram, labelled as a drawing, or
3. a command and the output it actually produced.

A screenshot that 404s is worse here than a broken image elsewhere, because it
is the part of the page a reader is supposed to be able to verify. That is why
the path is validated at boot and again from the rendered page.

## Adding a project: checklist

1. Add the entry to `config/projects.yml`, grouped under its `section`.
2. Choose `status` from the four known values and set `featured` deliberately.
3. Add `screenshots` under `public/screenshots/` or `public/diagrams/`, or a
   `demo` with a command and its real output.
4. Add absolute links; `bin/site links` will probe them.
5. Update `config/pages.yml` only if the section prose needs to change.
6. Run `bin/site check` and `bin/site links`.
7. Run `bin/site build && bin/site up --no-tunnel && bin/site verify` if the
   change could affect rendering or the runtime.
8. Open the page and read it as a reader would. Then re-read the editorial
   rules.

## Previewing content changes

In development, content is cached on file mtime, so an edit appears on the next
request without a restart:

```bash
bin/site dev     # http://127.0.0.1:3011
```

From the container path, `bin/site check` re-reads the working tree and will
fail on any content invariant before the page reaches a reader.
