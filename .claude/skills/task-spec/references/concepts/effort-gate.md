# Effort Gate

> **Purpose**: S/M/L/XL classification + refusal logic. The size-based safety primitive.
> **Confidence**: HIGH
> **MCP Validated**: 2026-05-19

## The rule

Task-Spec v2.1 accepts ONLY S and M effort. L and XL are REJECTED with routing to AgentSpec SDD.

```text
S  → Task-Spec ✅
M  → Task-Spec ✅
L  → Task-Spec ❌ → route to AgentSpec /agentspec:brainstorm
XL → Task-Spec ❌ → route to AgentSpec /agentspec:brainstorm
```

## The definitions

| Class | Time scope | Effort signal | Example |
|-------|-----------|---------------|---------|
| **S** | ≤ 1 day | One file or 2-3 closely-related files | Add a /health endpoint |
| **M** | 1-3 days | Module-level change, multiple coordinated files | Refactor a parser; add a new endpoint family |
| **L** | 3-7 days | New service or major migration | New microservice; cross-team interface |
| **XL** | > 1 week | Multi-team / multi-quarter | Platform rewrite; org-wide rollout |

## Why the gate matters

| Property | S/M (Task-Spec) | L/XL (AgentSpec) |
|----------|----------------|------------------|
| Eval loop overhead | Amortized over small surface | Crushing — too many things to verify |
| Human alignment cost | Small | Large — needs design phases |
| Single PR fits | Yes | No |
| Autonomous overnight execution | Sane | Risky |
| Recovery if it fails | Park, retry tomorrow | Major incident |

EDD's velocity advantage holds for S/M. For L/XL, the spec phase IS the work
— and SDD's 5-phase rigor handles that better.

## The classifier (task-architect agent)

The `task-architect` agent applies these heuristics:

```text
SIGNAL                                      → IMPLIES
─────────────────────────────────────────────────────
1 file changes                              → S
2-5 closely-related files                   → S or small M
Multiple modules touched                    → M
New top-level directory                     → likely L
Cross-language change                       → likely L
New service / new deployment unit           → L or XL
"big" / "huge" / "platform" in intent       → likely L or XL
Multi-team coordination required            → XL
```

If the classifier returns L/XL, the agent REFUSES and outputs:

```text
This task is L/XL effort.

Task-Spec v2.1 only accepts S/M. Route to AgentSpec instead:
  /agentspec:brainstorm "<your intent>"

AgentSpec's 5-phase SDD is designed for L/XL work:
  brainstorm → define → design → build → ship
```

## Edge cases

### "It's actually two tasks"

If a task feels L because it's two M tasks bundled — DECOMPOSE.

```text
Original (L): "Migrate auth from JWT to OAuth2 across all services"

Decomposed:
  T-1 (M): Add OAuth2 provider in auth-service
  T-2 (M): Switch user-service to OAuth2 client
  T-3 (M): Switch admin-service to OAuth2 client
  T-4 (S): Remove JWT code paths after migration verified
```

Decomposition restores Task-Spec eligibility.

### "It LOOKS small but actually isn't"

Some 1-file changes are L in disguise — touching a critical, fragile module.
Use repo-scan heuristics:

```text
RED FLAGS for "looks S but actually L":
  · File has > 500 lines and high test coverage (sensitive code)
  · File appears in CODEOWNERS with many reviewers
  · File is in src/core/, src/auth/, src/billing/ (high-stakes paths)
  · Last 5 commits touching the file all required follow-up fixes
```

When in doubt, classify UP (S→M or M→L). False S→M produces overengineered specs; false M→L routes to AgentSpec, which is fine.

### "I want to override and use Task-Spec anyway"

Don't. The effort gate is CRITICAL threshold (refuses, doesn't ask). Bypassing
it is how you get half-baked specs for half-baked work. Use the right tool.

## Related

- [task-spec-v1.md](task-spec-v1.md) — frontmatter spec for `effort` field
- [edd-vs-sdd-honest-comparison.md](edd-vs-sdd-honest-comparison.md) — when each wins
- [agent-contract.md](agent-contract.md) — how the agent refuses
