---
title: Upgrading a production Rails application from 3.2 to 5.2, in steps
date: 2026-10-12
summary: >
  The framework upgrade is rarely the hard part. What makes a version hop
  survivable is treating it as scheduled maintenance, releasing each step, and
  clearing deprecations while they are still cheap.
tags: [rails, upgrades, legacy]
---

From 2019 to 2024 I worked on the primary Rails application at City Electrical
Factors, a retail site that customers order through every day. The framework was
on 3.2 when I started, moved to 4.2, then to 5.2, and the upgrade work carried on
across later versions. None of that was a project with a start and an end. It was
maintenance, and doing it as maintenance is the whole argument of this post.

Details of that system's architecture are not mine to publish. What I can write
up is the method, because the method is not specific to that codebase.

## Two shapes that fail

The first is the rewrite. The version gap looks so large that the sensible-seeming
move is to start again on the current release. You lose the accumulated fixes
nobody wrote down, you spend the rewrite discovering why the code is shaped the
way it is, and you arrive at the same design a year later with the same
dependency problems — because the cause was never the framework version.

The second is the upgrade branch. Someone cuts a branch, starts working through
the framework diff, and it stays open because feature work does not stop. It
conflicts daily, it is too large to review, and after a few weeks it is a
graveyard that everyone avoids. The branch is not wrong; the unbounded scope in
it is.

## One hop at a time, and release it

What worked was treating each version as a separate delivery that ships: 3.2 to
4.2, release it, live with it; then 4.2 to 5.2, release it. The application is
never far from a supportable version, and every step is small enough to review
and to roll back.

The step that makes the *next* step cheap is unglamorous: clear the deprecations
now. Ruby and Rails both warn about what is going away, and a warning ignored in
one version becomes an error in the next one — the difference between a change
you make while the code is fresh in your head and a change you make while also
debugging a framework upgrade. Deferring deprecations is borrowing at a rate that
goes up.

The same logic applies to gems. The framework bump and the dependency work are
one job, done together. Leaving the gems for afterwards produces a second
migration immediately after the first.

## Make the environment reproducible first

The reason those hops were affordable was Docker. Before it, part of the cost of
every upgrade was a distinct class of failure that had nothing to do with the
code: an environment that no longer matched, a native extension that built on
one machine and not another. Making the environment reproducible turned the
upgrade into a problem about code, which is the problem it was supposed to be.

Bitbucket Pipelines came in the same pass, and that is what made "release it"
practical. A green build has to mean a runnable application, not merely a suite
that passed somewhere. Once it does, shipping an upgrade step is an ordinary
deploy rather than an event with a room booked for it.

## The cost is in the code no test reaches

The framework diff is mechanical. Almost all of the real cost sits in two places:
dependencies, and the paths with no test over them. A suite that passes is
evidence about the code it covers and nothing else, and an upgrade is precisely
the change that exercises the uncovered paths — the error handler, the
integration against an external system, the report that runs once a quarter.

So the sequencing that helps is unglamorous too: before touching a path, add the
test that pins the behaviour it has now. It does not have to be a good test of
the design. It has to fail if the upgrade changes the answer. That is what turns
"I think this still works" into something you can check.

## What I would do differently

**Start with coverage, not with the version.** I would spend the first weeks
making the suite trustworthy — measuring what it actually covers and building
characterisation tests around the untested paths — instead of treating that as
something to do when the upgrade breaks. The upgrade tells you where the holes
were. It is better to find them first.

**Never bundle it with a feature freeze.** A frozen application still needs bug
fixes, and a freeze makes the upgrade a project again, with all of a project's
appetite for delay.

**Give it a standing slot rather than a window.** A recurring allocation of time
turns the work into maintenance, which is what it is, and removes the argument
that resurfaces every time a deadline is close.

**The database outlives the framework.** Part of the work was integrating modern
applications with legacy Sybase systems, and the tempting mistake is to make the
upgrade and the data migration one effort. They are separate problems with
separate risk. Keep the integration boundary explicit and the version hop stays a
version hop.

## Why this is the work I want

An application that customers depend on cannot be rewritten on a whim, so the
people who keep it upgradeable are doing the work that makes everything else
possible. Clear the deprecations, keep the build honest, ship each step, and a
decade-old Rails application stops being a liability.

That is the job I am looking for, and it is what the [modular monolith case
study](/work/rails-modular-monolith) is about from the other direction —
boundaries rather than versions, on the same kind of codebase.
