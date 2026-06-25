# agents-kbs-tech-stack — Build Tech-Stack Agent Layers

> A meta-skill that scaffolds a project's **tech-coverage** agent layer from a
> curated menu. Pick your stack; for each tech you get a paired
> *(architect + developer)* agent and a full KB tree — plus three universal
> closers (reviewer, simplifier, documenter) that ground in every tech KB. v0.3.0
> adds a quality gate and cross-tool emission so Claude, Codex, Cursor, and
> Copilot all read the same agent contract.

---

## The 60-second pitch

Planning and implementation are different jobs. An agent that decides *server vs
client components* should reason about trade-offs and ADRs; an agent that *writes
the hook* should ship code with correct dependency arrays. Blending them produces
mush — architects that hand-wave code, developers that re-litigate decisions.

**`agents-kbs-tech-stack` splits the roles and covers the loop.** For each tech
you pick from a curated menu, it scaffolds an **architect** (plans, trade-offs,
no Bash) and a **developer** (code, tests, has Bash), each backed by a real KB.
Once per repo it installs three **closers** — `code-reviewer`,
`code-simplifier`, `code-documenter` — that are tech-agnostic by interface but
tech-aware at runtime: each reads `kb/_index.yaml`, detects the file's language,
and loads the matching tech KB.

> **"Architect plans. Developer ships. Closers polish. Stack covered."**

---

## What it produces

For each tech picked from the menu:

```text
<target-repo>/.claude/
├── agents/
│   ├── <tech>-architect.md         # Planning, trade-offs, ADRs — no Bash
│   └── <tech>-developer.md         # Code, tests, fixes — has Bash
└── kb/
    ├── _index.yaml                 # Tech registered as a domain block
    └── <tech>/                     # quick-reference + concepts×3 + patterns×3 + reference×2
```

Plus, exactly once per repo:

```text
<target-repo>/.claude/agents/
├── code-reviewer.md                # Universal pre-merge reviewer
├── code-simplifier.md              # Universal refactor-for-clarity agent
└── code-documenter.md              # Universal docstring/README/ADR writer
```

**What it does NOT do:** rules, slash commands, workflow pipelines, LESSONS
files, MCP server code, CLAUDE.md authoring, global agent installs, or writes
outside `<target-repo>/.claude/` *except* the four documented cross-tool files
(see below).

---

## The menu *is* the customization

There's no per-tech interview. Each entry in
[`menu/techs.yaml`](menu/techs.yaml) already declares thresholds, MCPs, KB seeds,
capabilities, and missions — so picking a tech picks a fully specified pair. The
curated menu currently covers:

```text
react        nextjs      fastapi     python      typescript
langgraph    postgres    sqlglot     react-flow  tailwind
aws-lambda   databricks-lakeflow     apache-spark
dbt          pyarrow     n8n         airflow     supabase
```

Want a tech that isn't listed? Add it to the menu first
(see [references/tech-menu-curation.md](references/tech-menu-curation.md)) — every
entry must declare ≥1 MCP — then run the skill.

---

## The workflow

```text
REPO-SHAPE CHECK  →  MENU PICK  →  PREVIEW  →  SCAFFOLD  →  QUALITY GATE  →  CROSS-TOOL EMIT  →  REPORT
     (0)              (1)          (2)         (3)            (3.5)             (4)               (5)
```

|Phase|What happens|
|---|---|
|**0 — Repo-shape check**|`detect-code-light.sh` runs in ~1s. Silent on the 95% (`CODE_HEAVY`); on a code-light repo it offers to redirect you to a sibling skill before scaffolding|
|**1 — Menu pick**|Project name + description + target path, then a multi-select of the curated techs|
|**2 — Preview & confirm**|Print the file tree (2N tech agents, N KB trees, closers if absent), then a single scaffold / revise / abort gate|
|**3 — Scaffold**|`scaffold.sh` per tech (renders architect + developer + KB, additive `_index.yaml`), then `install-closers.sh` once|
|**3.5 — Quality gate**|`quality-gate.sh` lints for role-boundary violations and placeholder leaks; advisory by default (`--strict` fails CI on BLOCKERs)|
|**4 — Cross-tool emit**|`emit-cross-tool.sh` translates `.claude/` into `AGENTS.md`, Cursor rules, and Copilot instructions — idempotent, writes `.proposed` instead of clobbering hand-edits|
|**5 — Report**|Summary table per tech + closer checklist + next steps|

---

## The architect/developer split

