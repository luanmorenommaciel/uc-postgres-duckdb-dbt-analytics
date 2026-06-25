#!/usr/bin/env bash
# accept-drafts.sh — Promote .draft.md files to .md (overwriting stubs).
#
# Companion to bootstrap-kb.sh. After /codex:rescue has populated the
# .draft.md files, run this to commit the drafts as the canonical KB content.
#
# Inputs:
#   TARGET_REPO  absolute path to the target repo
#
# Args:
#   $1  tech slug (e.g. 'python') OR '--all' to walk every domain in
#       .claude/kb/_index.yaml except 'code-quality'.
#
# Exit codes:
#   0  drafts accepted
#   1  arg / env error
#   2  target KB dir missing
#   3  no .draft.md files found (nothing to accept — hint the user toward bootstrap-kb.sh)

set -euo pipefail

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
  echo "ERROR: ${KB_ROOT} does not exist" >&2
  exit 2
fi

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

# ─── Walk each tech and find draft files ────────────────────────────────────
DRAFT_FILES=()
for tech in "${TECHS[@]}"; do
  tech_dir="${KB_ROOT}/${tech}"
  if [[ ! -d "${tech_dir}" ]]; then
    echo "WARN: ${tech_dir} does not exist — skipping" >&2
    continue
  fi
  while IFS= read -r draft; do
    DRAFT_FILES+=("${draft}")
  done < <(find "${tech_dir}" -type f -name "*.draft.md")
done

if [[ ${#DRAFT_FILES[@]} -eq 0 ]]; then
  cat >&2 <<HINT
ERROR: no .draft.md files found under the selected tech(s).

Did you run bootstrap-kb.sh first? The flow is:

  1. TARGET_REPO=/abs/path scripts/bootstrap-kb.sh <tech>   # stages drafts
  2. /codex:rescue                                           # populates drafts
  3. TARGET_REPO=/abs/path scripts/accept-drafts.sh <tech>   # this script
HINT
  exit 3
fi

# ─── Promote each draft ─────────────────────────────────────────────────────
ACCEPTED=0
for draft in "${DRAFT_FILES[@]}"; do
  target="${draft%.draft.md}.md"
  mv "${draft}" "${target}"
  echo "✓ accepted: ${target}"
  ACCEPTED=$((ACCEPTED + 1))
done

echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "Accepted ${ACCEPTED} draft file(s) across ${#TECHS[@]} tech(s)."
echo "Tech(s): ${TECHS[*]}"
echo "────────────────────────────────────────────────────────────────────────"
