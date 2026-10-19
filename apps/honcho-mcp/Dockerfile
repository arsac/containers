# syntax=docker/dockerfile:1

# Mirror of upstream's mcp/Dockerfile (plastic-labs/honcho): the entry, lock
# and config ship in the tarball - no authored code in this repo. House
# packaging on top: pinned base, source fetched at the renovate-tracked tag,
# 65534 runtime user, multi-arch via the bake file.
ARG VERSION="v3.3.0"

FROM mirror.gcr.io/oven/bun:1.2.23

# global-scope ARGs are not visible inside stages without re-declaration
ARG VERSION

WORKDIR /app

# Fetch the monorepo tarball at the pinned tag and extract the mcp workspace
ADD https://github.com/plastic-labs/honcho/archive/refs/tags/${VERSION}.tar.gz /tmp/honcho.tgz
RUN tar -xz --strip-components=2 -f /tmp/honcho.tgz "honcho-${VERSION#v}/mcp" \
 && rm /tmp/honcho.tgz

# Install as root (world-readable node_modules); the server is stateless and
# writes nothing, so the 65534 runtime user only needs read access
RUN bun install --frozen-lockfile --production

# PORT default matches the previously published image; override per deployment
ENV PORT=8080 \
    HOST=0.0.0.0

EXPOSE 8080

USER 65534:65534

CMD ["bun", "src/http.ts"]
