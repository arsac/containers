#!/usr/bin/env bash
# Fetch upstream kserve at the pinned ref and apply our downstream patches,
# producing the build context for kserve's huggingface_server.Dockerfile.
#
# This replaces the arsac/kserve fork: instead of maintaining the whole repo on
# a branch, we carry a small patch and pin the upstream commit. Same idea as
# apps/subgen (clone @ ref + git apply patches/), adapted because kserve builds
# from its OWN multi-stage Dockerfile rather than one we own.
#
# Run this before `docker buildx bake` — bake's context points at .src/python.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KSERVE_REPO="${KSERVE_REPO:-https://github.com/kserve/kserve.git}"
KSERVE_REF="${KSERVE_REF:?set KSERVE_REF to the pinned upstream commit}"
src="${SRC_DIR:-$here/.src}"

# Shallow fetch the single pinned commit (GitHub allows fetch-by-SHA). Avoids a
# full clone of a large repo in CI.
rm -rf "$src"
git init -q "$src"
git -C "$src" remote add origin "$KSERVE_REPO"
git -C "$src" fetch -q --depth 1 origin "$KSERVE_REF"
git -C "$src" checkout -q FETCH_HEAD

shopt -s nullglob
for p in "$here"/patches/*.patch; do
  echo "Applying $(basename "$p")"
  # No 3-way fallback: a hunk that doesn't match fails the build loudly, so an
  # upstream refactor surfaces here instead of in a broken image.
  git -C "$src" apply "$p"
done

echo "Prepared kserve build context: $src/python (ref ${KSERVE_REF})"
