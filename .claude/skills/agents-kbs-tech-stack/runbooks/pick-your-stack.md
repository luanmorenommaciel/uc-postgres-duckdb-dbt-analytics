# Runbook — Pick Your Stack End-to-End

> Step-by-step walkthrough of invoking `agents-kbs-tech-stack` against a real repo.

## Prerequisites

- Bash 3.2+ (macOS stock), `python3` with `pyyaml` installed (`pip install pyyaml`).
- The skill installed: either via symlink from `ontolayer/skills/agents-kbs-tech-stack/` into `~/.claude/skills/`, or unpacked tarball at `<target>/.claude/skills/agents-kbs-tech-stack/`.
- Target repo writable.
- `agents-kbs-fleet` (v1) **does not** need to be installed at the target — the bundle includes copies of the KB templates inlined.

## Step 1 — Decide your stack

Before invoking, list the techs the project uses. Skip techs the project doesn't depend on — extra agents bloat routing.

For each tech, ask: do I want both an architect (planning) and a developer (implementation), or is one enough? In v1, you get both per tech — no opt-out. If a tech only needs implementation help (no design questions), still scaffold both and ignore the architect.

## Step 2 — Invoke the skill

In a Claude Code session with the target repo as CWD:

```text
/agents-kbs-tech-stack
```

The skill enters Phase 1:

1. Asks for `PROJECT_NAME` (e.g., `ontolayer`).
2. Asks for `PROJECT_DESCRIPTION` (one sentence).
3. Asks for `TARGET_REPO` (default: current dir).
4. Presents the curated menu — pick 1–N techs via multi-select.

The menu shows the 10 techs from `menu/techs.yaml`: react, nextjs, fastapi, python, typescript, langgraph, postgres, sqlglot, react-flow, tailwind.

## Step 3 — Review the preview

The skill prints:

```text
For 3 picked techs (react, fastapi, postgres):
  - 6 tech agents:
    - react-architect.md, react-developer.md
    - fastapi-architect.md, fastapi-developer.md
    - postgres-architect.md, postgres-developer.md
  - 3 KB trees:
    - kb/react/{quick-reference + 3 concepts + 3 patterns + 2 reference}
    - kb/fastapi/{...}
    - kb/postgres/{...}
  - 3 closers (none currently present in <target>/.claude/agents/):
    - code-reviewer.md, code-simplifier.md, code-documenter.md
```

Confirm or abort. If you spot a tech you didn't mean to pick, abort and re-run.

## Step 4 — Scaffold

The skill calls `scripts/scaffold.sh` once per tech (passing `TECH=<slug>` plus the project vars), then `scripts/install-closers.sh` once.

Expected output:

```text
✓ Scaffolded tech: react
  Architect : <target>/.claude/agents/react-architect.md
  Developer : <target>/.claude/agents/react-developer.md
  KB        : <target>/.claude/kb/react/
  Index     : <target>/.claude/kb/_index.yaml
✓ Scaffolded tech: fastapi
  ...
✓ Scaffolded tech: postgres
  ...
✓ Installed code-reviewer → <target>/.claude/agents/code-reviewer.md
✓ Installed code-simplifier → <target>/.claude/agents/code-simplifier.md
✓ Installed code-documenter → <target>/.claude/agents/code-documenter.md
```

## Step 5 — Verify

```bash
ls <target>/.claude/agents/                       # 6 tech + 3 closers = 9
ls <target>/.claude/kb/                           # 3 tech subdirs + _index.yaml
cat <target>/.claude/kb/_index.yaml | head -30    # 3 domains registered
```

YAML parse check (each agent):

```bash
for f in <target>/.claude/agents/*.md; do
  python3 -c "
import yaml, sys
with open('$f') as fh:
    parts = fh.read().split('---', 2)
fm = yaml.safe_load(parts[1])
print('$f:', fm['name'])
"
done
```

Verify Bash boundary:

```bash
grep '^tools:' <target>/.claude/agents/react-architect.md  # should NOT include Bash
grep '^tools:' <target>/.claude/agents/react-developer.md  # SHOULD include Bash
```

## Phase 3.5: Quality gate

After Step 4 the skill automatically invokes `scripts/quality-gate.sh`. You can also run it on demand at any point — it never writes files, only reports.

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/quality-gate.sh \
  --target <target-repo>
```

Output (truncated):

```text
[gate] architect/Bash boundary ............ PASS (3/3 architects clean)
[gate] developer/Bash boundary ............ PASS (3/3 developers have Bash)
[gate] closer presence ..................... PASS (3/3 closers present)
[gate] kb tree completeness ................ PASS (3/3 techs have full tree)
[gate] threshold floor ..................... PASS (6/6 agents above floor)
[gate] unrendered placeholders ............. PASS (0 found)
[gate] index ↔ kb directory parity ......... PASS
─────────────────────────────────────────────────
SUMMARY: 7/7 checks passed.
```

### Strict mode (CI)

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/quality-gate.sh \
  --target <target-repo> \
  --strict
```

