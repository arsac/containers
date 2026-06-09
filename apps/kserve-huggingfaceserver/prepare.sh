#!/usr/bin/env bash
# Fetch upstream kserve at the pinned ref and apply our downstream patches,
# producing the build context for kserve's huggingface_server.Dockerfile.
#
# This replaces the arsac/kserve fork: instead of maintaining the whole repo on
# a branch, we carry a ~90-line patch and pin the upstream commit. Same pattern
# as apps/subgen (clone @ ref + git apply patches/), adapted because kserve
# builds from its OWN multi-stage Dockerfile rather than one we own.
#
# Run this before `docker buildx bake` — bake's context points at .src/python.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KSERVE_REPO="${KSERVE_REPO:-https://github.com/kserve/kserve.git}"
KSERVE_REF="${KSERVE_REF:?set KSERVE_REF to the pinned upstream commit}"
src="${SRC_DIR:-$here/.src}"

rm -rf "$src"
git clone --quiet "$KSERVE_REPO" "$src"
git -C "$src" checkout --quiet "$KSERVE_REF"

shopt -s nullglob
for p in "$here"/patches/*.patch; do
  echo "Applying $(basename "$p")"
  # --verbose + no fallback: a hunk that doesn't match fails the build loudly,
  # so an upstream refactor surfaces here instead of in a broken image.
  git -C "$src" apply --verbose "$p"
done

echo "Prepared kserve build context: $src/python (ref ${KSERVE_REF})"
