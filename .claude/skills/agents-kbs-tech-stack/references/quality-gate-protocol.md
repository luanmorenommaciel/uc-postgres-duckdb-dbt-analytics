# Quality Gate Protocol — agents-kbs-tech-stack v0.3.0

> The quality gate is a fast, advisory cold-eyes pass over the files the scaffold just produced. It catches drift before the user ships a half-rendered or role-misaligned agent into their repo.

This document is the contract between the skill and the gate. It exists so anyone editing `scripts/quality-gate.sh` or `prompts/kimi-review-scaffold.md` understands what each check exists for, when it should fire, and what the rescue path looks like when it does.

---

## Why a quality gate

Scaffolding is template substitution plus YAML editing. Both are mechanical, and both have known failure modes:

- A new menu entry forgets `architect_capabilities`, so the rendered template leaves `{ARCHITECT_CAPABILITIES_BLOCK}` in the file.
- Someone edits `templates/architect.md.tpl` and accidentally adds `Bash` to the architect's tool list — the architect is now allowed to execute code, silently violating the role split.
- A user re-runs the scaffold after renaming a tech, and `_index.yaml` now points to a `kb/old-name/` directory that no longer exists.

The agents themselves cannot detect these problems — they read the files as authoritative. The gate is the only pass that questions whether what was just written matches the doctrine.

The gate is **advisory by default** because most scaffold runs are clean and the user does not want a build break on a NIT. It becomes **enforcing** when invoked with `--strict`, which is the recommended CI posture.

---

## What each check does

The gate has five steps. Steps A–D are local; Step E is the optional cold-eyes pass via the `claude` CLI.

### Step A — Placeholder leak check

`grep -rnE '\{[A-Z_][A-Z0-9_]*\}' .claude/agents/ .claude/kb/`

The scaffold's renderer substitutes `{ALL_CAPS_TOKEN}` placeholders from environment variables. If the template references a token that the menu does not define, the renderer leaves the literal placeholder in the file. That file is then broken in a way that is easy to miss visually — it parses as YAML, it loads as an agent, it just contains a curly-brace string where a name or a threshold should be.

Every hit is recorded as a **BLOCKER**. The grep is rooted at the entire `.claude/agents/` and `.claude/kb/` trees so we catch leaks in both agent frontmatter and KB seed entries.

### Step B — Architect alignment (no Bash)

For each `*-architect.md` under `.claude/agents/`, the gate extracts the `tools:` line and verifies that the `Bash` token is not present. The regex is anchored — it matches `Bash` as a list element, not as a substring inside another tool name, so it does not false-positive on (hypothetical) `BashLike` or similar.

The architect role is "plans, decides, documents — does not execute." Granting it `Bash` collapses the role split and lets it run code paths the developer agent should own. Any architect with `Bash` is a **BLOCKER**.

### Step C — Developer alignment (Bash required)

The mirror of Step B. Every `*-developer.md` must contain `Bash` in its `tools:` line. Developers ship code, run tests, apply fixes — without `Bash` they cannot do their job. Missing `Bash` is a **BLOCKER**.

### Step D — Troubleshooter alignment (Bash yes, Edit/Write no)

For each `*-troubleshooter.md`, the gate requires `Bash` (the troubleshooter runs diagnostic commands) but forbids both `Edit` and `Write` (the troubleshooter is read-only by design — patches go through the developer). Any violation is a **BLOCKER**.

This check is skipped when no troubleshooters exist. The menu opts into troubleshooter generation per tech via the `roles:` field.

### Step E — Optional `/kimi:review` pass

If `command -v claude` resolves and `SKIP_KIMI` is not set in the env, the gate invokes:

```bash
claude --print "/kimi:review --base HEAD"
```

The prompt it sends is the file `prompts/kimi-review-scaffold.md`. The expected response is JSON of shape:

```json
{
  "summary": "...",
  "findings": [
    {"severity": "BLOCKER", "file": "...", "line": 42, "message": "...", "suggestion": "..."}
  ]
}
```

Findings from kimi are merged into the local findings list with a `[kimi]` prefix on the message. The gate is **defensive about kimi failures**:

- If `claude` is not installed → skipped silently.
- If `claude --print` exits non-zero → logged as `error`, gate continues.
- If stdout is not parseable JSON → logged as `non-json`, gate continues.
- If JSON parses but has no `findings` key → ignored, gate continues.

The gate **never blocks on kimi failure**. The local checks (Steps A–D) are the floor; kimi is an upgrade when available.

---

## Severity levels

Three levels, applied uniformly to local findings and kimi findings.

### BLOCKER

Any rubric violation. The scaffold is not safe to use until fixed. Examples:

- Architect with `Bash` in tools list.
- Developer without `Bash` in tools list.
- Troubleshooter with `Edit` or `Write` in tools list.
- Unrendered `{PLACEHOLDER}` in a generated file.
- Missing frontmatter key (`name`, `description`, `tools`, `model`, `color`).
- `_index.yaml` references a domain whose directory does not exist.

In `--strict` mode, **any** BLOCKER makes the gate exit 7.

### IMPORTANT

Drift or inconsistency that degrades quality but does not break the scaffold. The scaffold is still usable; these are findings the user should triage before relying on the output. Examples:

- Architect body contains a long production code block presented as the canonical answer (role drift).
- Developer body contains an ADR-style trade-off matrix instead of patterns (role drift in the opposite direction).
- `name:` in frontmatter does not match the filename slug.
- KB entry has no `<!-- TODO -->` blocks AND no real content (looks abandoned).
- Memorable maxim is empty or boilerplate.

