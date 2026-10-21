---
title: Making a green build mean a runnable application
date: 2026-10-20
summary: >
  A pipeline that runs tests but never boots the application can be green while
  the container is broken. The build is a product, and green should mean
  runnable.
tags: [ci-cd, docker, rails, testing]
---

A green build is a claim. If the pipeline runs the tests in one environment and
the deployment runs the application in another, the claim is narrower than it
looks. The suite can pass while the image is missing a native library, the
process binds the wrong port, the health check is wrong, or the application
starts with an empty content store.

The build is the first user of the code. It should be treated like a product:
one command, one contract, and a failure that a person can read.

## Pin the environment

A reproducible build starts with a reproducible runtime. The base image is
pinned by digest rather than by a tag that can move. The gems are locked. The
same commands work on a host Ruby and in the container, or the difference is
explicit and tested.

Pinning is not bureaucracy. The upgrade work is affordable because the
environment is not a variable. When the runtime moves, it moves deliberately,
and a rebuild months later is the same runtime rather than whatever the tag
points at that day.

## Build the production image in CI

The test environment and the production image are not the same thing. The
production image has no test framework and no compiler; it runs as an
unprivileged user with a read-only root filesystem. Those differences are the
point, and they are also where a build can pass and a deployment can fail.

So CI should build the production image and run it. Not only `docker build` —
start it, wait for it to be healthy, and make a request that proves it can serve
a real page. A health endpoint that returns `200` with an empty body is not
enough. The site's `/healthz` reads the same content store the pages read, so a
container that cannot read its content is reported unhealthy rather than serving
empty cards.

## One gate, and it must run something

The gate should be one command. Two commands that are almost the contract are
worse than one, because the second one becomes the one somebody runs when the
first is inconvenient.

The gate also has to refuse a vacuous pass. A test runner that collects zero
examples exits successfully; a suite that skips every database test because the
driver is missing reports a green line. The project has both guards: `rspec`
runs with `fail_if_no_examples`, and the entry point aborts when the database
driver is absent. The miners and the walker have the same rule in their own
suites: a command that did not run is not a pass.

## The checks that are not tests

Some of the most valuable checks are not unit tests:

- a real HTTP request to every page, including a path that must return `404`;
- an external link check, because a live project card can point at somebody
  else's service that has moved;
- a content validation at boot, so a missing screenshot or an unknown status is
  a startup failure rather than a blank card;
- a documentation check, so a command example the README promises is a command
  the CLI actually accepts.

These are cheap, and they catch the failures that a unit suite cannot see
because they are about the built thing rather than the code.

## The team version

On a long-lived retail application, Docker and a CI pipeline were the change
that made the framework upgrades affordable. Before that, part of the cost of
every upgrade was an environment that no longer matched: a native extension that
built on one machine and not another, a service that was only configured on the
machine it was written on. Making the environment reproducible turned the
upgrade into a problem about code, which is the problem it was supposed to be.

A green build has to mean a runnable application. Once it does, shipping an
upgrade step is an ordinary deploy rather than an event with a room booked for
it.

That is the standard I want from a pipeline: not a badge, but a statement that
the thing that passed is the thing that runs.
