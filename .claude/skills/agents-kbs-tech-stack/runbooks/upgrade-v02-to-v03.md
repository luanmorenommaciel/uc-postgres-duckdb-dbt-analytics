# Runbook — Upgrading an Existing v0.2 Scaffold to v0.3.0

> If you already shipped `.claude/agents/` and `.claude/kb/` with v0.2 of `agents-kbs-tech-stack`, this runbook walks you through adopting v0.3.0 without losing any of your hand-edited content. The upgrade is opt-in, additive, and never force-overwrites a file you've touched.

---

## What's new in v0.3.0

v0.3.0 leaves the v0.2 scaffolding contract intact (same architect/developer split, same KB taxonomy, same closer-hook protocol) and adds four complementary layers on top: a **quality gate** that lints scaffolded output for role-boundary drift and unrendered placeholders, a **cross-tool emission** step that translates the canonical `.claude/` surface into `AGENTS.md` + Cursor rules + Copilot instructions so Claude / Codex / Cursor / Copilot all read the same agent contract, a tunable **`doctrine.yaml`** that captures the portable defaults the emitter consumes, and a **Codex-driven KB bootstrap** flow (`bootstrap-kb.sh` → `/codex:rescue` → `accept-drafts.sh`) that turns `<!-- TODO -->` blocks into review-ready drafts without ever touching the canonical KB files. Existing v0.2 scaffolds keep working unmodified; the new pieces only activate when you opt in.

---

## Migration overview

The whole migration is four scripts, none of which mutate your existing v0.2 output destructively:

```text
1. install-closers.sh    # re-run — picks up any new closer doctrine pointers
2. refresh-doctrine.sh   # creates .claude/doctrine.yaml if missing
3. emit-cross-tool.sh    # writes AGENTS.md + Cursor + Copilot files
4. quality-gate.sh       # optional — finds drift introduced since v0.2
                         #            (and any KB content you forgot to populate)
5. bootstrap-kb.sh       # optional — Codex-drafts KB content for any tech
```

Everything else (your agent files, your KB content, your `_index.yaml`) stays exactly where it was. The upgrade adds files; it does not rewrite them.

---

## Prerequisites

- A target repo previously scaffolded with `agents-kbs-tech-stack` v0.2 — i.e., `<target>/.claude/agents/`, `<target>/.claude/kb/`, and a populated `<target>/.claude/kb/_index.yaml` already exist.
- v0.3.0 of the skill installed (symlinked into `~/.claude/skills/` or unpacked into `<target>/.claude/skills/`).
- Bash 3.2+, `python3` with `pyyaml`, and the rest of the v0.2 prerequisites.
- For the optional KB bootstrap path: Claude Code with the `codex:rescue` skill available.

If you're not sure which version produced your scaffold, the version-stamp footer on any agent file will tell you:

```bash
grep -h "Scaffolded by agents-kbs-tech-stack" \
  <target>/.claude/agents/*.md | sort -u
```

A v0.2 scaffold shows `v0.2.0`. After the upgrade, newly scaffolded agents will show `v0.3.0`; pre-existing v0.2 agents keep their v0.2 footer — the upgrade does not rewrite agent bodies.

---

## Step 1 — Re-run `install-closers.sh`

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/install-closers.sh \
  --target <target-repo>
```

Expected output for a project that already has v0.2 closers installed:

```text
NOTE: code-reviewer.md already exists at <target>/.claude/agents/ — leaving untouched
NOTE: code-simplifier.md already exists at <target>/.claude/agents/ — leaving untouched
NOTE: code-documenter.md already exists at <target>/.claude/agents/ — leaving untouched
```

That's the desired result. `install-closers.sh` has always refused to clobber existing closer files; v0.3.0 keeps the same contract. If you had hand-edited any of the three closers, those edits are preserved.

If a closer is **missing** (rare — only happens if you deleted one), it will be installed fresh from the v0.3.0 template. The v0.3.0 closer template includes a richer closer-hook protocol header that references `doctrine.yaml`, but it remains backward-compatible with v0.2 KB layouts.

### What about the doctrine?

`install-closers.sh` does **not** create `doctrine.yaml` — that's the job of `refresh-doctrine.sh` in Step 2. Keeping the responsibilities separate means you can re-run the closer installer in isolation without touching the doctrine, and vice versa.

---

## Step 2 — Run `refresh-doctrine.sh`

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/refresh-doctrine.sh \
  --target <target-repo>
```

