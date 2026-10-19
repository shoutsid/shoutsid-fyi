# Editorial rules

[Documentation index](README.md) · [Content authoring](content.md)

The point of this site is that it can be taken at face value. A portfolio that
overstates is worse than a shorter one, because the first interviewer question
exposes it. These are the rules the content follows, and the reason a few things
are conspicuously absent.

This page is policy, not style advice. Read it before adding a project, changing
a status, quoting a number or writing a case study.

## The test for any sentence

> Could I reproduce this, or point at the thing itself, if asked?

If the answer is "roughly", rewrite it until it is "yes" or delete it.

## Banned vocabulary

These words promise evidence the site does not carry:

- production-grade
- state-of-the-art
- industry-leading
- proven improvement
- successful training
- battle-tested
- enterprise-scale

And these numbers, unless they are reproducible and published on the site:
usage counts, customers, revenue, latency, benchmarks, "X% faster".

There is no exception to that. A figure is either reproducible from something
published here, or it is not stated as a figure at all.

A claim is also never attributed to a document this site does not carry. "My CV
records an X% reduction" fails twice over: a reader cannot check the CV from the
page that cites it, and the number is exactly what the line above bans. Say what
changed without the percentage, or leave it out.

## Status labels

Every project carries one, and the label is the claim:

| Status | Means | Must not be read as |
|---|---|---|
| **Live** | Deployed and publicly reachable at a URL you can visit. | A business with customers. |
| **Public repo** | Source is on GitHub and can be read. | Maintained, or finished. |
| **Research** | An ongoing investigation with a stated hypothesis. | A demonstrated result. |
| **In progress** | Work exists; there is no demo yet. | Something you can evaluate. |

A research project is never rendered beside a deployed one in the featured grid.
It gets its own section, with a visible "Experimental" marker and a callout that
repeats what has *not* been shown.

## Describing the career break

The break from October 2024 is stated plainly and briefly, for personal reasons
that are not elaborated on. Independent work during it is described as
independent development on selected projects — never as employment, never as a
business, and not as continuous work either.

"Intermittent" used to carry that last distinction, and was dropped: it put the
frequency of the work in the opening line of the entry, which gives it more
prominence than it earns. "On selected projects" is honest without the
emphasis. Private work is described at the level of the question and the
method.

See `config/experience.yml` — the first role is the break, with `current: true`
and `personal: true`.

## Privacy

- No personal circumstances behind the break.
- No proprietary architecture details from City Electrical Factors. The case
  study names the direction (modular monolith, Packwerk, domain boundaries) and
  credits the reference implementation it was informed by, and stops there.
- The Rails upgrade work at City Electrical Factors is written up on the blog at
  that same level: the version path (3.2 → 4.2 → 5.2, and that it carried on
  across later versions), how the work was sequenced, and what would have been
  done differently. No traffic, codebase size, coverage or timeline figures, and
  no detail about that system's architecture. "What broke" is written as method,
  not as incident — the lessons are the post, the client's code is not.
- Contact is an email address and public profiles; there is no contact form and
  therefore no user-submitted data anywhere on the site.

## The toolkit

`config/experience.yml` lists what has actually been used, not a list of things
that would look good on it. The two lists are easy to confuse when writing a
skills section, and the confusion is expensive: a toolkit line is a claim, and it
is a claim an interviewer tests with a single question.

So Rails 7, Rails 8, Hotwire, Solid Queue and Kamal are absent on purpose. The
public Rails work stops at 5.2, and the return to current versions is being made
now, which makes those words aspirational rather than true. They get added when
there is a project, a client or a repository that can be pointed at — not when
the release notes have been read.

The same test applies to the role titles and the headline. If a line cannot be
reproduced from something else on the site, it is either rewritten or deleted.

## Attribution

Where a project was informed by someone else's work, say so. The Rails modular
monolith project credits the Rootstrap reference implementation. Where a project
is inspired by a commercial product, say so and disclaim affiliation — see the
city-simulation project in `config/projects.yml`.

## Where the rules are enforced

Some of this is checked automatically, and some of it is a review standard:

- **Checked at boot:** known project statuses, required fields, figure files,
  link formats and the shape of every record.
- **Checked by the suite:** internal links on every rendered page, template
  prose, the palette's contrast, cache policy and the health endpoint's content
  counts.
- **Reviewed by a person:** whether a sentence is reproducible, whether a
  status is honest, whether a figure proves what the caption says, and whether
  a claim has been attributed.

The automated checks catch the failures that are cheap to state. The rest is
why the [content authoring](content.md) checklist ends with "read it as a
reader would".
