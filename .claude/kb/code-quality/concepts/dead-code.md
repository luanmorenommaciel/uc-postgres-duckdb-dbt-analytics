# Dead Code

> **Purpose:** Dead code is code that no execution path reaches AND no test exercises — both halves required.
> **Used By:** code-simplifier (primary), code-reviewer
> **Confidence Required:** 0.95
> **Last Updated:** auto-installed by `install-closers.sh`

## Overview

The simplifier's hardest job is distinguishing **dead** from **dormant**. Dead code is
unreached at runtime *and* untouched by tests *and* uncalled by tooling. Dormant code
looks unused locally but is wired up by dynamic dispatch, decorators, plugin registries,
config-driven imports, or downstream consumers.

This concept defines the detection signals and the removal checklist. Both halves of the
test — "no execution path reaches it" AND "no test exercises it" — must pass before the
simplifier deletes anything.

## Detection signals

| Signal | Confidence it's dead | Notes |
|--------|---------------------|-------|
| Unused export | Medium | Check downstream packages, plugin registries, config files |
| Unreferenced function (LSP says 0 refs) | High | But check dynamic dispatch and decorators |
| Commented-out block | Very high | Always delete; version control is the archive |
| Branch test-coverage never hits | High | Could be defensive code for impossible states — check intent |
| Feature flag stale > 90 days | High | Retire the flag *and* the dead branch together |
| `if False:` / `if 0:` block | Very high | Delete on sight |
| Module imported but never used | High | Most linters catch this — trust the linter |
| Class with no instantiations | High | But check serialization frameworks, ORM models, Pydantic |
| Function defined inside `__all__` but never used | Medium | Public API surface — needs an architect call |
| Last-modified > 2 years, no test coverage | Low | Age alone doesn't make it dead |

## Removal checklist

Before deleting any code, all of these must pass:

```text
[ ] Zero textual references (grep across the entire repo, not just the package)
[ ] Zero LSP/IDE references (the language's own resolver agrees)
[ ] No dynamic dispatch reaches it
    - No decorators register it (Flask routes, pytest fixtures, click commands)
    - No string-based dispatch (getattr, importlib, JSON-driven plugin systems)
    - No reflection (Python __subclasses__, JS Proxy, framework auto-discovery)
[ ] No tests exercise it
    - Including integration tests that may import it transitively
    - Including snapshot tests where output mentions it by name
[ ] No downstream package imports it
    - Check the project's published surface (__all__, package.json exports, setup.py entry_points)
    - Check sibling repos in the same monorepo
[ ] No config file references it by string
    - YAML/JSON/TOML configs often reference class names as strings
[ ] No documentation references it
    - README examples, ADRs, the CLAUDE.md handbook
[ ] Tests still pass AFTER the deletion (not just before)
```

If any box is unchecked, the code is dormant, not dead. Leave it.

## Anti-patterns

- **Deleting "unused in this commit" code.** A function added in PR #200 and used in PR #210 is not dead — it's planned. Check the open PRs and the recent merge history.
- **Trusting static analysis alone.** Decorators, dynamic dispatch, framework auto-discovery, and reflection all fool linters. Static analysis is necessary but never sufficient.
- **Leaving zombie tests for deleted code.** When the production code goes, so do its tests. A test that no longer has anything to test is itself dead.
- **Removing exports because they're "internal-looking".** If it's in `__all__` / `package.json#exports`, downstream code may depend on it — even if your own grep shows zero hits.
- **Deleting defensive branches that "never run".** A branch for an impossible state may be load-bearing if the state ever becomes possible. Check intent first — comment-driven defensive code stays.
- **Bulk-deleting "unused imports" in generated files.** Generated code's "unused" imports are often hooks for the generator. Simplify the generator instead.

## What dead code looks like across techs

| Tech | Common shapes of dead code |
|------|---------------------------|
| Python | Old `compat_*` modules, unused `Optional[X]` types, unreachable `else: raise NotImplementedError` |
| TypeScript | Unused exports in `index.ts`, unreferenced type aliases, dead branches behind `process.env.LEGACY_*` |
| React | Components imported but never rendered, stale prop drilling, unused hooks |
| SQL | Views nothing queries, columns nothing reads, migrations that drop already-dropped objects |
| Shell | Functions in `lib/*.sh` no script sources, dead `case` arms |

## Removal protocol

1. Identify the candidate via detection signals.
2. Walk the checklist. Document any "no" in writing.
3. Propose deletion with the simplifier's standard output format.
4. Run the full test suite — production + integration + e2e if available.
5. If anything breaks, the code wasn't dead. Revert and update the checklist with the new signal.

## When this applies

- Every simplification pass.
- Every refactor that touches a module > 6 months old.
- Every feature-flag cleanup.

## When this does NOT apply

- Performance-critical code paths — even if a branch looks dead, measure first.
- Generated files — simplify the generator, not the output.
- Public-API surface — that's an architect call, not a closer call.

## Related

- [comments](comments.md) — commented-out code is the most obvious dead code
- [security-universals](security-universals.md) — dead authentication paths are a security risk, not a cleanup task
