## Summary

<!-- What changes, and why is it needed? Link the issue if there is one. -->

Fixes #

## Type of change

- [ ] Bug fix
- [ ] Documentation correction
- [ ] Accessibility improvement
- [ ] Test or harness change
- [ ] Content or factual correction
- [ ] Refactor with no intended behaviour change
- [ ] Other (explain above)

## How it was verified

<!-- Paste the relevant command output, not a summary of it. -->

```text
bin/site check
```

If this touches `config/puma.rb`, the Dockerfile or a Compose file:

```text
bin/site build && bin/site up --no-tunnel && bin/site verify
```

If this changes an external URL:

```text
bin/site links
```

## Checklist

- [ ] The change is focused on one problem.
- [ ] I read the relevant documentation, including the editorial rules for content changes.
- [ ] `bin/site check` passes.
- [ ] I added or updated a test for a bug fix or a new invariant.
- [ ] I did not add a dependency without a reason in this description.
- [ ] I did not include a secret, a `.env` value or a tunnel token.
- [ ] I have the right to submit this work and accept the contribution terms in `CONTRIBUTING.md`.
