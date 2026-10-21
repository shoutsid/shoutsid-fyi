---
title: A refusal is an output, not a crash
date: 2026-10-21
summary: >
  The upgrader has three exit codes, and the distinction between them is the
  difference between "the ladder will not plan this", "nothing was established"
  and "something went wrong".
tags: [automation, cli, rails]
---

An automated upgrade tool has one job a person can check: when it says a step passed, something established that. Everything else is bookkeeping, and the bookkeeping is where the tool earns or loses its trust.

The [upgrader](/work/upgrader) is the client that walks a Rails application forward one release at a time. It has three exit codes, and they are part of the contract rather than an implementation detail.

## Three answers, three codes

`0` is a plan, a passed step, or a clean stop. `2` is a **refusal**: a fact about the move. The ladder reads forward, so a backwards move is a refusal; a target already at the top of the ladder is a refusal; a release the service has no chapter for is a refusal. `1` is a **failure**: a fact about the repository, the service or the machine.

Collapsing `2` into `1` reads "the ladder will not plan this" as "the tool crashed". A caller then retries a refusal for ever, or treats a real failure as a known answer. The service's own sentence travels with the refusal, so the caller knows which direction the ladder reads or which release has no chapter.

The third code has a subcase that matters more than it looks. A step whose verdict is `unverified` exits `1`, because `unverified` is not a pass with a caveat. It means no interpreter installed the bundle, the suite could not run, the baseline was red, or a required check did not run. Nothing established anything.

## The failure that named it

The first build treated `unverified` as success. A real walk found the cost: an interpreter could not reach GitHub, so every era failed to install, and every step exited `0` while measuring nothing. A caller reading only the exit code — which is what a scheduler does — was told that a walk was progressing when nothing had been installed at all.

The record still distinguishes `failed` from `unverified`, because the two want different responses. `failed` is a result: the move was measured and did not work. `unverified` is the absence of a measurement, and the next move is usually to fix the environment rather than the application.

## Settled is not delivered

A second conflation lived one layer up. A passed rung and a delivered pull request are two facts, and the loop treated them as one. A rung whose branch push or pull-request call failed was marked settled and never retried, so the work existed only on a machine that had already moved on.

Delivery has its own queue now: the ledger records what was settled, and a settled rung with an unfinished delivery is retried before new work is planned. The same distinction applies at the end of a walk. A target at its top release is done, and asking the ladder to move it again is a refusal — recording that refusal every cycle is how a finished walk grew a queue while learning nothing.

## What a pass is

A pass is not "the tool finished". It is a suite that was green before the move and green after it, on a named interpreter, with the baseline, the commands, their exit codes and the patch in the record. When the baseline was red and the step repaired it, the record says so, because a verdict that said "the suite was green before this step" over a tree that was repaired first would describe an application measured before it was fixed.

That is the standard I want from this kind of automation: a small diff, an evidence trail under every line, and an exit code that means what it says. A refusal is an output. An absence of measurement is not a pass. A merge is a decision, and the tool does not make it.

The upgrader's [design notes](https://github.com/shoutsid/upgrader/blob/main/docs/design-notes.md) carry these decisions with the failures that produced them.
