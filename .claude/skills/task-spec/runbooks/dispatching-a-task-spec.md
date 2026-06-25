# Runbook: Dispatching a Task-Spec

> **Use when:** A spec has passed the gate (`signed_off: true` in frontmatter) and you're ready to hand it to an autonomous engine.

This runbook closes the loop after stamping. Up to and including `safe-to-delegate.sh --stamp`, the author is in the driver's seat. Past `signed_off: true`, the engine is.

This file is a **router**. The pre-flight checks and post-dispatch verification are common to every engine; the engine-specific dispatch command lives in a paired recipe file under `dispatch-recipes/`.

---

## Pick your engine

The spec's `execution_backend:` frontmatter field names the canonical executor. Look up the value and jump to the matching recipe:

| `execution_backend` | Recipe | Best for |
|---------------------|--------|----------|
| `claude` | [dispatch-recipes/claude-code.md](dispatch-recipes/claude-code.md) | Interactive sessions, subagent delegation via `Task()` |
| `codex` | [dispatch-recipes/codex.md](dispatch-recipes/codex.md) | OpenAI Codex CLI with `codex_metadata:` block |
| `kimi` | [dispatch-recipes/kimi.md](dispatch-recipes/kimi.md) | Dark-factory broker pipeline with Codex plan + diff review |
| `gemini` | [dispatch-recipes/gemini.md](dispatch-recipes/gemini.md) | Generic completion-API CLIs (Gemini, llm, ollama, aichat) |
| `taskship` | [dispatch-recipes/taskship.md](dispatch-recipes/taskship.md) | taskship workspace runtime |
| `anthive` | [dispatch-recipes/anthive.md](dispatch-recipes/anthive.md) | Parallel-session dispatch with `output_artifacts:` capture |
| `any` / `custom` / unknown | [dispatch-recipes/custom.md](dispatch-recipes/custom.md) | DIY escape hatch; references v2.2's deferred `dispatch_recipe:` field |

If `execution_backend: any` (the default), the author left the choice to the dispatcher — pick whichever recipe matches the engine you have configured.

---

## Pre-flight checklist

Regardless of engine, verify these before dispatching:

```bash
# 1. The spec is at signed_off: true
grep '^signed_off:' tasks/T-<your-spec>.md
# Expect: signed_off: true

# 2. Re-running the gate is a no-op (idempotency) AND check the sign-off TIER
bash .claude/skills/task-spec/scripts/safe-to-delegate.sh tasks/T-<your-spec>.md
# Expect: VERDICT: DELEGATE
# Also read the sign-off tier line:
#   "sign-off: Tier 1"                          → full crypto trust, unsupervised OK
#   "sign-off: structural-only (Tier 2)"        → SUPERVISED DISPATCH ONLY (see policy below)
#   "sign-off: Tier 3"                          → DO NOT DISPATCH (tampered after stamping)

# 3. The working tree is clean (so we can attribute the engine's diff)
git status --short
# Expect: empty (or only the spec file itself)

# 4. You're on the branch where the work should land
git branch --show-current
```

If any of these fail, **do not dispatch**. Fix the precondition first, then return to your engine's recipe.

### Sign-off tier gate (MANDATORY, v2.2)

The HMAC sign-off envelope (see [../references/concepts/signed-off.md](../references/concepts/signed-off.md)) classifies every stamped spec into one of three tiers. Unsupervised dispatch eligibility depends on the tier:

| Tier | Meaning | Unsupervised crank? |
|------|---------|---------------------|
| **Tier 1** | key present, `signed_off_sig` HMAC verifies | **Yes** — full crypto trust |
| **Tier 2** | no key resolved, or no `signed_off_sig` (legacy spec) | **NO — supervised dispatch only** (read / inspect / triage). A human must supervise. |
| **Tier 3** | key present but HMAC mismatch / malformed sig | **NO** — treat as tampered; re-stamp before dispatch |

