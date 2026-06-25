#!/usr/bin/env bash
# scaffold.sh — Scaffold a tech specialist (architect + developer [+ troubleshooter] + KB tree) from the curated menu.
#
# Inputs (env vars):
#   TARGET_REPO            absolute path to the repo getting scaffolded
#   PROJECT_NAME           short project name (KB index `project:`)
#   PROJECT_DESCRIPTION    one-sentence project description
#   TECH                   tech slug — must exist in menu/techs.yaml
#
# Behavior:
#   - Loads the tech's full config from menu/techs.yaml
#   - Renders templates/architect.md.tpl → <target>/.claude/agents/<tech>-architect.md
#   - Renders templates/developer.md.tpl → <target>/.claude/agents/<tech>-developer.md
#   - If menu entry declares `roles:` including 'troubleshooter', additionally renders
#     templates/troubleshooter.md.tpl → <target>/.claude/agents/<tech>-troubleshooter.md
#   - Seeds the KB tree at <target>/.claude/kb/<tech>/ using the menu's seed slugs
#   - Updates <target>/.claude/kb/_index.yaml with the new tech domain
#   - Idempotent: refuses to overwrite existing agent files (per-role check)
#   - Touches nothing outside <target>/.claude/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
TEMPLATES="${SKILL_ROOT}/templates"
KB_TEMPLATES="${SKILL_ROOT}/templates/kb-shared"   # symlink to v1's templates/kb
MENU="${SKILL_ROOT}/menu/techs.yaml"

require() {
  local var="$1"
  if [[ -z "${!var:-}" ]]; then
    echo "ERROR: required env var ${var} is unset" >&2
    exit 1
  fi
}

for v in TARGET_REPO PROJECT_NAME PROJECT_DESCRIPTION TECH; do
  require "$v"
done

# ─── Load tech config from menu/techs.yaml via Python ───────────────────────
# Output: a series of `export KEY=VAL` lines sourced into this shell.
eval "$(python3 - "${MENU}" "${TECH}" <<'PYEOF'
import sys, json, os
try:
    import yaml
except ImportError:
    print("echo 'ERROR: PyYAML required for menu parsing (pip install pyyaml)' >&2", file=sys.stdout)
    print("exit 4", file=sys.stdout)
    sys.exit(0)

menu_path, tech = sys.argv[1], sys.argv[2]
with open(menu_path) as f:
    menu = yaml.safe_load(f)

if tech not in menu:
    print(f"echo 'ERROR: tech \"{tech}\" not in menu — valid: {sorted(menu)}' >&2", file=sys.stdout)
    print("exit 5", file=sys.stdout)
    sys.exit(0)

entry = menu[tech]

def sh_escape(v):
    s = str(v).replace("'", "'\"'\"'")
    return f"'{s}'"

# ─── Pre-flight validation ──────────────────────────────────────────────────
# Fail loudly BEFORE any partial rendering. Reports every missing field at
# once so an SME fixing a new menu entry sees the full diff in one pass.
def _missing_fields(entry, required):
    missing = []
    for path in required:
        cur = entry
        ok = True
        for part in path.split("."):
            if not isinstance(cur, dict) or part not in cur:
                ok = False
                break
            cur = cur[part]
        if not ok:
            missing.append(path)
    return missing

