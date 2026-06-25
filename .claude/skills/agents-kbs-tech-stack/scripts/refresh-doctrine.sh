#!/usr/bin/env bash
# refresh-doctrine.sh — Propagate <target>/.claude/doctrine.yaml back into every
# scaffolded agent body. Non-destructive to user-authored markdown — only
# rewrites the numeric values inside the Agreement Matrix ASCII block, the
# Confidence Modifiers table, and the Task Thresholds table.
#
# Inputs (env vars):
#   TARGET_REPO   absolute path to the repo whose agents should be refreshed
#
# Behavior:
#   1. Reads <target>/.claude/doctrine.yaml.
#      If missing, copies templates/doctrine.yaml.tpl into place and bails out
#      with an INFO message (re-run to apply).
#   2. Walks <target>/.claude/agents/*-architect.md, *-developer.md, and
#      *-troubleshooter.md.
#   3. For each agent, in-place updates:
#        - five numeric cells inside the Agreement Matrix ASCII block
#        - six/seven numeric cells inside the Confidence Modifiers table
#          (rows that map to a doctrine modifier are rewritten; others are
#          preserved verbatim)
#        - four numeric cells inside the Task Thresholds / Decision Categories
#          table
#   4. Reports per-file "✓ updated" or "○ no changes", then a summary line.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
DOCTRINE_TEMPLATE="${SKILL_ROOT}/templates/doctrine.yaml.tpl"

if [[ -z "${TARGET_REPO:-}" ]]; then
  echo "ERROR: TARGET_REPO env var is required" >&2
  exit 1
fi

TARGET_CLAUDE="${TARGET_REPO}/.claude"
DOCTRINE_PATH="${TARGET_CLAUDE}/doctrine.yaml"
AGENTS_DIR="${TARGET_CLAUDE}/agents"

if [[ ! -e "${DOCTRINE_PATH}" ]]; then
  if [[ ! -d "${TARGET_CLAUDE}" ]]; then
    mkdir -p "${TARGET_CLAUDE}"
  fi
  cp "${DOCTRINE_TEMPLATE}" "${DOCTRINE_PATH}"
  echo "INFO: created ${DOCTRINE_PATH} with current defaults; re-run to apply."
  exit 0
fi

if [[ ! -d "${AGENTS_DIR}" ]]; then
  echo "INFO: no ${AGENTS_DIR} directory — nothing to refresh."
  exit 0
fi

