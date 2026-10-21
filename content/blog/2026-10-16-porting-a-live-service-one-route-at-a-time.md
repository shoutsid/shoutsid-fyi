---
title: Porting a live service one route at a time, then deleting the old one
date: 2026-10-16
summary: >
  A stack migration is safest when the old implementation is the oracle, each
  route moves on its own, and the last step is a deletion rather than a second
  code path.
tags: [rails, migration, testing]
---

[agents-fyi](/work/agents-fyi) began as a Python service. Moving it to Ruby and
Rails was not a rewrite in the usual sense: there was a live corpus, a public
contract and clients that had to keep working. The migration that worked was
less dramatic than a rewrite and more demanding than a find-and-replace.

The shape was: record what callers actually receive, move one route at a time,
delete the old implementation of that route, and finish by deleting the old
tree. The recordings are what made the first three safe.

## Record from the outside, not from the code

The first parity fixtures were made by calling the application's own function
directly. That records what the code can be asked, not what a caller can send.
The web framework validates query parameters before the route runs; a recording
made inside the function never sees the refusal a malformed request gets. Eight
of the first thirty-three recorded answers were responses the service never sent
for those URLs, and both the Python and Ruby suites were green.

The fix was to record through a running service, over HTTP, with a real client,
and to record the request as well as the answer: the method, the content type,
the declared length, the body. The projection function that shapes a response
for comparison belongs to the test and is imported by the recorder, so the
thing being compared and the thing being recorded cannot drift.

Those recordings are now frozen. They were recorded against an implementation
that no longer exists, and the recorders went with it. Editing one to make a
port pass would be editing the contract, which is the one thing the fixtures
exist to prevent.

## Move the route, then remove its other implementation

Each route was flipped to Ruby in its own slice. The parity harness compared the
two implementations while both were alive. That works until the last route
flips, and then it stops being able to fail: a path that never leaves the legacy
fallback agrees with itself, so the harness cannot tell "Rails serves this" from
"Rails forwards this".

What replaced it is a route inventory test. Every path the contract names must
resolve to a named controller and action; a path nothing claims is a 404 now,
which is the answer an unmigrated route could never give while a catch-all stood
behind it. The compatibility bridge and its route were deleted, not left dormant.

## The green line that tested nothing

The corpus half of the suite once ran `230 runs, 0 failures, 230 skips` on its
first run. The application image installs its gems under Bundler, a bare `ruby`
in that image cannot `require "pg"`, and every test that needed a database
driver skipped. That is the greenest possible line for having tested nothing.

The step runs `bundle exec ruby` now, and the entry point aborts when the driver
is missing. A second green lie was smaller: minitest 6, which the bundle
resolves, does not ship `minitest/mock` where the previous image's Ruby carried
5.20. Four tests that stubbed a method raised `NoMethodError`. The replacement
is narrow and deliberate — installing the stub as the method body rebinds
`self` to the receiver and counts the wrong instance variable, so the handler is
called.

The general rule is the one the suite already had: a test that never runs is not
a test, and a run whose summary is invisible reads as a run that did not finish.

## The deletion is the migration

The Python service, its miner, its MCP server and the recorders were deleted
rather than left beside the new tree. A dormant second implementation is a
reader's problem every time it is read, and a place for behaviour to drift back
in. What remains is one Ruby service, its clients, and the frozen recordings.

The migration's success criterion was not that the new code resembled the old
one. It was that the bytes a caller receives did not move, and that the old tree
was gone. The cost is real: the recordings can never be re-made, so they have to
be right the first time.

That is a harder constraint than a rewrite, and a better one.
