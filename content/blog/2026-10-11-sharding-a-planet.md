---
title: The only thing two cells share is a port
date: 2026-10-11
summary: >
  Partitioning a world that is larger than memory settles one problem and
  creates a sharper one: two cells sharing an edge must stay consistent while
  being unable to see inside each other.
tags: [simulation, cpp, sharding]
---

Simulating a world larger than memory has an obvious first move: cut it into
cells and simulate each cell separately. That settles the memory problem and
creates a harder one. Two cells that share an edge now have to agree about the
world while having no way to see each other's state.

Planetary Matrix partitions the planet on the S2 grid. The mean cell area is
about 1.267 km² at level 13 and about 0.317 km² at level 14. Level 13 is the
unit of work: each level-13 cell is an independent shard of a sharded
key-value store. A level-14 cell is deliberately not a shard of its own — it
addresses a square inside a level-13 cell, which is how a shard holds detail
finer than its own level without becoming a second process.

## A cell cannot see over its own edge

The only thing two neighbouring cells share is a graph of boundary ports. A
cell's state is its own; what crosses the edge is a port and nothing else. That
constraint is what makes the partition real rather than decorative. If a cell
could reach into its neighbour whenever it liked, the shard boundary would be a
folder layout with extra steps.

## An evicted cell still answers

Residency is the part I keep coming back to. A shard can be evicted: its
payload is written back to the store and its connected ports become proxies.
The far side does not stop. It keeps running against what is effectively a
proxy horizon, receiving at the boundary from something that is no longer in
memory.

That is a claim about decoupling, and a claim is worth what the check behind it
is worth. So there is a command that drives it rather than asserting it: it
marries the boundary port, evicts the source, steps the simulation, and reports
whether the far side still received anything with the source out of memory.
Either the flow survives the eviction or the command says it did not.

The same shape appears in utility flow across two cells. A boundary scan
marries the dangling ports. The flow is reported as the neighbour's shortfall
rather than the supplier's surplus. The supplier is written down and dropped —
and the neighbour still receives, with that flow labelled synthesised, because
by then it is being produced at the boundary rather than read from a live cell.

## A gate that cannot reach the network

The build gate is one script, and it fetches nothing. That is a requirement
rather than a convenience: Flecs and doctest are vendored, and the S2 cell-id
algorithm is implemented in the tree rather than linked against
`google/s2geometry`, which would pull Abseil and OpenSSL into the build. A
clean configure and build needs no network, so it behaves the same on a machine
with egress disabled as on the one it was written on.

## What is built, and what is not

Three milestones exist, and each is demonstrated by a named artifact rather
than a paragraph: the headless CLI sandbox, cross-grid flow across an eviction,
and a browser viewport served by a second binary over a recorded HTTP contract.
The graphical client is deliberately not part of the simulation — it reads the
state of the cell around the player over HTTP and draws it.

The CLI keeps its command layer in its own translation unit for a related
reason: the suite can then drive a command directly instead of shelling out to
the binary, so the commands are tested as the things a person types.

None of this is finished. What is built is a minimum playable loop rather than
a feature list — each milestone is a thing that can be run and checked, which
is the only reason the boundary-port claim above is worth anything.
