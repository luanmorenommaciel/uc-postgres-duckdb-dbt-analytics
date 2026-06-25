# task-spec — Cornerstone CAW for Task-Spec v2.2

> The atomic, vendor-portable, self-verifying unit of work for autonomous
> agentic systems. Produces task specs that any agent (Claude, Codex, Kimi,
> taskship, anthive, /goal, manual humans) can pick up, execute, and verify.

---

## The 60-second pitch

Every AI coding tool today consumes some form of "task." Most of those tasks
are PRDs — written for humans, interpreted by humans, success judged by humans.
That makes agents non-autonomous: they need a human in the middle of the loop.

**Task-Spec v2.2 fixes that.** Each Task-Spec carries its own runnable bash
success criteria. The agent reads the spec, executes the work, runs the evals,
and loops on failure — entirely without human intervention. Humans enter at
intent-setting and PR-review only.

This is **Eval-Driven Development (EDD)** for agentic tasks — the same
conceptual leap as TDD, Infrastructure-as-Code, or DBT data contracts.

---

## Quick Start — three commands

Every author flow follows the same three-command sequence:

```bash
# 1. GENERATE — scaffold a new spec from intent
bash .claude/skills/task-spec/scripts/generate-task-spec.sh <slug> <effort> [agent] [source]

# 2. VALIDATE (pre-gate linter — structural only, does NOT stamp signed_off)
bash .claude/skills/task-spec/scripts/validate-task-spec.sh tasks/T-<your-spec>.md

# 3. GATE (THE gate — flips signed_off:true if structural + eval execution pass)
bash .claude/skills/task-spec/scripts/safe-to-delegate.sh --stamp tasks/T-<your-spec>.md
```

**A spec is ready to dispatch when, and only when, `safe-to-delegate.sh --stamp` returns `VERDICT: DELEGATE` and writes `signed_off: true` to the frontmatter.** Hand-stamping is rejected by the sign-off envelope check; the only path to the autonomy contract is the gate. As of v2.2 the envelope is a key-optional HMAC-SHA256 seal — `--stamp` writes `signed_off_sig` over a canonical payload, and `validate-task-spec.sh` Check 17 recomputes and compares (three-tier degrade when no key/crypto is present). See [CHANGELOG.md](CHANGELOG.md) and [references/concepts/signed-off.md](references/concepts/signed-off.md).

**Your first 10 minutes:** follow [runbooks/first-spec-walkthrough.md](runbooks/first-spec-walkthrough.md) — a complete copy-paste walkthrough from install through stamped spec in a tempdir.

After stamping see [runbooks/dispatching-a-task-spec.md](runbooks/dispatching-a-task-spec.md). For the contract itself see [references/concepts/signed-off.md](references/concepts/signed-off.md).

---

## Quick example — a complete Task-Spec

```markdown
---
id: T-20260519-add-health-endpoint
title: Add /health endpoint to api server
status: ready
effort: S
budget_iterations: 10
agent: any
depends_on: []
touches_paths:
  - src/api/server.py
  - tests/test_health.py
source_note: notes/2026-05-19-monitoring.md
created: 2026-05-19T14:00:00-0300
tags: ["api", "monitoring"]
---

> **Why:** Load balancer health checks fail because there's no /health endpoint.

## Goal

Add a `/health` endpoint returning `{"status":"ok"}` with HTTP 200.

## Context

FastAPI server at `src/api/server.py`. K8s probes at `infra/k8s/api.yaml`
already reference `/health` (currently 404).

## Success Criteria

```bash
eval_1() {
  uvicorn src.api.server:app --port 8001 & PID=$!
  sleep 2
  kill -0 $PID 2>/dev/null
}

eval_2() {
  curl -fs http://localhost:8001/health | jq -e '.status == "ok"'
}

eval_3() {
  pytest tests/test_health.py -q
}
```

## Validation Card

```yaml
success_criteria:
  - {id: eval_1, description: "Server starts cleanly", runnable: bash, terminal: true, expected_duration_sec: 3}
  - {id: eval_2, description: "/health returns 200 + correct JSON", runnable: bash, terminal: true, expected_duration_sec: 2}
  - {id: eval_3, description: "Test for /health passes", runnable: bash, terminal: true, expected_duration_sec: 5}

retry_policy:
  max_iterations: 10
  circuit_breaker_no_progress: 3
  on_terminal_failure: park_with_context

agent_contract:
  read: [intent, contract, guardrails, operations]
  produce: code + tests
  verify: run all success_criteria
  emit: pass | fail | retry_with_reason
