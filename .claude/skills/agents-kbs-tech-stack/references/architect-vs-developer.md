# Architect vs Developer — The Role Split

> Reference for why every tech gets *two* agents instead of one, and what each owns.

## TL;DR

For every tech, two agents share the same KB but play different roles:

- **Architect** — decides what to build and how. Outputs plans, ADRs, trade-off matrices, file manifests. **No `Bash` tool — does not execute.**
- **Developer** — builds what the architect decided. Outputs code, tests, fixes. **Has `Bash` — runs lint, tests, scripts.**

The split exists because Claude routes better when agents have one job. A single "react-expert" tries to do both and ends up doing both badly.

## Tool boundaries

```text
                       │ Architect │ Developer │
───────────────────────┼───────────┼───────────┤
Read                   │ ✓         │ ✓         │
Write (markdown)       │ ✓         │ ✓         │
Edit (markdown)        │ ✓         │ ✓         │
Edit (code)            │ —         │ ✓         │
Grep / Glob            │ ✓         │ ✓         │
Bash (run scripts)     │ —         │ ✓         │
TodoWrite              │ ✓         │ ✓         │
MCP tools              │ ✓         │ ✓         │
```

The architect can write *markdown* (plans, ADRs, manifests) but the lack of `Bash` is the discipline — it can't run tests, can't execute lint, can't push code. That's the developer's surface.

## Threshold defaults

```text
                                  │ Architect │ Developer │
──────────────────────────────────┼───────────┼───────────┤
Design / framework choice         │ 0.90      │ N/A       │
Code that gets merged             │ N/A       │ 0.95      │
Critical (security, data int)     │ 0.95      │ 0.98      │
Style / taste                     │ 0.75      │ 0.80      │
```

Architects escalate ambiguity in design (it's cheap to ask, expensive to undo). Developers escalate ambiguity in execution (it's cheap to ask, expensive to ship wrong).

## When invoked

### Architect routing examples

- "Should we use server actions or route handlers here?"
- "Plan the migration from Pages Router to App Router."
- "Compare the trade-offs of SSE vs WebSockets for this feed."
- "Lay out the file structure for the new feature."

The architect's `description:` frontmatter emphasizes phrases like *plan*, *decide*, *compare*, *lay out*, *trade-offs*.

### Developer routing examples

- "Implement the route handler the architect specified."
- "Fix this hook's dependency array — it's looping."
- "Refactor this component to use Suspense."
- "Add tests for the new endpoint."

The developer's `description:` frontmatter emphasizes phrases like *implement*, *write*, *fix*, *refactor*, *test*.

## The handoff

The healthy flow:

```text
User asks a design question
    ↓
Architect plans → writes file manifest → invokes (or names) Developer
    ↓
Developer implements per manifest → runs tests → reports back
    ↓
User invokes closers (code-reviewer, code-simplifier, code-documenter)
    ↓
Done.
```

Each handoff is a context save: the architect's plan is the developer's input; the developer's diff is the closers' input. Each agent gets less context than a single mega-agent would, which is *good* — agents perform best with focused inputs.

## When the split breaks down

There are cases where forcing two agents is overkill:

- **Trivial bug fix** — go straight to developer.
- **Pure design question, no code** — architect only.
- **Whole feature requires both, but the path is obvious from the start** — pre-write the manifest yourself; invoke developer with it.

The split is not a ceremony to follow blindly. It's a routing tool. Use it when routing benefits from it; skip the architect when the answer is "obviously implement X."

## What goes in each agent's body

### Architect's signature section: `## Decision Frameworks`

Trade-off matrices. "When to choose X over Y" tables. Red flags. No code.

Example for a React architect:

```markdown
### Framework: SSR vs RSC vs CSR

**Use RSC when:**
- Data lives on the server and never needs client hydration
- SEO matters and the content is static or per-request

**Use SSR when:**
- The page needs full hydration for interactivity
- You're on Pages Router and don't want to migrate

**Use CSR when:**
- The data is per-user and behind auth
- The page is a dashboard that updates frequently

**Red flags (don't pick any):**
- "I'm not sure how often this data changes"
- "Let's mix them per-component without a clear model"
```

### Developer's signature section: `## Implementation Patterns`

Production code. Anti-patterns. Tests.

Example for a React developer:

```markdown
### Pattern: Custom hook with cleanup

**When:** Subscribing to anything external (WebSocket, EventSource, setInterval)

```typescript
function useEventStream(url: string) {
  const [data, setData] = useState<Event[]>([])
  useEffect(() => {
    const es = new EventSource(url)
    es.onmessage = (e) => setData(prev => [...prev, JSON.parse(e.data)])
    return () => es.close()
  }, [url])
  return data
}
```

**Anti-pattern:**

```typescript
useEffect(() => {
  const es = new EventSource(url)
  es.onmessage = ...
  // No cleanup — leaks connections on re-render
}, [url])
```
```

## What's identical between them

Both agents share:

- The Agreement Matrix (KB × MCP scoring)
- The Confidence Modifiers table
- The Quick Reference 5-step decision flow
- The Anti-Patterns section format
- The Quality Checklist format
- The Remember / Mission closing

