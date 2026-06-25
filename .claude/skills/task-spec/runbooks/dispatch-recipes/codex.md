# Dispatch Recipe: Codex CLI

> **Use when:** `execution_backend: codex` — hand the spec to the OpenAI Codex CLI (or its Claude Code plugin sibling) for autonomous execution.

Codex consumes the spec via its CLI front-end and honors a `codex_metadata:` block in the frontmatter when present (model selection, sandbox profile, approval mode). The CLI surfaces exit codes the dispatcher must respect.

---

## Prerequisites

- `codex` CLI installed and on PATH (verify with `codex --version`).
- Codex auth completed (`codex login` or `OPENAI_API_KEY` exported).
- Spec is at `signed_off: true` with the gate clean.
- Optional but recommended: a `codex_metadata:` block in the spec frontmatter naming `model`, `sandbox`, and `approval_mode`. Absent it, Codex applies its installed defaults.
- Working tree is clean so the diff is attributable.

---

## Dispatch command

The canonical invocation runs the spec as a task file. Verify the exact flag set against your installed Codex CLI version — older builds used `codex exec`, current builds use `codex run`:

```bash
codex run --task tasks/T-<spec>.md --cd "$(pwd)"
```

Common flag overrides (consult `codex run --help` for your version):

```bash
codex run --task tasks/T-<spec>.md \
  --model gpt-5-codex \
  --sandbox workspace-write \
  --approval-mode never
```

The `codex_metadata:` block (when present) feeds these flags so the dispatcher does not have to repeat them on the command line.

---

## Status reporting

Codex does not flip `status:` automatically. After the CLI returns:

```bash
test $? -eq 0 && bash .claude/skills/task-spec/scripts/transition-status.sh \
  tasks/T-<spec>.md in-progress done
```

For wraparound automation, wrap the dispatch in a shell function that flips `ready -> in-progress` before the call and `in-progress -> done|parked` based on `$?`.

---

## Failure modes

| Exit code | Meaning | Action |
|-----------|---------|--------|
| 0 | Codex completed successfully | Run `safe-to-delegate.sh` to confirm evals pass; flip `status: done` |
| 1 | Codex reported task failure | Re-run with `--verbose`; inspect last assistant turn for unresolved blockers |
| 2 | Sandbox or approval policy denied a needed action | Tighten `touches_paths` so Codex stays inside the workspace-write boundary |
| 124 | CLI timeout | Increase `--timeout`; split the spec if the task is genuinely too large |
| Codex returns 0 but evals still fail | Engine hallucinated completion | Treat as defect — revert diff and re-dispatch with eval log in the prompt |

---

## See also

- [../dispatching-a-task-spec.md](../dispatching-a-task-spec.md) — router and pre-flight checklist
- [claude-code.md](claude-code.md) — alternative when no Codex auth is available
- [../../references/concepts/agent-contract.md](../../references/concepts/agent-contract.md) — read-zone semantics Codex honors
- [custom.md](custom.md) — for non-standard Codex deployments (e.g. self-hosted)
