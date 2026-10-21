---
title: What changes when your caller is an agent
date: 2026-10-20
summary: >
  An HTTP API for agents is not a website with JSON. The caller has no browser,
  no cookies and no patience for an error it cannot act on.
tags: [api-design, agents, webcap, typescript]
---

[Webcap](/work/webcap) is an HTTP API for capturing web pages, extracting
structured content and watching pages for changes. It was built to be called
from scripts and software agents, with a free preview and pay-per-call access
rather than a required account.

That last sentence changes the design. A person clicking through a dashboard can
interpret an error, find a login form and try again. An agent needs a schema, a
stable identifier and a next step. When the caller is a machine, the API is the
product.

## The response is the interface

A browser automation API can return a screenshot and call it done. An agent
usually needs something it can reason about: the title, the headings, the links,
the paragraphs, the Markdown, and an explicit indication of whether the result
was truncated. A screenshot is evidence for a person; structured content is
evidence a program can use.

The free preview is part of the same idea. It lets a caller see the shape of the
answer before paying for it, and it marks what was omitted. A truncated response
that says it is truncated is useful; one that silently drops half the page is a
trap.

## Errors have to be actionable

An HTML error page is invisible to an agent. A prose message is barely better.
The error needs a status, a stable type and, where possible, the field or
parameter that caused it. "Invalid request" is not an error a model can recover
from; "send `url` as an absolute http(s) URL" is.

The same rule applies to timeouts and browser failures. A page that took too
long, a selector that no longer exists and a site that refused the request are
different failures. If they all arrive as a generic 500, the caller cannot
decide whether to retry, change the request or give up.

## Batch and idempotency are not optional

An agent rarely has one URL. It has a run of them. A batch endpoint that returns
one result per input, with a per-item status, is the difference between one
round trip and twenty-five. The response should say which items succeeded, which
were duplicates and which failed, without failing the whole batch.

Retries are the other half. A capture that times out may be worth retrying; a
request that was refused because the URL is invalid is not. Idempotency keys and
stable job ids let the caller retry a run without creating a second copy of the
work.

## Payment is part of the protocol

Webcap uses the x402 flow: a caller that has not paid gets a `402` with the
payment instructions, and access is settled in USDC on Base per call rather than
through a required account. The free preview is the part that lets a caller
evaluate the service before it pays.

That is an API-design decision, not a billing detail. The payment challenge is
machine-readable, it happens inside the request flow, and it does not require a
human to sign up first. For an agent, that is the difference between an API it
can use and a service it has to ask its operator to configure.

## The browser is the engine, not the interface

Underneath, Webcap runs Playwright: a real browser loading a real page,
capturing it, and extracting the parts the caller asked for. That is expensive
and failure-prone, so the API has to bound it. Timeouts, concurrency limits,
caching and SSRF protection are not implementation details; they are what make
the service safe to expose.

Scheduling and webhooks are the same shape in the other direction. A caller that
wants a page watched does not want to poll; it wants a webhook when the content
changes. The webhook is an API call the service makes, and it needs the same
care as the one it receives: retries, signatures, a stable payload and a way to
turn it off.

## The old automation, with a new caller

The lineage is familiar. An earlier role used Watir and Sidekiq to automate a
browser and remove manual work; Webcap uses Playwright and an HTTP contract to
do the same thing for a caller that is not a person. The tools changed. The
question did not: what does the caller need to know, and what should it be able
to do next?

When the caller is an agent, the answer is in the schema, the error and the
payment challenge. The browser is the engine. The API is the product.
