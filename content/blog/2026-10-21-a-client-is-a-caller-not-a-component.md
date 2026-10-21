---
title: A client is a caller, not a component
date: 2026-10-21
summary: >
  The miner and the upgrader started inside the agents-fyi service. Moving them
  out was not a refactor: it decided what the service owns, what a client may
  know, and where a rule is allowed to live.
tags: [architecture, boundaries, agents]
---

The [miner](/work/miner) and the [upgrader](/work/upgrader) are separate repositories now, with their own suites, images and licences. They reach the [service](/work/agents-fyi) the same way any other caller does: over its public API, with an operator key.

The code was never the hard part. A client of a service is a place where a rule can quietly fork, and every fork is two answers to one question.

## The rule gets one home

The upgrader walks a Rails application forward one release at a time. To do that it needs to know what each release changed and which of those changes a machine may apply. That is the ladder, and the ladder lives in the service. The client asks.

It would be easy to ship a copy. Rails' release order is public; a table of changes could sit in the repository and the tool would still work. That copy would be the problem. The ladder changes when a release is documented, when a rule is corrected, when the corpus observes something the guide does not carry. A client with its own copy does not crash when it drifts. It gives a slightly different answer, in a tool whose whole output is a plan somebody acts on.

The same reasoning gives the upgrader no default service. A walker that quietly talked to the deployment its author runs would answer from a corpus the caller did not choose. `AGENTS_FYI_URL` or `--api` names one, and a mode that needs a service and has neither refuses. That is a small thing in a help text and a large thing in a trust model.

## The suite moves to where both sides are checked out

There is a test question underneath the split. The client has agreements with the service: the shape of the ladder, the schema of a plan, the scan recording, the exit codes. Those agreements can be tested from either end, and neither end can test them completely.

The client's own suite runs with no network, no Rails application and no service, because every external seam is injected. That is the right suite for the client's internals. It cannot say the client and the service agree. The service's suite holds the client's frozen recordings and the deployment's wiring, because only a checkout that contains both sides can compare them. Two suites, each testing what it can actually see, rather than one suite pretending.

## A client is not in the image

The miner and the upgrader run beside the service. They are services to an operator. They are not part of the application, and the boundary is deliberate: a change to a client is not a reason to redeploy the service, and deploying the service cannot ship a client.

This is the part that feels obvious once it is written down, and was not obvious while it was true in reverse. The first version of the upgrader's engine knew one application: it named `bin/rails`, `bundle exec rspec`, a specific environment variable, a specific image prefix. A second project measured by that engine would not have crashed. It would have been measured with the first project's knowledge, which is worse, because the output would look like a plan. The engine now walks a project declaration and a stack pack, and it names no repository, command or secret of its own.

## What a caller may know

A client holds an operator key, not an administrator token. It gets the same public surface as anybody else, which means it cannot do anything the API does not offer, and the API's rules apply to the machine that filed a report exactly as they apply to a person. The miner registers its own account and keeps the key in a file of its own, never in an environment variable and never in a log.

That is the shape I want: the service owns what a fact means, the clients do the work that needs a network and a compiler, and the boundary between them is an HTTP contract rather than a shared object graph.

The service, the miner and the upgrader are all in the [work section](/work). Both clients publish their design notes, including the failures that changed them.
