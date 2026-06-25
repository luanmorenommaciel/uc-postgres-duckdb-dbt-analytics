# Bootstrap KB content for tech: <TECH>

## Context

Each markdown file under `.claude/kb/<TECH>/` contains `<!-- TODO -->` blocks. Replace these with concrete production-quality content grounded in `<TECH>`'s documentation and idiomatic patterns.

The files you will edit live at:

```
<TARGET_REPO>/.claude/kb/<TECH>/
├── quick-reference.md
├── concepts/*.md
├── patterns/*.md
└── reference/*.md
```

Each file is a stub. Section headings, frontmatter, and structural scaffolding are already in place. Your job is to populate the **content** — tables, code snippets, prose — that lives inside (or replaces) the `<!-- TODO -->` markers.

Work file-by-file. Read each stub once, infer the intent from the filename + headings, then write the body.

## Hard constraints

These are not suggestions. Violating them produces a worse KB than no KB.

1. **Never invent APIs that don't exist.** If you're not sure whether a function, flag, or syntax exists in `<TECH>` as of its current stable release — leave a comment marker (`<!-- VERIFY: <claim> -->`) instead of guessing. Hallucinated APIs are worse than missing content because they corrupt agents that ground in this KB.
2. **Cite source URLs at the bottom of each file when applicable.** Use a `## Sources` section at the end with bullet links to the official docs, RFCs, or canonical guides you drew from. Skip the section only if the content is purely conceptual and not tied to a specific document.
3. **Preserve all existing structural markdown headings.** The `##` and `###` headings already in the file are the contract — agents read by section. Do not rename, reorder, or delete them.
4. **Replace TODO blocks only — never alter section structure.** If a section feels wrong for the file, leave it stubbed rather than restructuring. Structure changes are a separate skill-level edit, not a content-population edit.

## Per-file size and content limits

| File class | Hard line limit | Required sections | Content shape |
|------------|-----------------|-------------------|---------------|
| `quick-reference.md` | ≤100 lines | (preserve existing) | Tables only. No prose paragraphs, no code blocks. |
| `concepts/*.md` | ≤150 lines | "Common Mistakes" + "Related" | Mostly prose with small code snippets; one table OK. |
| `patterns/*.md` | ≤200 lines | "When to Use" + "When NOT to Use" + at least one code example | Code-heavy. Each example must be runnable in isolation. |
| `reference/*.md` | Unlimited | (preserve existing) | Mostly tables. Exhaustive lookup material. |

If a stub already has placeholder sections matching the required ones, populate them. If a stub is missing a required section, append it at the end **without removing anything else**.

## Style

- Code blocks must declare a language fence (` ```python `, ` ```typescript `, etc.) matching the tech's primary language.
- Tables must have a header row and an alignment row. No malformed pipe tables.
- Use sentence case for table cells, title case for headings.
- Prefer concrete API names and CLI flags over hand-wavy descriptions ("`pyproject.toml`'s `[project.dependencies]` table" beats "the dependency config").
- When the official docs use a specific term ("transformer", "actor", "executor"), use that exact term — do not paraphrase.

## Output

- Write modified files in-place. Overwrite the existing stub with the populated version.
- At the end of your run, report the list of files modified (absolute paths), one per line.
- If a file was left unchanged (e.g., you couldn't responsibly populate it without inventing APIs), say so explicitly with a one-line reason.

## Failure mode

If you find yourself about to invent an API, a flag, or a version-specific behavior you can't verify — STOP. Leave the TODO in place with a `<!-- VERIFY: <what you'd need to check> -->` comment. The next pass (a human or a more grounded run) will fill it in. A KB with honest gaps is infinitely more useful than a KB with confident hallucinations.