IMPORTANT findings never affect exit code. They roll up into `APPROVE_WITH_WARNINGS`.

### NIT

Pure style. Things that do not affect agent behavior but matter for readability and maintainability. Examples:

- Inconsistent capitalization in headings.
- Trailing whitespace on a frontmatter value.
- Missing blank line before a fenced code block.

NIT findings are listed in the verdict block so the user can address them, but they never affect exit code or escalate to a rescue path.

---

## Verdict computation

```text
BLOCKERs > 0                                          → BLOCK
BLOCKERs == 0 AND (IMPORTANTs > 0 OR NITs > 0)        → APPROVE_WITH_WARNINGS
no findings                                           → APPROVE
```

The verdict is printed as the last line of the gate's stdout and is intended to be both human-readable and grep-friendly.

---

## The `--strict` contract

| Mode      | BLOCKERs | Exit code |
|-----------|----------|-----------|
| default   | any      | 0         |
| `--strict`| 0        | 0         |
| `--strict`| 1+       | 7         |

Default mode is **informational**: the gate runs, prints, exits 0. The user sees the findings; the scaffold proceeds; downstream automation (Phase 4 report) decides how to surface them.

`--strict` mode is **enforcing**: BLOCKERs cause exit 7. This is the recommended posture for CI hooks, pre-commit gates, and anywhere a human will not be reading the output in real time.

Exit code 7 was chosen because:
- It does not collide with bash's reserved codes (1, 2, 126, 127, 128+N).
- It does not collide with the upstream scaffold's exit codes (1–8 are taken by `scaffold.sh` for distinct render failures).
- It is far enough from 0 to be unmistakable in CI dashboards.

Other exit codes from the gate:
- `0` — success (advisory mode, or strict mode with no BLOCKERs).
- `2` — `TARGET_REPO` env var unset or `.claude/` directory missing. Indicates a wiring bug, not a scaffold quality issue.

---

## How `/kimi:review` integrates

`kimi:review` is a slash command provided by the kimi plugin. The gate delegates to it via `claude --print "/kimi:review --base HEAD"`, which:

1. Runs in a non-interactive subprocess (no TTY required).
2. Returns to stdout when the review finishes.
3. Exits zero on a successful review, non-zero on any internal error.

The contract the gate expects:

- **Input**: the prompt at `prompts/kimi-review-scaffold.md` is the authoritative rubric. The gate passes the prompt by reference (the prompt lives in the skill bundle so the reviewer can inspect it independently).
- **Output**: JSON object with `summary` (string) and `findings` (array of `{severity, file, line, message, suggestion}`).
- **Failure modes**: any non-zero exit, any non-JSON stdout, any malformed JSON is treated as "kimi unavailable." The gate prints a one-line note (`kimi:review unavailable — proceeding with local checks only`) and continues with steps A–D only.

This is deliberate. The local checks are deterministic and fast; kimi is a probabilistic LLM call that may or may not be available. The gate treats kimi as a strict upgrade, never a dependency.

---

## The `/codex:rescue` handoff for BLOCKERs

When the gate emits BLOCKER findings, the skill's Phase 4 report offers a single option to the user: invoke `/codex:rescue` with the gate findings as input. This is the rescue path.

`codex:rescue` is a Codex plugin slash command that:

1. Reads the gate's verdict block + per-file details from stdin or via an argument.
2. Patches the offending files — restores the `Bash` boundary, fills missing frontmatter keys, replaces unrendered placeholders with sensible defaults or escalates.
3. Returns a summary of what was patched.

The handoff is a one-shot offering, not an automatic step. The skill does not silently call `codex:rescue` because:

- Rescue is a code-modifying action; the user should consent.
- BLOCKERs sometimes indicate a menu authoring bug (e.g., a missing `architect_capabilities` field). The user may want to fix the menu and re-run the scaffold instead of patching the rendered files.

When rescue completes, the user should re-run the gate to confirm the BLOCKERs are gone. The gate is cheap (sub-second for typical fleet sizes), so this is a fine pattern.

---

## Operational notes

- The gate is **bash 3.2 safe** — it runs on stock macOS without modernization. The findings buffer uses a tmpfile (no associative arrays), and all loops use `while read` over `find -print0`.
- The gate does **not** require Python except for the optional kimi JSON parser. The local checks are pure shell + grep.
- The gate writes nothing to the target repo. It only reads and prints.
- `SKIP_KIMI=1` is a useful env var for CI runs where the Claude CLI is installed but you want deterministic, network-free behavior.

---

## When to extend the gate

Add a new check when:

1. A new role is added to the doctrine (the gate must learn its tool boundary).
2. A new structural invariant emerges in the templates (e.g., a required section in every architect body).
3. A new class of render bug appears in practice (the gate is the cheap defense against repeat occurrences).

Do **not** add a check that requires LLM reasoning to the local steps — those belong in the kimi prompt. The local steps must remain deterministic, sub-second, and offline.

---

## See also

- [`prompts/kimi-review-scaffold.md`](../prompts/kimi-review-scaffold.md) — the cold-eyes review prompt.
- [`scripts/quality-gate.sh`](../scripts/quality-gate.sh) — the gate orchestrator.
- [`references/architect-vs-developer.md`](./architect-vs-developer.md) — why the Bash boundary matters.
- [`SKILL.md`](../SKILL.md) — Phase 3.5 (quality gate) and Phase 4 (report) in the scaffold workflow.
