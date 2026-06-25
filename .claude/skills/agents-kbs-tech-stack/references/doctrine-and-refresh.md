# Doctrine + Refresh — fleet-wide numeric truth for tech-stack agents

> **TL;DR.** Every architect / developer / troubleshooter scaffolded by
> `agents-kbs-tech-stack` embeds three numeric tables — the Agreement Matrix,
> the Confidence Modifiers, and the Task Thresholds. The doctrine layer makes
> those numbers tunable *after* scaffolding. Edit `.claude/doctrine.yaml`, run
> `scripts/refresh-doctrine.sh`, and every agent in the repo picks up the new
> values without touching their tech-specific body.

---

## 1. Why the doctrine exists (the frozen-at-scaffold problem)

Before v0.3, the numeric cells in every agent body were literally hard-coded
into the templates:

```text
| HIGH: 0.95     | CONFLICT: 0.50 | MEDIUM: 0.75   |
| MCP-ONLY: 0.85 | N/A            | LOW: 0.50      |
```

That worked for one agent. It does not scale to a fleet. If, six months after
scaffolding, you decide:

- `CONFLICT` should be `0.55` (not `0.50`) because your team treats
  KB-disagrees-MCP cases more conservatively, or
- `CRITICAL` should be `0.99` (not `0.98`) because you now ship to a regulated
  environment, or
- the `production_examples_plus` modifier should be `+0.10` (not `+0.05`)
  because you discovered real-world examples are a stronger signal than the
  default assumes —

then with the old design you would have to hand-edit every `*-architect.md`,
`*-developer.md`, and `*-troubleshooter.md` in every repo. With four techs
and three roles, that is twelve files per repo. With a portfolio of repos,
it gets worse. And every hand-edit risks accidentally breaking a row of
ASCII art or skipping a file.

The doctrine layer flips the relationship. The agent bodies still *display*
the numbers (so a reader of the agent file sees the rules in context), but
the **canonical source** is `.claude/doctrine.yaml`. A refresh script
propagates the canonical numbers back into the agent bodies in one pass.

---

## 2. Schema of `.claude/doctrine.yaml`

The file is loaded by `scripts/refresh-doctrine.sh` as plain YAML. The
template lives at `templates/doctrine.yaml.tpl` and is installed verbatim
(no placeholder substitution) the first time `scripts/scaffold.sh` runs in
a repo.

### 2.1 Top-level fields

| Field | Type | Meaning |
|-------|------|---------|
| `schema_version` | int | Currently `1`. Bump when the refresh script changes the field set in a breaking way. |
| `agreement_matrix` | map | Five numeric cells — see §2.2. |
| `modifiers` | map | Seven numeric modifiers — see §2.3. |
| `thresholds` | map | Four severity thresholds — see §2.4. |

### 2.2 `agreement_matrix` (5 cells)

The five non-N/A cells of the 2×3 matrix that every agent embeds.

| Key | Default | Maps to ASCII label | Meaning |
|-----|---------|---------------------|---------|
| `kb_has_pattern_mcp_agrees` | `0.95` | `HIGH` | KB and MCP agree. Strongest signal. |
| `kb_has_pattern_mcp_disagrees` | `0.50` | `CONFLICT` | KB and MCP disagree. Halt and investigate. |
| `kb_has_pattern_mcp_silent` | `0.75` | `MEDIUM` | KB has a pattern; MCP can't speak to it. Proceed cautiously. |
| `kb_silent_mcp_agrees` | `0.85` | `MCP-ONLY` | KB silent; MCP confirms. Proceed but log the gap. |
| `kb_silent_mcp_silent` | `0.50` | `LOW` | Neither source has a strong opinion. Ask the user. |

### 2.3 `modifiers` (7 entries)

Adjustments applied on top of the base agreement-matrix score. Positive values
raise confidence; negative values lower it. The defaults are deliberately
symmetric so that for every "+X" modifier there is a corresponding "-X"
counterpart capturing the opposite condition.