```

## Exit Check

```bash
eval_1 && eval_2 && eval_3
```

## Anti-Patterns

- **Don't add auth** — health endpoints are public by k8s convention.
- **Don't add liveness/readiness depth** — simplest possible check; depth later.

## Do-Not-Touch

- `infra/k8s/api.yaml` — already correctly references `/health`.

## Open Questions

(none — fully specified)
```

That's a complete Task-Spec v2.2. ~80 lines. Any agent can pick it up.

---

## The four zones

Every Task-Spec has YAML frontmatter + 4 zones:

| Zone | Purpose | Why |
|------|---------|-----|
| **1 — Intent** | Why this task exists | Brief context, link to existing docs |
| **2 — Contract** | Runnable evals + validation card + exit check | THE MOAT — self-verifying |
| **3 — Rollback** | How to reverse if execution fails | Remove recovery ambiguity |
| **4 — Observability** | What to watch during and after execution | Runtime expectations explicit |
| **5 — Guardrails** | Anti-patterns + do-not-touch | Bound the agent's blast radius |
| **6 — Operations** | Open questions | Admit unknowns; document recovery |

Full anatomy: [references/concepts/six-zones.md](references/concepts/six-zones.md)
Full spec: [references/concepts/task-spec-v1.md](references/concepts/task-spec-v1.md)

---

## The 18 load-bearing concepts (v2.2)

| Zone | Concepts |
|------|----------|
| Frontmatter | task-id, status-lifecycle, effort-gate, budget-iterations, agent-hint, touches-paths, depends-on, source-note |
| 1 (Intent) | goal-statement, context-bounded |
| 2 (Contract) | success-criteria (runnable bash), validation-card (YAML), exit-check-bash, agent-output-contract, agent-agnostic-input |
| 3 (Guardrails) | anti-patterns, do-not-touch |
| 4 (Operations) | open-questions |

Each concept has a definition in `references/concepts/` or `references/patterns/`.
v2/v3 roadmap concepts are deferred — see [references/quick-reference.md](references/quick-reference.md).

---

## The agent contract — vendor portability

Any agent that consumes a Task-Spec must honor this contract:

```yaml
on_pickup:
  - read: zones 1-4
  - parse: validation_card YAML
  - acquire: lock via transition-status.sh

per_iteration:
  - execute: implementation
  - run: all success_criteria as bash
  - emit: pass | fail | retry_with_reason

on_terminal_state:
  pass: status -> done; archive
  budget_exhausted: status -> parked
```

This is what makes Task-Spec portable across Claude, Codex, Kimi, taskship,
anthive, and manual execution. Full spec: [references/concepts/agent-contract.md](references/concepts/agent-contract.md)

---

## Install (works in any repo)

```bash
# Method 1 — global install (recommended, works in every repo on your machine)
cp -r ~/.claude/skills/task-spec ~/.claude/skills/   # already there if you cloned
bash ~/.claude/skills/task-spec/scripts/install.sh

# Method 2 — share to a teammate
tar czf task-spec.tar.gz -C ~/.claude/skills task-spec
# Send the tar; teammate untars + runs install.sh
```

After install, restart Claude Code. `/task-spec` appears in slash menu.

---

## Generate a Task-Spec

```bash
# From any repo:
bash ~/.claude/skills/task-spec/scripts/generate-task-spec.sh \
    verify-langfuse-otel S any notes/2026-05-04-handoff.md

# Then fill the {{TODO}} stubs in the generated file
# Validate before commit:
bash ~/.claude/skills/task-spec/scripts/validate-task-spec.sh \
    tasks/T-YYYYMMDD-verify-langfuse-otel.md
```

Or invoke via Claude: `/task-spec "verify our langfuse stack ingests OTEL traces"`
— the skill handles intent → research → compose → validate.

---

## Validate an existing Task-Spec

```bash
bash ~/.claude/skills/task-spec/scripts/validate-task-spec.sh tasks/T-XXX.md
```

Checks structural rules. Exit 0 = valid v2.2. Non-zero = errors listed. **Note:** this is the pre-gate linter only — see [runbooks/dispatching-a-task-spec.md](runbooks/dispatching-a-task-spec.md) for the autonomy contract via `safe-to-delegate.sh --stamp`.

---

## Convert a legacy task

If you have a pre-Task-Spec markdown file:

```bash
# Read the legacy file, identify what's missing
bash ~/.claude/skills/task-spec/scripts/validate-task-spec.sh tasks/legacy.md
# Manually map sections; add runnable evals
```

See [runbooks/from-existing-task.md](runbooks/from-existing-task.md).

---

## Who consumes Task-Spec

