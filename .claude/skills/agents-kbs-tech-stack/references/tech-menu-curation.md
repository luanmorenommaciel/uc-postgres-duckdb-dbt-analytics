# Tech Menu Curation — Adding a Tech to `menu/techs.yaml`

> Reference for extending the curated menu. v1 of the skill ships with 10 techs;
> add more here.

## Why a curated menu (not freeform)

The menu is the only customization layer. A user picks a tech and gets architect + developer + KB tree — no per-tech interview. That speed only works if the menu entries are *high quality*: every entry must declare the right MCPs, the right thresholds, the right seed slugs, and capability bullets that map cleanly to "Use PROACTIVELY when..." routing language.

Adding a tech is therefore a deliberate act, not a freeform fallback.

## Schema (every field required unless marked optional)

```yaml
<slug>:
  display_name: "Human Name"
  description: "One-line scope (≤80 chars)"
  primary_language: python | typescript | sql | bash | go | rust | java
  recommended_mcps: ["mcp__id__*", ...]   # 1–4 MCP tool ids
  default_threshold_architect: 0.85 | 0.90 | 0.95 | 0.98
  default_threshold_developer: 0.85 | 0.90 | 0.95 | 0.98
  agent_color_architect: blue | green | purple | orange | red | yellow
  agent_color_developer: <same options>
  kb_seed:
    concepts:  [<slug>, ...]    # 2–4 entries
    patterns:  [<slug>, ...]    # 2–4 entries
    reference: [<slug>, ...]    # 1–3 entries
  architect_capabilities:        # 3–5 bullets
    - "..."
  developer_capabilities:        # 3–5 bullets
    - "..."
  memorable_maxim: "One-line maxim"
  architect_mission: "One-sentence mission"
  developer_mission: "One-sentence mission"

  # ─── OPTIONAL: per-tech role expansion ──────────────────────────────────
  # Default behavior (omit `roles:` entirely) = [architect, developer].
  # The valid role set is: architect, developer, troubleshooter.
  # Adding 'troubleshooter' opts in a third paired agent (read-only diagnostic
  # specialist). See references/architect-vs-developer.md → "The optional
  # troubleshooter role" for when to opt in vs skip.
  roles: [architect, developer, troubleshooter]   # OPTIONAL

  # The following fields are REQUIRED only when `roles` includes 'troubleshooter'.
  # Omit them otherwise — the scaffold ignores them.
  troubleshooter_mission: "One-sentence mission"            # REQUIRED if opted in
  troubleshooter_capabilities:                              # REQUIRED if opted in — 3–5 bullets
    - "Diagnosing <failure mode 1>"
    - "Tracing <symptom 2>"
  default_threshold_troubleshooter: 0.92 | 0.95 | 0.98      # OPTIONAL — defaults to 0.95
  agent_color_troubleshooter: red | orange | yellow | ...   # OPTIONAL — defaults to red
```

### When to opt a tech into the troubleshooter role

Add `roles: [architect, developer, troubleshooter]` when:

- The tech has non-obvious failure modes (Postgres slow queries, LangGraph stuck conversations, React re-render loops).
- Reusable diagnostic playbooks exist (same EXPLAIN queries, same trace patterns).
- Incidents in this tech have a cost (prod data, customer-visible perf, regulated systems).

Skip the troubleshooter for stateless / pure techs (Tailwind, sqlglot ASTs, plain TypeScript types) where "the developer fixing the bug" already subsumes diagnosis.

## Checklist for a quality menu entry

Before adding a tech, verify:

```text
[ ] Tech is stable (released ≥6 months, not in alpha/beta breaking-changes phase)
[ ] At least one MCP grounds it well (context7 covers most public libraries;
    exa for niche; ref for API reference docs)
[ ] Thresholds are calibrated:
    - Architect 0.90 is default; 0.95 for high-stakes (database, security, payments)
    - Developer 0.95 is default; 0.98 for critical-path (security, data integrity)
[ ] KB seeds are specific (not generic "patterns" — name the patterns)
[ ] Capabilities use action verbs ("Designing X", "Implementing Y") — not nouns
[ ] Memorable maxim is one line, opinionated, true
[ ] Missions are imperative voice ("Ship X", "Design Y")
```

## Worked example — adding `vue`

```yaml
vue:
  display_name: Vue
  description: "Vue 3 + Composition API + Pinia + Vite"
  primary_language: typescript
  recommended_mcps: ["mcp__context7__*", "mcp__ref__*"]
  default_threshold_architect: 0.90
  default_threshold_developer: 0.95
  agent_color_architect: green
  agent_color_developer: blue
  kb_seed:
    concepts: [reactivity-mental-model, composition-api, sfc-anatomy]
    patterns: [pinia-store, composables, async-components]
    reference: [directive-catalog, lifecycle-hooks]
  architect_capabilities:
    - "Designing component composition with the Composition API"
    - "Choosing between options API (legacy) and Composition API (new code)"
    - "Pinia store design and SSR considerations"
    - "Deciding between SFCs, render functions, and JSX"
  developer_capabilities:
    - "Writing typed Composition-API components with `<script setup>`"
    - "Building composables with correct reactivity (ref vs reactive)"
    - "Wiring Pinia stores with SSR-safe hydration"
    - "Testing components with Vitest + Vue Test Utils"
  memorable_maxim: "Reactivity is a graph. ref for primitives, reactive for objects, computed for derived."
  architect_mission: "Design Vue trees that compose cleanly and stay reactive without surprises."
  developer_mission: "Ship Vue components that hydrate correctly and test cleanly with act()-free semantics."
```

## Anti-patterns to avoid

| Anti-Pattern | Why |
|--------------|-----|
| Adding a tech still under heavy breaking changes (e.g., a v0.x library) | KB seeds rot weekly; threshold modifier always -0.15 |
| Recommending MCPs that don't exist | The agent will request a missing tool at runtime |
| Same agent_color for architect and developer | Reduces visual distinction in the agent picker |
| Generic seed slugs ("patterns", "concepts", "basics") | The point is to seed *named* topics |
| Capabilities written as "Understands X" instead of "Designing X" / "Implementing X" | Doesn't route well; needs imperative verbs |
| Memorable maxim that's 3 sentences | One line. Memorable means short. |

## Process for adding a tech

1. **Draft the entry** in `menu/techs.yaml` per the schema above.
2. **Validate the YAML** parses (`python3 -c "import yaml; yaml.safe_load(open('menu/techs.yaml'))"`).
3. **Verify recommended MCPs exist** — try invoking each with a smoke query in a Claude Code session.
4. **Dogfood** — scaffold the tech into `/tmp/test-newtech/`, confirm both agents and KB tree render with no leaked placeholders.
5. **Update SKILL.md's menu table** if it references the count of techs.
6. **Bump the skill version** in `scripts/bundle.sh` if publishing — adding a tech is a minor version bump (0.1.0 → 0.2.0).

## When to remove a tech

- The tech is deprecated by upstream (e.g., Vue 2, Angular.js).
- Better MCP coverage emerged for a sibling tech, making this entry redundant.
- The KB seeds have been wrong for two consecutive validations.

Removal is a major version bump (breaks anyone using that tech entry). Prefer deprecation notice in `description` for one version before removal.
