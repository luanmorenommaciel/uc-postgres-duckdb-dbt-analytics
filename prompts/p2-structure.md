# Converge · Pass 2 — Structure

**Engine:** Claude Code — open the repo. We check the spec against what actually exists.
**Inputs:** `docs/tech-spec-analytical-engine.pdf` (the spec from Pass 1) · the repo (`src/`, the `Makefile`, `src/README.md`).
**Output:** none — Pass 2 produces **shared understanding, held in the session**, not a file.
**Gate:** you can explain the whole system end to end, and it is consistent with the spec and the real brownfield.

Three steps: **comprehend → ground & interrogate → confirm.** Run them in **one Claude Code session** and keep it open into Pass 3 — the understanding is the handoff.

> Teaching note: Pass 2 is comprehension, not creation. The tech-spec already exists (Pass 1). The repo is a *verified brownfield* — Postgres source, a seeder, a 14-mode defect generator, and a Postgres → DuckDB `raw.*` landing that all run today. Our job is to understand the spec deeply, grounded against that working base, so decomposition stands on solid ground.

---

## Step 1 · Comprehend

```text
Read the tech-spec PDF, then look at the repo (src/, the Makefile, src/README.md).
Explain the system back to me end to end: what exists today and what the spec
asks us to BUILD on top. Trace it source to consumer — Postgres public.* →
src/transition lands it into DuckDB raw.* → (to build) a dbt medallion over raw.*
→ (to build) a FastAPI/MCP layer over the gold tables. Plain language, no
restating the doc verbatim.
```

## Step 2 · Ground & interrogate

```text
Now pressure-test it. Prove the brownfield actually works, then check the spec
against it:

  make up && make seed && make land

That should load Postgres (customers=500, products=200, orders=5000,
payments=5000) and land DuckDB raw.* with exact row parity. Confirm raw.* is the
ONLY schema in the warehouse — there is no transform or serving layer yet; that's
what we build.

Then interrogate the spec against this reality. Where is it vague or hard to
build as written? Does what it asks for fit what's in src/ (the raw.* contract,
the three stamp columns, the _control fence that never lands)? Give me the 3-4
things that would bite us if we decomposed it as-is.
```

## Step 3 · Confirm

```text
Good. Restate the system as a clean component-and-dependency map: what's GIVEN
(Postgres source, seeder, generator, the raw.* landing) versus what's to BUILD
(dbt bronze→silver→gold over raw.*, then FastAPI/MCP over gold). Name the seam
between transformation and serving, and the build order. This is the picture we
break into plans next. Keep it tight; flag anything still unresolved.
```

---

## Gate — confirm before leaving Pass 2

- [ ] You can explain the full system in plain language — what's given vs. what's built.
- [ ] The brownfield runs: `make up && make seed && make land` reconciles with row parity.
- [ ] You confirmed the warehouse holds `raw.*` only — no transform/serving exists yet.
- [ ] The spec is consistent with the real `src/` (the `raw.*` contract, stamp columns, the `_control` fence).
- [ ] You have a clear given-vs-build component map and a sane build order.
- [ ] Open/unresolved items are flagged, not glossed.

When these hold, **stay in the session** and descend to **Pass 3 — Decomposition**, where this understanding becomes the plans under `sketch/`.

---

### Notes

- **No artifact, so don't lose the session.** Pass 2's output is the loaded understanding in Claude Code's context. Run Pass 3 in the *same* session — close it and the understanding is gone. Pass 2 → Pass 3 is one continuous session by design.
- **Why Code, not Chat:** understanding the spec means checking it against the real `src/` *and running it*. The repo is evidence the spec must honor — "the spec says serve gold tables; confirm DuckDB has only `raw.*` today, so the medallion is genuinely net-new."
- **The senior move is Step 2** — running `make land` and reading the actual `raw.*` rather than trusting the doc. The likely catch: the spec may imply fresher-than-batch data, but a full-refresh landing is minutes-fresh at best. Name gaps now; they're cheapest to fix before decomposition.
- **Unattended later?** These are short because you're driving. To hand a step to an unwatched agent, make it precise — and have it emit the component map as a file so the next step has an input.
