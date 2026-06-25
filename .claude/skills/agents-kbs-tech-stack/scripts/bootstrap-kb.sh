#!/usr/bin/env bash
# bootstrap-kb.sh — Stage KB stub files for /codex:rescue to populate.
#
# The skill cannot drive an interactive Claude Code subagent from a shell script.
# So this script does the deterministic half of the bootstrap:
#   1) Copies every kb/<tech>/**/*.md to <file>.draft.md (originals untouched).
#   2) Prints the exact /codex:rescue prompt the user must invoke from Claude
#      Code, with <TECH> and <TARGET_REPO> already substituted.
#
# The user runs codex:rescue manually (interactive), which edits the .draft.md
# files in place. Then `accept-drafts.sh` promotes the drafts to the canonical
# stub files. This three-step shape (stage → draft → accept) is intentional:
# it makes the codex pass auditable, reversible, and decoupled from the skill.
#
# Inputs:
#   TARGET_REPO  absolute path to the repo with .claude/kb/ scaffolded
#
# Args:
#   $1  tech slug (e.g. 'python', 'react') OR '--all' to loop over every
#       domain in .claude/kb/_index.yaml except 'code-quality'.
#
# Exit codes:
#   0  drafts staged, prompt printed
#   1  arg parse / env validation failure
#   2  target tech KB dir not found
#   3  no KB stubs to draft

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
PROMPT_FILE="${SKILL_ROOT}/prompts/codex-bootstrap-kb.md"

if [[ -z "${TARGET_REPO:-}" ]]; then
  echo "ERROR: TARGET_REPO must be set (absolute path to the target repo)" >&2
  exit 1
fi

if [[ $# -lt 1 ]]; then
  echo "Usage: TARGET_REPO=/abs/path $0 <tech-slug | --all>" >&2
  exit 1
fi

TECH_ARG="$1"
KB_ROOT="${TARGET_REPO}/.claude/kb"
INDEX_PATH="${KB_ROOT}/_index.yaml"

if [[ ! -d "${KB_ROOT}" ]]; then
  echo "ERROR: ${KB_ROOT} does not exist — scaffold a tech first." >&2
  exit 2
fi

# ─── Resolve tech list ──────────────────────────────────────────────────────
resolve_techs() {
  if [[ "${TECH_ARG}" != "--all" ]]; then
    printf '%s\n' "${TECH_ARG}"
    return
  fi
  if [[ ! -e "${INDEX_PATH}" ]]; then
    echo "ERROR: --all requires ${INDEX_PATH} to exist" >&2
    exit 2
  fi
  python3 - "${INDEX_PATH}" <<'PYEOF'
import sys
from pathlib import Path
try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required for --all mode (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)
data = yaml.safe_load(Path(sys.argv[1]).read_text()) or {}
for slug in (data.get("domains") or {}).keys():
    if slug == "code-quality":
        continue
    print(slug)
PYEOF
}

TECHS=()
while IFS= read -r line; do
  [[ -n "${line}" ]] && TECHS+=("${line}")
done < <(resolve_techs)

if [[ ${#TECHS[@]} -eq 0 ]]; then
  echo "ERROR: no techs resolved from arg '${TECH_ARG}'" >&2
  exit 2
fi

# ─── Stage drafts for each tech ─────────────────────────────────────────────
STAGED_FILES=()
for tech in "${TECHS[@]}"; do
  tech_dir="${KB_ROOT}/${tech}"
  if [[ ! -d "${tech_dir}" ]]; then
    echo "ERROR: ${tech_dir} does not exist — has tech '${tech}' been scaffolded?" >&2
    exit 2
  fi

  echo "─── Staging drafts for: ${tech} ───"
  # Find every .md under the tech dir, skipping any pre-existing .draft.md files
  # (a re-run shouldn't double-stage).
  while IFS= read -r md_file; do
    case "${md_file}" in
      *.draft.md) continue ;;
    esac
    draft="${md_file%.md}.draft.md"
    cp "${md_file}" "${draft}"
    STAGED_FILES+=("${draft}")
    echo "  staged: ${draft}"
  done < <(find "${tech_dir}" -type f -name "*.md")
done

if [[ ${#STAGED_FILES[@]} -eq 0 ]]; then
  echo "ERROR: no .md stubs found under any selected tech — nothing to draft." >&2
  exit 3
fi

# ─── Print the codex invocation hint ────────────────────────────────────────
cat <<'BANNER'

════════════════════════════════════════════════════════════════════════════════
  Codex will draft content into the following files:
════════════════════════════════════════════════════════════════════════════════
BANNER

for f in "${STAGED_FILES[@]}"; do
  echo "  ${f}"
done

cat <<BANNER

────────────────────────────────────────────────────────────────────────────────
  NEXT STEP — run this in Claude Code (the script can't drive codex itself):

  /codex:rescue
BANNER

# Print one invocation per tech so the user has a copy/pasteable block.
for tech in "${TECHS[@]}"; do
  cat <<HINT

  ── Prompt for tech: ${tech} ──────────────────────────────────────────────────
  (paste this after invoking /codex:rescue)

  Bootstrap KB content for tech: ${tech}

  Target files (edit IN PLACE, do NOT touch the non-.draft.md stubs):
$(find "${KB_ROOT}/${tech}" -type f -name "*.draft.md" | sed 's/^/    /')

  Follow the constraints in:
    ${PROMPT_FILE}

  Key rules (repeated here so they don't get lost):
    - Never invent APIs that don't exist.
    - Cite source URLs at the bottom of each file under a '## Sources' section.
    - Preserve all existing markdown headings — replace TODO blocks only.
    - quick-reference: ≤100 lines, tables only.
    - concepts: ≤150 lines, include 'Common Mistakes' + 'Related'.
    - patterns: ≤200 lines, include code example + 'When to Use' / 'When NOT to Use'.
    - reference: unlimited but mostly tables.

  When done, report the list of files modified.
HINT
done

cat <<'BANNER'

────────────────────────────────────────────────────────────────────────────────
  After codex finishes, review the .draft.md files. When satisfied:

    TARGET_REPO=<path> scripts/accept-drafts.sh <tech | --all>

  That step renames .draft.md → .md (overwriting the stubs).
════════════════════════════════════════════════════════════════════════════════
BANNER
