#!/usr/bin/env bash
# quality-gate.sh — Cold-eyes quality gate for agents-kbs-tech-stack v0.3.0 scaffolds.
#
# Inputs (env vars):
#   TARGET_REPO   absolute path to the repo whose .claude/ tree should be audited
#   SKIP_KIMI     if set (any non-empty value), skip the optional /kimi:review pass
#
# Flags:
#   --strict      exit 7 when BLOCKER findings are present (default: always exit 0)
#
# Behavior:
#   Step A — placeholder leak check across .claude/agents/ and .claude/kb/
#   Step B — architect alignment (no Bash in tools list)
#   Step C — developer alignment (Bash present in tools list)
#   Step D — troubleshooter alignment (Bash present; Edit, Write absent)
#   Step E — optional /kimi:review pass via the `claude` CLI (advisory, never blocks)
#   Step F — print verdict (APPROVE | APPROVE_WITH_WARNINGS | BLOCK)
#
# Exit codes:
#   0  — default mode, or strict mode with no BLOCKER findings
#   7  — strict mode with one or more BLOCKER findings
#   2  — TARGET_REPO unset or missing
#
# Self-contained: no external Python, no jq required. POSIX grep + bash 3.2 safe.

set -uo pipefail

STRICT=0
for arg in "$@"; do
  case "${arg}" in
    --strict) STRICT=1 ;;
    *) ;;
  esac
done

if [[ -z "${TARGET_REPO:-}" ]]; then
  echo "ERROR: TARGET_REPO env var is unset" >&2
  exit 2
fi
if [[ ! -d "${TARGET_REPO}/.claude" ]]; then
  echo "ERROR: ${TARGET_REPO}/.claude does not exist — nothing to gate" >&2
  exit 2
fi

AGENTS_DIR="${TARGET_REPO}/.claude/agents"
KB_DIR="${TARGET_REPO}/.claude/kb"

# Counters
BLOCKERS=0
IMPORTANTS=0
NITS=0
FILES_CHECKED=0

# Findings buffer — bash 3.2 has no associative arrays we can rely on; we
# append "SEVERITY|FILE|MESSAGE" lines into a tmpfile and replay at the end.
FINDINGS_FILE="$(mktemp -t quality-gate.XXXXXX)"
trap 'rm -f "${FINDINGS_FILE}"' EXIT

record() {
  local severity="$1" file="$2" message="$3"
  printf '%s|%s|%s\n' "${severity}" "${file}" "${message}" >> "${FINDINGS_FILE}"
  case "${severity}" in
    BLOCKER)   BLOCKERS=$((BLOCKERS + 1)) ;;
    IMPORTANT) IMPORTANTS=$((IMPORTANTS + 1)) ;;
    NIT)       NITS=$((NITS + 1)) ;;
  esac
}

# ─── Step A: Placeholder leak check ─────────────────────────────────────────
# Any unrendered {ALL_CAPS_TOKEN} is a render bug.
if [[ -d "${AGENTS_DIR}" || -d "${KB_DIR}" ]]; then
  LEAK_TARGETS=()
  [[ -d "${AGENTS_DIR}" ]] && LEAK_TARGETS+=("${AGENTS_DIR}")
  [[ -d "${KB_DIR}" ]] && LEAK_TARGETS+=("${KB_DIR}")
  if [[ "${#LEAK_TARGETS[@]}" -gt 0 ]]; then
    while IFS= read -r line; do
      [[ -z "${line}" ]] && continue
      # grep -rn output: path:lineno:content
      file_part="${line%%:*}"
      rest="${line#*:}"
      record "BLOCKER" "${file_part}" "Unrendered placeholder leak: ${rest}"
    done < <(grep -rnE '\{[A-Z_][A-Z0-9_]*\}' "${LEAK_TARGETS[@]}" 2>/dev/null || true)
  fi
fi

# ─── Helper: extract the tools: line from an agent file ─────────────────────
# Agents use `tools: [Read, Write, ...]` on a single line. We grep for the
# first line starting with "tools:" — safe across our three templates.
tools_line_of() {
  local file="$1"
  grep -m1 -E '^tools:' "${file}" 2>/dev/null || true
}

# ─── Step B: Architect alignment (no Bash) ──────────────────────────────────
if [[ -d "${AGENTS_DIR}" ]]; then
  while IFS= read -r -d '' agent; do
    FILES_CHECKED=$((FILES_CHECKED + 1))
    line="$(tools_line_of "${agent}")"
    if [[ -z "${line}" ]]; then
      record "BLOCKER" "${agent}" "Missing 'tools:' line in frontmatter"
      continue
    fi
    if echo "${line}" | grep -qE '(^|[][[:space:],])Bash([][[:space:],]|$)'; then
      record "BLOCKER" "${agent}" "Architect must NOT have Bash in tools list (found: ${line})"
    fi
  done < <(find "${AGENTS_DIR}" -maxdepth 1 -type f -name '*-architect.md' -print0 2>/dev/null)
fi

# ─── Step C: Developer alignment (Bash required) ────────────────────────────
if [[ -d "${AGENTS_DIR}" ]]; then
  while IFS= read -r -d '' agent; do
    FILES_CHECKED=$((FILES_CHECKED + 1))
    line="$(tools_line_of "${agent}")"
    if [[ -z "${line}" ]]; then
      record "BLOCKER" "${agent}" "Missing 'tools:' line in frontmatter"
      continue
    fi
    if ! echo "${line}" | grep -qE '(^|[][[:space:],])Bash([][[:space:],]|$)'; then
      record "BLOCKER" "${agent}" "Developer MUST have Bash in tools list (found: ${line})"
    fi
  done < <(find "${AGENTS_DIR}" -maxdepth 1 -type f -name '*-developer.md' -print0 2>/dev/null)
