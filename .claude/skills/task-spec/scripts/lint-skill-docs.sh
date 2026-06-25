#!/usr/bin/env bash
# lint-skill-docs.sh — Regression guard for v2.1 doc consistency.
#
# Codifies the v2.1 audit checks as a lint script that future PRs must pass.
# Catches: v1/v2 drift, version mismatches, missing distribution files,
# missing --version support, and the "validate as the gate" mis-naming.
#
# Usage:
#   bash lint-skill-docs.sh
#   bash lint-skill-docs.sh --version
#
# Exit codes:
#   0   all checks pass
#   1   one or more checks failed
#   2   usage error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./_lib.sh
source "$SCRIPT_DIR/_lib.sh"
ts_version_flag "$@"

SKILL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=()
WARNINGS=()
CHECKS=0

err() { ERRORS+=("$1"); }
warn() { WARNINGS+=("$1"); }

# ---------------------------------------------------------------------------
# Check 1: no banned v1/v2-drift phrases outside CHANGELOG / git-history docs
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
banned_hits=$(grep -rEn 'Task-Spec v1\b|v2 will add|will be added in v2|will be additive in v2' \
  "$SKILL_DIR" --include='*.md' 2>/dev/null \
  | grep -vE '/CHANGELOG\.md:' \
  || true)
if [[ -n "$banned_hits" ]]; then
  err "v1/v2 drift phrases found outside CHANGELOG:"
  while IFS= read -r line; do err "  $line"; done <<< "$banned_hits"
fi

# ---------------------------------------------------------------------------
# Check 2: SKILL.md frontmatter version matches _lib.sh TASKSPEC_VERSION
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
SKILL_VER=$(grep -m1 '^version:' "$SKILL_DIR/SKILL.md" 2>/dev/null | sed -E 's/^version:[[:space:]]*"?([^"]*)"?[[:space:]]*$/\1/')
LIB_VER=$(grep -m1 '^TASKSPEC_VERSION=' "$SKILL_DIR/scripts/_lib.sh" 2>/dev/null | sed -E 's/^TASKSPEC_VERSION="?([^"]*)"?[[:space:]]*$/\1/')
if [[ -z "$SKILL_VER" ]]; then
  err "SKILL.md frontmatter missing 'version:' field"
elif [[ -z "$LIB_VER" ]]; then
  err "_lib.sh missing TASKSPEC_VERSION"
elif [[ "$SKILL_VER" != "$LIB_VER" ]]; then
  err "version mismatch: SKILL.md says '$SKILL_VER' but _lib.sh says '$LIB_VER'"
fi
# Also assert plugin.json + marketplace.json match the canonical version.
for vf in plugin.json marketplace.json; do
  if [[ -f "$SKILL_DIR/$vf" ]]; then
    JSON_VER=$(grep -m1 '"version"' "$SKILL_DIR/$vf" 2>/dev/null | sed -E 's/.*"version"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/')
    if [[ -n "$LIB_VER" && "$JSON_VER" != "$LIB_VER" ]]; then
      err "version mismatch: $vf says '$JSON_VER' but _lib.sh says '$LIB_VER'"
    fi
  fi
done

# ---------------------------------------------------------------------------
# Check 3: plugin.json + marketplace.json present (distribution surface)
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
for f in plugin.json marketplace.json CHANGELOG.md; do
  if [[ ! -f "$SKILL_DIR/$f" ]]; then
    err "required distribution file missing: $f"
  fi
done