**Why Tier 2 is supervised-only:** Tier 2 is structurally valid but cryptographically unverified — an adversary who read this skill could run the verifier *without* the key to reach the (forgeable) Tier-2 state and try to dispatch unsupervised. The supervised-only rule removes that bypass. To promote a Tier-2 spec to Tier-1 unsupervised trust: provision a key with `configs/setup-taskspec-signing-key.sh` (or export `TASKSPEC_SIGNING_KEY`), then re-run `safe-to-delegate.sh --stamp`.

**Enforcing the policy in automation (v2.2):** the supervised-only rule is not just prose — an automated dispatcher can enforce it mechanically.

*Machine-readable tier* — for any signed spec, `safe-to-delegate.sh` emits exactly one `TIER=N` line to stdout (`N` ∈ {1,2,3}). Parse that line instead of the colored prose:

```bash
tier=$(bash .claude/skills/task-spec/scripts/safe-to-delegate.sh tasks/T-<spec>.md | sed -n 's/^TIER=//p')
[[ "$tier" == "1" ]] || { echo "refusing unsupervised dispatch (Tier $tier)"; exit 1; }
```

*Hard gate* — pass `--require-tier1` to make the gate itself exit non-zero on anything below Tier 1, so a CI pipeline that branches on `$?` cannot crank a Tier-2 spec unattended:

```bash
bash .claude/skills/task-spec/scripts/safe-to-delegate.sh --require-tier1 tasks/T-<spec>.md
# exit 0 only when sign-off is Tier 1 (crypto trust); exit 1 otherwise
```

---

## Post-dispatch verification

The engine is responsible for flipping `status:` from `ready` → `in-progress` → `done` (or `parked` on failure). After the session completes:

```bash
# 1. The spec's status should reflect the outcome
grep '^status:' tasks/T-<spec>.md

# 2. Re-run the gate against the now-complete work. Evals should all pass.
bash .claude/skills/task-spec/scripts/safe-to-delegate.sh tasks/T-<spec>.md
# Expect: VERDICT: DELEGATE with N pass / 0 fail

# 3. Inspect the engine's diff
git diff HEAD~1
# Or, for engines that don't auto-commit:
git diff
```

If the engine reported success but the gate now reports `DO NOT DELEGATE`, treat that as a **real defect** — the engine claimed completion that the contract does not corroborate. Park the task with `blocked_reason: engine-success-but-gate-fails`, document the divergence, and re-author or re-dispatch.

---

## What NOT to do

- **Don't manually flip `signed_off:` back to `false` after dispatch.** The contract is durable — if the engine produces wrong work, the right response is to revert the diff, not to relitigate the gate. Park the task instead.
- **Don't dispatch a spec whose `signed_off: true` was hand-edited.** The structural sign-off envelope check (see `validate-task-spec.sh` v2.1+) will reject it; supervisors should refuse to dispatch.
- **Don't dispatch from a dirty working tree.** You'll lose the ability to isolate the engine's contribution from your pending work.
- **Don't ignore engine exit codes 2-6.** Each one names a specific recoverable condition; treating them as opaque failures wastes the typed-error system the engine provides. See the engine's recipe for the exit-code table.

---

## See also

- [dispatch-recipes/claude-code.md](dispatch-recipes/claude-code.md)
- [dispatch-recipes/codex.md](dispatch-recipes/codex.md)
- [dispatch-recipes/kimi.md](dispatch-recipes/kimi.md)
- [dispatch-recipes/gemini.md](dispatch-recipes/gemini.md)
- [dispatch-recipes/taskship.md](dispatch-recipes/taskship.md)
- [dispatch-recipes/anthive.md](dispatch-recipes/anthive.md)
- [dispatch-recipes/custom.md](dispatch-recipes/custom.md)
- [validating-a-task-spec.md](validating-a-task-spec.md) — pre-gate linter walkthrough
- [../references/concepts/signed-off.md](../references/concepts/signed-off.md) — the autonomy contract
- [../references/concepts/agent-contract.md](../references/concepts/agent-contract.md) — cross-vendor execution contract
- [from-fuzzy-intent.md](from-fuzzy-intent.md) — paragraph → spec (start here if you don't have a spec yet)
- [first-spec-walkthrough.md](first-spec-walkthrough.md) — your first 10 minutes (new authors)
