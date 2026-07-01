# syntax=docker/dockerfile:1

# Build stage runs natively on the build host for every target platform: the
# output is an arch-independent JS bundle, so nothing here runs under QEMU.
FROM --platform=$BUILDPLATFORM oven/bun:1.2-slim AS build

# Pinned upstream Honcho release tag (renovate-annotated in docker-bake.hcl).
ARG HONCHO_REF="v3.0.11"

WORKDIR /app

# Fetch the upstream monorepo tarball at the pinned tag. No sha256 pin: GitHub's
# on-the-fly archive tarballs are NOT byte-stable — the same tag/commit yields
# different bytes over time, so a pinned checksum breaks the build on
# regeneration. Integrity here is HTTPS + the pinned release tag (the same
# approach every other app in this repo uses). Remote tars are not auto-extracted,
# so extract mcp/ ourselves (tarball root honcho-<version>/, target .../mcp).
ADD https://github.com/plastic-labs/honcho/archive/refs/tags/${HONCHO_REF}.tar.gz /tmp/honcho.tgz
RUN tar -xz --strip-components=2 -f /tmp/honcho.tgz "honcho-${HONCHO_REF#v}/mcp" \
 && rm /tmp/honcho.tgz src/index.ts

# Overlay our authored files over upstream (entry + our manifest/lock/tsconfig).
COPY package.json bun.lock tsconfig.json ./
COPY src/http.ts ./src/http.ts

# Reproducible install → type-check gate (fails on upstream signature drift) →
# bundle to a single ESM file (.mjs so Node runs it as ESM: top-level await).
RUN bun install --frozen-lockfile \
 && bunx tsc --noEmit \
 && bun build src/http.ts --target node --outfile dist/http.mjs

# Run stage is per-$TARGETPLATFORM; it only copies the arch-independent bundle.
FROM node:24-slim
WORKDIR /app
COPY --from=build /app/dist/http.mjs ./dist/http.mjs
# Streamable HTTP listener (stateless); override with PORT (default 8080).
EXPOSE 8080
# Non-root nobody (repo convention); server writes nothing → read-only-fs safe.
USER 65534:65534
ENTRYPOINT ["node", "/app/dist/http.mjs"]
