---
title: Holding a boundary in a Rails app nobody is going to rewrite
date: 2026-10-12
summary: >
  Modularising an application that is not getting rewritten works when the
  boundary is a failing build rather than a diagram, and when each step is small
  enough to ship on an ordinary week.
tags: [rails, architecture, packwerk]
---

There are two ways a modular refactor of a long-lived Rails application fails,
and they fail in opposite directions.

The first is the diagram. Someone draws contexts and dependencies on a
whiteboard, everyone agrees it looks right, and nothing about the code changes.
A year later the diagram is wrong and the code is exactly as coupled as it was,
because a convention that cannot fail is a convention nobody has to follow.

The second is the extraction. The same boundaries are drawn, and then acted on
by pulling the first one out into its own service. Coupling that was a method
call is now a network call, the transaction that used to be atomic spans two
processes, and the boundary is harder to move than it was before.

The path between them is to make a boundary that *already exists* into something
the build refuses to cross — and then to leave it where it is.

## Start from the boundaries the code already respects

You rarely get to choose the boundaries. The application has had them for years;
they are just not written down. There is a set of tables only one part of the app
touches, a model that is only ever reached through one entry point, a directory
an outsider would think twice about opening. Those are the real boundaries, and
they are already load-bearing.

So the design work is not inventing them. It is finding the ones that exist,
naming them, and writing down which way the arrows are allowed to point.

## Make the boundary a failing build, not a review comment

This is the part that decides whether any of it holds. A rule that lives in a
document is a rule a newcomer breaks in good faith and a reviewer catches when
they happen to notice.

In a Rails application the cheapest version of the enforcement is a packaging
tool such as Packwerk. Each domain becomes a directory with a package file, the
package file lists the other domains that domain may use, and a check runs in CI.
A reference that leaves the boundary — one domain reaching into another's
internals — becomes a failing build with a file and a line number, on the pull
request, before anyone has to hold an opinion about architecture.

That check *is* the design. The dependency list is the only architecture
document that cannot rot, because it is executed on every push.

## The legal dependencies are the interesting part

Once the check exists, the question stops being "should these be separate
domains" and becomes "is this arrow allowed" — a much better question, because it
has an answer someone can argue about and then write down.

The list of permitted dependencies should be short, and every addition to it is a
decision. A new arrow is either a genuine domain relationship, which ought to be
rare and deliberate, or it is a shortcut around one, which is exactly the thing
worth seeing in a diff.

There is a second, quieter benefit. The boundaries make the blast radius of a
change visible: when a change touches four domains, the check says so, and you
get to decide whether that is the shape of the problem or the shape of the
shortcut.

## Do not extract a service yet

A network hop is not an architecture. It buys independent deploys, independent
scaling, or a boundary that two teams genuinely need to move on separately. It
costs everything a method call gave away for free: an atomic transaction, a stack
trace, a reference you can follow, a test that runs in one process.

Where none of those three things is actually true, extracting the boundary turns
a modular monolith into a distributed one — all of the coupling, none of the
decoupling, plus a serialization format. The boundary is worth having on its own,
and inside one application it is far cheaper to enforce.

## Small enough to ship on an ordinary week

The migration itself should read as tidying rather than surgery. One domain at a
time. Keep the suite green between steps. Resist the rename that touches every
file, because it makes the diff unreviewable and the rollback worse.

None of this is fast. It is maintenance rather than a project, which is the
point: the alternative is a rewrite, and rewriting an application that people
depend on is the most expensive way to arrive at the same design.

The direction and the tooling, without the proprietary detail, are in the
[modular monolith case study](/work/rails-modular-monolith).
