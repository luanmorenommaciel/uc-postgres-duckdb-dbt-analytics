#!/usr/bin/env bash
# install-closers.sh — Render the three universal closers into a target repo,
# plus install the kb/code-quality/ tree they ground in.
#
# Idempotent: existing files are left untouched (NOTE printed per file).
# Run once per repo, typically after the first scaffold.sh invocation.
#
# Inputs:
#   TARGET_REPO  absolute path to the target repo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
TEMPLATES="${SKILL_ROOT}/templates/closer"
KB_TEMPLATES="${SKILL_ROOT}/templates/code-quality"

if [[ -z "${TARGET_REPO:-}" ]]; then
  echo "ERROR: TARGET_REPO must be set" >&2
  exit 1
fi
export TARGET_REPO

AGENT_DIR="${TARGET_REPO}/.claude/agents"
KB_DIR="${TARGET_REPO}/.claude/kb/code-quality"
KB_CONCEPTS_DIR="${KB_DIR}/concepts"
INDEX_PATH="${TARGET_REPO}/.claude/kb/_index.yaml"

mkdir -p "${AGENT_DIR}" "${KB_CONCEPTS_DIR}"

# Closers and KB files are pure copies — no placeholder substitution (tech-agnostic by design).
# The closer-hook protocol they document is read at runtime, not at scaffold time.

install_closer() {
  local name="$1"
  local src="${TEMPLATES}/${name}.md.tpl"
  local dst="${AGENT_DIR}/${name}.md"
  if [[ -e "${dst}" ]]; then
    echo "NOTE: ${name} already exists — leaving untouched (${dst})"
    return 0
  fi
  cp "${src}" "${dst}"
  echo "✓ Installed ${name} → ${dst}"
}

install_kb_file() {
  # $1: source path relative to KB_TEMPLATES (e.g. "quick-reference.md.tpl")
  # $2: destination path relative to KB_DIR     (e.g. "quick-reference.md")
  local rel_src="$1"
  local rel_dst="$2"
  local src="${KB_TEMPLATES}/${rel_src}"
  local dst="${KB_DIR}/${rel_dst}"
  if [[ -e "${dst}" ]]; then
    echo "NOTE: kb/code-quality/${rel_dst} already exists — leaving untouched (${dst})"
    return 0
  fi
  cp "${src}" "${dst}"
  echo "✓ Installed kb/code-quality/${rel_dst} → ${dst}"
}

install_closer code-reviewer
install_closer code-simplifier
install_closer code-documenter

install_kb_file "quick-reference.md.tpl"            "quick-reference.md"
install_kb_file "concepts/comments.md.tpl"          "concepts/comments.md"
install_kb_file "concepts/dead-code.md.tpl"         "concepts/dead-code.md"
install_kb_file "concepts/security-universals.md.tpl" "concepts/security-universals.md"

# ─── Register the code-quality domain in _index.yaml ────────────────────────
# Idempotent: only added when the slug is missing. Same pattern as scaffold.sh.
if [[ -e "${INDEX_PATH}" ]]; then
  python3 - "${INDEX_PATH}" <<'PYEOF'
import sys
from datetime import date
from pathlib import Path

try:
    import yaml
except ImportError:
    print("NOTE: PyYAML not available — skipping _index.yaml registration. "
          "Install with `uv pip install pyyaml` and rerun install-closers.sh "
          "to register the code-quality domain.", file=sys.stderr)
    sys.exit(0)

index_path = Path(sys.argv[1])
data = yaml.safe_load(index_path.read_text()) or {}
domains = data.get("domains") or {}

slug = "code-quality"
if slug in domains:
    print(f"NOTE: domain '{slug}' already in _index.yaml — leaving existing entry untouched.", file=sys.stderr)
    sys.exit(0)

today = date.today().isoformat()
domains[slug] = {
    "name": "Code Quality",
    "description": "Cross-tech universals — comments, dead code, security baseline. Grounded in by every closer.",
    "path": "code-quality/",
    "mcp_validated": today,
    "entry_points": {"quick_reference": "quick-reference.md"},
    "concepts": [
        {"name": "comments",            "path": "concepts/comments.md",            "confidence": 0.85},
        {"name": "dead-code",           "path": "concepts/dead-code.md",           "confidence": 0.95},
        {"name": "security-universals", "path": "concepts/security-universals.md", "confidence": 0.95},
    ],
    "patterns":  [],
    "reference": [],
}
data["domains"] = domains
data["last_updated"] = today
index_path.write_text(yaml.safe_dump(data, sort_keys=False, default_flow_style=False))
print(f"✓ Registered domain 'code-quality' in {index_path}")
PYEOF
else
  echo "NOTE: ${INDEX_PATH} does not exist — closers will still work, but no domain index entry was created."
  echo "      Run scaffold.sh for at least one tech to bootstrap _index.yaml, then re-run install-closers.sh."
fi

echo ""
echo "Closers ready. They'll auto-load the tech KBs registered in .claude/kb/_index.yaml on invocation,"
echo "plus the code-quality KB for cross-tech universals (comments, dead code, security)."