`--strict` makes any FAIL exit non-zero. Wire this into a pre-merge CI check to catch drift introduced by hand-edits.

### What to do on a FAIL

| Check | Common cause | Fix |
|-------|--------------|-----|
| `architect/Bash boundary` FAIL | Someone added `Bash` to an architect's `tools:` list | Remove `Bash`; architects plan, they don't execute |
| `developer/Bash boundary` FAIL | Developer is missing `Bash` | Add `Bash` to `tools:` — developers ship code, they need it |
| `kb tree completeness` FAIL | Someone deleted a KB file | Restore from git, or re-scaffold the tech |
| `threshold floor` FAIL | A threshold was lowered below the menu floor | Either raise the threshold or amend the menu floor with rationale |
| `unrendered placeholders` FAIL | scaffold.sh missed an export | File a bug; hand-fill the placeholder for now |

## Phase 4: Cross-tool emission

After the quality gate, the skill invokes `scripts/emit-cross-tool.sh` once. This step writes (or proposes) the following files outside `.claude/`:

```text
<target-repo>/AGENTS.md
<target-repo>/.cursor/rules/agents.mdc
<target-repo>/.cursor/rules/<tech>.mdc      # one per tech
<target-repo>/.github/copilot-instructions.md
```

Run on demand:

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/emit-cross-tool.sh \
  --target <target-repo>
