---
title: A bug report is a differential, not a description
date: 2026-09-25
summary: >
  Release notes record what somebody said changed. A corpus that answers
  upgrade questions has to execute one release against the next, file the
  interpreter's own refusal, and let somebody else reproduce it.
tags: [agents, verification, debugging]
---

The failure that made the point is small:

```text
TypeError: Client.__init__() got an unexpected keyword argument 'proxies'
```

An argument-binding error is raised before the callable runs, so the traceback
names no `site-packages` frame. A tool that reads a library off the stack has
nothing to read. A person holding the traceback knows which library they were
upgrading; a service has to know it some other way.

That is the shape [agents-fyi](/work/agents-fyi) was built around. It is a
shared memory for coding agents, and its reports are not summaries of release
notes. Each one is the result of running the same call against two releases:
the older accepts it, the newer refuses it, and the interpreter's own output is
the evidence. A finding is arithmetic, not a description.

## What a release note cannot say

Release notes say an argument was deprecated. An advisory says a version is
vulnerable. A pull request says a dependency moved. None of them says whether
*this* call site breaks, because nobody ran it.

So the miner runs it. It installs one release of a package, then another, and
executes the same call against each. When the older release accepts the call and
the newer one refuses it by name, that refusal is filed. The corpus does not
have to guess which library the report is about, because the miner chose the
release. It does not have to guess whether the upgrade breaks a caller, because
it was the caller.

The pair is deliberate. The predecessor is not the release before the newest —
consecutive patch releases of a mature package almost never remove an argument,
so ten packages in a row can produce nothing while the corpus waits. A caller
who is behind is behind by a *line*, not by a patch: what breaks people is the
upgrade that crosses from one minor series to the next, which is what
`pip install -U` performs. The pair is the latest release against the newest
release of an earlier series.

## Refusing to guess

The first version of the rename rule asked `difflib` for the closest string
among a release's exports and filed the answer as a fact. It was wrong in the
way that matters: it produced plausible advice.

`paramiko`'s removed `DSSKey` was offered as "renamed to `ECDSAKey`" — a DSA
class replaced by an ECDSA one. `numpy`'s `RankWarning` "became `hanning`", a
warning class offered as a window function. `litellm`'s
`is_azure_document_intelligence_model` became `is_openai_finetune_model`; the
two strings score exactly the cutoff because they share a prefix and a suffix
and nothing else.

A rename keeps a name's *words*, so the rule now asks for that. `setReconnect`
for `set_reconnect`, `random_lobster_graph` for `random_lobster`, `float64` for
`float_`. A tie is refused rather than broken, because `float32` and `float64`
are both `float_` plus a number, and picking one is guessing with better
manners. The trade is explicit: a fix the corpus cannot support is worse than
the removal it can, even when that means losing a real rename.

A removal that denies a successor is its own lie, too. `wsproto.Event`,
`toml.InlineTableDict`, `websockets.parse_uri` and
`litellm.parse_ocr_request_format` were all still exported one submodule down,
while the reports said the release exported nothing close. So a second pass
asks the release where the name is defined, not where it is re-exported, and
files `toml.decoder.InlineTableDict` with an import that was executed to prove
the path works.

## The third answer

The verifier is where the design gets its teeth. A report is promoted to
`resolved_verified` only when operators other than its author reproduce it. Two
services run beside the miner under their own accounts: one executes the call
sites the report names and then the fix it hands over; the other re-derives the
claim from the two releases and ignores the report's prose. Two methods because
one execution written twice is one opinion. A report neither can execute gets
no vote.

The hardest part was not the execution. It was admitting that a probe has three
answers, not two: refused, resolved, and *never ran*. A timeout, a wheel that
would not install, a signature neither release can read — those are not
evidence that the call site works now. The first version filed "never ran" as
"resolved", and a probe against an environment that was not finished raised
`ModuleNotFoundError`, which read as "the call site no longer refuses the
argument". Five true reports were contradicted by a machine executing as
carefully as it knew how.

An environment that exists is not an environment that is finished. `venv`
creates `bin/python` long before `pip` has installed anything, and the fast path
looked for the interpreter outside the lock that builds it. The lookup moved
inside the lock, a build that raises removes the directory it was building into,
and `unreached?` is now a distinct value checked by every verdict path.

## What a confirmation is worth

`GET /reports/{id}` returns every verification with the environment it was made
in and what the operator wrote, so `confirmations: 2` is checkable rather than
arithmetic. That is the difference between a corpus and a pile of confident
answers. The value is not that the corpus holds a fix; it is that the fix has an
execution under it, by somebody other than the person who filed it.

The live service and the project page are at
[agents.shoutsid.fyi](https://agents.shoutsid.fyi/). The interesting part is not
that a machine can find a break. It is that a claim about the break can be
reproduced.
