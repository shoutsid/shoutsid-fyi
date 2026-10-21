---
title: The outbox is a table, not a library
date: 2026-10-20
summary: >
  The dual-write problem is not solved by a gem. The outbox is a row written in
  the same transaction as the change, and everything after it is delivery.
tags: [rails, kafka, distributed-systems, outbox]
---

The failure is easy to describe and hard to make impossible. The application
writes an order, commits the database transaction, and then publishes an event.
If the process dies between the commit and the publish, the order exists and the
event does not. Retrying the write duplicates the order; skipping the retry
loses the event. An `after_commit` callback narrows the window but does not
close it: the callback is application code, and the process can die after the
commit and before the callback runs.

The database is the only component in that pair that can commit both facts
atomically. So the event has to be a row in the same database, written in the
same transaction as the change it describes.

## One transaction, two rows

An outbox table is deliberately boring: an id, the aggregate it belongs to, the
event type, the payload, when it occurred, and whatever the relay needs to find
it. The write path does the ordinary thing and then inserts the outbox row
before the transaction commits. Either both rows exist or neither does.

The relay is a separate concern. In the
[rails-modular-monolith](/work/rails-modular-monolith) project, Debezium tails
the outbox table through Kafka Connect and publishes the committed rows onto
Kafka. The application does not publish in the request path at all.
That is the useful split: the application owns the fact, and the relay owns the
delivery.

The relay can lag, restart or replay. Those are operational states, not
correctness failures, because the rows are still in the table and the log is
still the source. A relay that has been down for an hour catches up from the
table; it does not need the application to remember what it failed to send.

## At-least-once is the contract

An outbox gives you at-least-once delivery, not exactly-once. A relay can publish
a row and die before recording that it did, and the next attempt publishes it
again. That is the correct trade: a duplicate is cheaper than a lost event, but
only if the consumer is built for it.

So the consumer needs an idempotency key. The outbox row's id is the natural one.
A Karafka consumer can record the ids it has processed in the same transaction
as the effect it applies, and a repeated delivery becomes a no-op. If the effect
is an external call that cannot join the transaction, the consumer needs a
deduplication table and a reconciliation path instead.

The project's consumer also has a dead-letter queue. A poison message should not
block a partition for ever, and a message that failed because the downstream
system was unavailable should not be treated the same as a message that can
never succeed. The DLQ is where the distinction becomes visible to an operator.

## What the outbox does not solve

The pattern is often sold as a complete answer to distributed transactions. It
is not.

- **Ordering.** Kafka orders within a partition, not across a topic. If two
  events for one aggregate can land on different partitions, the consumer can
  see them out of order. The key has to make the ordering you need.
- **Exactly-once.** The outbox is at-least-once. Exactly-once is a property of
  the whole pipeline, including the consumer's side effects, and it is usually
  bought with idempotency rather than with a stronger guarantee.
- **Schema evolution.** The payload is a contract. A consumer that reads an old
  shape has to keep working, or the event has to carry a version.
- **Retention.** The table grows. If the relay is Debezium reading the WAL, the
  table can be pruned on a schedule; if the application polls it, the published
  marker and the retention policy are part of the design.
- **The relay's own failure modes.** A connector that cannot reach Kafka is a
  queue, a backlog and an alert. The outbox makes the failure recoverable; it
  does not make it invisible.

## The failure tests are the point

The outbox is only worth the extra table if the failure cases are tested. The
tests that matter are not "the event is published"; they are:

- a transaction commits and the process fails before the relay runs, and the
  event is still delivered after a restart;
- the same event is delivered twice, and the consumer applies it once;
- a poison event reaches the dead-letter queue without stopping the partition;
- an event for an aggregate that no longer exists is handled deliberately rather
  than crashing the consumer.

The project is a worked example, not a finished platform. The Packwerk
boundaries, the outbox, the Kafka path and the Karafka consumer are implemented;
the reference implementation's per-domain databases and saga choreography are
not. That caveat matters, because the interesting part of the pattern is the
part that survives a failure, and a partial port should say which failures it
has actually exercised.

The outbox is not a library you add to a Rails app. It is a table you commit to,
a relay you operate, and a consumer that assumes it will see the same fact twice.
That is a smaller idea than "event-driven architecture", and a more useful one.
