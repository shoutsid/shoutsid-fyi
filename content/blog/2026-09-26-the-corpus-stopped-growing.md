---
title: The corpus stopped growing, and every number looked healthy
date: 2026-09-26
summary: >
  A background service that keeps cycling, reports healthy and does nothing is
  the hardest failure to see. The fixes were about what a bound is measured in,
  and what an empty answer says.
tags: [observability, background-jobs, measurement]
---

The miner behind [agents-fyi](/work/agents-fyi) cycled every ten minutes and
logged `0 pair(s) mined`. It did not crash. It did not error. Its heartbeat was
fresh, the queue was full, and sixty-four pairs sat due behind it.

Finished and stuck look identical from outside. That is the whole cost of a
quiet scheduler. The interesting engineering was not adding another log line;
it was finding three bounds that measured the wrong thing, and one empty state
that described the tool rather than the corpus.

## The bound was on the wrong noun

The queue ranks never-touched packages first, on purpose: a fresh miner should
walk the whole watchlist before revisiting anything. But a package with no
version crossing — `mdurl`, whose releases are all on one line, or the
`opentelemetry-*` packages, whose releases are all pre-releases — produces no
pair. Nothing is written to the ledger, so the package is never stamped as
touched, so it returns to the front for ever.

The planner then looked at the top twelve packages and stopped. The bound was on
*packages considered*, which is free, rather than on *index requests made*,
which is the resource worth protecting. Reaching twelve packages that had work
meant walking past hundreds that did not.

The fix is not a bigger number. It is a bound on the right noun: walk the whole
ranking until there is work, and charge the fetch allowance only for the
requests that actually happen. A package whose history is already on disk is
read for free. If the walk has to ask the index for a package, that is what the
allowance is for.

That sounds obvious in hindsight. It was invisible in the logs because the
scheduler was doing exactly what it was told: it considered twelve packages,
found no work, and reported success.

## The list ran out, and running out is silent

The watchlist was a thousand package names, described as a few dozen hours of
mining. Measured against the ledger, it was about nine thousand release
crossings in under two days. After that the miner had worked the whole list,
could find nothing, cycled every ten minutes logging `0 pair(s)`, and reported
healthy. The corpus had stopped growing while every number it published looked
fine.

A list sized by a guess about the work will run out. The fix was to size it
against the measured rate, and to make the empty case explain itself. A dry
cycle now names its reasons with counts: how many pairs were already mined in
the window, and how many cannot be examined on this machine. "Nothing due" is a
different state from "nothing left", and the reader can tell them apart without
opening the ledger.

The same lesson appeared one layer up. The service's queue endpoint validated a
request parameter with a ceiling, and the miner asked for its whole watchlist
depth in one request — a thousand against a cap of five hundred. Every start was
a 422. The client read a failed queue read as "the service has no queue, use the
local list", which is the right fallback for an outage and the wrong one for a
refusal that happens every time. The queue the service computed, with its demand
signals and its reasons, had never once driven its only reader, and the startup
log said the opposite.

The endpoint now clamps the value and serves the clamp, so a client pages
instead of guessing a constant on the other side of an HTTP call. And the
failure is recorded, because a bare `except` around a remote call makes a
permanent refusal look like a quiet afternoon.

## The fixtures could not see it

The corpus has a recall probe that asks the live service for every report by
that report's own words. It is deliberately not a fixture: a fixture's wording
is chosen by whoever wrote it, while the corpus's wording is chosen by the
failure.

The probe found a regex whose own comment gave `uvicorn.Config` as its example,
while the pattern required the attribute half to start with a lowercase letter.
The example never matched, and neither did any class name. A whole family of
removed-name reports — `cleo.DescriptorHelper`, `toml.InlineTableDict`,
`networkx.OrderedMultiDiGraph` — had stored the same two generic tokens as every
sibling release, so a search could not tell them apart. Recall fell below its
floor while the suite stayed green, because the suite files the text it then
looks for.

The fix was a data migration in the careful direction: union the newly
recognised token class into the existing rows, rather than re-extracting
everything. Re-extraction would have dropped every symptom that came from a
trace the schema no longer keeps. After the backfill the probe read one miss in
the whole corpus, and the one miss was a real one.

## A self-check is not demand

The probe had a second, subtler problem. It was sweeping the whole corpus
through the search log, and the search log is the service's only measure of what
callers look for and cannot find. In one measured window, almost every event in
that table came from the probe itself. The gap report was describing the tool,
not the corpus.

The fix is a `record=false` parameter on the search and answer routes. A flag,
not an account, because the same operator does both kinds of traffic. The rule
generalises: when a table is an *observation* rather than a record, ask who else
writes to it. A synthetic row does not look wrong. It looks exactly like a user.

## Make the zero explain itself

The common thread is not "add more monitoring". It is that a bound has to be
measured in the resource it protects, an empty answer has to say which of its
meanings it is, and a self-check must not write demand.

A healthy-looking zero is a claim. The scheduler should be able to say, in one
line, whether it is finished, waiting, or unable to see the work.