On a v0.2 project, `doctrine.yaml` does not yet exist. The script auto-creates it from the bundled default:

```text
✓ doctrine.yaml not found at <target>/.claude/doctrine.yaml
✓ writing bundled default (v0.3.0)
✓ schema validation passed
✓ doctrine in sync — 0 derived fields updated
```

The created file looks like:

```yaml
version: 0.3.0

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

These defaults match the assumptions every v0.2 scaffold already made (architects don't have Bash, developers do, etc.), so nothing about your scaffolded files needs to change. The doctrine just makes those assumptions explicit and tunable.

### Re-runs are idempotent

Run `refresh-doctrine.sh` again and it's a no-op:

```text
✓ doctrine.yaml found at <target>/.claude/doctrine.yaml
✓ schema validation passed
✓ doctrine in sync — 0 derived fields updated
```

If you edit `doctrine.yaml` (say, raise `threshold_floor.closer` to 0.90), re-running the script revalidates the schema and recomputes any derived fields it tracks. It does **not** rewrite your agent files; that's deliberate, so you can preview the doctrine change before propagating it.

---

## Step 3 — Run `emit-cross-tool.sh`

This is the step that produces new files outside `.claude/`:

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/emit-cross-tool.sh \
  --target <target-repo>
```

Expected first-run output on a v0.2 project:

```text
✓ wrote   <target>/AGENTS.md
✓ wrote   <target>/.cursor/rules/agents.mdc
✓ wrote   <target>/.cursor/rules/react.mdc
✓ wrote   <target>/.cursor/rules/fastapi.mdc
✓ wrote   <target>/.cursor/rules/postgres.mdc
✓ wrote   <target>/.github/copilot-instructions.md
EMITTED 6 files. 0 hand-edited files were spared (no .proposed siblings written).
```

### What got written

| Path | Consumer | Generated from |
|------|----------|----------------|
| `<target>/AGENTS.md` | Codex, OpenAI Agents SDK, taskship, anthive | `agents/*.md` frontmatter + `doctrine.yaml` |
| `<target>/.cursor/rules/agents.mdc` | Cursor (always-applied) | `doctrine.yaml` |
| `<target>/.cursor/rules/<tech>.mdc` | Cursor (per tech, scoped) | menu entry + per-tech KB quick-reference |
| `<target>/.github/copilot-instructions.md` | GitHub Copilot | `doctrine.yaml` + flat digest of per-tech rules |

### If you've already hand-rolled any of these files

