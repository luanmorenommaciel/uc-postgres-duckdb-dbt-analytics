#!/usr/bin/env bash
# _lib.sh — shared helpers for the task-spec skill.
#
# Source this from every top-level script:
#   _LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"
#   source "$_LIB"
#
# Exports:
#   TASKSPEC_VERSION       — canonical version string (single source of truth)
#   TASKSPEC_SKILL_DIR     — absolute path of the task-spec skill root
#   TASKSPEC_BACKLOG_DIR   — configurable backlog directory (default: tasks)
#
# Helpers:
#   ts_version_flag "$@"   — call ONCE at the top of arg parsing.
#                            If $1 is --version, prints "task-spec v$TASKSPEC_VERSION"
#                            and exits 0. Otherwise returns 0 silently.
#   ts_die <msg>           — print to stderr and exit 1.

# ----- Canonical version (single source of truth) -----
# Format change protocol:
#   1) bump TASKSPEC_VERSION here
#   2) bump version field in SKILL.md frontmatter (must match)
#   3) add a CHANGELOG.md entry
#   4) bump version field in plugin.json + marketplace.json (if present)
# The doc-consistency lint asserts (1) == (2) == (4).
TASKSPEC_VERSION="2.2.1"

# ----- Resolve skill root from this file's location -----
# Works whether sourced from scripts/ or via an indirect symlink.
__lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TASKSPEC_SKILL_DIR="$(cd "$__lib_dir/.." && pwd)"
export TASKSPEC_VERSION TASKSPEC_SKILL_DIR

# ----- Configurable backlog dir (allow downstream users to override) -----
# Defaults to "tasks" relative to PWD (preserves existing behavior).
# Override per-call: TASKSPEC_BACKLOG_DIR=path/to/backlog command...
: "${TASKSPEC_BACKLOG_DIR:=tasks}"
export TASKSPEC_BACKLOG_DIR

# ----- --version handler -----
# Usage at the top of arg parsing:
#   ts_version_flag "$@"
# Call ts_version_flag BEFORE the per-script flag loop so authors can always
# discover the version without learning per-script syntax.
ts_version_flag() {
  if [[ "${1:-}" == "--version" ]]; then
    echo "task-spec v$TASKSPEC_VERSION"
    exit 0
  fi
  return 0
}

# ----- Error helper -----
ts_die() {
  echo "ERROR: $*" >&2
  exit 1
}

# ----- Safe temp-target preparation (symlink-attack hardening) -----
# The in-place editors write to a predictable sibling temp path ("<file>.tmp.$$"
# / ".fmset.$$") then mv it over the original. A shell redirect `> "$tmp"`
# FOLLOWS a pre-existing symlink at that path, which an attacker with write
# access to the directory could plant to clobber an arbitrary target. Call this
# immediately before redirecting into a predictable temp path: it removes any
# pre-existing file/symlink at that path so the redirect creates a fresh regular
# file. $1 = the temp path. Returns 0 (best-effort rm; a still-present path is
# caught by the caller's post-write checks).
ts_prepare_tmp() {
  rm -f "$1" 2>/dev/null
  return 0
}

# ===========================================================================
# B2 — key-optional HMAC sign-off envelope (v2.2)
# ===========================================================================
# These helpers implement the cryptographic floor for the sign-off envelope.
# They are intentionally key-optional and crypto-binary-optional: a fresh
# clone with no key, or a minimal CI image with no openssl, MUST degrade to
# structural-only (Tier 2) rather than hard-fail. See the three-tier contract
# in references/concepts/signed-off.md.
#
# Portability floor (REQUIREMENT 3):
#   ts_sha256        — sha256 over stdin; detects openssl > shasum -a 256 > sha256sum.
#                      Prints the hex digest. Returns 0 on success; prints the
#                      sentinel TS_CRYPTO_UNAVAILABLE and returns 0 (callers treat
#                      that string as "no crypto" and fall to Tier 2) when none
#                      of the three providers exists.
#   ts_hmac_sha256   — HMAC-SHA256(key, message). Prefers `openssl dgst -sha256
#                      -hmac KEY`; if only a plain sha256 tool is present,
#                      constructs HMAC manually via the RFC-2104 ipad/opad
#                      construction (block size 64) so the result is byte-for-byte
#                      identical to openssl. Emits TS_CRYPTO_UNAVAILABLE when no
#                      sha256 provider exists.
#
# All HMAC inputs treat the key as LITERAL STRING BYTES (matching openssl's
# `-hmac KEY` default), NOT as decoded hex. This keeps the manual and openssl
# paths interchangeable.