```

### What gets emitted

- **`AGENTS.md`** — consumed by Codex, the OpenAI Agents SDK, taskship, and anthive. Lists every agent's name, threshold, tools, mission, and a pointer to its KB. This is the canonical cross-tool surface; even tools that don't know about Claude subagents will read this file.
- **`.cursor/rules/agents.mdc`** — Cursor "always" rule mirroring `doctrine.yaml` (Bash boundary, threshold floors, closer-hook protocol).
- **`.cursor/rules/<tech>.mdc`** — one per tech, scoped to the menu's `cursor_globs` (e.g., `**/*.tsx` for react). Holds the per-tech do/don't summary.
- **`.github/copilot-instructions.md`** — flat prose digest for GitHub Copilot's repo-level instruction file.

### Idempotency & hand-edits

If you hand-edited a file the emitter would otherwise own, the emitter writes a `.proposed` sibling instead of clobbering:

```text
✓ wrote   AGENTS.md
NOTE      .cursor/rules/agents.mdc was hand-edited — wrote .cursor/rules/agents.mdc.proposed
✓ wrote   .cursor/rules/react.mdc
✓ wrote   .github/copilot-instructions.md
```

Reconcile by diffing the `.proposed` file, picking your edits in, then deleting the `.proposed` sibling.

## KB content bootstrap with Codex

Empty `<!-- TODO -->` blocks are the long tail of the scaffold. v0.3.0 ships `scripts/bootstrap-kb.sh`, which delegates draft KB authoring to Codex (via `codex:rescue`) without touching the canonical KB files. The flow is three steps:

### Step 1 — Generate draft prompts

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/bootstrap-kb.sh \
  --target <target-repo> \
  --tech react
```

This walks `kb/react/` and, for every file containing `<!-- TODO -->`, writes a sibling `*.draft.prompt.md` that contains:

- The KB taxonomy contract for that file slot (concepts vs patterns vs reference).
- The tech's menu entry as grounding (capabilities, MCPs, threshold floor).
- A `codex:rescue` invocation block ready to copy into Claude Code.

Nothing else is written. The canonical KB files remain untouched.

### Step 2 — Invoke codex:rescue manually

For each prompt, copy the block into Claude Code:

```text
/codex:rescue Generate a draft for kb/react/concepts/component-model.md
  using the prompt in kb/react/concepts/component-model.draft.prompt.md
  and write the result to kb/react/concepts/component-model.draft.md.
```

Codex reads the prompt, drafts the KB content, and writes a `*.draft.md` sibling. Multiple files can be drafted in parallel — each rescue call is independent.

### Step 3 — Review the `.draft.md` files

The drafts live alongside the canonical files:

```text
kb/react/concepts/
├── component-model.md             # canonical, still has <!-- TODO -->
├── component-model.draft.md       # Codex draft
└── component-model.draft.prompt.md
```

Open each `.draft.md`, prune what's wrong, sharpen what's right. Codex is **best at scaffolding plausible structure** and weakest at deciding what your team actually believes — read every draft critically.

### Step 4 — Accept drafts

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/accept-drafts.sh \
  --target <target-repo> \
  --tech react
```

For every `*.draft.md` you haven't deleted, this script:

1. Backs up the canonical file as `*.bak`.
2. Overwrites the canonical file with the draft content.
3. Deletes the `*.draft.md` and `*.draft.prompt.md`.

Add `--dry-run` to preview without writing. If you want to keep a draft for later, just delete it before running `accept-drafts.sh`.

## Tuning the doctrine

`doctrine.yaml` is the portable subset of the skill's defaults — the things every emitted format (AGENTS.md, Cursor rules, Copilot instructions) needs to agree on. It lives at `<target-repo>/.claude/doctrine.yaml` and ships with sensible defaults on first run.

### Step 1 — Open the doctrine

```bash
$EDITOR <target-repo>/.claude/doctrine.yaml
```

Top-level keys (see the bundled default for full schema):

```yaml
bash_boundary:
  architects_have_bash: false
  developers_have_bash: true

threshold_floor:
  architect: 0.90
  developer: 0.85
  closer: 0.85

closer_hook_protocol:
  detection: extension_first
  fallback: ask_user

cross_tool:
  emit_agents_md: true
  emit_cursor_rules: true
  emit_copilot_instructions: true
```

### Step 2 — Refresh

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/refresh-doctrine.sh \
  --target <target-repo>
```

`refresh-doctrine.sh`:

1. Re-validates the doctrine schema.
2. Recomputes any agent fields derived from the doctrine (e.g., thresholds clamped to the new floor).
3. **Does not** re-run the cross-tool emitter — that's a separate step you invoke explicitly to keep responsibilities clean.

### Step 3 — Re-emit

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/emit-cross-tool.sh \
  --target <target-repo>
```

The emitter picks up the new doctrine and rewrites `AGENTS.md` / Cursor rules / Copilot instructions accordingly. Hand-edited files become `.proposed` siblings, as always.

### When to tune

| Trigger | Likely change |
|---------|---------------|
| Project wants architects to run read-only Bash | flip `architects_have_bash: true` — but think hard first |
| Team raises the bar on closer confidence | bump `threshold_floor.closer` to 0.90 |
| Repo doesn't use Cursor | flip `emit_cursor_rules: false`, re-emit |
| New tool joins the org | add a new emitter, then expose a flag here |

## Step 6 — Populate KB content

Each KB entry ships with `<!-- TODO -->` blocks. Order of attack:

1. **`quick-reference.md` first** — the agent reads this first on every invocation.
2. **`concepts/` next** — these are the rules the architect and developer ground in.
3. **`patterns/` after** — concrete code samples for the developer.
4. **`reference/` last** — comprehensive lookup, can wait until you have real data.

Time budget: ~1 hour per tech to reach "useable", ~1 day to "production-grade." Don't try to fill it all at once — start with quick-reference and add as you work.

## Step 7 — Populate agent body sections

### Architect body — `## Decision Frameworks`

Add 2–3 trade-off matrices. Each one:

- One named decision (e.g., "When to use SSR vs RSC")
- A "Use X when" / "Use Y when" / "Red flags" structure
- Cites the KB

### Developer body — `## Implementation Patterns`

Add 2–4 production code samples. Each one:

- One named pattern (e.g., "Custom hook with cleanup")
- "When:" trigger
- 20–50 lines of production code
- Anti-pattern showing what it looks like done wrong

## Step 8 — Adding a tech later

Re-run the skill. It refuses to overwrite existing agents but happily scaffolds new ones:

```text
✓ Scaffolded tech: langgraph         # new
NOTE: domain 'react' already in _index.yaml — leaving existing entry untouched
NOTE: code-reviewer already exists — leaving untouched
```

Existing closers and existing techs are detected and skipped with NOTE lines.

## Step 9 — Bundling for another repo

```bash
bash ontolayer/skills/agents-kbs-tech-stack/scripts/bundle.sh
```

Output: `dist/agents-kbs-tech-stack-v0.3.0.tar.gz` (under 100 KB). The bundle inlines the KB templates from v1 — drop-in is self-contained.

## Troubleshooting

### `ERROR: tech "foo" not in menu`

You passed a tech slug that doesn't exist in `menu/techs.yaml`. Either pick from the menu, or add the tech first (see `references/tech-menu-curation.md`).

### `ERROR: PyYAML required for menu parsing`

The skill needs `pyyaml` to parse `menu/techs.yaml`. Install with `pip install pyyaml`.

### `WARN: unrendered placeholders found: {SOME_KEY}`

A template references a placeholder that the scaffold script didn't substitute. Likely a bug in `scripts/scaffold.sh`'s export list — open an issue or hand-edit the generated file.

### `ERROR: architect already exists`

You're scaffolding a tech that's already been scaffolded. The skill refuses to clobber. Either:

- Skip this tech in your menu selection.
- Delete the existing agent file (only if you're certain you want to lose customizations).

### Closer routes poorly to the wrong tech KB

Edit the `## Closer-Hook Protocol` section of the closer's file to override the detection table for your project's specific file layout.

## Closing the loop in practice

A typical day:

```text
1. User: "Plan the new auth feature using FastAPI sessions."
   → fastapi-architect plans, writes manifest, names fastapi-developer
2. User: "Implement the manifest."
   → fastapi-developer ships code + tests
3. User: "Review."
   → code-reviewer walks the diff, cites kb/fastapi/ + kb/python/
4. User: "Anything to simplify?"
   → code-simplifier proposes consolidations
5. User: "Document."
   → code-documenter writes docstrings in Google-style (per kb/python/)
```

That's the loop. Architect → developer → reviewer → simplifier → documenter. Each agent has one job, well done.