| Key | Default | Apply when |
|-----|---------|------------|
| `fresh_info_plus` | `+0.05` | MCP result is < 1 month old. |
| `stale_info_minus` | `-0.05` | KB has not been updated in > 6 months. |
| `breaking_change_minus` | `-0.15` | A breaking major version is known to affect callers. |
| `production_examples_plus` | `+0.05` | Real-world implementations of the pattern were located. |
| `no_examples_minus` | `-0.05` | No production references could be located. |
| `exact_match_plus` | `+0.05` | The KB pattern matches the request exactly. |
| `tangential_minus` | `-0.05` | The KB pattern is only loosely related to the request. |

### 2.4 `thresholds` (4 cells)

Minimum confidence required to act without escalation, indexed by task
severity. Falling below the threshold means: refuse, ask the user, or
escalate to the agent's counterpart (architect ↔ developer ↔ troubleshooter).

| Key | Default | Severity |
|-----|---------|----------|
| `critical` | `0.98` | Security, data integrity, production hot path. |
| `important` | `0.95` | Public API, contract changes, perf regressions on hot paths. |
| `standard` | `0.90` | Internal refactor, bug fix, slow-but-not-hot query. |
| `advisory` | `0.80` | Formatting, naming, dead code, minor nits. |

---

## 3. How `refresh-doctrine.sh` works

The script is a thin Bash entrypoint that delegates the real work to inline
Python. The flow:

1. **Validate inputs.** `TARGET_REPO` env var is required. If not set, exit
   non-zero with a clear error.
2. **Locate the doctrine.** Read `<TARGET_REPO>/.claude/doctrine.yaml`. If the
   file is missing, copy `templates/doctrine.yaml.tpl` into place and exit with
   an INFO message instructing the user to re-run. This makes the script
   idempotent and self-bootstrapping — you can invoke it on a repo that has
   never been scaffolded and it leaves a tunable doctrine in its wake.
3. **Locate agents.** Glob over `<TARGET_REPO>/.claude/agents/` for files
   matching `*-architect.md`, `*-developer.md`, and `*-troubleshooter.md`.
