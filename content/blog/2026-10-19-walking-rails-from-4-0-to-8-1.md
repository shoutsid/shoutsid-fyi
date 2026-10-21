---
title: Walking a Rails application from 4.0 to 8.1, one rung at a time
date: 2026-10-19
summary: >
  A Rails upgrade is a sequence of small, evidenced moves. The interesting
  engineering is not the Gemfile edit; it is the ladder as data, the judgement
  as a decision, and the suite as the only verdict.
tags: [rails, upgrades, automation]
---

I wrote earlier about [upgrading a production Rails application by
hand](/blog/upgrading-a-production-rails-application): one version at a time,
release each step, clear the deprecations while they are cheap. This is the
other half of that argument. If the method is a sequence of small moves, a
machine can do most of the moving — provided a machine's "passed" means
something.

The client is part of [agents-fyi](/work/agents-fyi). It reads an application's
`Gemfile.lock`, asks the service what a move crosses, and executes one rung on a
scratch copy. The first complete walk of the reference application went from
Rails 4.0 to 8.1, opened a pull request per rung, and used no model call. That
last detail is the one to keep in view: the interesting result is not that an
agent can edit a Gemfile. It is that every edit has an owner and an execution
under it.

## The ladder is data

The service holds the Rails upgrade ladder as one JSON file: thirteen steps and
ninety-five documented changes, read by both the server and the client. A step
knows its Ruby floor, the changes it carries, and which of those a machine may
apply. The client does not keep a second copy of Rails' release order. It asks.

The ladder is the *documented* half. The corpus is the executed half: reports
that were produced by running one release against another, with the interpreter's
own refusal attached. The third kind of fact is the gem digest — the things no
execution establishes, such as a source that no longer exists, a fork kept for a
Rails release that has since shipped, or a pin that cannot sit beside the
framework. Those three sources answer different questions and are kept apart on
purpose.

The split of labour is deliberate: the service has no route to a package index,
and the client does not get to decide what a reading means. Whoever can reach
the network fetches; the service decides what the reading is and when it
happened.

## The walk

A step starts by choosing an interpreter. The era matrix is data — six Ruby
versions, each image pinned by digest — but the choice is probed rather than
looked up: candidates meet the step's Ruby floor, start from what the
application itself names, and run `bundle install` in order. The first one that
installs the bundle is the machine. Every attempt travels in the record. "No
interpreter meets this floor" is a verdict with a reason, never a silent
fallback to the wrong Ruby.

The application runs in a container per step, with the database and Redis inside
it, because a 2013 `database.yml` says `host: localhost` and a service on a
Docker network is not localhost. The baseline suite runs before anything is
changed. That is not ceremony: an application old enough to need this walk
usually arrives red, and a red baseline makes everything after it unmeasurable.
If the baseline is repaired, the verdict says so.

Then the pipeline: preflight repairs the Gemfile's own dead protocols and
forks; the scan locates call sites for the changes this rung carries; rules
apply the mechanical edits; the gem moves that the move requires are applied;
Rails is pinned with a conservative resolve; `app:update` runs; the application
boots; the suite runs again. Every command, exit code and refusal goes into the
record. A passed rung is committed to a kept tree and delivered as a branch and
a pull request chained to the previous rung, so a reviewer sees one step's diff
rather than the whole walk.

## Rules, bridges, surveys and gaps

The automation is layered because the changes are not one kind of thing.

A **rule** is a pattern and a line-checked edit. It refuses a line that moved
between the read and the write, and it has an idempotence guard so a second walk
does not write the same option twice.

A **bridge** is a declaration that is the whole fix: `rails-controller-testing`
for `assigns` and `assert_template`, or `bootsnap` for a rung whose
`app:update` writes the require. There is no line to rewrite and no pattern to
match, so it is a separate mechanism rather than a rule pretending to be one.

A **survey** neither edits nor declares. It reports where a judgement-shaped
change lands — the callers that chain conditions onto a `default_scope`, the
lines that assign to a `has_many_attached` collection, the aliases whose
original attribute a file defines. A wrong survey costs a reviewer a glance; a
wrong rewrite costs the application its behaviour. That asymmetry is why the
analysis lives here rather than in a guessed edit.

