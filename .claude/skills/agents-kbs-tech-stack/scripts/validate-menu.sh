#!/usr/bin/env bash
# validate-menu.sh — Validate every entry in menu/techs.yaml has the fields
# scaffold.sh requires. Intended for pre-commit / CI use.
#
# Exit codes:
#   0  — all entries valid
#   2  — PyYAML unavailable
#   3  — menu file unreadable
#   6  — one or more entries missing required field(s)
#
# Output:
#   Per-entry "OK: <slug>" or "FAIL: <slug> missing: <fields>" lines, then
#   a final summary "Menu validation: <N> ok, <M> failed".

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
MENU="${SKILL_ROOT}/menu/techs.yaml"

if [[ ! -r "${MENU}" ]]; then
  echo "ERROR: cannot read ${MENU}" >&2
  exit 3
fi

python3 - "${MENU}" <<'PYEOF'
import sys

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

menu_path = sys.argv[1]
with open(menu_path) as f:
    menu = yaml.safe_load(f) or {}

REQUIRED_BASE = [
    "display_name",
    "description",
    "primary_language",
    "recommended_mcps",
    "default_threshold_architect",
    "default_threshold_developer",
    "agent_color_architect",
    "agent_color_developer",
    "memorable_maxim",
    "architect_mission",
    "developer_mission",
    "architect_capabilities",
    "developer_capabilities",
    "kb_seed.concepts",
    "kb_seed.patterns",
    "kb_seed.reference",
]

REQUIRED_TROUBLESHOOTER = [
    "default_threshold_troubleshooter",
    "agent_color_troubleshooter",
    "troubleshooter_mission",
    "troubleshooter_capabilities",
]


def missing_fields(entry, required):
    out = []
    for path in required:
        cur = entry
        ok = True
        for part in path.split("."):
            if not isinstance(cur, dict) or part not in cur:
                ok = False
                break
            cur = cur[part]
        if not ok:
            out.append(path)
    return out


ok_count = 0
fail_count = 0

for slug in sorted(menu):
    entry = menu[slug]
    if not isinstance(entry, dict):
        print(f"FAIL: {slug} not a mapping", file=sys.stderr)
        fail_count += 1
        continue
    roles = entry.get("roles", ["architect", "developer"])
    required = list(REQUIRED_BASE)
    if isinstance(roles, list) and "troubleshooter" in roles:
        required += REQUIRED_TROUBLESHOOTER
    missing = missing_fields(entry, required)
    if missing:
        print(f"FAIL: {slug} missing: {', '.join(missing)}", file=sys.stderr)
        fail_count += 1
    else:
        print(f"OK: {slug}")
        ok_count += 1

print(f"Menu validation: {ok_count} ok, {fail_count} failed")
sys.exit(6 if fail_count else 0)
PYEOF