TS_CRYPTO_UNAVAILABLE="TS_CRYPTO_UNAVAILABLE"

# Detect a sha256 provider once. Echoes one of: openssl|shasum|sha256sum|none
# Each candidate is PROBE-RUN (not just `command -v`) so a masked/stub binary
# that is on PATH but non-functional is treated as absent — this is what makes
# PATH-masking the three tools degrade cleanly to the sentinel (Tier 2) instead
# of detecting a tool that then fails at runtime.
ts_sha256_provider() {
  local probe="ts-probe"
  if command -v openssl >/dev/null 2>&1 \
     && printf '%s' "$probe" | openssl dgst -sha256 >/dev/null 2>&1; then
    echo openssl; return 0
  fi
  if command -v shasum >/dev/null 2>&1 \
     && printf '%s' "$probe" | shasum -a 256 >/dev/null 2>&1; then
    echo shasum; return 0
  fi
  if command -v sha256sum >/dev/null 2>&1 \
     && printf '%s' "$probe" | sha256sum >/dev/null 2>&1; then
    echo sha256sum; return 0
  fi
  echo none
}

# sha256 hex of stdin. Never hard-fails; emits the sentinel when no provider.
ts_sha256() {
  local provider
  provider="$(ts_sha256_provider)"
  case "$provider" in
    openssl)   openssl dgst -sha256 2>/dev/null | sed 's/^.*= //' ;;
    shasum)    shasum -a 256 | awk '{print $1}' ;;
    sha256sum) sha256sum | awk '{print $1}' ;;
    *)         printf '%s\n' "$TS_CRYPTO_UNAVAILABLE" ;;
  esac
}

# Internal: hex-encode stdin without requiring xxd (od is POSIX-portable).
ts__to_hex() { od -An -v -tx1 | tr -d ' \n'; }

# Internal: decode a hex string ($1) to raw bytes on stdout without xxd.
ts__from_hex() {
  local hex="$1" out="" i
  for (( i=0; i<${#hex}; i+=2 )); do out+="\\x${hex:i:2}"; done
  printf '%b' "$out"
}

# Internal: sha256 hex of stdin using the plain-tool providers only (shasum /
# sha256sum / openssl dgst). Used by the manual HMAC fallback.
ts__sha256_plain() {
  local provider
  provider="$(ts_sha256_provider)"
  case "$provider" in
    openssl)   openssl dgst -sha256 2>/dev/null | sed 's/^.*= //' ;;
    shasum)    shasum -a 256 | awk '{print $1}' ;;
    sha256sum) sha256sum | awk '{print $1}' ;;
    *)         printf '%s\n' "$TS_CRYPTO_UNAVAILABLE" ;;
  esac
}