4. **For each agent, read-modify-write** using three surgical regex passes:
   - **Agreement Matrix.** Find each occurrence of `HIGH: <num>`,
     `CONFLICT: <num>`, `MEDIUM: <num>`, `MCP-ONLY: <num>`, `LOW: <num>`
     (with flexible whitespace) and replace the number while preserving the
     label, colon, and surrounding ASCII art.
   - **Confidence Modifiers.** For each row whose label maps to a doctrine
     modifier key (Fresh info, Stale info, Breaking change, Production
     examples, No examples, Exact match, Tangential), replace the numeric
     cell with the signed doctrine value. Rows that don't map to a doctrine
     key (e.g., the troubleshooter's "Reproducible failure | +0.10") are
     **preserved verbatim** — they are tech/role-specific and outside the
     doctrine's scope.
   - **Task Thresholds.** For each row whose label starts with `CRITICAL`,
     `IMPORTANT`, `STANDARD`, or `ADVISORY`, replace the numeric cell with
     the matching `thresholds.<key>` value.
5. **Report.** For each agent file, print `✓ updated <name>` or
   `○ no changes <name>`. Print a final summary `Refreshed N files from
   doctrine.yaml`.

### Why regex and not full markdown parsing?

The numeric cells are embedded inside two different surface forms — an ASCII
diagram (for the Agreement Matrix) and a markdown table (for Modifiers and
Thresholds). A markdown AST parser would correctly handle the table but
ignore the diagram. A YAML/JSON sidecar would lose the in-context readability
that makes the agent file self-documenting. Targeted regex preserves both
surfaces and treats every other byte of the agent body as immutable.

---

## 4. When to run it

There are exactly three trigger points:

### 4.1 You edited `doctrine.yaml`

The most common case. You tuned a number; you want every agent in the repo to
reflect it.

```bash
# from inside the skill source
TARGET_REPO=/path/to/repo scripts/refresh-doctrine.sh
```

### 4.2 You upgraded the skill

A newer version of `agents-kbs-tech-stack` may ship updated defaults. The
upgrade procedure is:

1. Inspect the diff between your `doctrine.yaml` and the new
   `templates/doctrine.yaml.tpl` (these two files are intentionally kept
   schema-aligned so a `diff` is meaningful).
2. Reconcile any new fields or changed defaults.
3. Run `refresh-doctrine.sh`.

### 4.3 You scaffolded a new tech and want it to inherit existing tuning

`scaffold.sh` installs the doctrine on the *first* scaffold and leaves it
alone on subsequent scaffolds. That means a freshly scaffolded agent renders
with the *template* defaults baked in, even if your `doctrine.yaml` has
already been tuned. Run `refresh-doctrine.sh` immediately after scaffolding
a new tech to bring the new agents into line with the existing fleet.

---

## 5. Safety — what refresh does NOT touch

This is the design contract. Anything outside this list is preserved
byte-for-byte:

| Touched | Untouched |
|---------|-----------|
| `<LABEL>: <number>` cells inside the Agreement Matrix ASCII block, where `<LABEL>` is one of: HIGH, CONFLICT, MEDIUM, MCP-ONLY, LOW. | Anything inside the agent's YAML frontmatter (`name:`, `description:`, `tools:`, `color:`, `model:`). |
| Modifier rows whose label prefix is one of the seven doctrine modifier names. | Modifier rows whose label is tech/role-specific (e.g., "Reproducible failure", "Tests cover the change", "Idiomatic per KB"). |
| Threshold rows whose label prefix is `CRITICAL`, `IMPORTANT`, `STANDARD`, or `ADVISORY`. | The body of every "Pattern", "Playbook", "Decision Framework", "Anti-Patterns" section. |
| | Markdown headings, paragraphs, bullets, code fences, ASCII art *outside* the matrix cells. |
| | KB files under `.claude/kb/`. |
| | Closer agents (`code-reviewer.md`, `code-simplifier.md`, `code-documenter.md`) — those are governed by the closer-hook protocol, not the doctrine. |

The regex passes are deliberately conservative — they match on a unique
label prefix plus a numeric token, anchored to the row-start pipe for tables
and the inline label for the ASCII matrix. A user who renames a row label
(e.g., "Fresh info (< 1 month)" → "Recent MCP result") effectively opts that
row *out* of the doctrine — the refresh script will leave it untouched and
print a `○ no changes` line if no other doctrine-controlled cell changed.

### What if I want a value other than the doctrine's?

Two paths:

1. **Override the doctrine.** Edit `.claude/doctrine.yaml`. This is the
   intended path — the doctrine is the project's tuning surface.
2. **Opt a single agent out.** Rename the row label or the matrix cell label
   in that agent file. The regex will no longer match, and the cell becomes
   user-owned. Keep a comment explaining why.

### Idempotency

Running `refresh-doctrine.sh` twice in a row produces:

```
  ○ no changes <file>
  ...
Refreshed 0 files from doctrine.yaml
```

The second run is a no-op. This makes it safe to invoke from a pre-commit
hook, CI gate, or `make` target without worrying about churn in version
control.

---

## 6. Related references

- [`closer-hook-protocol.md`](./closer-hook-protocol.md) — how the three
  universal closers ground in every tech KB without needing per-tech
  numeric tuning. The closers are deliberately outside the doctrine.
- [`architect-vs-developer.md`](./architect-vs-developer.md) — the role
  contract that the doctrine numbers operationalize. The thresholds in
  `doctrine.yaml.thresholds` are the numeric expression of "when does
  the architect refuse vs. ask vs. proceed."
- [`tech-menu-curation.md`](./tech-menu-curation.md) — how to add a new
  tech to the menu. The new tech inherits the doctrine automatically; you
  do not need to touch numbers in the menu entry.
