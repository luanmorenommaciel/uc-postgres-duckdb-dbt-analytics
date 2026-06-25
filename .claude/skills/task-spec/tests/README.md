# task-spec skill — Self-Test Suite

## Running the tests

```bash
bash .claude/skills/task-spec/tests/test-task-spec-skill.sh
```

The suite is fully self-contained and runs in a temporary directory. It does **not**
read or write the real `tasks/` backlog.

## What is covered

| Step | Script | Assertion |
|------|--------|-----------|
| 1 | `generate-task-spec.sh` | Creates a file with correct ID ↔ filename match |
| 2 | — | Fills the generated stub with a valid Task-Spec v2 |
| 3 | `validate-task-spec.sh` | Passes on a well-formed task |
| 4 | `validate-task-spec.sh` | Fails with a specific error when a placeholder is injected |
| 5 | `transition-status.sh` | `ready → in-progress` updates status and keeps file in `tasks/` |
| 6 | `transition-status.sh` | `in-progress → done` moves file to `tasks/done/` |
| 7 | `rebuild-state.sh` | Rebuilds `_state.yaml` and reflects the correct status |
| 8 | `list-ready.sh` | Excludes done tasks from the ready queue |
| 9 | `archive.sh` | Is a no-op when all done/parked tasks are already archived |
| 10 | `backup-backlog.sh` | Creates a `.tar.gz` archive in the requested directory |

## Isolation strategy

The scripts operate relative to the current working directory and do not accept a
`--root` override. The self-test therefore:

1. Creates a temp directory (`mktemp -d`).
2. `cd`s into it and runs `git init` so `validate-task-spec.sh` can resolve a
   repository root for path lookups.
3. Calls the skill scripts via absolute paths; their internal `SKILL_DIR` lookup
   still finds templates and sibling scripts correctly.
4. Uses `trap 'rm -rf "$TMPDIR"' EXIT` so cleanup happens even on early failure.

## macOS compatibility

`transition-status.sh` uses `flock(1)` (from `util-linux`), which is not present on
macOS. The self-test detects the missing binary and prepends a minimal shim to
`PATH`. The shim is safe because the test environment is single-threaded with no
concurrent access.
