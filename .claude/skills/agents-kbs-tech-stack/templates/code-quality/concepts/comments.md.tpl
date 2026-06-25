# Comments

> **Purpose:** Comments document WHY, not WHAT — code documents what.
> **Used By:** code-documenter (primary), code-simplifier, code-reviewer
> **Confidence Required:** 0.85
> **Last Updated:** auto-installed by `install-closers.sh`

## Overview

A comment exists to record information the reader cannot recover from the code alone:
surprises, constraints, the reason a workaround is shaped this way, the trade-off behind
a non-obvious choice. Every other comment is debt — it lies eventually, distracts always,
and adds maintenance load forever.

The closers use this concept as the universal rule. Tech-specific docstring *style*
(Google vs NumPy vs TSDoc vs JSDoc) lives in the tech KB; the *decision to write a
comment at all* lives here.

## Core principles

1. **Comment surprises and constraints.** If a future reader will ask "wait, why?", that
   question deserves a comment. If the answer is "because the code says so", delete it.
2. **Never comment what the code already says.** `// increment i by 1` is noise. The
   comment must add information the code cannot.
3. **Docstrings document contracts, inline comments document non-obvious decisions.**
   Public APIs always get a docstring (inputs, outputs, errors, side effects). Inline
   comments are reserved for the surprising line.

## Decision matrix

| Code smell | Comment fix |
|------------|-------------|
| Magic number (`if retries > 3:`) | Name the constant (`MAX_RETRIES = 3`) — no comment needed |
| Surprising branch (`if x and not legacy_mode:`) | Comment WHY the legacy_mode path differs |
| Workaround for a library bug | Link the upstream issue / PR; date the workaround |
| Obvious code (`# fetch user`) | Delete the comment |
| Empty function with `# TODO` | Either implement, or delete the empty body |
| `# returns the user's name` on `get_user_name()` | Delete — the signature already says so |
| Math that isn't obvious | Cite the source (paper, Wikipedia, RFC, ADR) |
| Non-obvious ordering constraint | Comment the dependency — "must run before X because Y" |

## What deserves a comment

- **Surprises** — anything the next reader will pause on.
- **Constraints** — invariants that aren't enforced by the type system or tests.
- **Workarounds** — link the upstream bug; without the link the comment rots.
- **Performance choices** — "O(n²) is fine here because n ≤ 32; measured at <1ms".
- **Security boundaries** — "validated upstream in `auth.py`; do not re-validate".
- **Public API contracts** — docstrings for everything imported across module boundaries.

## What does NOT deserve a comment

- Code that already self-documents through naming.
- Restating the language (`# loop over items`, `// assign x to y`).
- Section banners with no content (`# ─── HELPERS ───`).
- Commented-out code — delete it; git remembers.
- Personal notes (`# Bob's hack`, `# TODO(me): fix later`) — open a ticket instead.
- Comments that haven't been true since 2019 — delete on sight.

## Anti-patterns

- **Commented-out code.** Always delete. Version control is the archive.
- **Restating the obvious.** `# increment i by 1` on `i += 1` is pure cost.
- **Banner comments without content.** `# ─── SECTION ───` with nothing useful below is
  decoration. If the section needs a name, the function does.
- **Stale TODOs.** A TODO older than the last refactor is fiction. Convert to issue or delete.
- **Comments that argue with the code.** When the comment and the code disagree, both are
  wrong. Reconcile or delete.

## When this applies

- Every diff the documenter touches.
- Every simplification pass — the simplifier removes what-comments aggressively.
- Every review — the reviewer flags comments that lie about the code.

## When this does NOT apply

- Generated files (`*_pb2.py`, `*.generated.ts`) — let the generator decide.
- Test files — tests stay verbose by choice; over-documenting tests is rarely the problem.
- Migration scripts — comments here often *are* the documentation; preserve liberally.

## Tech-specific overrides

Style (Google vs NumPy vs TSDoc vs JSDoc vs `///`) lives in the tech KB. This concept
governs *whether* to write the comment; the tech KB governs *how* it's formatted.
When a tech KB is silent, default to:

- **Python**: Google-style docstrings on public functions/classes; `# ` inline for surprises.
- **TypeScript/JavaScript**: TSDoc (`/** */`) on exports; `// ` inline for surprises.
- **SQL**: `-- ` on non-obvious columns and CTEs; never on `SELECT *`.

## Related

- [dead-code](dead-code.md) — commented-out code is dead code
- [security-universals](security-universals.md) — security comments must cite the boundary they enforce