These are the kurv-edp invariants. The *role-specific* content (Decision Frameworks vs Implementation Patterns) is what differs.

## Why not architect + developer + reviewer + simplifier + documenter all per-tech?

Considered. Rejected because:

1. **N × 5 agents per project bloats routing.** A 4-tech project would have 20 agents. Claude struggles past ~15.
2. **Reviewer/simplifier/documenter are tech-agnostic at the interface.** Their work doesn't depend on the *tech*; it depends on the *change*. They ground via the hook protocol.
3. **One reviewer the user trusts > five reviewers they don't.** Concentrating polish in three universal agents builds confidence faster than per-tech variants.

The closer-hook protocol (`closer-hook-protocol.md`) is what lets one reviewer act tech-aware without being tech-coupled.

## The optional troubleshooter role

The default scaffold is architect + developer. Some techs benefit from a **third paired specialist: the troubleshooter** — a read-only diagnostician that owns failure-mode reasoning the way the architect owns design and the developer owns implementation.

### Tool boundaries (the troubleshooter slot)

```text
                       │ Architect │ Developer │ Troubleshooter │
───────────────────────┼───────────┼───────────┼────────────────┤
Read                   │ ✓         │ ✓         │ ✓              │
Write (markdown)       │ ✓         │ ✓         │ ✓ (reports)    │
Edit (markdown)        │ ✓         │ ✓         │ —              │
Edit (code)            │ —         │ ✓         │ —              │
Grep / Glob            │ ✓         │ ✓         │ ✓              │
Bash (run scripts)     │ —         │ ✓         │ ✓ (read-only)  │
TodoWrite              │ ✓         │ ✓         │ ✓              │
MCP tools              │ ✓         │ ✓         │ ✓              │
```

The troubleshooter has `Bash` (for `git log`, `EXPLAIN`, `ps`, log greps, repro scripts) but **no `Edit`/`Write` on code** — it diagnoses and reports; the developer patches. That tool boundary is the discipline.

### Threshold defaults (troubleshooter column)

```text
                                  │ Architect │ Developer │ Troubleshooter │
──────────────────────────────────┼───────────┼───────────┼────────────────┤
Design / framework choice         │ 0.90      │ N/A       │ N/A            │
Code that gets merged             │ N/A       │ 0.95      │ N/A            │
Diagnosis report                  │ N/A       │ N/A       │ 0.92           │
Critical (incident root cause)    │ 0.95      │ 0.98      │ 0.98           │
Style / taste                     │ 0.75      │ 0.80      │ 0.85           │
```

The troubleshooter's default (0.92) sits between developer (0.95) and architect (0.90): a diagnosis that's published is acted on, so it needs evidence — but the cost of being slightly wrong is "ask for more evidence", not "ship a regression".

### When to opt a tech into troubleshooter

Add `roles: [architect, developer, troubleshooter]` to a tech's menu entry **when**:

1. **The tech's failure modes are non-obvious from the symptom.**
   - Postgres: slow queries can be a missing index, a bloated table, a planner statistics miss, a lock contention, a connection-pool exhaustion. Symptom = same; cause = wildly different.
   - LangGraph: a stuck conversation can be a checkpointing bug, a non-JSON-safe state, an interrupt resume mismatch, or a missing edge.
   - React: a re-render loop can be hooks, refs, context invalidation, or concurrent rendering edge cases.

2. **Diagnostic playbooks are reusable across incidents.** If you find yourself running the same five queries every time the tech misbehaves, that's a troubleshooter playbook.

3. **Incidents have a cost.** Diagnosis matters most where wrong rollbacks are expensive (prod data, customer-visible perf, payments, anything regulated).

### When NOT to opt a tech in

Skip troubleshooter when:

- **The tech is mostly stateless / pure.** Tailwind doesn't have "incidents". Neither does sqlglot at the AST layer — failures are local and obvious.
- **The developer already covers diagnosis cheaply.** For small libraries with thin failure surfaces, the developer's "fix the bug" loop subsumes diagnosis.
- **The team is small.** Three agents per tech × N techs gets unwieldy past ~6 techs. Pick the 1–2 techs with the highest incident cost.

### How the three roles compose

```text
User reports a problem
    ↓
Troubleshooter diagnoses → writes recovery brief → hands off
    ↓
    ├─ Code change needed? → Developer applies the fix
    └─ Design change needed? → Architect re-plans, then Developer ships
    ↓
Closers polish.
```

The troubleshooter is the **diagnostic counterpart** to the architect's design role and the developer's implementation role. It's the "what happened?" lane, distinct from "what should we build?" (architect) and "go build it" (developer).

### Required menu fields when opting in

A tech entry that includes `troubleshooter` in `roles` MUST also declare:

- `troubleshooter_mission` — one-sentence imperative-voice mission.
- `troubleshooter_capabilities` — 3–5 action-verb bullets (e.g., "Diagnosing slow EXPLAIN plans").
- `default_threshold_troubleshooter` — optional, defaults to `0.95` in the scaffold (template renders `0.92` in the table as the STANDARD category default).
- `agent_color_troubleshooter` — optional, defaults to `red` (incidents = red).

See `references/tech-menu-curation.md` for the full schema.