_required_base = [
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

_declared_roles = entry.get("roles", ["architect", "developer"])
_required = list(_required_base)
if isinstance(_declared_roles, list) and "troubleshooter" in _declared_roles:
    _required += [
        "default_threshold_troubleshooter",
        "agent_color_troubleshooter",
        "troubleshooter_mission",
        "troubleshooter_capabilities",
    ]

_missing = _missing_fields(entry, _required)
if _missing:
    print(
        f"echo \"ERROR: tech '{tech}' missing required field(s): {', '.join(_missing)}\" >&2",
        file=sys.stdout,
    )
    print("exit 6", file=sys.stdout)
    sys.exit(0)

# Scalar fields — always required
exports = {
    "DISPLAY_NAME": entry["display_name"],
    "DOMAIN_SCOPE": entry["description"],
    "LANGUAGE": entry["primary_language"],
    "THRESHOLD_ARCHITECT": entry["default_threshold_architect"],
    "THRESHOLD_DEVELOPER": entry["default_threshold_developer"],
    "AGENT_COLOR_ARCHITECT": entry["agent_color_architect"],
    "AGENT_COLOR_DEVELOPER": entry["agent_color_developer"],
    "MEMORABLE_MAXIM": entry["memorable_maxim"],
    "ARCHITECT_MISSION": entry["architect_mission"],
    "DEVELOPER_MISSION": entry["developer_mission"],
}

# MCPs → "mcp__id__*, mcp__other__*"
exports["SELECTED_MCPS_YAML"] = ", ".join(entry["recommended_mcps"])

# KB seed slugs → comma-separated
exports["KB_CONCEPTS"] = ",".join(entry["kb_seed"]["concepts"])
exports["KB_PATTERNS"] = ",".join(entry["kb_seed"]["patterns"])
exports["KB_REFERENCES"] = ",".join(entry["kb_seed"]["reference"])

# Capabilities → markdown bullets
def caps_block(caps):
    return "\n".join(f"- {c}" for c in caps)
exports["ARCHITECT_CAPABILITIES_BLOCK"] = caps_block(entry["architect_capabilities"])
exports["DEVELOPER_CAPABILITIES_BLOCK"] = caps_block(entry["developer_capabilities"])

# ─── Role selection (optional, default = [architect, developer]) ───────────
# The `roles:` field on a tech entry is the entire backwards-compat lever.
# When absent, only architect + developer are scaffolded — identical to v1.
roles = entry.get("roles", ["architect", "developer"])
if not isinstance(roles, list) or not roles:
    print("echo 'ERROR: roles must be a non-empty list' >&2", file=sys.stdout)
    print("exit 6", file=sys.stdout)
    sys.exit(0)

valid_roles = {"architect", "developer", "troubleshooter"}
for r in roles:
    if r not in valid_roles:
        print(f"echo 'ERROR: unknown role \"{r}\" in tech \"{tech}\" — valid: {sorted(valid_roles)}' >&2", file=sys.stdout)
        print("exit 7", file=sys.stdout)
        sys.exit(0)

# If troubleshooter is opted in, validate required fields and export them.
if "troubleshooter" in roles:
    missing = [f for f in ("troubleshooter_mission", "troubleshooter_capabilities") if f not in entry]
    if missing:
        print(f"echo 'ERROR: tech \"{tech}\" declares troubleshooter role but is missing: {missing}' >&2", file=sys.stdout)
        print("exit 8", file=sys.stdout)
        sys.exit(0)
    exports["THRESHOLD_TROUBLESHOOTER"] = entry.get("default_threshold_troubleshooter", "0.95")
    exports["AGENT_COLOR_TROUBLESHOOTER"] = entry.get("agent_color_troubleshooter", "red")
    exports["TROUBLESHOOTER_MISSION"] = entry["troubleshooter_mission"]
    exports["TROUBLESHOOTER_CAPABILITIES_BLOCK"] = caps_block(entry["troubleshooter_capabilities"])

# Expose the role list to bash (space-separated for easy iteration).
exports["SCAFFOLD_ROLES"] = " ".join(roles)

for k, v in exports.items():
    print(f"export {k}={sh_escape(v)}")
PYEOF
)"

# ─── Derived ────────────────────────────────────────────────────────────────
export SLUG="${TECH}"
export SLUG_UPPER="$(echo "${TECH}" | tr '[:lower:]-' '[:upper:]_')"
export LAST_UPDATED="${LAST_UPDATED:-$(date -u +%Y-%m-%d)}"
export MCP_VALIDATION_DATE="${LAST_UPDATED}"
export AUTHORITATIVE_SOURCE="${AUTHORITATIVE_SOURCE:-<TODO: cite official ${DISPLAY_NAME} docs>}"

# ─── Scaffold provenance stamp ──────────────────────────────────────────────
# Stamped into the bottom of each rendered agent body (never into frontmatter,
# which is Claude's routing surface and must stay clean). Bump SKILL_VERSION on
# breaking template/menu schema changes; future migrate.sh can grep for the
# stamp to detect drift on previously scaffolded repos.
export SKILL_VERSION="${SKILL_VERSION:-0.3.0}"
export SCAFFOLDED_AT="${SCAFFOLDED_AT:-${LAST_UPDATED}}"

# Re-export the basics
export TARGET_REPO PROJECT_NAME PROJECT_DESCRIPTION

TARGET_CLAUDE="${TARGET_REPO}/.claude"
ARCHITECT_PATH="${TARGET_CLAUDE}/agents/${SLUG}-architect.md"
DEVELOPER_PATH="${TARGET_CLAUDE}/agents/${SLUG}-developer.md"
TROUBLESHOOTER_PATH="${TARGET_CLAUDE}/agents/${SLUG}-troubleshooter.md"
KB_DIR="${TARGET_CLAUDE}/kb/${SLUG}"
INDEX_PATH="${TARGET_CLAUDE}/kb/_index.yaml"

mkdir -p "${TARGET_CLAUDE}/agents" "${KB_DIR}/concepts" "${KB_DIR}/patterns" "${KB_DIR}/reference"

