---
name: task-spec
version: "2.2.1"
description: |
  Generate atomic, vendor-portable, self-verifying Task-Spec v2.1 files for any
  agentic system. Produces task PRDs with runnable bash evals that work in
  Claude, Codex, Kimi, taskship, anthive, /goal, or manual execution.
  Use when authoring new tasks, decomposing intent into work units, converting
  legacy task docs to Task-Spec format, or generating overnight backlog.
---

# task-spec — Cornerstone CAW for Task-Spec v2.1

> **Identity:** The unit-of-work primitive for autonomous agentic systems
> **Domain:** Task PRD generation, eval-driven development, backlog management
> **Default Threshold:** severity-scaled (0.80–0.99) — see Threshold Mapping below
> **MCP Validated:** 2026-05-19

This skill is part of the **CAW Triad** for task generation:
- **C** (this Skill): the workflow + bundled scripts + templates
- **A** (Agent): `task-architect` — applies Agreement Matrix, ensures quality
- **W** (MCPs): Context7, Exa, Ref — fresh validation at authoring time

---

## When to invoke this skill

Trigger conditions (Claude auto-invokes when context matches):
- User says "create a task," "scaffold a task," "decompose this into work"
- User has fuzzy intent ("verify the deploy pipeline works")
- User wants to convert a meeting note into actionable backlog
- User mentions Task-Spec, EDD, eval-driven, or "make this executable"
- User asks for a task that any agent (Claude/Codex/Kimi) can pick up

Skip if:
- Task is L/XL effort (route to AgentSpec SDD instead)
- Output is subjective (UX, copy, design — use SDD)
- User just wants a one-off prompt, not a reusable spec

---

## Workflow

```text
┌──────────────────────────────────────────────────────────────────┐
│  TASK-SPEC WORKFLOW                                               │
├──────────────────────────────────────────────────────────────────┤
│  Phase 1: UNDERSTAND    parse intent, classify effort             │
│  Phase 2: RESEARCH      Context7 + Exa + Ref MCPs                 │
│  Phase 3: SCAN          read host repo for touches_paths          │
│  Phase 4: ARCHITECT     spawn task-architect agent for judgment   │
│  Phase 5: COMPOSE       fill 4 zones, write T-*.md from template  │
│  Phase 6: VALIDATE      structural linter — validate-task-spec.sh │
│  Phase 7: GATE          THE gate — safe-to-delegate.sh --stamp    │
│  Phase 8: DISPATCH      hand off to executor per execution_backend│
└──────────────────────────────────────────────────────────────────┘
```

