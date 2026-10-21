---
title: The boundary you cannot move
date: 2026-10-20
summary: >
  Some systems cannot be rewritten, paused or reset. The integration is a
  product boundary, and the work is translation, contracts and reconciliation.
tags: [rails, legacy, integration, architecture]
---

Not every system can be rewritten. A retail ERP, a Sybase database, a supplier's
API or a warehouse service may have its own release cycle, its own data model
and a failure mode that predates the application you are maintaining. The modern
application has to meet it where it is.

That is a different problem from a greenfield integration. The boundary is not
something you design on a whiteboard; it is something you find, name, and keep
from leaking into the rest of the system.

## The anti-corruption layer is the product

The most useful move is to make one adapter own the legacy protocol. The rest of
the application talks in its own language: orders, customers, prices, states. The
adapter translates those into whatever the legacy system calls them, and
translates the replies back.

The rule is that legacy columns, status codes and quirks stop at the adapter.
They do not appear in the domain model, the controllers or the templates. If
they do, every future change has to know two models, and the legacy system has
quietly become the architecture.

That adapter is also where the contract is written down. A request has a shape,
a response has a shape, and an error has a meaning. If the legacy system has no
versioning, the adapter is where you keep the version you depend on.

## Test the system you have, not the one you wish you had

A fake of a legacy system is useful only if it reproduces the behaviour that
matters. An idealised fake — one that returns clean data, never times out and
never sends a partial response — tests the adapter against a system that does not
exist.

So the tests are characterisation tests first. Record the real payloads and
record the real failures. Build a fake that can return the malformed field, the
slow response and the duplicate submission. Then test the adapter against those.
A mock that is wrong is worse than no test, because it makes the integration look
covered.

At the edges of the boundary, a canary read and a reconciliation report are worth
more than another unit test. A canary proves the connection is alive and the
contract still holds. A reconciliation report compares the two sides and names
the rows that disagree; it is the only thing that catches a partial write months
later.

## Failure is part of the contract

A legacy boundary rarely gives you a distributed transaction. The write may
succeed on one side and fail on the other. The response may be lost. The same
submission may arrive twice.

So the modern side needs a state machine and a repair path. Idempotency keys for
anything that creates; a record of what was sent and what came back; retries with
a bound; a dead-letter or reconciliation queue for the cases a retry cannot fix.
The goal is not to pretend the boundary is reliable. The goal is to make a
failure visible, attributable and recoverable.

This is also why the framework upgrade and the data migration should not be one
project. The upgrade changes the application; the integration boundary changes
the data. Bundling them makes every failure ambiguous and every rollback larger.
Keep the boundary explicit, and the version hop stays a version hop.

## The database outlives the framework

A long-lived application accumulates integrations that are older than its
current framework, its current team and sometimes its current owner. That is
normal. The mistake is to treat the legacy system as a temporary embarrassment
rather than a boundary with a contract.

Once the boundary is named, the rest of the system can be designed as if the
legacy were a supplier: it has a response time, an error vocabulary, a version
and a reconciliation process. The adapter is the only place that knows the
supplier's dialect. That is a much smaller surface to maintain than a domain
model with legacy columns in it.

The boundary you cannot move is still a boundary you can name. Naming it is most
of the work.