|Agent|Owns|Has Bash?|
|---|---|---|
|`<tech>-architect`|Decision frameworks, trade-off matrices, ADRs, boundaries|No|
|`<tech>-developer`|Production code, tests, fixes, debugging|Yes|

Putting code blocks in an architect or high-level decisions in a developer is an
explicit anti-pattern — the quality gate flags role-boundary violations. See
[references/architect-vs-developer.md](references/architect-vs-developer.md).

---

## The closer-hook protocol

The three closers are installed once and never re-substituted — they discover
techs at runtime. When a closer runs on a file it reads `kb/_index.yaml`, maps
the file extension to a tech, and loads that tech's KB before reviewing,
simplifying, or documenting. So the more KBs you populate, the sharper the
closers get — for free. See
[references/closer-hook-protocol.md](references/closer-hook-protocol.md).

---

## Cross-tool emission (v0.3.0)

One source of truth (`.claude/`) drives every agentic tool your team uses. The
emitter is the **only** code path that writes outside `.claude/`, it's
idempotent, and it never overwrites a hand-edited file:

|Path|Consumer|Why|
|---|---|---|
|`<repo>/AGENTS.md`|Codex, OpenAI Agents SDK, taskship, anthive|Repo-root agent contract|
|`<repo>/.cursor/rules/agents.mdc`|Cursor|Always-applied doctrine rules|
|`<repo>/.cursor/rules/<tech>.mdc`|Cursor|Per-tech rules, scoped via Cursor globs|
|`<repo>/.github/copilot-instructions.md`|GitHub Copilot|Repo-level instruction file|

Portable defaults (Bash boundary, threshold floors, closer-hook protocol) live in
a tunable `doctrine.yaml`. Edit it and re-run `emit-cross-tool.sh` to retune the
cross-tool surface without re-scaffolding.

---

## Self-containment guarantee

Everything lands under `<target-repo>/.claude/` **except** the four cross-tool
files above. No CLAUDE.md changes, no source touched, no git ops, no network
calls. Drop the bundle in offline, run offline.

---

## When to reach for a sibling instead

|You want…|Use|
|---|---|
|Portable tech specialists (architect + developer) per stack|**`agents-kbs-tech-stack`** (this skill)|
|Project-specific specialists coupled to *this* repo's domain|`agents-kbs-fleet`|
|One reusable Skill + Agent + MCP capability (a Triad)|`caw-scaffold`|

Most real projects end up with all three layers. Use them together.

---

## Installation

```bash
cp -r skills/agents-kbs-tech-stack ~/.claude/skills/
```

Restart Claude Code, then invoke with `/agents-kbs-tech-stack` or describe it:

> "Scaffold the agent layer for this stack — React, FastAPI, and Postgres."

---

## What's in the folder

```text
agents-kbs-tech-stack/
├── SKILL.md                       # The phased workflow + emission contract
├── README.md                      # You are here
├── menu/
│   └── techs.yaml                 # The curated tech menu (the customization layer)
├── scripts/
│   ├── detect-code-light.sh       # Phase 0 repo-shape check
│   ├── scaffold.sh                # Renders architect + developer + KB per tech
│   ├── install-closers.sh         # Installs the 3 universal closers once
│   ├── quality-gate.sh            # Role-boundary + placeholder lint
│   ├── emit-cross-tool.sh         # AGENTS.md + Cursor + Copilot emission
│   ├── refresh-doctrine.sh        # (Re)generate doctrine.yaml
│   ├── validate-menu.sh           # Menu schema check
│   ├── bootstrap-kb.sh            # KB tree seeding
│   ├── accept-drafts.sh           # Promote .proposed files
│   └── bundle.sh                  # Pack the skill for sharing
├── templates/                     # architect.md.tpl, developer.md.tpl, closers, KB
├── prompts/                       # Quality-gate + emission prompts
├── references/
│   ├── architect-vs-developer.md  # Why the role split
│   ├── closer-hook-protocol.md    # Runtime grounding for closers
│   ├── quality-gate-protocol.md   # Check inventory + severity model
│   └── tech-menu-curation.md      # How to add a tech to the menu
└── runbooks/
    ├── pick-your-stack.md         # End-to-end walkthrough
    └── upgrade-v02-to-v03.md      # Migrating an existing scaffold
```

---

> **Mission:** Bootstrap a project's tech-coverage agent layer in 5 minutes, with
> the closed engineering loop wired in by default — and cross-tool emission plus a
> quality gate that keep Claude, Codex, Cursor, and Copilot reading the same agent
> contract.
>
> *agents-kbs-tech-stack v0.3.0.*
