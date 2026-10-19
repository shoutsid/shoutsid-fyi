# Documentation

This directory is the long-form documentation for `shoutsid.fyi`. The
[README](../README.md) is the project overview; these pages are the reference
material behind it.

## Start here

| If you want to… | Read |
|---|---|
| Run the site locally | [Getting started](getting-started.md) |
| Change ports, version or runtime settings | [Configuration](configuration.md) |
| Understand how a request becomes a page | [Architecture](architecture.md) |
| Add or edit a project, post or page | [Content authoring](content.md) |
| Deploy behind the Cloudflare Tunnel | [Deployment](deployment.md) |
| Run the checks or add a test | [Testing](testing.md) |
| Diagnose a failure | [Troubleshooting](troubleshooting.md) |
| Decide whether a sentence belongs on the site | [Editorial rules](editorial.md) |

## Project policies

These live at the repository root because GitHub surfaces them there:

- [Contributing](../CONTRIBUTING.md)
- [Code of Conduct](../CODE_OF_CONDUCT.md)
- [Security policy](../SECURITY.md)
- [Changelog](../CHANGELOG.md)
- [License](../LICENSE)

## Reading order

For a first contribution, the useful order is:

1. [Getting started](getting-started.md) — get the site running and the gate
   passing.
2. [Architecture](architecture.md) — learn where the moving parts are.
3. [Content authoring](content.md) — change what the site says.
4. [Testing](testing.md) — know what will fail and why.
5. [Editorial rules](editorial.md) — check the claim before you publish it.

Deployment and configuration are reference pages: read them when you need to
change the environment or the edge, not before the first run.

## A note on accuracy

The documentation describes the code in this repository, and the code is the
final authority. Where this directory and the implementation disagree, the
implementation is correct and the documentation is a bug. The same rule applies
to the site's content: see [Editorial rules](editorial.md).