# ─── Install fleet-wide doctrine on first scaffold ──────────────────────────
# doctrine.yaml is the single source of numeric truth for the Agreement Matrix,
# Modifiers, and Thresholds embedded in every agent template. We copy it
# verbatim (no placeholder substitution) the first time we scaffold into a
# repo; subsequent scaffolds leave the user's tuned values untouched.
DOCTRINE_PATH="${TARGET_CLAUDE}/doctrine.yaml"
DOCTRINE_INSTALLED=0
if [[ ! -e "${DOCTRINE_PATH}" ]]; then
  cp "${TEMPLATES}/doctrine.yaml.tpl" "${DOCTRINE_PATH}"
  DOCTRINE_INSTALLED=1
fi

# ─── Idempotency guard — per-role check (allows opting in later) ────────────
# We do NOT hard-fail if a role file already exists; we skip it and report.
# This makes "add troubleshooter to an existing tech" a one-line menu edit + rerun.
SCAFFOLD_RENDER_ARCHITECT=0
SCAFFOLD_RENDER_DEVELOPER=0
SCAFFOLD_RENDER_TROUBLESHOOTER=0
for role in ${SCAFFOLD_ROLES}; do
  case "${role}" in
    architect)
      if [[ -e "${ARCHITECT_PATH}" ]]; then
        echo "NOTE: ${SLUG}-architect already exists — leaving untouched (${ARCHITECT_PATH})" >&2
      else
        SCAFFOLD_RENDER_ARCHITECT=1
      fi
      ;;
    developer)
      if [[ -e "${DEVELOPER_PATH}" ]]; then
        echo "NOTE: ${SLUG}-developer already exists — leaving untouched (${DEVELOPER_PATH})" >&2
      else
        SCAFFOLD_RENDER_DEVELOPER=1
      fi
      ;;
    troubleshooter)
      if [[ -e "${TROUBLESHOOTER_PATH}" ]]; then
        echo "NOTE: ${SLUG}-troubleshooter already exists — leaving untouched (${TROUBLESHOOTER_PATH})" >&2
      else
        SCAFFOLD_RENDER_TROUBLESHOOTER=1
      fi
      ;;
  esac
done

# ─── Placeholder substitution ───────────────────────────────────────────────
render() {
  local src="$1" dst="$2"
  python3 - "$src" "$dst" <<'PYEOF'
import os, sys, re
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    content = f.read()
def sub(match):
    key = match.group(1)
    val = os.environ.get(key)
    return val if val is not None else match.group(0)
content = re.sub(r"\{([A-Z_][A-Z0-9_]*)\}", sub, content)
with open(dst, "w") as f:
    f.write(content)
PYEOF
}

# ─── Render architect (with role-specific exports) ──────────────────────────
if [[ "${SCAFFOLD_RENDER_ARCHITECT}" == "1" ]]; then
  export AGENT_COLOR="${AGENT_COLOR_ARCHITECT}"
  render "${TEMPLATES}/architect.md.tpl" "${ARCHITECT_PATH}"
fi

# ─── Render developer ───────────────────────────────────────────────────────
if [[ "${SCAFFOLD_RENDER_DEVELOPER}" == "1" ]]; then
  export AGENT_COLOR="${AGENT_COLOR_DEVELOPER}"
  render "${TEMPLATES}/developer.md.tpl" "${DEVELOPER_PATH}"
fi

# ─── Render troubleshooter (only if opted in via menu's `roles:` field) ─────
if [[ "${SCAFFOLD_RENDER_TROUBLESHOOTER}" == "1" ]]; then
  export AGENT_COLOR="${AGENT_COLOR_TROUBLESHOOTER}"
  render "${TEMPLATES}/troubleshooter.md.tpl" "${TROUBLESHOOTER_PATH}"
fi

# ─── KB quick-reference ─────────────────────────────────────────────────────
export DOMAIN_DISPLAY_NAME="${DISPLAY_NAME}"
render "${KB_TEMPLATES}/quick-reference.md.tpl" "${KB_DIR}/quick-reference.md"