A **gap** is the residue. Every change no rule covers carries a sentence saying
what would close it. The generic fallback is not allowed, because a generic
sentence reads as work somebody has already considered. "Nothing is never" is
the posture: a change with no rule is a named gap, not a verdict that the change
is unautomatable for ever.

## The failures are the design

The most useful bugs were the ones that made a wrong answer look right.

A family that reads a call has to read every way the call can be written. The
`:confirm` rule's guard knew `data: { confirm: ... }` and not
`:data => { :confirm => ... }`; it rewrote a call that already had the new form
into a line that was not a call. Another family's lookahead accepted `,`, `)`
and the end of the line, so every call site in an ERB view ending with `%>` was
invisible — and the residue read as a refusal rather than as unreadable.

A guard has to read the text its pattern reads. `Rule#already` matched the raw
line while every pattern matched a masked line. A comment mentioning
`data: { confirm: x }` made a line that needed the edit report as `satisfied`,
and the residue said nothing. A missed edit is visible as a decision. A false
`satisfied` is silent, and the change it drops is the one the person was relying
on the tool to find.

A bound that keeps the wrong end is worse than no bound. The record kept the
last four thousand bytes of a failed command, but a Ruby failure puts the
exception class and message on its first line and the frames nearest the failure
on its last. Three rounds of debugging were spent reading frames and guessing.
Resolver output is the extreme case: every `Bundler could not find compatible
versions` block is a candidate cause, and the root is neither first nor last. The
record now keeps both ends, and the four resolver commands get a larger bound.

Then there was the step container that was never removed. `stop!` was called only
for a rejected interpreter, the container's process was `sleep infinity`, and
`--rm` only removes a container whose process exits. Eight were running. A
process that is *killed* runs no `ensure` at all, so containers carry the
walker's pid and a reaper removes the ones whose owner is gone. Later, `docker
create` hung for eight minutes; every daemon call is now bounded, not only the
teardown.

## Decisions are rows

The 6.0 rung needed two view edits that a machine should not decide: which
parents a nested route helper should receive, and whether to guard a link that
the layout renders on pages with no category. Those became rows — a question
with its file and line, the evidence, and the options — rather than a note in a
walk log.

A model may propose an answer. Only an operator accepts one, and the two actors
are different columns. An accepted answer's effects are applied to the working
tree before the scan, in a declared order, and each edit carries
`origin: decision:<id>` so the record says who made it. A passed rung verifies
the answer that was in force: the run whose suite was green with the change in
the tree sets `verified_by_run_id`. A failed or unverified run verifies nothing,
because it is not evidence that the answer was wrong.

Acceptance is the operator's word; verification is the suite's. A proposal
applies nothing. That is not a limitation of the model; it is the rule that
makes a model's suggestion safe to keep in the same system as an executed fix.

## The database is part of the evidence

The walk needed new tables — the brief a rung was walked with, the questions a
person answered, the patches an answer applies — and the first version wrote
them straight into `db/structure.sql`. That is a bug class the project had
already paid for once: a table edited into the dump is in no database that has
already been built, so the running service answered `relation
"decision_questions" does not exist` for a feature whose tests were green.

Every schema change is a versioned migration now, and the dump is what the
migrations produce. The gate loads the committed dump into a scratch database,
runs the migrations against it — nothing may run, because the dump carries the
version list — dumps again, and compares. The dump comes from `pg_dump` 16 inside
the test container because the server is 16 and a newer client writes settings
the server refuses. A passed rung is a claim; the database that stores the claim
has to be reproducible too.

## What a pass means

The first complete walk had no model call. The one rung that had leaned on a
repair agent was re-done mechanically, because a green rung that leaned on a
model has to be read differently from one that did not. The goal is not
autonomy. It is a smaller diff a person can review, with an evidence trail under
every line: the command that ran, the output it produced, the decision that was
in force, and the suite that passed afterwards.

That is the standard I want for this kind of automation. Not "the machine
changed the Gemfile." A rung is a pass only when the suite says so, and a
decision is only a decision when somebody can be named for it.