The emitter checks for hand-edits via a content fingerprint embedded in the file header (`<!-- agents-kbs-tech-stack: fingerprint=… -->`). If the fingerprint is missing (you created the file yourself) or mismatches (you've edited an emitted file), the emitter writes a `.proposed` sibling instead of clobbering:

```text
NOTE      AGENTS.md was hand-edited or pre-existing — wrote AGENTS.md.proposed
✓ wrote   .cursor/rules/agents.mdc
…
EMITTED 5 files. 1 hand-edited file was spared (1 .proposed sibling written).
```

Reconcile by diffing the `.proposed` file against your hand-rolled version, merging in the structural pieces you want from the emitter, then deleting the `.proposed` sibling. The next `emit-cross-tool.sh` run will treat your reconciled file as canonical (it computes a fresh fingerprint).

### Disabling individual emitters

If a tool doesn't apply (say, no one on the team uses Cursor), set `cross_tool.emit_cursor_rules: false` in `doctrine.yaml`, then re-run `emit-cross-tool.sh`. Already-emitted Cursor files are left alone — the emitter is additive only.

---

## Step 4 — (Optional) Run `quality-gate.sh --strict` to surface drift

```bash
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/quality-gate.sh \
  --target <target-repo> \
  --strict
```

The quality gate is read-only. On a v0.2 scaffold that's been hand-edited over time, `--strict` is a fast way to surface anything that drifted away from the contract:

| Check | What v0.2 projects commonly fail on |
|-------|-------------------------------------|
| `architect/Bash boundary` | Someone added `Bash` to an architect's `tools:` list to unblock an investigation |
| `developer/Bash boundary` | Developer file missing `Bash` because the tools list was copy-pasted from an architect |
| `kb tree completeness` | A KB file was deleted during cleanup |
| `threshold floor` | A threshold was lowered below the menu floor without rationale |
| `unrendered placeholders` | `{SOME_KEY}` leaked through because a v0.2 scaffold.sh export was missing |
| `index ↔ kb directory parity` | A tech was scaffolded then partially deleted, leaving a half-row in `_index.yaml` |

Default (non-strict) mode prints PASS/FAIL but exits 0 — useful for an exploratory pass. `--strict` exits non-zero on any FAIL, so you can wire it into pre-merge CI once you've cleaned the project up.

### What to do about findings

Findings are advisory: the gate never edits files. Common fixes:

- **Boundary drift**: re-align the `tools:` frontmatter list by hand. If an architect legitimately needs Bash for a one-off, override at the doctrine level (`bash_boundary.architects_have_bash: true`) so the gate stops complaining for the whole project rather than silently for one file.
- **KB tree gaps**: restore from git if recent; otherwise re-scaffold the affected tech and `git restore` the agent files you still want.
- **Placeholder leaks**: hand-edit to fill the placeholder. File a bug if you're confident `scaffold.sh` should have substituted it.

---

## Step 5 — (Optional) Bootstrap KB content with Codex

If your v0.2 KBs are still dominated by `<!-- TODO -->` blocks (a normal outcome — KB content is the long tail), use the v0.3.0 Codex-driven bootstrap flow to get review-ready drafts without round-tripping each file by hand:

```bash
# 1. Generate prompts for every <!-- TODO --> in kb/<tech>/
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/bootstrap-kb.sh \
  --target <target-repo> \
  --tech react

# 2. For each prompt, copy/paste into Claude Code:
#    /codex:rescue Generate a draft for kb/react/concepts/component-model.md
#       using the prompt in kb/react/concepts/component-model.draft.prompt.md
#       and write the result to kb/react/concepts/component-model.draft.md

# 3. Review the resulting *.draft.md files. Prune what's wrong.

# 4. Accept the drafts you kept:
bash <target>/.claude/skills/agents-kbs-tech-stack/scripts/accept-drafts.sh \
  --target <target-repo> \
  --tech react
```

`accept-drafts.sh` backs up the canonical file as `*.bak` before overwriting, and cleans up the `*.draft.md` + `*.draft.prompt.md` siblings. Add `--dry-run` to preview without writing.

Run the flow per tech, not all at once — review burden adds up fast.

See [`pick-your-stack.md`](pick-your-stack.md#kb-content-bootstrap-with-codex) for the full walkthrough.

---

## Backwards compatibility statements

The v0.3.0 upgrade is designed to be **opt-in, additive, and never destructive**. Specifically:

### v0.2 scaffolds stay valid

Every agent file, every KB file, every `_index.yaml` entry produced by v0.2 still validates against v0.3.0's quality gate without modification, assuming you didn't hand-edit something into non-compliance. The v0.2 version-stamp footer (`Scaffolded by agents-kbs-tech-stack v0.2.0 on …`) remains on those files — the upgrade does not rewrite scaffolded agents.

If you re-scaffold a tech (e.g., to pick up a new menu entry), the **new** files will carry the v0.3.0 footer; the **existing** files retain their v0.2 footer because v0.3.0 still refuses to clobber existing scaffolded files. A mixed-version footer state across a repo is expected and benign — both are valid.

### Refresh is opt-in

You can ignore v0.3.0 indefinitely. Your v0.2 scaffold keeps working in Claude Code exactly as it did before. The new pieces (quality gate, cross-tool emission, doctrine, KB bootstrap) only activate when you explicitly invoke their scripts. There is no automatic migration on next `scaffold.sh` invocation; nothing in v0.3.0 lazily writes new files behind your back.

### Nothing is force-overwritten

- `install-closers.sh` skips closer files that already exist.
- `refresh-doctrine.sh` only writes `doctrine.yaml` if it's missing; otherwise re-validates in place.
- `emit-cross-tool.sh` writes `.proposed` siblings rather than clobbering hand-edited files.
- `bootstrap-kb.sh` writes prompts only; never touches the canonical KB file.
- `accept-drafts.sh` makes a `*.bak` backup before overwriting and asks for explicit `--tech` scope to avoid blanket replacement.
- `quality-gate.sh` is read-only by definition — `--strict` only affects exit code, never the working tree.

### Rollback

If the upgrade goes wrong, rollback is straightforward because v0.3.0 only adds files:

```bash
# Remove the cross-tool emission
rm -f <target>/AGENTS.md
rm -rf <target>/.cursor/rules/   # if Cursor wasn't otherwise in use
rm -f <target>/.github/copilot-instructions.md

# Remove the doctrine
rm -f <target>/.claude/doctrine.yaml

# Leave .claude/agents/ and .claude/kb/ alone — they predate v0.3.0
```

Your v0.2 scaffold is then restored bit-for-bit. No agent files, no KB files, no `_index.yaml` were touched by the upgrade, so there's nothing to undo there.

### Version pinning

`bundle.sh` produces `dist/agents-kbs-tech-stack-v0.3.0.tar.gz`. If you need to stay on v0.2 for any reason, pin to the v0.2 tarball — the v0.2 codebase still builds cleanly from the corresponding tag, and v0.3.0 ships from a separate, parallel tag.

---

## Common upgrade pitfalls

| Symptom | Cause | Fix |
|---------|-------|-----|
| `emit-cross-tool.sh` writes only `.proposed` files | All target files already existed and lacked fingerprints | Diff the `.proposed` files, merge by hand, then delete `.proposed` siblings |
| `quality-gate.sh --strict` fails on a v0.2 project that "should be clean" | Hand-edits drifted the project away from the contract since the v0.2 scaffold | Read the failing check; either fix the file or tune `doctrine.yaml` to match your project's reality |
| `refresh-doctrine.sh` reports a schema error | You hand-edited `doctrine.yaml` and broke the schema | Restore the bundled default by deleting the file and re-running |
| `bootstrap-kb.sh` writes 0 prompts | The KB no longer has `<!-- TODO -->` blocks — you've already populated it | Nothing to do; the bootstrap flow is unnecessary for this tech |
| `AGENTS.md` lists agents that no longer exist | Stale entries from an earlier scaffold remain in `_index.yaml` | Edit `_index.yaml` to remove the stale rows, then re-emit |
| Cursor doesn't pick up the new rules | Cursor caches rules — restart the editor | Restart Cursor; `agents.mdc` is an always-applied rule and should activate immediately |

---

## After the upgrade

You're done. The v0.2 → v0.3 migration is meant to be a 5-minute pass:

1. `install-closers.sh` — 5 seconds.
2. `refresh-doctrine.sh` — 5 seconds.
3. `emit-cross-tool.sh` — 10 seconds.
4. `quality-gate.sh --strict` — 5 seconds, plus however long it takes to fix any FAILs.
5. `bootstrap-kb.sh` (per tech, optional) — minutes per tech, but parallelizable.

From here on, treat v0.3.0 as your steady state:

- Tune `doctrine.yaml` when project conventions shift.
- Re-emit with `emit-cross-tool.sh` whenever the doctrine, the menu, or the agent files change.
- Wire `quality-gate.sh --strict` into CI to catch drift early.
- Use `bootstrap-kb.sh` whenever you scaffold a new tech and want a head start on KB content.

The next major skill version (v0.4.x) will preserve the v0.3.0 contract exactly — same scaffold layout, same doctrine schema, same emission targets — so this upgrade is the last "structural" pass you'll need to do for a while.

---

*agents-kbs-tech-stack v0.3.0 — upgrade runbook.*
