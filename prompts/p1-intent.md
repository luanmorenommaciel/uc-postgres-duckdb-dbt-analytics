# Converge · Pass 1 — Intent

**Engine:** Claude CoWork (a project) — conversational, no repo, no code.
**Input:** `docs/brd-analytical-backbone.pdf` — the client's business-requirements doc, *handed to us*. Attach it to the project.
**Output:** `docs/tech-spec-analytical-engine.pdf` — our deliverable: the engineering solution to the client's problem.
**Gate:** the spec answers the brief — every requirement verifiable and KPI-tied, scope explicit. **No premature technology.**

> Teaching note: the client owns the problem; we own the solution. The BRD is the INPUT — the *what* and the *why*. Pass 1 comprehends it and PRODUCES the tech-spec — the *how*, at a level the client can sign off on. We don't invent a stack yet; we make the problem unambiguous and verifiable first.

Three steps, run in order: **understand → interrogate → crystallize.**

---

## Step 1 · Understand

```text
Read this BRD like the consultant who has to deliver it, not a summarizer. The
client wrote it — it's their problem in their words. What's the real pain, who
feels it, and what does it cost them? Cover the whole board — financial,
operational, strategic — in their own numbers. Then tell me, in one paragraph,
what "solved" looks like from the client's seat.
```

## Step 2 · Interrogate

```text
Now grill me — I'm the consultant who took this engagement, so I have to be able
to answer for it. Ask the 2-3 questions that would most change what we build:
across scope, what "done" means, and any number or claim in the brief that looks
soft or unverifiable. For each: give your own best default answer so we keep
moving, and name which client stakeholder should own the real answer if it's
above my pay grade.
```

## Step 3 · Crystallize

```text
Turn this into a technical specification — our deliverable back to the client.
Structure it: the problem restated in plain language, in/out of scope,
requirements each made VERIFIABLE and tied to one of the client's KPIs, success
metrics as current → target, and open assumptions. This is the SOLUTION shape —
but stay above the stack: describe WHAT the engine must do and HOW WELL, not
which database or framework builds it. Premature tech choices belong to the
plans (Pass 3), not here.

Make it visual and digestible: diagrams of the problem and its impact — how the
pain flows through the business, current state vs. desired state, who's affected.
Use visuals to clarify the problem and the required outcome, NOT to commit an
architecture.

Output a clean, professionally formatted PDF named tech-spec-analytical-engine.pdf
— a document the client could sign off on. Cover page, clear sections, diagrams
where they aid understanding, tight.
```

---

## Gate — confirm before leaving Pass 1

- [ ] The spec answers the brief — every client pain maps to a requirement.
- [ ] Scope (in / out) explicit at the problem level — what the engine must do and how well, not which stack does it. (The stack belongs to Pass 3's plans.)
- [ ] Every requirement is **verifiable** — a future eval could pass or fail it.
- [ ] Success metrics trace to the BRD's KPIs (current → target).
- [ ] Open assumptions recorded.
- [ ] **No premature technology** — the stack belongs to Pass 3's plans.

When the spec answers the brief, it feeds **Pass 2 — Structure**, where we check it against the real repo.

---

### Notes

- **Brief in, spec out.** The BRD is the client's; the tech-spec is ours. Don't blur them — Pass 1's whole job is the translation from *their problem* to *our verifiable solution shape*.
- **The flip in Step 2 is the moment** — narrate it: "watch, I'm having it grill *me* about the engagement." Real seams to expect against this brief: what "fresh enough" actually means for analytics, whether the API is a hard deliverable or a phase-2 nice-to-have, and any GMV/revenue figure stated without a baseline.
- **PDF on purpose.** The spec is a consensus object the client reads and approves — keep it PDF while it's being aligned on. It becomes the markdown input the build reads only once it's locked.
- **Going unattended later?** These prompts are short because *you're watching*. To hand a step to an unwatched agent, spell out the output structure — the conversation can't fix drift when no one's in it. The gate constraints (verifiable, KPI-tied, no premature tech) never drop, regardless of length.