fi

# ─── Step D: Troubleshooter alignment (Bash yes, Edit/Write no) ─────────────
if [[ -d "${AGENTS_DIR}" ]]; then
  while IFS= read -r -d '' agent; do
    FILES_CHECKED=$((FILES_CHECKED + 1))
    line="$(tools_line_of "${agent}")"
    if [[ -z "${line}" ]]; then
      record "BLOCKER" "${agent}" "Missing 'tools:' line in frontmatter"
      continue
    fi
    if ! echo "${line}" | grep -qE '(^|[][[:space:],])Bash([][[:space:],]|$)'; then
      record "BLOCKER" "${agent}" "Troubleshooter MUST have Bash in tools list (found: ${line})"
    fi
    if echo "${line}" | grep -qE '(^|[][[:space:],])Edit([][[:space:],]|$)'; then
      record "BLOCKER" "${agent}" "Troubleshooter must NOT have Edit in tools list (read-only diagnosis)"
    fi
    if echo "${line}" | grep -qE '(^|[][[:space:],])Write([][[:space:],]|$)'; then
      record "BLOCKER" "${agent}" "Troubleshooter must NOT have Write in tools list (read-only diagnosis)"
    fi
  done < <(find "${AGENTS_DIR}" -maxdepth 1 -type f -name '*-troubleshooter.md' -print0 2>/dev/null)
fi

# ─── Step E: Optional /kimi:review pass ─────────────────────────────────────
# We invoke `claude --print "/kimi:review --base HEAD"` and try to parse
# stdout as JSON. Any failure mode (CLI missing, non-zero exit, non-JSON
# output, malformed findings) is non-fatal — we log a one-line note and
# continue with the local checks.
KIMI_STATUS="skipped"
if [[ -z "${SKIP_KIMI:-}" ]] && command -v claude >/dev/null 2>&1; then
  KIMI_TMP="$(mktemp -t kimi-review.XXXXXX)"
  KIMI_PARSER="$(mktemp -t kimi-parser.XXXXXX.py)"
  cat > "${KIMI_PARSER}" <<'PYEOF'
import json, re, sys
src, sink = sys.argv[1], sys.argv[2]
with open(src) as f:
    text = f.read()
data = None
try:
    data = json.loads(text)
except Exception:
    m = re.search(r"\{.*\}", text, re.DOTALL)
    if m:
        try:
            data = json.loads(m.group(0))
        except Exception:
            data = None
if not isinstance(data, dict) or "findings" not in data:
    sys.exit(1)
out = []
for f in data.get("findings", []) or []:
    sev = str(f.get("severity", "")).upper()
    if sev not in ("BLOCKER", "IMPORTANT", "NIT"):
        continue
    fp = str(f.get("file", "(kimi)"))
    msg = str(f.get("message", "")).replace("|", "/").replace("\n", " ")
    out.append(f"{sev}|{fp}|[kimi] {msg}")
with open(sink, "a") as g:
    for line in out:
        g.write(line + "\n")
sys.exit(0)
PYEOF
  if claude --print "/kimi:review --base HEAD" >"${KIMI_TMP}" 2>/dev/null; then
    if python3 "${KIMI_PARSER}" "${KIMI_TMP}" "${FINDINGS_FILE}" 2>/dev/null; then
      KIMI_STATUS="ok"
    else
      KIMI_STATUS="non-json"
      echo "kimi:review unavailable — proceeding with local checks only (non-JSON output)" >&2
    fi
  else
    KIMI_STATUS="error"
    echo "kimi:review unavailable — proceeding with local checks only (CLI error)" >&2
  fi
  rm -f "${KIMI_TMP}" "${KIMI_PARSER}"
fi

# Recompute counters from FINDINGS_FILE in case kimi appended entries.
BLOCKERS=0
IMPORTANTS=0
NITS=0
if [[ -s "${FINDINGS_FILE}" ]]; then
  while IFS='|' read -r sev rest_file rest_msg; do
    case "${sev}" in
      BLOCKER)   BLOCKERS=$((BLOCKERS + 1)) ;;
      IMPORTANT) IMPORTANTS=$((IMPORTANTS + 1)) ;;
      NIT)       NITS=$((NITS + 1)) ;;
    esac
  done < "${FINDINGS_FILE}"
fi

# ─── Step F: Verdict ────────────────────────────────────────────────────────
echo "=== Quality Gate ==="
echo "Files checked: ${FILES_CHECKED}"
echo "BLOCKER findings: ${BLOCKERS}"
echo "IMPORTANT findings: ${IMPORTANTS}"
echo "NIT findings: ${NITS}"
echo "kimi:review: ${KIMI_STATUS}"

if [[ -s "${FINDINGS_FILE}" ]]; then
  echo ""
  echo "--- Details ---"
  # Group by file for readability.
  current_file=""
  while IFS='|' read -r sev file msg; do
    if [[ "${file}" != "${current_file}" ]]; then
      echo ""
      echo "${file}"
      current_file="${file}"
    fi
    echo "  [${sev}] ${msg}"
  done < <(sort -t'|' -k2,2 "${FINDINGS_FILE}")
  echo ""
fi

if [[ "${BLOCKERS}" -gt 0 ]]; then
  VERDICT="BLOCK"
elif [[ "${IMPORTANTS}" -gt 0 || "${NITS}" -gt 0 ]]; then
  VERDICT="APPROVE_WITH_WARNINGS"
else
  VERDICT="APPROVE"
fi
echo "Verdict: ${VERDICT}"

# Exit code policy
if [[ "${STRICT}" -eq 1 && "${BLOCKERS}" -gt 0 ]]; then
  exit 7
fi
exit 0