| Consumer | How it reads |
|----------|--------------|
| Claude Code (`/goal`) | Native — markdown + YAML + bash |
| AgentSpec (`/agentspec:build`) | Reads tasks/ as input to build phase |
| anthive | Dispatches one session per Task-Spec |
| taskship | Runs 3-phase mini-SDD against each Task-Spec |
| overnight-builder | Cron picks `status: ready` Task-Specs |
| Codex CLI | Same markdown + YAML — cross-vendor |
| Kimi | Same |
| Cursor / Aider | Same |
| Manual human | Reads as checklist; runs evals in terminal |

One format. Many executors.

---

## EDD vs SDD — honest comparison

| Dimension | SDD (AgentSpec) | EDD (Task-Spec) | Winner |
|-----------|-----------------|-----------------|--------|
| "Done" definition | Human review | Bash evals return 0 | EDD |
| Iteration cadence | Hours-days | Seconds-minutes | EDD |
| Cross-vendor portability | Vendor-specific | Universal | EDD |
| Authoring time | Faster (prose) | Slower (evals harder) | SDD |
| Audit trail | Narrative | Machine ledger | EDD |
| Subjective output (UX, copy) | Works fine | Doesn't work | SDD |
| L/XL effort | Designed for it | Refuses it | SDD |
| Catches ambiguity | Maybe | Yes (eval fails) | EDD |

**EDD wins 5/8.** Use SDD for L/XL and subjective work; EDD for S/M with
bash-checkable success. Full analysis: [references/concepts/edd-vs-sdd-honest-comparison.md](references/concepts/edd-vs-sdd-honest-comparison.md)

---

## Backlog architecture — 5 layers

| Layer | Purpose |
|-------|---------|
| 1 — git | Permanent record |
| 2 — tasks/ folder | The backlog (active / done/ / parked/) |
| 3 — frontmatter status | Authoritative per-file truth |
| 4 — _state.yaml | Derived index (rebuildable) |
| 5 — _metrics.jsonl | Append-only forensic ledger |

Every state change is atomic + logged + git-committed. Crashes are recoverable.
Full architecture: [references/concepts/backlog-architecture.md](references/concepts/backlog-architecture.md)

---

## Anti-patterns

What people try that doesn't work:

- ❌ Editing T-*.md frontmatter directly (bypasses lock + ledger) — use transition-status.sh
- ❌ Skipping evals because "the task is simple" — every spec needs ≥3 evals
- ❌ Verbose Zone 1 (Context > 100 lines) — you wrote a PRD; trim
- ❌ Vague Zone 3 ("be careful") — anti-patterns must be specific
- ❌ Including subjective evals ("looks good") — bash can't check beauty; use SDD
- ❌ Effort = L/XL — Task-Spec refuses; route to AgentSpec

---

## Naming and conventions

- Skill name: `task-spec` (the format IS the name; OpenAPI Spec / TypeSpec convention)
- Agent name: `task-architect` (the judgment layer)
- File pattern: `T-YYYYMMDD-<kebab-slug>.md`
- Format version: v2.2 (current release v2.2.1; see CHANGELOG.md for version history; future format changes will be additive)

---

## Roadmap

The format ships at v2.2 today, with v2.2.1 the current patch release; see [CHANGELOG.md](CHANGELOG.md) for what shipped in each release. The v2.2 release added the key-optional HMAC sign-off envelope (`signed_off_sig`); v2.2.1 fixed the eval-runner stdin-hang. Format changes that have shipped (budget_iterations, precondition, execution_backend, signed_off, signed_off_sig, creates_paths) are documented in [references/concepts/task-spec-v1.md](references/concepts/task-spec-v1.md) (filename retained for link stability — the document covers the current v2.2 format).

---

## Contributing / Extending

- New concept? Add to `references/concepts/` (≤150 lines)
- New pattern? Add to `references/patterns/` (≤200 lines)
- New runbook? Add to `runbooks/` (operational playbooks)
- Format change? Bump version in `scripts/_lib.sh` + `SKILL.md` + `CHANGELOG.md`; provide migration script if breaking
- Bug in scripts? PR with test case in `scripts/test-*.sh`

---

## License

MIT — built by Luan Moreno. Use freely. Attribute when citing.

---

## See also

- [references/concepts/task-spec-v1.md](references/concepts/task-spec-v1.md) — THE published format spec
- [references/concepts/eval-driven-development.md](references/concepts/eval-driven-development.md) — the methodology
- [references/concepts/edd-vs-sdd-honest-comparison.md](references/concepts/edd-vs-sdd-honest-comparison.md) — when to use which
- [runbooks/from-fuzzy-intent.md](runbooks/from-fuzzy-intent.md) — paragraph → Task-Spec
- [runbooks/empirical-experiment-protocol.md](runbooks/empirical-experiment-protocol.md) — the SDD vs EDD experiment

> **"Specs that verify themselves don't need humans in the middle of the loop."**
