---
title: What an MCP server owes a model
date: 2026-10-17
summary: >
  An MCP server is a product surface for a model, not a JSON-RPC wrapper.
  Annotations, actionable errors and a harness that measures discovery decide
  whether an agent can use it.
tags: [mcp, agents, api-design]
---

The first version of the [agents-fyi](/work/agents-fyi) MCP server was a
hand-rolled JSON-RPC loop and a 72 KB recording of the handshake a Python server
gave, served byte for byte. That worked while the protocol was small. When the
surface grew, the server moved onto the official Ruby SDK and the recording
became an oracle rather than the bytes a client receives.

The move exposed the part that is easy to miss: an MCP server is not a transport
wrapper. It is the API a model sees, and every part of that API has to be
designed for a reader that cannot inspect the server.

## Annotations are not neutral

No tool carried MCP annotations. A harness uses `readOnlyHint` to decide whether
a call needs its operator's permission first, and unset does not mean "probably
fine". It means every search of a read-only knowledge base looks like a write.

The three shapes are declared once — read-only, upsert, create — so a tool
cannot be annotated by feel. One detail matters more than it looks:
`submit_report` is deliberately *not* idempotent. A repeat is refused as a
duplicate, and a harness that retried on an idempotency hint would get a 409 it
did not expect. The annotation has to describe the operation, not the mood of
the endpoint.

## Errors are part of the API

The SDK sends a `ToolError`'s message to the caller. Every other exception is a
crash, and the model receives only `Error executing tool <name>` while the text
stays on the server. That difference is the whole error design.

Every refusal this service writes is a next step: "Report not found", "send `q`,
or a `trace`", "This reads forward moves: `2.0.0` is ahead of `1.2`". All of it
was being discarded. `_fail` is now the one place that raises, and a transport
test pins that the sentence arrives over the wire rather than merely existing in
the source.

The temptation is to treat error wording as a nicety. For an agent it is the
only correction it gets. A model that is told "Error executing tool" learns
nothing; a model that is told to send `q` instead of `query` can continue.

## Discoverability is measurable

`dev.sh mcp` proves the tools answer when they are called. It cannot prove an
agent reaches them. A tool can be perfect and undiscoverable, or discoverable
and unusable by a model that has to choose it from a list.

So the project has a harness. It mounts the MCP server and turns every other
capability off, including the SearxNG MCP server a user-level patch mounts into
every profile. Then it runs six tasks phrased the way a caller would ask them.
None of the tasks names a tool, because choosing the tool is the first thing
under test. The score is read from the live corpus — a substring, a regex or a
tool call — with no judge model. A task is predictable only if it passed every
repeat, and the command exits zero only then, so a task that works two times in
three cannot hide in a pass rate.

The harness found three things the unit tests could not.

**A small local model was not good enough.** The same six tasks, same harness:
it never called the right tool and spent its calls on invented tasks. A hosted
model completed them. The result is not a model ranking; it is a statement that
the surface can be measured, and that "the tools answer" and "a model reaches
the tools" are different claims.

**The probe could reach a write tool.** Every task was a read, but the harness
mounted all fourteen tools, and nothing stopped a model from calling one of the
eight that change the corpus. One model invented a failure nobody asked about
and called `submit_reports`; another tried to file four reports and a batch
while answering a question. The API key is now cleared rather than inherited
(`--api-key` is the opt-in), the corpus-changing tools are counted from the
server's own annotations, and a call to one fails the attempt. The effect on
the harness's own score was immediate: a run that had looked perfect became an
imperfect one, because the writes were always happening and were not being
counted.

**A refusal never reached the model.** That is the `ToolError` fix above, found
by asking a real model to use the surface rather than by reading the handler.

## A hosted endpoint has a different caller

The same surface is served over Streamable HTTP, one server per request, reading
the caller's own operator key and storing nothing. The transport changed one
sentence: a write with no credential used to say `AGENTS_FYI_API_KEY is not
set`, which is true for a stdio server reading its own environment and a dead
end for a remote caller. The refusal now names the header the caller can set —
`X-API-Key` or `Authorization: Bearer`.

That is the same rule as the rest of the surface: the error is written for the
person or process that can act on it. A local harness and a hosted caller need
different instructions because they have different powers.

## The test is whether a model can use it

An agent tool is not finished when it works in-process. It is finished when a
model can discover it, call it, and read what went wrong. The transport test
covers the schemas and annotations on the wire; the harness covers the choice
and the refusal. Neither replaces the other, and the unit suite cannot stand in
for either one.

The server in this project is small. The same questions apply to any MCP surface
that expects a model to use it without a person reading the README first.
