---
title: An experiment that can say no
date: 2026-10-20
summary: >
  A research repo should be able to return "no" and still be useful.
  Pre-register the decision rule, keep the null arms, and make the claim
  checkable from committed artifacts.
tags: [research, machine-learning, methodology, reproducibility]
---

Most AI writing is a result looking for a hypothesis. A research programme is
more interesting when it can record a negative result without collapsing.

The `ACT` project asks whether a network's topology can adapt during
pretraining, and whether that can improve the trade-off between capability and
compute against fixed architectures of comparable capacity. The central question
is still open. That sentence is not a disclaimer at the bottom; it is the
project's current state, and the method is designed to make it possible to say
so.

## Declare the decision before the run

A result is only meaningful against a rule that was written first. The studies
are pre-registered with declared decision rules, control and null arms, and a
do-nothing clause. A campaign that would settle the question has to be able to
fail; otherwise it is a demonstration with error bars.

The rule is not a formality. It decides what counts as an improvement, what
counts as noise, and what would make the hypothesis wrong. Without it, every
outcome can be read as encouraging after the fact.

## Keep the null arms

Controls are the part of a pretraining experiment that is easiest to talk
yourself out of. A fixed architecture of comparable capacity is the baseline the
adaptive topology has to beat. A null arm says what happens when nothing is
changed. A do-nothing clause says that doing nothing is allowed to be the
answer.

Those arms are expensive, and they are the reason a result is worth reading. If
the adaptive network only beats a smaller model, or only wins on one seed, or
only wins when the baseline is undertrained, the comparison is not the one the
hypothesis needs.

## Make the claim machine-checkable

The project has a verification script that audits the report against its
committed artifacts, and the suite pins each arm's recorded result against its
own summary. A claim that drifts from the record fails the build.

That is a stronger standard than "the notebook is in the repository". A notebook
can be run with different data, a different seed or a different commit and still
look like evidence. A committed artifact plus a check that reads it is a claim
someone else can re-run. The point is not to make the research infallible; it is
to make it possible to tell when the prose and the record disagree.

## Record the negative outcomes

Negative and null outcomes are recorded as they stand rather than rounded toward
the hypothesis. That is harder than it sounds, because a null result is not a
story. But a research repo that only contains the runs that worked is a
marketing page with a bibliography.

The later architecture-search phase reports a positive result on a narrower
question. That does not settle the central one, and the project does not present
it as if it does. The distinction between "a narrower question was answered" and
"the hypothesis was demonstrated" is the whole discipline.

## The method is the reusable part

A pre-registered study is not slower than an exploratory one; it is slower to
start and faster to trust. The decision rule, the control arms and the
artifact-checking script are the reusable part. The next experiment inherits
them, and the reader inherits a way to check the claim rather than a reason to
believe it.

The point is not to be right. The point is to make it possible to know whether
you were.
