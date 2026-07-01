# syntax=docker/dockerfile:1

# Build stage runs natively on the build host for every target platform: the
# output is an arch-independent JS bundle, so nothing here runs under QEMU.
FROM --platform=$BUILDPLATFORM oven/bun:1.2-slim AS build

# Pinned upstream Honcho release + release-tarball checksum. Bump together
# (docker-bake.hcl carries the renovate annotation for HONCHO_REF).
ARG HONCHO_REF="v3.0.11"
ARG HONCHO_SHA256="be832a84f8bbdddcfb38f5dd1777414512d9be6a576e860a96a2371a00929eab"

WORKDIR /app

# Fetch the upstream monorepo tarball at the pinned tag; --checksum fails the
# build on any drift/MITM. Remote tars are not auto-extracted, so extract mcp/
# ourselves (tarball root is honcho-<version>/, target honcho-<version>/mcp).
ADD --checksum=sha256:${HONCHO_SHA256} \
    https://github.com/plastic-labs/honcho/archive/refs/tags/${HONCHO_REF}.tar.gz /tmp/honcho.tgz
RUN tar -xz --strip-components=2 -f /tmp/honcho.tgz "honcho-${HONCHO_REF#v}/mcp" \
 && rm /tmp/honcho.tgz src/index.ts

# Overlay our authored files over upstream (entry + our manifest/lock/tsconfig).
COPY package.json bun.lock tsconfig.json ./
COPY src/stdio.ts ./src/stdio.ts

# Reproducible install → type-check gate (fails on upstream signature drift) →
# bundle to a single ESM file (.mjs so Node runs it as ESM: top-level await).
RUN bun install --frozen-lockfile \
 && bunx tsc --noEmit \
 && bun build src/stdio.ts --target node --outfile dist/stdio.mjs

# Run stage is per-$TARGETPLATFORM; it only copies the arch-independent bundle.
FROM node:22-slim
WORKDIR /app
COPY --from=build /app/dist/stdio.mjs ./dist/stdio.mjs
# Non-root nobody (repo convention); server writes nothing → read-only-fs safe.
USER 65534:65534
ENTRYPOINT ["node", "/app/dist/stdio.mjs"]
