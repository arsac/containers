# Pin to upstream commit — rldiao/mealie-mcp-server has no tagged releases.
ARG VERSION="f7a2a5e21e68e223629393a5ad16f55dca6ea577"

FROM python:3.12-slim-bookworm

ARG VERSION

ENV PYTHONFAULTHANDLER=1 \
    PYTHONHASHSEED=random \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Fetch the source at the pinned commit (no clone, just the tarball).
RUN curl -fsSL "https://github.com/rldiao/mealie-mcp-server/archive/${VERSION}.tar.gz" \
    | tar -xz --strip-components=1

# Install Python deps — these mirror upstream pyproject.toml exactly.
# Pinned via the SHA above; bumping the SHA triggers a rebuild and re-resolves.
RUN pip install --no-cache-dir \
        "httpx>=0.28.1" \
        "mcp[cli]>=1.12.0" \
        "pydantic>=2.11.3" \
        "python-dotenv>=1.1.0"

# Drop privileges. 65534 (nogroup/nobody) is the repo convention.
USER 65534:65534

# Stdio MCP server — toolhive's proxyrunner attaches stdin/stdout to translate
# to streamable-HTTP for downstream clients.
CMD ["python", "/app/src/server.py"]