# Internal: RFC-2104 HMAC-SHA256 built from a plain sha256 tool, byte-for-byte
# identical to `openssl dgst -sha256 -hmac KEY`. $1=key (literal bytes), reads
# the message from stdin. Block size 64. Keys >64 bytes are hashed first.
ts__hmac_manual() {
  local key="$1" msg keyhex keylen blocksize=64
  msg="$(cat)"
  keyhex=$(printf '%s' "$key" | ts__to_hex)
  keylen=$(( ${#keyhex} / 2 ))
  if (( keylen > blocksize )); then
    keyhex=$(printf '%s' "$key" | ts__sha256_plain)
    keylen=32
  fi
  local padcount=$(( (blocksize - keylen) * 2 ))
  if (( padcount > 0 )); then
    keyhex="${keyhex}$(printf '0%.0s' $(seq 1 "$padcount"))"
  fi
  local i ipad="" opad="" b
  for (( i=0; i<${#keyhex}; i+=2 )); do
    b=$(( 16#${keyhex:i:2} ))
    ipad+=$(printf '%02x' $(( b ^ 0x36 )))
    opad+=$(printf '%02x' $(( b ^ 0x5c )))
  done
  local inner
  inner=$( { ts__from_hex "$ipad"; printf '%s' "$msg"; } | ts__sha256_plain )
  { ts__from_hex "$opad"; ts__from_hex "$inner"; } | ts__sha256_plain
}

# HMAC-SHA256. $1=key (literal bytes). Reads message from stdin. Emits hex.
# Prefers openssl; otherwise constructs HMAC manually via RFC-2104. Emits the
# sentinel TS_CRYPTO_UNAVAILABLE when no sha256 provider exists.
ts_hmac_sha256() {
  local key="$1" provider
  provider="$(ts_sha256_provider)"
  case "$provider" in
    openssl)
      openssl dgst -sha256 -hmac "$key" 2>/dev/null | sed 's/^.*= //'
      ;;
    shasum|sha256sum)
      ts__hmac_manual "$key"
      ;;
    *)
      printf '%s\n' "$TS_CRYPTO_UNAVAILABLE"
      ;;
  esac
}

# ----- Sign-off key resolution (REQUIREMENT 4) -----
# Resolve the repository signing key, in priority order:
#   1. TASKSPEC_SIGNING_KEY env var:
#        - if it names a readable FILE, read the key material from it;
#        - otherwise use the value DIRECTLY as raw key material.
#   2. <git-dir>/info/taskspec-signing-key, where <git-dir> is whatever
#      `git rev-parse --git-dir` resolves to from the spec's location. In a
#      normal clone that is `.git`; in a linked WORKTREE `.git` is a file but
#      git resolves it to the per-worktree gitdir (…/.git/worktrees/<name>), so
#      the key IS found there too. The path is used only when that resolved
#      gitdir is a real directory AND the key file exists inside its info/.
#      A relative gitdir is canonicalized to absolute first.
#   3. otherwise: no key (prints nothing, returns 1 → caller degrades to Tier 2).
#
# Key material is trimmed of surrounding whitespace/newlines so a key file
# written with a trailing newline still produces a stable MAC.
# $1 (optional): a path used to locate the git dir (defaults to PWD).
ts_resolve_signing_key() {
  local anchor="${1:-$PWD}" key=""
  if [[ -n "${TASKSPEC_SIGNING_KEY:-}" ]]; then
    if [[ -f "$TASKSPEC_SIGNING_KEY" && -r "$TASKSPEC_SIGNING_KEY" ]]; then
      key="$(cat "$TASKSPEC_SIGNING_KEY")"
    else
      key="$TASKSPEC_SIGNING_KEY"
    fi
  else
    local anchor_dir git_dir
    if [[ -d "$anchor" ]]; then anchor_dir="$anchor"; else anchor_dir="$(dirname "$anchor")"; fi
    git_dir="$(cd "$anchor_dir" 2>/dev/null && git rev-parse --git-dir 2>/dev/null || true)"
    if [[ -n "$git_dir" ]]; then
      if [[ "$git_dir" != /* ]]; then
        git_dir="$(cd "$anchor_dir" 2>/dev/null && cd "$git_dir" 2>/dev/null && pwd || true)"
      fi
      if [[ -n "$git_dir" && -d "$git_dir" && -f "$git_dir/info/taskspec-signing-key" ]]; then
        key="$(cat "$git_dir/info/taskspec-signing-key")"
      fi
    fi
  fi
  key="${key#"${key%%[![:space:]]*}"}"
  key="${key%"${key##*[![:space:]]}"}"
  if [[ -z "$key" ]]; then
    return 1
  fi
  printf '%s' "$key"
  return 0
}

# keyid = first 8 hex of sha256(key). Stable short fingerprint that a stamp can
# carry so a verifier can confirm it is checking against the same key.
ts_keyid() {
  local key="$1" digest
  digest="$(printf '%s' "$key" | ts_sha256)"
  if [[ "$digest" == "$TS_CRYPTO_UNAVAILABLE" ]]; then
    printf '%s' "nokeyid"
    return 0
  fi
  printf '%s' "${digest:0:8}"
}

# ----- Injection-safe frontmatter field writer (REQUIREMENT 1 integrity) -----
# Set a frontmatter field to an EXACT value, carrying any byte literally.
# Rewrites the first existing `<name>:` line inside the frontmatter block; if the
# field is absent, injects `<name>: <value>` immediately before the closing '---'.
#
# CRITICAL: the value is passed to awk via the PROCESS ENVIRONMENT
# (ENVIRON["TS_FMSET_VAL"]), NEVER via `awk -v` and NEVER through a sed
# substitution. `awk -v` runs C-string escape processing on the assignment, so a
# value containing the two characters backslash+n would be expanded into a real
# newline and inject a forged extra frontmatter line — even though no newline
# BYTE was present. ENVIRON[] does NO escape processing, so every byte is carried
# verbatim. This is the single serialization path used to stamp signed_off,
# signed_off_by (user/CI-controlled), signed_off_at, and signed_off_sig. A value
# containing `|`, `&`, `\`, a literal `:`, a backslash-n sequence, a tab, or any
# other byte is written verbatim. Only frontmatter (the region between the first
# two '---' lines) is touched; a body line that happens to start with `<name>:`
# is never rewritten.
#
# $1=file  $2=field name  $3=field value.  Edits the file in place (temp+mv,
# portable across BSD and GNU). The file is left UNTOUCHED on any failure.
# Returns:
#   0  the field was written (rewritten in place or injected before closing ---)
#   2  the value contains a real newline or carriage-return BYTE — REJECTED. A
#      YAML scalar written this way must be single-line. (Belt-and-suspenders:
#      ENVIRON[] already prevents escape-driven injection; this guard rejects a
#      genuine embedded newline byte before it reaches the file.)
#   1  no writable frontmatter found — the file has no closing '---', so there is
#      nowhere to inject. The caller MUST hard-fail rather than HMAC a spec whose
#      field was silently not written.
# The field NAME ($2) is script-controlled (never user input) and is passed via
# -v because it is used as a regex anchor; the VALUE is the untrusted channel.
ts_set_frontmatter_field() {
  local file="$1" fname="$2" fval="$3" tmp rc
  case "$fval" in
    *$'\n'*|*$'\r'*)
      echo "ts_set_frontmatter_field: refusing multi-line value for '$fname' (newline/CR not allowed in a frontmatter scalar)" >&2
      return 2
      ;;
  esac
  tmp="${file}.fmset.$$"
  ts_prepare_tmp "$tmp"
  # awk exits 0 if the field was written, 3 if the frontmatter had no closing
  # '---' (field could not be placed). Any other awk failure also leaves the
  # original untouched. The value comes from ENVIRON (verbatim); only fname is -v.
  TS_FMSET_VAL="$fval" awk -v fname="$fname" '
    BEGIN { fm_count=0; in_fm=0; done=0; fval=ENVIRON["TS_FMSET_VAL"] }
    /^---[[:space:]]*$/ {
      fm_count++
      if (fm_count == 1) { in_fm=1; print; next }
      if (fm_count == 2) {
        if (in_fm == 1 && done == 0) { print fname ": " fval; done=1 }
        in_fm=0
        print
        next
      }
      print; next
    }
    {
      if (in_fm == 1 && done == 0 && $0 ~ ("^" fname ":")) {
        print fname ": " fval
        done=1
        next
      }
      print
    }
    END { if (done == 0) exit 3 }
  ' "$file" > "$tmp"
  rc=$?
  if [[ $rc -ne 0 ]]; then
    rm -f "$tmp"
    [[ $rc -eq 3 ]] && echo "ts_set_frontmatter_field: no closing '---' frontmatter delimiter in $file; '$fname' not written" >&2
    return 1
  fi
  mv "$tmp" "$file"
}

# ----- Canonical sign-off payload (REQUIREMENT 1 boundary) -----
# Extract the spec BODY = everything AFTER the closing '---' of the frontmatter.
# Line 1 is the opening '---'; the body starts after the SECOND '---'.
ts_spec_body() {
  local file="$1"
  awk '
    BEGIN { fm=0 }
    NR==1 && /^---[[:space:]]*$/ { fm=1; next }
    fm==1 && /^---[[:space:]]*$/ { fm=2; next }
    fm==2 { print }
  ' "$file"
}

# sha256 hex of the spec body. Emits the sentinel when no crypto provider.
ts_body_digest() {
  ts_spec_body "$1" | ts_sha256
}

# Build the CANONICAL signed payload: newline-joined, fixed field order:
#   id=<id>
#   body_digest=<sha256 hex of body>
#   signed_off=<value>
#   signed_off_by=<value>
#   signed_off_at=<value>
# CRITICAL BOUNDARY: this reads the three signed_off* VALUES as they appear in
# the frontmatter and EXCLUDES the signed_off_sig line itself. It does NOT
# depend on frontmatter line ordering — each field is grepped by name. This is
# what makes the MAC verify on the very next read after stamping.
# $1=file. Echoes the payload (no trailing newline) on stdout.
ts_signoff_payload() {
  local file="$1"
  local id body_digest so so_by so_at
  id=$(grep -m1 '^id:' "$file" | sed -E 's/^id:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')
  body_digest=$(ts_body_digest "$file")
  so=$(grep -m1 '^signed_off:' "$file" | sed -E 's/^signed_off:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')
  so_by=$(grep -m1 '^signed_off_by:' "$file" | sed -E 's/^signed_off_by:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')
  so_at=$(grep -m1 '^signed_off_at:' "$file" | sed -E 's/^signed_off_at:[[:space:]]*//' | sed -E 's/[[:space:]]*$//')
  printf 'id=%s\nbody_digest=%s\nsigned_off=%s\nsigned_off_by=%s\nsigned_off_at=%s' \
    "$id" "$body_digest" "$so" "$so_by" "$so_at"
}

# Compute the full signed_off_sig field value for a spec, given a key.
# Format: hmac-sha256-v1:<keyid>:<hex>
# Echoes the value; returns 1 (and echoes nothing) if crypto is unavailable.
ts_compute_signoff_sig() {
  local file="$1" key="$2" payload keyid mac
  payload="$(ts_signoff_payload "$file")"
  if [[ "$payload" == *"$TS_CRYPTO_UNAVAILABLE"* ]]; then
    return 1
  fi
  mac="$(printf '%s' "$payload" | ts_hmac_sha256 "$key")"
  if [[ "$mac" == "$TS_CRYPTO_UNAVAILABLE" || -z "$mac" ]]; then
    return 1
  fi
  keyid="$(ts_keyid "$key")"
  printf 'hmac-sha256-v1:%s:%s' "$keyid" "$mac"
  return 0
}

# ----- bash 4+ guard -----
# Some aux scripts (lint-backlog.sh, query-metrics.sh) use associative arrays
# (declare -A) and mapfile/readarray, which require bash 4+. macOS ships the
# GPL-2 system bash 3.2.57 at /bin/bash, where these constructs hard-fail with
# "declare: -A: invalid option". The core gate path (validate-task-spec.sh,
# safe-to-delegate.sh, run-task-spec.sh, _lib.sh) stays bash-3.2-clean; only
# these two aux scripts need this guard.
#
# Behavior:
#   - If the running bash is already 4+, return silently.
#   - Otherwise, look for a bash 4+ on PATH and re-exec the calling script
#     under it (preserving "$@"). $TS_BASH4_REEXEC guards against re-exec loops.
#   - If no bash 4+ is found, print a one-line remediation and exit 3.
ts_require_bash4() {
  if [[ "${BASH_VERSINFO[0]:-0}" -ge 4 ]]; then
    return 0
  fi

  if [[ -n "${TS_BASH4_REEXEC:-}" ]]; then
    echo "task-spec: requires bash 4+; on macOS run: brew install bash, then re-run this script with that bash" >&2
    exit 3
  fi

  local candidate candidate_major
  candidate="$(command -v bash 2>/dev/null || true)"
  if [[ -n "$candidate" ]]; then
    candidate_major="$("$candidate" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo 0)"
    if [[ "$candidate_major" -ge 4 && "$candidate" != "${BASH:-}" ]]; then
      export TS_BASH4_REEXEC=1
      exec "$candidate" "${BASH_SOURCE[1]:-$0}" "$@"
    fi
  fi

  echo "task-spec: requires bash 4+; on macOS run: brew install bash, then re-run this script with that bash" >&2
  exit 3
}
