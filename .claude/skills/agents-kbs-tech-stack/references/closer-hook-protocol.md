# Closer-Hook Protocol — How Closers Ground in Tech KBs

> Reference for the three universal closers (`code-reviewer`, `code-simplifier`, `code-documenter`).
> Explains how they stay tech-aware without being tech-coupled.

## The problem

A reviewer that only knows "good code is good" produces useless reviews. A reviewer per tech (`react-reviewer`, `python-reviewer`, …) bloats the agent count.

The closer-hook protocol resolves this: **one reviewer, but it loads the matching tech KB at invocation time, based on what's actually in the diff.**

## The protocol

When a closer is invoked:

1. **Enumerate tech domains.** Read `.claude/kb/_index.yaml`. The `domains:` map lists every tech the project has scaffolded (e.g., `react`, `fastapi`, `postgres`).

2. **Detect tech per file.** For each file in the closer's scope:
   - File extension → primary tech candidate
   - Imports / shebangs / file content → secondary tech candidates
   - Project signal (e.g., `package.json` framework) → tiebreaker

3. **Load matching KBs.** For each candidate tech that exists in `_index.yaml`, load:
   - `quick-reference.md` (always — it's the fast lookup)
   - `patterns/<file>.md` relevant to the change kind (only the relevant ones, not all)
   - `concepts/<file>.md` for any concept the diff touches
   - Skip `reference/` unless a specific lookup is needed (reference files can be large)

4. **Always also load `kb/code-quality/`** if present — that's the closer's own KB, tech-agnostic universals (no-comments policy, dead-code patterns, doc style).

5. **Cite at output.** Every finding (reviewer), proposed deletion (simplifier), or doc addition (documenter) cites the KB file + section.

## Detection table

The closers use these defaults; override per project by editing the closer's own file.

| Extension / Pattern | Primary tech | Fallback |
|---------------------|--------------|----------|
| `.tsx`, `.jsx` | `react` if registered, else `typescript` | `code-quality` |
| `.ts` | `typescript` | `code-quality` |
| `.py` | `python` + any framework (`fastapi`, `langgraph`, `sqlglot`) detected from imports | `code-quality` |
| `.sql` | `postgres` or `sqlglot` depending on context | `code-quality` |
| `*.css`, Tailwind classes in markup | `tailwind` | `code-quality` |
| `next.config.*`, `app/` dir, `pages/` dir | `nextjs` (in addition to react/typescript) | — |
| `*.tf`, `terraform/` | (not in v1 menu — `code-quality` only) | `code-quality` |
| `Dockerfile`, `docker-compose.*` | (not in v1 menu — `code-quality` only) | `code-quality` |

**Layering matters.** A `.tsx` file in a Next.js project should pull `react` + `nextjs` + `typescript` KBs (in that order — most specific first).

## Examples

### Reviewer reviewing `web/app/components/GraphCard.tsx`

```text
1. Read kb/_index.yaml → domains: [react, nextjs, typescript, react-flow, tailwind, code-quality]
2. File extension .tsx → candidates: react, react-flow, typescript
3. Content scan: imports from 'reactflow' → confirms react-flow tech
4. Load:
   - kb/react/quick-reference.md
   - kb/react-flow/quick-reference.md
   - kb/react-flow/patterns/custom-node.md (diff modifies a custom node)
   - kb/typescript/quick-reference.md
   - kb/code-quality/quick-reference.md
5. Findings cite the loaded KB:
   - "BLOCKER — Custom node not wrapped in React.memo (kb/react-flow/patterns/custom-node.md, perf section)"
```

### Simplifier simplifying `src/agent/nodes/schema_context_node.py`

```text
1. Read kb/_index.yaml → domains include: python, langgraph, code-quality
2. File extension .py → primary: python; check for langgraph imports
3. Content scan: imports langgraph.graph → confirms langgraph
4. Load:
   - kb/python/quick-reference.md
   - kb/langgraph/quick-reference.md
   - kb/langgraph/concepts/json-safe-state.md (diff touches state)
   - kb/code-quality/quick-reference.md
5. Proposals cite KB:
   - "Remove try/except around impossible state mutation (kb/langgraph/concepts/json-safe-state.md, anti-patterns)"
```

### Documenter documenting a SQL file

```text
1. Read kb/_index.yaml → postgres registered
2. Extension .sql → postgres tech
3. Load:
   - kb/postgres/quick-reference.md (docstring style: -- comments only on non-obvious columns)
   - kb/code-quality/quick-reference.md
4. Generate inline comments matching the project's style; never use /* */ unless KB says so
```

## Why this works

- **One reviewer the user trusts beats five they don't.** Concentration of polish builds confidence.
- **No per-tech reviewer drift.** When the React KB changes, the reviewer adapts automatically — no need to update a `react-reviewer.md` separately.
- **Adding a tech is one scaffold call.** Adding `vue` to the menu and running scaffold means the closers gain Vue awareness immediately — no closer code changes.
- **Closers stay focused.** Each closer has one job (review / simplify / document); tech awareness is orthogonal grounding, not an extra responsibility.

## When the protocol breaks down

- **Diff spans many techs with conflicting conventions.** The closer should load all relevant KBs and explicitly note when conventions clash ("React KB prefers X here; Tailwind KB prefers Y").
- **A tech in the file isn't registered in `_index.yaml`.** The closer falls back to `code-quality/` and notes the gap: "No KB for this tech — review is style-agnostic. Consider scaffolding `<tech>`."
- **The `_index.yaml` is empty (no techs scaffolded yet).** The closer reviews universals only. Output should suggest scaffolding the relevant techs.

## What the closer KB (`kb/code-quality/`) contains

The closers' own KB lives under `kb/code-quality/` if the user creates it. It's optional in v1 of this skill — the closers function without it. If created, populate with:

- `quick-reference.md` — universal code-quality lookup table
- `concepts/comments.md` — when to write a comment, when not to
- `concepts/dead-code.md` — how to identify dead code safely
- `concepts/security-universals.md` — secrets, injection, auth
- `concepts/documentation-style.md` — universals around docstrings/READMEs
- `patterns/diff-review-rubric.md` — how to walk a diff systematically
- `patterns/refactor-safety.md` — preserve behavior, test green

The skill does NOT scaffold this KB in v1. The user creates it if they want closer sharpness on universals; otherwise the closers ground purely in the tech KBs.

## Override / customization

Each closer's file is editable. If the protocol's defaults don't fit a project:

- Edit the `## Closer-Hook Protocol` section of the closer's file to extend the detection table.
- Add project-specific tech mappings (e.g., "files under `pipelines/` → load `kb/lakeflow/`").
- The closer's frontmatter and core sections are stable; the protocol section is the customization surface.

The skill never overwrites closer files on re-run (see `install-closers.sh`) — once customized, they stay customized.