# ─── KB seed entries (concept / pattern / reference) ────────────────────────
render_entry() {
  local kind="$1" slug="$2"
  local tpl="${KB_TEMPLATES}/${kind}.md.tpl"
  local dir
  case "$kind" in
    concept|pattern) dir="${kind}s" ;;
    reference)       dir="reference" ;;
  esac
  local dst="${KB_DIR}/${dir}/${slug}.md"
  local title
  title="$(echo "$slug" | tr '-' ' ' | awk '{for(i=1;i<=NF;i++)$i=toupper(substr($i,1,1))substr($i,2)}1')"
  case "$kind" in
    concept)
      export CONCEPT_NAME="$title"
      export ONE_LINE_DESCRIPTION="<TODO: one-line description of ${slug}>"
      export CONFIDENCE_LEVEL="${THRESHOLD_DEVELOPER}"
      ;;
    pattern)
      export PATTERN_NAME="$title"
      export WHAT_PROBLEM_THIS_SOLVES="<TODO: problem statement for ${slug}>"
      ;;
    reference)
      export REFERENCE_TITLE="$title"
      export REFERENCE_DESCRIPTION="<TODO: scope of this reference>"
      ;;
  esac
  render "$tpl" "$dst"
}

IFS=',' read -ra CONCEPT_LIST <<< "${KB_CONCEPTS}"
for c in "${CONCEPT_LIST[@]}"; do [[ -n "$c" ]] && render_entry concept "$c"; done

IFS=',' read -ra PATTERN_LIST <<< "${KB_PATTERNS}"
for p in "${PATTERN_LIST[@]}"; do [[ -n "$p" ]] && render_entry pattern "$p"; done

IFS=',' read -ra REFERENCE_LIST <<< "${KB_REFERENCES}"
for r in "${REFERENCE_LIST[@]}"; do [[ -n "$r" ]] && render_entry reference "$r"; done

# ─── Initialize or update _index.yaml ───────────────────────────────────────
if [[ ! -e "${INDEX_PATH}" ]]; then
  render "${KB_TEMPLATES}/_index.yaml.tpl" "${INDEX_PATH}"
fi

python3 - "${INDEX_PATH}" <<PYEOF
import sys
from pathlib import Path
import yaml

index_path = Path(sys.argv[1])
slug = "${SLUG}"
display = "${DISPLAY_NAME}"
scope = "${DOMAIN_SCOPE}"
last_updated = "${LAST_UPDATED}"
threshold = float("${THRESHOLD_DEVELOPER}")
concepts = [c for c in "${KB_CONCEPTS}".split(",") if c]
patterns = [p for p in "${KB_PATTERNS}".split(",") if p]
references = [r for r in "${KB_REFERENCES}".split(",") if r]

data = yaml.safe_load(index_path.read_text()) or {}
domains = data.get("domains") or {}

if slug in domains:
    print(f"NOTE: domain '{slug}' already in _index.yaml — leaving existing entry untouched.", file=sys.stderr)
else:
    domains[slug] = {
        "name": display,
        "description": scope,
        "path": f"{slug}/",
        "mcp_validated": last_updated,
        "entry_points": {"quick_reference": "quick-reference.md"},
        "concepts":  [{"name": c, "path": f"concepts/{c}.md",  "confidence": threshold} for c in concepts],
        "patterns":  [{"name": p, "path": f"patterns/{p}.md"} for p in patterns],
        "reference": [{"name": r, "path": f"reference/{r}.md"} for r in references],
    }
    data["domains"] = domains
    data["last_updated"] = last_updated
    index_path.write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False))
PYEOF

# ─── Leak check ─────────────────────────────────────────────────────────────
LEAK_TARGETS=()
[[ -e "${ARCHITECT_PATH}" ]]      && LEAK_TARGETS+=("${ARCHITECT_PATH}")
[[ -e "${DEVELOPER_PATH}" ]]      && LEAK_TARGETS+=("${DEVELOPER_PATH}")
[[ -e "${TROUBLESHOOTER_PATH}" ]] && LEAK_TARGETS+=("${TROUBLESHOOTER_PATH}")
LEAK_TARGETS+=("${KB_DIR}")
LEAKED=$(grep -rE '\{[A-Z_][A-Z0-9_]*\}' "${LEAK_TARGETS[@]}" 2>/dev/null || true)
if [[ -n "${LEAKED}" ]]; then
  echo "WARN: unrendered placeholders found:" >&2
  echo "${LEAKED}" >&2
fi

echo "✓ Scaffolded tech: ${TECH}"
[[ -e "${ARCHITECT_PATH}" ]]      && echo "  Architect      : ${ARCHITECT_PATH}"
[[ -e "${DEVELOPER_PATH}" ]]      && echo "  Developer      : ${DEVELOPER_PATH}"
[[ -e "${TROUBLESHOOTER_PATH}" ]] && echo "  Troubleshooter : ${TROUBLESHOOTER_PATH}"
echo "  KB             : ${KB_DIR}/"
echo "  Index          : ${INDEX_PATH}"
[[ "${DOCTRINE_INSTALLED}" == "1" ]] && echo "  Doctrine       : ${DOCTRINE_PATH}"