# ─── Locate agent files ─────────────────────────────────────────────────────
# Glob over the three known role suffixes. Bash 3.2-compatible (no globstar).
shopt -s nullglob
AGENT_FILES=(
  "${AGENTS_DIR}"/*-architect.md
  "${AGENTS_DIR}"/*-developer.md
  "${AGENTS_DIR}"/*-troubleshooter.md
)
shopt -u nullglob

if [[ ${#AGENT_FILES[@]} -eq 0 ]]; then
  echo "INFO: no scaffolded agents found under ${AGENTS_DIR} — nothing to refresh."
  exit 0
fi

# ─── Read doctrine + rewrite agents via Python ──────────────────────────────
# We delegate to Python because we need real YAML parsing and surgical regex
# rewrites over multi-line ASCII blocks. The Python side reports per-file
# status to stdout so the bash caller can echo a final summary.
python3 - "${DOCTRINE_PATH}" "${AGENT_FILES[@]}" <<'PYEOF'
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML required (pip install pyyaml)", file=sys.stderr)
    sys.exit(2)

doctrine_path = Path(sys.argv[1])
agent_files = [Path(p) for p in sys.argv[2:]]

doctrine = yaml.safe_load(doctrine_path.read_text()) or {}
matrix = doctrine.get("agreement_matrix", {})
modifiers = doctrine.get("modifiers", {})
thresholds = doctrine.get("thresholds", {})


def fmt(value: float) -> str:
    """Format a doctrine number using the agents' canonical fixed-2 decimal."""
    return f"{float(value):.2f}"


def fmt_signed(value: float) -> str:
    """Format a modifier preserving its leading sign (+/-)."""
    v = float(value)
    return f"+{v:.2f}" if v >= 0 else f"{v:.2f}"


# ─── Agreement Matrix cells ────────────────────────────────────────────────
# Each pattern preserves the surrounding label (HIGH, CONFLICT, etc.) and
# replaces only the numeric token after the colon.
MATRIX_LABELS = {
    "HIGH": "kb_has_pattern_mcp_agrees",
    "CONFLICT": "kb_has_pattern_mcp_disagrees",
    "MEDIUM": "kb_has_pattern_mcp_silent",
    "MCP-ONLY": "kb_silent_mcp_agrees",
    "LOW": "kb_silent_mcp_silent",
}

# ─── Confidence Modifier rows ──────────────────────────────────────────────
# Maps the row-label substring (case-insensitive) to a doctrine modifier key.
# Only rows that match are rewritten; tech-specific rows (e.g., "Tests cover
# the change") are preserved as authored.
MODIFIER_ROWS = [
    ("Fresh info",                "fresh_info_plus"),
    ("Stale info",                "stale_info_minus"),
    ("Breaking change",           "breaking_change_minus"),
    ("Production examples",       "production_examples_plus"),
    ("No examples",               "no_examples_minus"),
    ("Exact match",               "exact_match_plus"),
    ("Tangential",                "tangential_minus"),
]

# ─── Task Thresholds / Decision Categories rows ────────────────────────────
THRESHOLD_LABELS = {
    "CRITICAL":  "critical",
    "IMPORTANT": "important",
    "STANDARD":  "standard",
    "ADVISORY":  "advisory",
}


def rewrite_matrix(text: str) -> str:
    """Update the five numeric cells inside the ASCII Agreement Matrix."""
    for label, key in MATRIX_LABELS.items():
        if key not in matrix:
            continue
        new_val = fmt(matrix[key])
        # Match: "<LABEL>: <number>" with flexible whitespace; preserve label + colon.
        pattern = re.compile(
            r"(" + re.escape(label) + r":\s*)(\d+\.\d+)"
        )
        text = pattern.sub(lambda m: f"{m.group(1)}{new_val}", text)
    return text


def rewrite_modifiers(text: str) -> str:
    """Update modifier rows in the Confidence Modifiers markdown table."""
    for row_label, key in MODIFIER_ROWS:
        if key not in modifiers:
            continue
        new_val = fmt_signed(modifiers[key])
        # Row shape: "| <row-label something> | <+/-N.NN> | <apply-when> |"
        # The label may contain extra text ("Fresh info (< 1 month)") so we
        # anchor to the row-start pipe + label prefix, then the next pipe-
        # delimited cell carries the number.
        pattern = re.compile(
            r"(^\|\s*"
            + re.escape(row_label)
            + r"[^|]*\|\s*)([+-]?\d+\.\d+)(\s*\|)",
            flags=re.MULTILINE,
        )
        text = pattern.sub(lambda m: f"{m.group(1)}{new_val}{m.group(3)}", text)
    return text


def rewrite_thresholds(text: str) -> str:
    """Update CRITICAL/IMPORTANT/STANDARD/ADVISORY rows in the threshold table."""
    for label, key in THRESHOLD_LABELS.items():
        if key not in thresholds:
            continue
        new_val = fmt(thresholds[key])
        # Row shape: "| <LABEL> ... | <N.NN> | <action> |"
        # Anchor on the leading pipe + label, allow arbitrary descriptive text
        # before the next pipe, capture and rewrite the number cell.
        pattern = re.compile(
            r"(^\|\s*"
            + re.escape(label)
            + r"[^|]*\|\s*)(\d+\.\d+)(\s*\|)",
            flags=re.MULTILINE,
        )
        text = pattern.sub(lambda m: f"{m.group(1)}{new_val}{m.group(3)}", text)
    return text


updated_count = 0
for agent_file in agent_files:
    original = agent_file.read_text()
    rewritten = original
    rewritten = rewrite_matrix(rewritten)
    rewritten = rewrite_modifiers(rewritten)
    rewritten = rewrite_thresholds(rewritten)
    if rewritten != original:
        agent_file.write_text(rewritten)
        print(f"  ✓ updated   {agent_file.name}")
        updated_count += 1
    else:
        print(f"  ○ no changes {agent_file.name}")

print(f"Refreshed {updated_count} files from doctrine.yaml")
PYEOF
