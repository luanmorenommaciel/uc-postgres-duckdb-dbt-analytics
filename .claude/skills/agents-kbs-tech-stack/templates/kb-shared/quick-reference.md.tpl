# {DOMAIN_DISPLAY_NAME} — Quick Reference

> **Purpose:** Fast lookup for {DOMAIN_DISPLAY_NAME}. The first read for both the
> architect and developer agents, and for any closer working a file in this tech.
> **Hard limit:** 100 lines. Deep material lives in `concepts/`, `patterns/`, `reference/`.

## Identity

<!-- TODO: one paragraph — what this tech is, its role in THIS project, and the one
     thing an agent must never get wrong about it. Ground in the official docs cited
     in reference/. -->

## Decision flow

```text
┌─────────────────────────────────────────────────────────────┐
│  {DOMAIN_DISPLAY_NAME} — AGENT FLOW                         │
├─────────────────────────────────────────────────────────────┤
│  1. CLASSIFY → architect (plan) or developer (ship)?        │
│  2. LOAD     → this KB, then the matching concept/pattern    │
│  3. VALIDATE → KB + MCP agreement matrix                     │
│  4. ACT      → cite the specific doc per decision/finding    │
│  5. VERIFY   → tests/assertions green; grounded in docs      │
└─────────────────────────────────────────────────────────────┘
```

## Index

| Kind | Doc | Read it when |
|------|-----|--------------|
<!-- TODO: one row per concept / pattern / reference doc seeded below. -->

## Cross-references

| Need | Where |
|------|-------|
| Project conventions every task follows | `CLAUDE.md` at repo root |
| Cross-tech code-quality universals | `kb/code-quality/quick-reference.md` |
| Architecture plans this tech serves | `sketch/analytical-backbone.md`, `sketch/sentinel-engine.md` |
