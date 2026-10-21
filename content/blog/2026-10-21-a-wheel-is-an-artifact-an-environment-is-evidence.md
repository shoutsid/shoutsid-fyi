---
title: A wheel is an artifact, an environment is evidence
date: 2026-10-21
summary: >
  The miner installs thousands of releases, and it shares its download cache
  between three clients while refusing to share the environments. The line is
  not disk cost: a wheel is an artifact, and an environment is where a verdict
  was produced.
tags: [python, caching, measurement, verification]
---

The [miner](/work/miner) installs releases all day. Every comparison is two virtual environments, one per release, and every environment is a `pip install` that pulls the same transitive dependencies the last one did. So the obvious optimisation is to share what is shared, and the interesting part is deciding what that is.

## The measurement that made the case

The first version kept `PIP_NO_CACHE_DIR=1`. That is the right default for an image build and the wrong one for a container whose job is installing releases. Measured on the live deployment, of 1,622 wheel installations across 143 environments, only 426 were distinct: seventy-four per cent were a wheel already present in another environment on the same volume, and `typing_extensions` alone had been installed 43 times.

The fix is a `pip_cache` volume shared by all three clients — the miner and the two verifiers. Ten common transitive dependencies, installed into a fresh environment, then read 18 cached and 0 downloaded, about 16 KB on the wire against roughly 3 MB before. The cache is bounded: unbounded it reached 1.7 GB in forty minutes across 1,462 entries.

## What is not shared, and why

The environments are deliberately separate. That is not a disk decision. An environment is where the wheel is unpacked and executed, which makes it evidence — the thing a finding was produced in. A verifier probing inside the miner's environment would be checking a claim with the material the claim came from, and the confirmation would stop being independent without anything looking wrong.

So the rule is about what a thing is *of*, not what it costs. A wheel is an artifact: the index published a hash for it, two readers cannot disagree about its bytes, and a copy of it is not a claim about anything. An environment is a working tree: it is what ran, it is what a verdict is attributed to, and it has to be built by the party that will be judged on it.

The same split appears one layer down in the [upgrader](/work/upgrader). Its step runs on an era interpreter — the oldest Ruby the rung allows — and its bundle used to be keyed by the working copy alone. At the 7.0 rung, the first rung to run in a different era, the 2.7 era's `bundle install` loaded an extension the 2.5 era had built: `LoadError: libruby.so.2.5: cannot open shared object file`. Every era after the first then failed the machine probe with it, and the probe is itself a `bundle install`, so its failure read as "no interpreter installed the application's bundle". The bundle path now carries the era. A gem cache may be shared; the tree a gem is unpacked into may not.

## The budget that measured the wrong thing

There is a second version of the same mistake, and it is about what a number counts. The environment budget summed `st_size` — the length of each file's contents — while the disk is spent in blocks. A `site-packages` directory is thousands of small modules, and each rounds up to a whole block, so the figure came in about ten per cent low. The verifier's 9.1 GB of environments summed to 8.2 GB of file lengths, inside an 8 GiB budget, so the pruner returned `(0, 0)` while the cache sat over its bound. It sums `st_blocks * 512` now.

A fixture with one large file cannot see that bug. The case that rounds is many small files, which is exactly what an installed environment is.

## What the distinction buys

The cache is now a shared, bounded, disposable thing, and the environments are three private working sets pruned on their own budgets. The verifiers still install the same releases the miner installed, so they still hit the cache — they just do it in their own trees, which is the whole point.

A shared cache is a performance decision. A shared environment would have been an evidence decision, made accidentally, in the direction of the answer the machine was already giving.

The measurements are in the miner's [design notes](https://github.com/shoutsid/miner/blob/main/docs/design-notes.md), with the failures that produced them.
