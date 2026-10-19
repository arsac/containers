# syntax=docker/dockerfile:1

# Upstream has no tagged releases; Renovate tracks main HEAD via the bake
# file, which overrides this default at build time. Kept in sync here so
# plain `docker build` (build-push-local.sh) builds the same code as CI.
ARG VERSION="86ebf379536cf2b3a07c2007798db02894c51f21"

FROM mirror.gcr.io/library/python:3.12.15-slim-bookworm AS builder

# global-scope ARGs are not visible inside stages without re-declaration
ARG VERSION

ENV UV_LINK_MODE=copy \
    UV_HTTP_TIMEOUT=300

WORKDIR /app

# pipefail: a truncated tarball must fail the build, not extract garbage
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fetch the source at the pinned commit (tarball, no clone)
RUN curl -fsSL "https://github.com/rldiao/mealie-mcp-server/archive/${VERSION}.tar.gz" \
    | tar -xz --strip-components=1

# uv resolves the dependency graph from upstream's uv.lock (frozen): the
# image ships exactly the versions upstream tested, including their mcp<2
# cap, instead of a loose pip resolution of a hand-mirrored list
COPY --from=ghcr.io/astral-sh/uv:0.13.1 /uv /usr/local/bin/uv
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev

FROM mirror.gcr.io/library/python:3.12.15-slim-bookworm

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY --from=builder /app/src /app/src

ENV PATH="/app/.venv/bin:$PATH"

# stdio MCP server - toolhive's proxyrunner attaches stdin/stdout and
# translates to streamable-HTTP for downstream clients. MCP_TRANSPORT can
# switch to sse/streamable-http (MCP_PORT, default 8765).
USER 65534:65534

CMD ["python", "src/server.py"]