# ---------------------------------------------------------------------------
# Check 4: every top-level script supports --version
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
for s in "$SKILL_DIR"/scripts/*.sh; do
  base="$(basename "$s")"
  # _lib.sh is sourced, not invoked
  [[ "$base" == "_lib.sh" ]] && continue
  set +e
  out=$(bash "$s" --version 2>&1)
  rc=$?
  set -e
  if [[ "$rc" != "0" ]] || [[ "$out" != *"task-spec v"* ]]; then
    err "script does not honor --version: $base (got rc=$rc, out='$out')"
  fi
done

# ---------------------------------------------------------------------------
# Check 5: safe-to-delegate.sh is named as THE gate in canonical author docs
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
for doc in SKILL.md README.md references/concepts/signed-off.md runbooks/dispatching-a-task-spec.md; do
  if [[ ! -f "$SKILL_DIR/$doc" ]]; then
    err "canonical doc missing: $doc"
    continue
  fi
  if ! grep -q 'safe-to-delegate.sh --stamp' "$SKILL_DIR/$doc"; then
    err "$doc does not name 'safe-to-delegate.sh --stamp' (the gate must be named in canonical docs)"
  fi
done

# ---------------------------------------------------------------------------
# Check 6: never-hand-stamp rule present in agent-contract + task-architect
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
for doc in references/concepts/agent-contract.md agents/task-architect.md; do
  if [[ ! -f "$SKILL_DIR/$doc" ]]; then
    err "doc missing: $doc"
    continue
  fi
  if ! grep -qE 'hand-stamp|never stamp yourself|Never hand-stamp|do not hand-stamp' "$SKILL_DIR/$doc"; then
    err "$doc does not forbid hand-stamping (required by v2.1 autonomy contract)"
  fi
done

# ---------------------------------------------------------------------------
# Check 7: tests/fixtures/oracle.json present and has 8 fixtures
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
if [[ ! -f "$SKILL_DIR/tests/fixtures/oracle.json" ]]; then
  err "tests/fixtures/oracle.json missing — WS5 regression suite cannot run"
else
  fixture_count=$(python3 -c "import json; print(len(json.load(open('$SKILL_DIR/tests/fixtures/oracle.json'))['fixtures']))" 2>/dev/null || echo 0)
  if [[ "$fixture_count" -lt 8 ]]; then
    err "oracle.json declares only $fixture_count fixtures (expected ≥8: 6 inverted-grep variants + hand-stamped + golden)"
  fi
fi

# ---------------------------------------------------------------------------
# Check 8: tests/test-portability-e2e.sh present and executable
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
if [[ ! -f "$SKILL_DIR/tests/test-portability-e2e.sh" ]]; then
  err "tests/test-portability-e2e.sh missing — WS8 e2e smoke test cannot run"
elif [[ ! -x "$SKILL_DIR/tests/test-portability-e2e.sh" ]]; then
  warn "tests/test-portability-e2e.sh is not executable (chmod +x recommended)"
fi

# ---------------------------------------------------------------------------
# Check 9: first-spec-walkthrough.md present
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
if [[ ! -f "$SKILL_DIR/runbooks/first-spec-walkthrough.md" ]]; then
  err "runbooks/first-spec-walkthrough.md missing — new authors have no onboarding path"
fi

# ---------------------------------------------------------------------------
# Check 10: dogfood — the skill's own scripts MUST NOT contain the banned
# inverted-count anti-patterns that validate-task-spec.sh Check 16 rejects.
# Excludes validate-task-spec.sh itself (it carries the regexes as string
# literals) and lint-skill-docs.sh (this file documents the patterns).
# ---------------------------------------------------------------------------
CHECKS=$((CHECKS + 1))
DOGFOOD_HITS=0
for s in "$SKILL_DIR"/scripts/*.sh; do
  base="$(basename "$s")"
  case "$base" in
    validate-task-spec.sh|lint-skill-docs.sh|_lib.sh) continue ;;
  esac
  # The banned pattern: $(...) or `...` ending in `|| (echo <int>|true)`
  # chained off grep -c / wc, i.e. the inverted-count footgun.
  if grep -nE '(\$\(|`)[^)`]*grep[[:space:]]+-c[^)`]*\|\|[[:space:]]*(echo[[:space:]]+[0-9]+|true)' "$s" >/dev/null 2>&1 \
     || grep -nE '(\$\(|`)[^)`]*wc[[:space:]]+-[lcwm][^)`]*\|\|[[:space:]]*(echo[[:space:]]+[0-9]+|true)' "$s" >/dev/null 2>&1; then
    hit=$(grep -nE '(\$\(|`)[^)`]*(grep[[:space:]]+-c|wc[[:space:]]+-[lcwm])[^)`]*\|\|[[:space:]]*(echo[[:space:]]+[0-9]+|true)' "$s" | head -1)
    err "dogfood: $base contains the inverted-count anti-pattern the skill itself bans: $hit"
    DOGFOOD_HITS=$((DOGFOOD_HITS + 1))
  fi
done

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------
echo "lint-skill-docs.sh ($CHECKS checks)"
echo "════════════════════════════════════════"
if [[ ${#WARNINGS[@]} -gt 0 ]]; then
  echo "Warnings:"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi
if [[ ${#ERRORS[@]} -gt 0 ]]; then
  echo "FAIL: ${#ERRORS[@]} doc-consistency error(s):"
  for e in "${ERRORS[@]}"; do echo "  - $e"; done
  exit 1
fi
echo "OK: skill docs are consistent at v$TASKSPEC_VERSION"
exit 0