> **Alternative: Batch Sprint Compose** — when you need N specs at once in a
> known domain, skip Phase 2 (MCP research) and Phase 4 (task-architect spawn).
> See [Batch Sprint Compose](#batch-sprint-compose-fast-batch) below.

### Phase 1 — Understand

Parse the user's intent. Critical questions answered before scaffolding:

1. **What's the verbal description?** (1 paragraph from user)
2. **Effort class?** S (≤1 day) or M (1-3 days). L/XL → refuse, route to AgentSpec.
3. **Agent hint?** `any` (vendor-portable) OR specific (`python-developer`, etc.)
4. **Source provenance?** Meeting note, audit, ticket — must have one
5. **Touches what paths?** Best guess; refined in Phase 3

If unclear, ASK ONCE for clarification. Don't proceed with vague intent.

### Phase 2 — Research (MCP validation)

For the domain in the user's intent, query MCPs:

```text
Context7 → official docs for any tool/library mentioned
Exa      → production examples of similar tasks
Ref      → canonical references
```

The research output feeds the `anti-patterns` and `do-not-touch` zones —
both should be informed by real-world failure modes from MCP findings.

### Phase 3 — Scan

Read the host repo to refine:
- Which files actually exist on `touches_paths`?
- Any cross-cutting concerns (touches the same files as in-flight tasks)?
- Existing conventions (CLAUDE.md, .editorconfig, project style)?

This uses Glob + Grep + Read in the host repo — no writes.

### Phase 4 — Architect (spawn the agent)

Spawn the **`task-architect`** agent with:
- The intent
- Phase 2 research findings
- Phase 3 repo scan findings

The agent:
- Applies Agreement Matrix (KB + MCP)
- Decides isolation class (worktree vs branch)
- Drafts the 3 evals as runnable bash
- Drafts anti-patterns + do-not-touch from research
- Returns a structured build plan with confidence score

If confidence < 0.95, ASK the user before composing.

### Phase 5 — Compose

Run `scripts/generate-task-spec.sh` to create the T-*.md file from the template,
then fill in:

| Zone | What goes in |
|------|--------------|
| Frontmatter | id, title, status=ready, format_version=2, effort, budget=15, agent, touches_paths, source_note |
| Zone 1 | Why / Goal / Context (lean) |
| Zone 2 | 3+ evals + validation_card YAML + exit_check bash |
| Zone 3 | Rollback Plan (or `(none)`) |
| Zone 4 | Observability Hooks (or `(none)`) |
| Zone 5 | Anti-patterns + do-not-touch list |
| Zone 6 | Open questions (or `(none)`) |

**Layered policy (legacy tolerance):** `format_version` defaults to `2` for new specs. Tasks created before 2026-05-27 (or explicitly marked `format_version: 0` or `1`) are treated as legacy. The validator accepts legacy v0/v1 tasks with warnings rather than hard failures, and the `migrate-legacy-task.sh` script converts legacy markdown checklists into runnable eval stubs.

### Phase 6 — Validate (pre-gate structural linter)

> **Validate is NOT the gate.** It is the structural linter that runs BEFORE the gate. It does not execute evals; it does not stamp `signed_off`. See [references/concepts/signed-off.md](references/concepts/signed-off.md) for the validate-vs-gate contract.

Run `scripts/validate-task-spec.sh tasks/T-*.md`:
- Confirms all 6 zones present
- Confirms all required frontmatter fields
- Confirms no `{{TODO}}` placeholders remain
- Confirms eval functions are syntactically valid bash
- Confirms `id` matches the filename basename
- Confirms every `depends_on` references an existing task (warns if target is parked/done)
- Confirms every `touches_paths` exists on disk (warns only if task is parked)
- Confirms Exit Check calls every `eval_N()` defined in Success Criteria
- For v2: confirms `agent_contract` has `produce` as YAML list, `emit` as enum list,
  `timeout_minutes` as 1–1440, `sandbox_type` as host|isolated|ephemeral, and
  `required_tools` as a non-empty list
- `--shellcheck-evals` (opt-in): pipes each `eval_N()` body through `shellcheck -S warning`
  to catch syntax errors and dead variables
- `--dry-run-eval` (opt-in): sources the bash blocks in a disposable subshell and verifies
  the Exit Check exits 0 against the current repo

**State invariant:** Every successful validation idempotently updates `tasks/_state.yaml` with the
 task's frontmatter snapshot, `last_validated` timestamp, and `validator_version`. Failed
 validations do **not** write state — broken specs never pollute the audit trail. If
 `_state.yaml` doesn't reflect a task file's frontmatter, the validator hasn't run on it
 OR `rebuild-state.sh` is overdue.

### Phase 7 — Gate (the autonomy contract)

**This is THE gate.** It is the only path to `signed_off: true`. Authors do not hand-edit `signed_off`; hand-stamping is rejected by the v2.1 structural sign-off envelope check.

Run `scripts/safe-to-delegate.sh --stamp tasks/T-*.md`:

- Composes `validate-task-spec.sh` (structural) + `run-task-spec.sh` (eval execution) into one go/no-go verdict
- `validate` must exit 0 (structural pass)
- Eval bodies must execute without bash-level errors (no `syntax error`, no `unbound variable`, no `command not found`, no inverted-grep-c footguns)
- Assertion failures are EXPECTED on an unbuilt task — the work isn't done yet. The gate fails for the RIGHT reason (assertion not yet true) not the WRONG reason (eval is broken bash)
- On success: flips `signed_off: false` → `signed_off: true`, stamps `signed_off_by: $USER` (override with `--stamp-by`), and records `signed_off_at: <iso-8601>`
- On failure: prints `VERDICT: DO NOT DELEGATE` and exits 1. The spec stays `signed_off: false`

`scripts/run-task-spec.sh` runs the evals directly (used by the gate; usually not invoked standalone):

- Extracts Success Criteria and Exit Check bash blocks
- Runs each `eval_N()` in an isolated subshell with `set -euo pipefail`
- Captures per-eval stdout/stderr/duration
- Reports `pass`/`fail` per eval with timing
- Exits 0 only when the Exit Check returns 0
- `--ci` flag emits one JSON line per eval for non-interactive pipelines

### Phase 8 — Dispatch

A spec with `signed_off: true` is ready to hand to an autonomous executor. See [runbooks/dispatching-a-task-spec.md](runbooks/dispatching-a-task-spec.md) for the full handoff protocol.

The spec's frontmatter carries an `execution_backend:` field that names the canonical executor:

| Value | Executor |
|-------|----------|
| `any` (default) | Author's choice |
| `kimi` | Kimi CLI via the broker — `/kimi:crank tasks/T-<spec>.md` |
| `claude` | Claude Code — `Task()` tool, or `/kimi:crank` (Claude drives Kimi) |
| `codex` | Codex CLI — see Codex plugin docs |
| `taskship` / `anthive` / `agentspec` | External agentic systems — see their respective docs |

Report to user:

- File path + signed_off status
- Gate verdict (DELEGATE / DO NOT DELEGATE)
- Recommended dispatch command per `execution_backend`
- Optional: dispatch immediately if user said "and run it"

---

## Batch Sprint Compose (Fast Batch)

Use the **Fast Batch** path when you're decomposing a known audit or feature
into many atomic specs against an in-repo codebase. Skip the per-task MCP
research and architect spawn; compose directly from structured intent.

### When to use Fast Batch vs Full Workflow

| Criterion | Fast Batch | Full Workflow |
|-----------|------------|---------------|
| Domain familiarity | Known — you already understand the codebase | Unknown — greenfield task, unfamiliar library |
| MCP research value | Low — no external docs needed | High — need Context7 / Exa / Ref for failure modes |
| Intent structure | User provides `slug: description` per line | User gives a fuzzy paragraph |
| Task count | 3–20 specs at once | 1 spec at a time |
| Structural confidence | ≥ 0.95 — user already provided `touches_paths`, `evals`, etc. | < 0.95 — need task-architect to draft evals |
| Empirical signal | Prior batch validated first-try | Novel task with unknown failure modes |

**Decision rule:** If ≥ 4 of the 6 criteria above favor Fast Batch, use it.
Otherwise, run the full 6-phase workflow.

### Batch Sprint flow

```text
┌──────────────────────────────────────────────────────────────────┐
│  BATCH SPRINT COMPOSE                                             │
├──────────────────────────────────────────────────────────────────┤
│  Step 1: PREPARE        collect intent list (slug + description)  │
│  Step 2: GENERATE       batch-generate.sh → N stub T-*.md files   │
│  Step 3: FILL           edit stubs: title, why, goal, evals, etc. │
│  Step 4: BULK-VALIDATE  validate-task-spec.sh on each file        │
│  Step 5: COMMIT         git add tasks/ + state + metrics          │
└──────────────────────────────────────────────────────────────────┘
```

### Input format

One line per task in `slug: description` form:

```text
fix-login-redirect   Redirect to /dashboard after OAuth success instead of /
add-rate-limiting    Add 100 req/min rate limit to /api/v1/analyze endpoint
update-telemetry     Emit batch-completed event to Langfuse after each sprint
```

Save to a file (e.g. `intents.txt`) and run:

```bash
bash ~/.claude/skills/task-spec/scripts/batch-generate.sh \
    --intent-file intents.txt \
    --effort S \
    --agent any \
    --queue
```

Flags:
- `--intent-file <path>` — required. File with one `slug: description` per line.
- `--effort S|M` — required. Applied to every generated spec.
- `--agent <name>` — optional. Defaults to `any`.
- `--source-note <path>` — optional. Applied to every spec.
- `--queue` — optional. Write to `tasks/queue/` instead of `tasks/`.
- `--dry-run` — optional. Print what would be created without writing files.
- `--skip-validation` — optional. Skip the bulk validation pass.
- `--validate-opts <opts>` — optional. Pass extra flags to the validator (e.g. `--skip-touches-paths`).

### After generation

1. **Fill each stub** — edit titles, `why`, `goal`, `touches_paths`, evals, anti-patterns, do-not-touch.
2. **Run bulk validation** — the script validates each file by default; failures are reported per-task.
3. **Commit** — `git add tasks/ tasks/_state.yaml tasks/_metrics.jsonl`

### Anti-pattern: silent skipping

Don't skip Phase 2 or Phase 4 silently. The `--fast` path is an **explicit opt-in**
(via `--intent-file` + known-domain context). If you're unsure, run the full
workflow on one spec first, then batch the rest once the pattern is proven.

---

## Self-containment

This skill is portable as a single folder:

```bash
cp -r ~/.claude/skills/task-spec /tmp/share/
# On target machine:
cp -r /tmp/share/task-spec ~/.claude/skills/
bash ~/.claude/skills/task-spec/scripts/install.sh
# /task-spec now works in EVERY repo on that machine
```

**Bash portability:** The core gate path — `validate-task-spec.sh`,
`safe-to-delegate.sh`, `run-task-spec.sh`, and `_lib.sh` — is bash-3.2-safe and
runs on the macOS system `/bin/bash` (3.2.57) with no extra setup. Two auxiliary
scripts, `lint-backlog.sh` and `query-metrics.sh`, use associative arrays
(`declare -A`) and so require **bash 4+**. They guard themselves via
`ts_require_bash4`: if launched under bash 3.x they auto-detect a bash 4+ on
`PATH` and re-exec under it, and if none is found they print a one-line
remediation (`brew install bash`) and exit 3 — never the cryptic
`declare: -A: invalid option` failure.

External dependencies: Context7, Exa, Ref MCPs must be user-configured.

---

## Worker layer (MCPs)

| MCP | Purpose |
|-----|---------|
| Context7 | Fresh library/framework docs |
| Exa | Production examples and patterns |
| Ref | Canonical references |

---

## Specialist agent

Spawns **`task-architect`** for the judgment-heavy work:
- Lives at: `~/.claude/agents/task-architect.md`
- Installed via: `bash ~/.claude/skills/task-spec/scripts/install.sh`
- Runs in: isolated context, returns structured build plan
- Scoped tools: Read, Grep, Glob, Bash, Write, TodoWrite, MCP suite

---

## Threshold Mapping (severity-scaled)

Task quality threshold scales with consequence. Below the severity-specific
threshold, the agent ASKs the user before composing. Above it, the agent
PROCEEDS with a disclaimer.

| Severity | Threshold | Rationale |
|----------|----------:|-----------|
| cosmetic | 0.80 | Doc typos, comment fixes; cheap to revert |
| refactor | 0.85 | Code shape changes with tests; semantic equivalence required |
| feature | 0.90 | New behavior; well-scoped acceptance criteria |
| bugfix | 0.95 | Correctness change with regression risk (legacy default) |
| security | 0.98 | Authentication, auth, cryptography, secrets handling |
| financial-critical | 0.99 | Money fields, accounting, ledger; silent errors compound |

**Backward compatibility:** Tasks without a `severity` field default to `bugfix`
(0.95), preserving the historical IMPORTANT threshold.

| Action | Class |
|--------|-------|
| Reading the user's intent | ADVISORY |
| MCP research | STANDARD |
| Drafting evals | IMPORTANT (severity-scaled) |
| Refusing L/XL effort | CRITICAL (always refuses, never overrides) |
| Detecting subjective output | CRITICAL (refuses EDD, routes to SDD) |

---

## CLI commands (bundled in scripts/)

| Command | Purpose |
|---------|---------|
| `generate-task-spec.sh <slug> <effort> [agent] [source]` | Create a new T-*.md from template |
| `batch-generate.sh --intent-file <path> --effort S|M [opts]` | Bulk-create N stub T-*.md files from an intent list, then bulk-validate |
| `validate-task-spec.sh [opts] <path>` | Lint a T-*.md against v2 format. Flags: `--shellcheck-evals`, `--dry-run-eval`, `--skip-touches-paths`, `--strict-depends` |
| `lint-backlog.sh [--help]` | Cross-task linter: detects touches_paths overlaps, depends_on cycles, duplicate IDs, stale preconditions across the backlog |
| `run-task-spec.sh [--ci] <path>` | Execute evals from a T-*.md. Runs each `eval_N` in isolation, then the Exit Check. `--ci` emits JSON-per-eval |
| `safe-to-delegate.sh [--skip-touches-paths] <path>` | **Pre-delegation gate.** One command: structural validate + shellcheck-evals + eval execution (broken-logic guard). Emits DELEGATE / DO-NOT-DELEGATE verdict (exit 0/1). Run before handing a spec to Kimi/Codex blind. |
| `migrate-legacy-task.sh <path>` | Convert a legacy task's markdown checklist into v2.1 eval stubs + validation_card |
| `transition-status.sh <id> <new-status> [reason]` | Atomic status change |
| `rebuild-state.sh` | Regenerate `_state.yaml` from frontmatter (recovery). Run after direct writes or when state is stale. |
| `list-ready.sh [--effort=S] [--agent=any]` | Show tasks ready for pickup |
| `archive.sh` | Move done/parked tasks to subdirs |
| `backup-backlog.sh [dir]` | Snapshot tasks/ folder |
| `install-hooks.sh` | Install git pre-commit hook that runs `rebuild-state.sh` to catch drift from direct-Write users |
| `install.sh` | Install bundled agent to ~/.claude/agents/ |

---

## Linting

Task-Spec v2.1 files use YAML frontmatter with a `title:` field **and** a body H1 (`# Title`). This is intentional: the frontmatter title is machine-readable metadata; the body H1 is human-readable when the file is rendered outside a parser. The combination triggers **MD025** (multiple H1 headings) in markdownlint by default.

This skill ships a scoped `.markdownlintrc` in its root that tells markdownlint to treat the frontmatter `title:` as the document's sole H1:

```json
{
  "MD025": {
    "front_matter_title": ""
  }
}
```

The empty string `""` matches the frontmatter key name exactly, so the body H1 is no longer flagged as a duplicate.

**How to use:**
- If your IDE or linter looks at the skill root, no action needed.
- If your IDE lints from `tasks/` or the repo root, copy or symlink the config:
  ```bash
  ln -s ~/.claude/skills/task-spec/.markdownlintrc tasks/.markdownlintrc
  ```

**Why not drop the body H1?** Because it breaks every existing spec and reduces readability for humans skimming raw markdown. The skill owns its convention via config rather than changing the convention.

---

## References

- `references/concepts/task-spec-v1.md` — THE published format spec (living doc, currently v2.1; filename retained for link stability; includes v0→v1→v2→v2.1 version history)
- `references/concepts/eval-driven-development.md` — EDD methodology
- `references/concepts/edd-vs-sdd-honest-comparison.md` — when to use which
- `references/concepts/six-zones.md` — zone-by-zone deep dive
- `references/concepts/effort-gate.md` — S/M/L/XL routing rules
- `references/concepts/agent-contract.md` — cross-vendor contract (includes v2 machine schema)
- `references/concepts/backlog-architecture.md` — 5-layer state management
- `references/patterns/runnable-bash-evals.md` — eval writing patterns
- `references/patterns/validation-card-yaml.md` — YAML contract patterns
- `references/patterns/atomic-status-transitions.md` — transition protocol
- `references/patterns/anti-patterns-extraction.md` — mining from MCP research
- `references/patterns/do-not-touch-detection.md` — repo-scan patterns
- `runbooks/from-fuzzy-intent.md` — paragraph → Task-Spec
- `runbooks/from-meeting-note.md` — Krisp output → Task-Spec
- `runbooks/from-existing-task.md` — legacy task → v2.1 conversion
- `runbooks/batch-sprint-compose.md` — bulk intent list → N Task-Spec stubs
- `runbooks/validating-a-task-spec.md` — linting walkthrough
- `runbooks/recovering-from-crash.md` — state recovery
- `runbooks/empirical-experiment-protocol.md` — SDD vs EDD test design

---

## Remember

> **"Specs that verify themselves don't need humans in the middle of the loop."**

**Mission:** Be the cornerstone primitive — the atomic, vendor-portable,
self-verifying unit-of-work format that any agentic system can produce, consume,
and trust.
