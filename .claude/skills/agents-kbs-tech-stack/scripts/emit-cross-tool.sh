#!/usr/bin/env bash
# emit-cross-tool.sh — Emit the three cross-tool files from the canonical
# .claude/ layout:
#
#   1. AGENTS.md                                  (repo root, cross-tool index)
#   2. .cursor/rules/agents-kbs-tech-stack.mdc    (Cursor shim)
#   3. .github/copilot-instructions.md            (Copilot pointer)
#
# All three are *generated* — they overwrite on every run. The source of truth
# is .claude/agents/ + .claude/kb/_index.yaml. Run this after:
#
#   - adding/removing a tech (scaffold.sh / install-closers.sh)
#   - renaming the project (changing kb/_index.yaml `project:`)
#   - bumping doctrine
#
# Inputs:
#   TARGET_REPO  absolute path to the target repo
#
# Exit codes:
#   0  emitted
#   1  TARGET_REPO unset or invalid
#   2  .claude/ scaffolding incomplete (no _index.yaml or no agents dir)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
TEMPLATES="${SKILL_ROOT}/templates"

if [[ -z "${TARGET_REPO:-}" ]]; then
  echo "ERROR: TARGET_REPO must be set (absolute path to the target repo)" >&2
  exit 1
fi

if [[ ! -d "${TARGET_REPO}" ]]; then
  echo "ERROR: TARGET_REPO does not exist: ${TARGET_REPO}" >&2
  exit 1
fi

INDEX_PATH="${TARGET_REPO}/.claude/kb/_index.yaml"
AGENTS_DIR="${TARGET_REPO}/.claude/agents"

if [[ ! -e "${INDEX_PATH}" ]]; then
  echo "ERROR: ${INDEX_PATH} does not exist — scaffold at least one tech first." >&2
  exit 2
fi

if [[ ! -d "${AGENTS_DIR}" ]]; then
  echo "ERROR: ${AGENTS_DIR} does not exist — scaffold at least one tech first." >&2
  exit 2
fi

LAST_UPDATED="$(date -u +%Y-%m-%d)"

# ─── Build the AGENTS.md content via Python (needs yaml + filesystem walk) ──
RENDER_OUTPUT="$(python3 - "${INDEX_PATH}" "${AGENTS_DIR}" "${TEMPLATES}/AGENTS.md.tpl" "${LAST_UPDATED}" <<'PYEOF'
import sys
import re
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

index_path = Path(sys.argv[1])
agents_dir = Path(sys.argv[2])
tpl_path   = Path(sys.argv[3])
last_updated = sys.argv[4]

data = yaml.safe_load(index_path.read_text()) or {}
project_name = data.get("project") or "<unnamed project>"
domains      = data.get("domains") or {}

# ─── Agents table ──────────────────────────────────────────────────────────
# Parse agent frontmatter to extract `name` + `description` per file. Falls
# back to the filename if frontmatter is malformed.
agent_rows = []
for md in sorted(agents_dir.glob("*.md")):
    text = md.read_text()
    name = md.stem
    description = ""
    role = "unknown"

    # Frontmatter parse: between leading '---' fences.
    fm_match = re.match(r"^---\s*\n(.*?)\n---\s*\n", text, re.DOTALL)
    if fm_match:
        try:
            fm = yaml.safe_load(fm_match.group(1)) or {}
            name = fm.get("name", name)
            description = (fm.get("description") or "").strip().replace("\n", " ")
            # First sentence only — keep the table tight.
            if description:
                first = re.split(r"(?<=[.!?])\s+", description, maxsplit=1)[0]
                description = first
        except yaml.YAMLError:
            pass

    # Infer role from name suffix.
    if name.endswith("-architect"):
        role = "architect"
    elif name.endswith("-developer"):
        role = "developer"
    elif name.endswith("-troubleshooter"):
        role = "troubleshooter"
    elif name in {"code-reviewer", "code-simplifier", "code-documenter"}:
        role = "closer"

    rel_path = md.relative_to(agents_dir.parent.parent).as_posix()
    agent_rows.append((name, role, description, rel_path))

if agent_rows:
    lines = [
        "| Agent | Role | Purpose | File |",
        "|-------|------|---------|------|",
    ]
    for name, role, desc, path in agent_rows:
        # Pipe-escape so table cells don't break.
        desc_safe = (desc or "").replace("|", "\\|")
        lines.append(f"| `{name}` | {role} | {desc_safe} | [`{path}`]({path}) |")
    agents_table = "\n".join(lines)
else:
    agents_table = "_(no agents scaffolded yet)_"

# ─── KB table ──────────────────────────────────────────────────────────────
if domains:
    lines = [
        "| Domain | Description | Quick reference |",
        "|--------|-------------|-----------------|",
    ]
    for slug, block in domains.items():
        d_name = block.get("name") or slug
        d_desc = (block.get("description") or "").replace("|", "\\|")
        path = block.get("path") or f"{slug}/"
        qr_rel = (block.get("entry_points") or {}).get("quick_reference") or "quick-reference.md"
        qr_link = f".claude/kb/{path.rstrip('/')}/{qr_rel}"
        lines.append(f"| `{slug}` ({d_name}) | {d_desc} | [`{qr_link}`]({qr_link}) |")
    kb_table = "\n".join(lines)
else:
    kb_table = "_(no domains registered yet)_"

# ─── Render ────────────────────────────────────────────────────────────────
content = tpl_path.read_text()
content = content.replace("{PROJECT_NAME}", project_name)
content = content.replace("{AGENTS_TABLE}", agents_table)
content = content.replace("{KB_TABLE}", kb_table)
content = content.replace("{LAST_UPDATED}", last_updated)

print(content)
PYEOF
)"

# ─── Write AGENTS.md ────────────────────────────────────────────────────────
AGENTS_MD="${TARGET_REPO}/AGENTS.md"
printf '%s' "${RENDER_OUTPUT}" > "${AGENTS_MD}"
echo "✓ wrote ${AGENTS_MD}"

# ─── Write Cursor mdc ───────────────────────────────────────────────────────
CURSOR_DIR="${TARGET_REPO}/.cursor/rules"
mkdir -p "${CURSOR_DIR}"
CURSOR_MDC="${CURSOR_DIR}/agents-kbs-tech-stack.mdc"
cp "${TEMPLATES}/cursor-rules.mdc.tpl" "${CURSOR_MDC}"
echo "✓ wrote ${CURSOR_MDC}"

# ─── Write Copilot instructions ─────────────────────────────────────────────
GH_DIR="${TARGET_REPO}/.github"
mkdir -p "${GH_DIR}"
COPILOT_MD="${GH_DIR}/copilot-instructions.md"
cp "${TEMPLATES}/copilot-instructions.md.tpl" "${COPILOT_MD}"
echo "✓ wrote ${COPILOT_MD}"

echo ""
echo "────────────────────────────────────────────────────────────────────────"
echo "Cross-tool index emitted (overwrote any prior versions):"
echo "  • ${AGENTS_MD}"
echo "  • ${CURSOR_MDC}"
echo "  • ${COPILOT_MD}"
echo ""
echo "Re-emit after adding/removing a tech, renaming the project, or"
echo "bumping doctrine. These files are generated — do not hand-edit."
echo "────────────────────────────────────────────────────────────────────────"
