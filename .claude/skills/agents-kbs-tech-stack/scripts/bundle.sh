#!/usr/bin/env bash
# bundle.sh — Produce a portable tarball of the agents-kbs-tech-stack skill.
#
# IMPORTANT: this skill symlinks its KB templates from agents-kbs-fleet
# (templates/kb-shared → ../../agents-kbs-fleet/templates/kb). The bundle
# resolves and inlines those templates so the unpacked tarball is fully
# self-contained — no v1 skill required at the target.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SKILL_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
SKILL_NAME="agents-kbs-tech-stack"
VERSION="${VERSION:-0.3.0}"

DIST="${SKILL_ROOT}/dist"
mkdir -p "${DIST}"

TARBALL="${DIST}/${SKILL_NAME}-v${VERSION}.tar.gz"

# Stage the skill into a temp dir with the symlink replaced by a real copy.
STAGE="$(mktemp -d)"
trap "rm -rf '${STAGE}'" EXIT

cp -R "${SKILL_ROOT}" "${STAGE}/${SKILL_NAME}"
# Replace symlink with concrete copy
rm "${STAGE}/${SKILL_NAME}/templates/kb-shared"
cp -R "${SKILL_ROOT}/templates/kb-shared/" "${STAGE}/${SKILL_NAME}/templates/kb-shared/"

# Drop dist/ from the staged copy
rm -rf "${STAGE}/${SKILL_NAME}/dist"

tar --exclude='.DS_Store' \
    --exclude='__pycache__' \
    --exclude='*.swp' \
    -czf "${TARBALL}" \
    -C "${STAGE}" \
    "${SKILL_NAME}"

SIZE_BYTES=$(stat -f%z "${TARBALL}" 2>/dev/null || stat -c%s "${TARBALL}")
SIZE_KB=$((SIZE_BYTES / 1024))

echo "✓ Bundled ${SKILL_NAME} v${VERSION}"
echo "  Artifact : ${TARBALL}"
echo "  Size     : ${SIZE_KB} KB"
if (( SIZE_KB > 100 )); then
  echo "  WARN     : bundle exceeds 100 KB — investigate before publishing." >&2
fi
echo ""
echo "Install in another repo:"
echo "  tar -xzf ${SKILL_NAME}-v${VERSION}.tar.gz -C <target-repo>/.claude/skills/"
echo ""
echo "Install globally (symlink):"
echo "  ln -s ${SKILL_ROOT} ~/.claude/skills/${SKILL_NAME}"
