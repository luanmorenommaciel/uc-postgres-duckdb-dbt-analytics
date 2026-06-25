#!/usr/bin/env bash
# detect-code-light.sh — Classify a repo as CODE_LIGHT or CODE_HEAVY.
#
# Used by SKILL.md Phase 0 to advise the user when the repo doesn't look
# like a code-heavy target for tech-stack scaffolding. ADVISORY ONLY —
# never blocks, never exits non-zero on classification.
#
# Contract:
#   INPUT  env  : TARGET_REPO  (default: current dir)
#   OUTPUT stdout: exactly one token — CODE_LIGHT or CODE_HEAVY
#   OUTPUT stderr: human-readable stats line + JSON line for machine parsing
#   EXIT       : 0 always (classifier failure → fail open to CODE_HEAVY)
#
# Threshold: a repo is CODE_LIGHT when code_files / (code_files + content_files) < 0.30.
# Empty repos classify as CODE_LIGHT (defensive — don't scaffold over nothing).

set -uo pipefail

TARGET_REPO="${TARGET_REPO:-.}"

if ! command -v python3 >/dev/null 2>&1; then
  echo "WARN: python3 not found — defaulting to CODE_HEAVY" >&2
  echo "CODE_HEAVY"
  exit 0
fi

if [[ ! -d "${TARGET_REPO}" ]]; then
  echo "WARN: TARGET_REPO not a directory (${TARGET_REPO}) — defaulting to CODE_HEAVY" >&2
  echo "CODE_HEAVY"
  exit 0
fi

python3 - "${TARGET_REPO}" <<'PYEOF'
import json, sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()

# Tunable knobs — see header for rationale.
THRESHOLD = 0.30
MAX_FILES = 50_000
MAX_DEPTH = 12

CODE_EXTS = {
    ".py", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs",
    ".go", ".rs", ".java", ".kt", ".scala", ".rb", ".php",
    ".c", ".cc", ".cpp", ".h", ".hpp", ".swift",
}
CONTENT_EXTS = {
    ".md", ".markdown", ".rst", ".txt", ".org",
    ".yaml", ".yml", ".json", ".toml", ".ini",
}
EXCLUDE_DIRS = {
    ".git", ".hg", ".svn", "node_modules", ".venv", "venv", "env",
    "__pycache__", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    "dist", "build", "target", "out", ".next", ".turbo", ".cache",
    "coverage", ".coverage", ".tox", ".nox",
}

code = content = other = 0
total = 0
truncated = False
seen_inodes = set()

def walk(path, depth=0):
    global code, content, other, total, truncated
    if depth > MAX_DEPTH or total >= MAX_FILES:
        truncated = True
        return
    try:
        entries = list(path.iterdir())
    except (PermissionError, OSError):
        return
    for entry in entries:
        if total >= MAX_FILES:
            truncated = True
            return
        try:
            if entry.is_symlink():
                continue
            if entry.is_dir():
                if entry.name in EXCLUDE_DIRS or entry.name.startswith("."):
                    if entry.name not in {".claude", ".github"}:
                        continue
                try:
                    st = entry.stat()
                    if st.st_ino in seen_inodes:
                        continue
                    seen_inodes.add(st.st_ino)
                except OSError:
                    continue
                walk(entry, depth + 1)
            elif entry.is_file():
                total += 1
                ext = entry.suffix.lower()
                if ext in CODE_EXTS:
                    code += 1
                elif ext in CONTENT_EXTS:
                    content += 1
                else:
                    other += 1
        except (PermissionError, OSError):
            continue

walk(root)

denom = code + content
if denom == 0:
    classification = "CODE_LIGHT"
    code_pct = 0.0
else:
    code_pct = code / denom
    classification = "CODE_LIGHT" if code_pct < THRESHOLD else "CODE_HEAVY"

stats = (
    f"code: {code} files ({code_pct*100:.0f}%) | "
    f"content: {content} files ({(content/denom*100 if denom else 0):.0f}%) | "
    f"other: {other} files"
)
print(stats, file=sys.stderr)
print(json.dumps({
    "classification": classification,
    "code_files": code,
    "content_files": content,
    "other_files": other,
    "code_pct": round(code_pct, 4),
    "threshold": THRESHOLD,
    "truncated": truncated,
    "target_repo": str(root),
}), file=sys.stderr)
print(classification)
PYEOF
