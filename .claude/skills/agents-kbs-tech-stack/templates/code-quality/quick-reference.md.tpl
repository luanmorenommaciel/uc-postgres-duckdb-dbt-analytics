# Code Quality Quick Reference

> **Purpose:** Cross-tech baseline that every closer grounds in. Tech-agnostic universals only.
> **Used By:** code-reviewer, code-simplifier, code-documenter
> **Last Updated:** auto-installed by `install-closers.sh`

<!--
  Hard limit: 100 lines. Universal patterns only — anything tech-specific belongs in `kb/<tech>/`.
  This file is the closers' SECOND read (after the tech KB) and the source of truth for findings
  that don't have a tech-specific KB section to cite.
-->

## Identity

Cross-tech code quality — comments, dead code, security universals. Grounded in by every closer
in the project. When a closer finds an issue that isn't tech-specific (e.g. a hardcoded secret,
a commented-out block, a `// increment i by 1`), it cites this KB instead of the tech KB.

## Decision flow

```text
┌─────────────────────────────────────────────────────────────┐
│  CLOSER → CODE-QUALITY KB FLOW                              │
├─────────────────────────────────────────────────────────────┤
│  1. CLASSIFY     → review | simplify | document             │
│  2. LOAD         → this KB + matching tech KB for the file  │
│  3. CROSS-CHECK  → universals first, tech-specific second   │
│  4. APPLY        → cite the specific concept doc per finding│
│  5. VERIFY       → tests still green; no behavior change    │
└─────────────────────────────────────────────────────────────┘
```

## Index

| Concept | File | When the closers read it |
|---------|------|--------------------------|
| Comments | [concepts/comments.md](concepts/comments.md) | `code-documenter` — every docstring/comment decision |
| Dead code | [concepts/dead-code.md](concepts/dead-code.md) | `code-simplifier` — every deletion proposal |
| Security universals | [concepts/security-universals.md](concepts/security-universals.md) | `code-reviewer` — every diff, before tech-specific checks |

## When closers consult this KB

- **code-reviewer** reads `security-universals.md` first on every diff. Universal security
  rules apply before any tech-specific check. A leaked secret is a BLOCKER regardless of
  what language it leaked in.
- **code-simplifier** reads `dead-code.md` before proposing any deletion. The "is it
  actually dead?" checklist is the universal gate; the tech KB adds language-specific
  signals (e.g. Python decorators, JS dynamic imports).
- **code-documenter** reads `comments.md` to decide *whether* a comment should exist.
  The tech KB decides the *style* (docstring format, JSDoc vs TSDoc, etc.).

## Universal lookup

| Signal | Closer | Action | Concept |
|--------|--------|--------|---------|
| Hardcoded API key / token | reviewer | BLOCKER | [security-universals](concepts/security-universals.md) |
| Commented-out code block | simplifier | DELETE | [dead-code](concepts/dead-code.md) |
| Comment restates code | simplifier / documenter | DELETE | [comments](concepts/comments.md) |
| Unreferenced export | simplifier | DELETE (after grep + tests) | [dead-code](concepts/dead-code.md) |
| Public API without docstring | documenter | ADD | [comments](concepts/comments.md) |
| User input concatenated into SQL/shell | reviewer | BLOCKER | [security-universals](concepts/security-universals.md) |
| Auth check skipped on a privileged path | reviewer | BLOCKER | [security-universals](concepts/security-universals.md) |
| Magic number with no constant | documenter / reviewer | NAME the constant | [comments](concepts/comments.md) |
| Banner comment with no content | simplifier | DELETE | [comments](concepts/comments.md) |
| Feature flag stale > 90 days | simplifier | RETIRE | [dead-code](concepts/dead-code.md) |

## Cross-references

| Need | File |
|------|------|
| Comment policy (WHY vs WHAT) | [concepts/comments.md](concepts/comments.md) |
| Dead-code detection + removal checklist | [concepts/dead-code.md](concepts/dead-code.md) |
| Five universal security rules | [concepts/security-universals.md](concepts/security-universals.md) |
| Tech-specific style | `kb/<tech>/quick-reference.md` |
| Project handbook | `CLAUDE.md` at repo root |
