# ComfyUI UI/Backend Split Image Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new `comfyui-ui` image to the `arsac/containers` repo that serves the ComfyUI React frontend as static files from nginx, with reverse-proxying and response caching so it can fulfill browser requests (GET `/`, websocket upgrades, `GET /object_info`, etc.) even when the GPU-backed ComfyUI backend pod is scaled to 0.

**Architecture:** A new sibling app `apps/comfyui-ui/` that produces `ghcr.io/arsac/comfyui-ui:rolling` via the existing Renovate + GitHub Actions build pipeline. The image is a multi-stage build: a small `fetch` stage downloads `dist.zip` from the `Comfy-Org/ComfyUI_frontend` GitHub release that matches the `comfyui-frontend-package` version pinned by the current ComfyUI backend (`apps/comfyui/docker-bake.hcl` `VERSION`). The `runtime` stage is `nginx:alpine` with a config that serves static assets directly, reverse-proxies dynamic endpoints to a configurable backend service, and uses `proxy_cache` with `proxy_cache_use_stale` for the load-time metadata endpoints (`/object_info`, `/embeddings`, `/extensions`, `/system_stats`) so the UI remains functional after first successful load even when the backend is scaled to 0.

**Tech Stack:**
- `nginx:alpine` base image (pinned by Renovate per `.renovaterc.json5` rules)
- Docker BuildKit with `docker buildx bake` (matches repo's existing pipeline)
- Renovate custom manager that reads `# renovate: datasource=... depName=...` annotations in `docker-bake.hcl`
- `bats` for shell script tests if needed; static file integrity verified with curl/grep at build-time

**Scope boundary:** This plan covers ONLY the new image in `arsac/containers`. The consuming home-ops manifests (Deployment, Service, HTTPRoute, ScaledObject) are a separate follow-up plan in the `arsac/home-ops` repo. This plan produces and publishes the image; downstream deployment is out of scope.

---

## File Map

| Action | Path | Purpose |
| ------ | ---- | ------- |
| Create | `apps/comfyui-ui/Dockerfile` | Multi-stage build: fetch dist.zip, produce nginx runtime image |
| Create | `apps/comfyui-ui/docker-bake.hcl` | Bake config with Renovate-tracked version variables |
| Create | `apps/comfyui-ui/nginx.conf` | Nginx server config: static serving, reverse proxy, caching |
| Create | `apps/comfyui-ui/test/test-build.bats` | Build-and-verify test asserting image structure is correct |
| Create | `apps/comfyui-ui/README.md` | Short usage doc: env vars, volumes, expected backend service |
| Modify | `.renovaterc.json5` | Add a packageRule grouping `comfyanonymous/ComfyUI` updates across both `apps/comfyui/` and `apps/comfyui-ui/` so they bump together |

---

## Prerequisite Context

**Before starting any task, read these files in this order to understand the repo's conventions:**

1. `/Users/mailoarsac/Development/personal/containers/README.md` — top-level repo conventions
2. `/Users/mailoarsac/Development/personal/containers/apps/comfyui/docker-bake.hcl` — the pattern you are copying (variables, targets, Renovate annotations)
3. `/Users/mailoarsac/Development/personal/containers/apps/comfyui/Dockerfile` — how the comfyui backend is built; the frontend version you need MUST match
4. `/Users/mailoarsac/Development/personal/containers/apps/whisper-asr-webservice/Dockerfile` — a simpler single-stage sibling that confirms the minimum pattern
5. `/Users/mailoarsac/Development/personal/containers/.github/workflows/image-builder.yaml` — shows that the build matrix expects `image` and `image-devel` as the ONLY bake target names. Your `docker-bake.hcl` must expose a `target "image"` that produces the runtime image
6. `/Users/mailoarsac/Development/personal/containers/.renovaterc.json5` — how Renovate custom managers extract versions from `docker-bake.hcl`

**Non-obvious constraint from step 5:** You CANNOT create a new bake target with a custom name like `image-ui` and expect the workflow to build it automatically. The workflow hardcodes the target name at `image-builder.yaml:200` as `image` (or `image-devel` for the `devel` variant). If you want a separate image artifact, you MUST put it in a separate `apps/<name>/` directory with its own `docker-bake.hcl` exposing `target "image"`. That is why this plan creates `apps/comfyui-ui/` as a sibling, not a new target inside `apps/comfyui/`.

**Version-coupling context:** The ComfyUI Python backend (`apps/comfyui/docker-bake.hcl` `VERSION = "v0.14.2"`) pins a specific `comfyui-frontend-package` version in its upstream `requirements.txt`. For `v0.14.2`, that is `comfyui-frontend-package==1.38.14`, which corresponds to git tag `v1.38.14` on `Comfy-Org/ComfyUI_frontend`. The new `comfyui-ui` image MUST serve the frontend static files from that exact version or the UI's API contract with the backend will drift (undefined errors, missing nodes, websocket message format mismatches). This plan handles version coupling by having `comfyui-ui/docker-bake.hcl` declare its OWN `FRONTEND_VERSION` variable tracked by Renovate, plus a renovate packageRule that groups `comfyui` and `comfyui-ui` backend bumps so the maintainer remembers to bump `FRONTEND_VERSION` alongside `COMFYUI_VERSION`. Fully automated cross-reference (reading `requirements.txt` at build time) is rejected as too magical for a reviewer to understand.

---

### Task 1: Create the new app directory with a minimal Dockerfile

**Files:**

- Create: `apps/comfyui-ui/Dockerfile`
- Create: `apps/comfyui-ui/docker-bake.hcl`

Start with the smallest working Dockerfile and bake file that the existing workflow can build. Get the scaffold right before adding nginx config, caching, or tests.

- [ ] **Step 1: Create `apps/comfyui-ui/docker-bake.hcl`**

Create the file with this exact content:

```hcl
target "docker-metadata-action" {}

variable "APP" {
  default = "comfyui-ui"
}

# This is the ComfyUI backend version that this UI image is paired with.
# When this changes, FRONTEND_VERSION below must be updated to the
# comfyui-frontend-package version that ComfyUI's requirements.txt pins
# for this ComfyUI tag. The .renovaterc.json5 packageRule groups these
# together so Renovate bumps both in one PR and a human can verify.
variable "COMFYUI_VERSION" {
  // renovate: datasource=github-releases depName=comfyanonymous/ComfyUI
  default = "v0.14.2"
}

# ComfyUI frontend release that matches COMFYUI_VERSION's pinned
# comfyui-frontend-package. For ComfyUI v0.14.2 this is v1.38.14.
# Verify by reading:
#   https://raw.githubusercontent.com/comfyanonymous/ComfyUI/<COMFYUI_VERSION>/requirements.txt
# and finding the `comfyui-frontend-package==X.Y.Z` line.
variable "FRONTEND_VERSION" {
  // renovate: datasource=github-releases depName=Comfy-Org/ComfyUI_frontend
  default = "v1.38.14"
}

variable "SOURCE" {
  default = "https://github.com/Comfy-Org/ComfyUI_frontend"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    FRONTEND_VERSION = "${FRONTEND_VERSION}"
    COMFYUI_VERSION  = "${COMFYUI_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${FRONTEND_VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64",
    "linux/arm64"
  ]
}
```

- [ ] **Step 2: Create `apps/comfyui-ui/Dockerfile` (scaffold only, no nginx.conf yet)**

Create the file. The fetch stage uses Alpine to download and unzip the frontend release. The runtime stage is nginx:alpine with the extracted files copied in. We'll add the nginx config in a later task.

```dockerfile
# syntax=docker/dockerfile:1.9

ARG FRONTEND_VERSION="v1.38.14"
ARG COMFYUI_VERSION="v0.14.2"

# =============================================================================
# Fetch stage - download the ComfyUI_frontend dist.zip matching FRONTEND_VERSION
# =============================================================================
FROM alpine:3.22 AS fetch

ARG FRONTEND_VERSION

RUN apk add --no-cache curl unzip ca-certificates

RUN mkdir -p /dist \
    && curl -fsSL --retry 3 --retry-delay 2 \
        -o /tmp/dist.zip \
        "https://github.com/Comfy-Org/ComfyUI_frontend/releases/download/${FRONTEND_VERSION}/dist.zip" \
    && unzip -q /tmp/dist.zip -d /dist \
    && rm /tmp/dist.zip \
    && test -f /dist/index.html \
    && echo "Fetched ComfyUI_frontend ${FRONTEND_VERSION}"

# =============================================================================
# Runtime stage - nginx serving static files (config added in later task)
# =============================================================================
FROM nginx:1.27-alpine

ARG FRONTEND_VERSION
ARG COMFYUI_VERSION

LABEL org.opencontainers.image.title="comfyui-ui"
LABEL org.opencontainers.image.description="Static ComfyUI frontend served by nginx, paired with ComfyUI ${COMFYUI_VERSION}"

COPY --from=fetch /dist /usr/share/nginx/html

EXPOSE 8188

# nginx.conf is copied in a later task. For now, the default nginx config
# (which listens on port 80) will be overridden via the per-site include.
```

- [ ] **Step 3: Verify the bake file parses**

Run from the repo root:

```bash
cd /Users/mailoarsac/Development/personal/containers/apps/comfyui-ui
docker buildx bake --print image 2>&1 | head -40
```

Expected: JSON output showing the target `image` with `FRONTEND_VERSION` and `COMFYUI_VERSION` args. No parse errors. If you see "failed to parse", fix the HCL.

- [ ] **Step 4: Verify a local build succeeds (scaffold only)**

Build the image locally (no push):

```bash
cd /Users/mailoarsac/Development/personal/containers/apps/comfyui-ui
docker buildx bake image-local
```

Expected: build succeeds, produces `comfyui-ui:v1.38.14`. Takes ~30 seconds (downloads ~22MB zip).

If the curl inside the fetch stage fails, verify the URL by running:

```bash
curl -sI https://github.com/Comfy-Org/ComfyUI_frontend/releases/download/v1.38.14/dist.zip | head -5
```

Expected: `HTTP/2 302` (redirect to S3) or `HTTP/2 200`.

- [ ] **Step 5: Verify the image has the expected file layout**

```bash
docker run --rm --entrypoint sh comfyui-ui:v1.38.14 -c \
  'ls /usr/share/nginx/html/index.html /usr/share/nginx/html/assets 2>&1'
```

Expected output: the file `/usr/share/nginx/html/index.html` exists, and `/usr/share/nginx/html/assets` is a directory listing.

- [ ] **Step 6: Commit**

```bash
cd /Users/mailoarsac/Development/personal/containers
git add apps/comfyui-ui/Dockerfile apps/comfyui-ui/docker-bake.hcl
git commit -m "feat(comfyui-ui): scaffold new image with ComfyUI frontend dist.zip"
```

---

### Task 2: Write a failing bats test for the nginx config behavior

**Files:**

- Create: `apps/comfyui-ui/test/test-build.bats`

Test-first: the test describes WHAT the image should do (serve static `/`, proxy `/prompt` to a fake upstream, cache `/object_info`). It will fail until we add the nginx.conf in Task 3.

- [ ] **Step 1: Install bats locally if not present**

```bash
which bats || brew install bats-core
```

Expected: `bats` prints a path, or brew installs it. On Linux: `sudo apt-get install bats` or download from https://github.com/bats-core/bats-core/releases.

- [ ] **Step 2: Create the test file**

Create `apps/comfyui-ui/test/test-build.bats`:

```bash
#!/usr/bin/env bats

# Build-and-verify tests for comfyui-ui image.
#
# These spin up the image with `docker run` and point it at a fake
# upstream (nginx serving static responses) so we can assert that
# proxy/cache/static behavior is correct without needing a real
# ComfyUI backend.
#
# Run from repo root:
#   bats apps/comfyui-ui/test/test-build.bats

IMAGE="comfyui-ui:test"
NETWORK="comfyui-ui-test"
UI_PORT="18188"
BACKEND_PORT="18189"

setup() {
    # Build the image once per test file run.
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        docker buildx bake \
            --file apps/comfyui-ui/docker-bake.hcl \
            --set "*.tags=${IMAGE}" \
            --set "*.output=type=docker" \
            image >&2
    fi

    # Dedicated network so ui container can reach backend by name.
    docker network inspect "$NETWORK" >/dev/null 2>&1 \
        || docker network create "$NETWORK" >/dev/null

    # Fake backend: plain nginx with canned responses for each endpoint
    # the UI will hit. This file is created fresh per test via
    # docker run --volume.
    local fake_conf
    fake_conf="$(mktemp -d)/default.conf"
    cat > "$fake_conf" <<'EOF'
server {
    listen 80 default_server;
    location = /object_info   { return 200 '{"Kitty":{}}'; default_type application/json; }
    location = /embeddings    { return 200 '[]';           default_type application/json; }
    location = /system_stats  { return 200 '{"gpu":"fake"}'; default_type application/json; }
    location = /prompt        { return 200 '{"prompt_id":"fake-1"}'; default_type application/json; }
    location = /ws            { return 101; }
    location ~ ^/view        { return 200 'fake-image-bytes'; }
    location /                { return 404 'fake-backend: no handler'; }
}
EOF
    export FAKE_CONF_DIR="$(dirname "$fake_conf")"

    docker run -d --rm --name comfyui-ui-fake-backend \
        --network "$NETWORK" \
        -v "${FAKE_CONF_DIR}:/etc/nginx/conf.d:ro" \
        -p "${BACKEND_PORT}:80" \
        nginx:1.27-alpine >/dev/null

    # Start UI pointing at fake backend via COMFYUI_BACKEND env var
    # (nginx.conf will substitute this into upstream directive).
    docker run -d --rm --name comfyui-ui-under-test \
        --network "$NETWORK" \
        -e COMFYUI_BACKEND="http://comfyui-ui-fake-backend:80" \
        -p "${UI_PORT}:8188" \
        "$IMAGE" >/dev/null

    # Wait for UI to be responsive (nginx reload takes <1s).
    local i
    for i in 1 2 3 4 5; do
        if curl -sf "http://localhost:${UI_PORT}/index.html" >/dev/null; then
            return 0
        fi
        sleep 1
    done
    echo "UI container failed to become responsive" >&2
    docker logs comfyui-ui-under-test >&2 || true
    return 1
}

teardown() {
    docker rm -f comfyui-ui-under-test comfyui-ui-fake-backend >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
    [[ -n "${FAKE_CONF_DIR:-}" ]] && rm -rf "$FAKE_CONF_DIR"
}

@test "serves index.html at / from static files" {
    run curl -sf "http://localhost:${UI_PORT}/"
    [ "$status" -eq 0 ]
    [[ "$output" == *"<title>ComfyUI</title>"* ]]
}

@test "serves static assets from /assets/ without touching backend" {
    # Stop the backend so any proxy attempt would fail.
    docker stop comfyui-ui-fake-backend >/dev/null

    # Pick any file from /assets and request it.
    local asset
    asset=$(docker run --rm --entrypoint sh "$IMAGE" \
        -c 'ls /usr/share/nginx/html/assets/ | head -1')
    run curl -sf -o /dev/null -w "%{http_code}" \
        "http://localhost:${UI_PORT}/assets/${asset}"
    [ "$output" = "200" ]
}

@test "proxies POST /prompt to backend" {
    run curl -sf -X POST -H 'Content-Type: application/json' \
        -d '{}' "http://localhost:${UI_PORT}/prompt"
    [ "$status" -eq 0 ]
    [[ "$output" == *"prompt_id"* ]]
}

@test "proxies GET /object_info to backend and adds cache header" {
    run curl -sS -i "http://localhost:${UI_PORT}/object_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kitty"* ]]
    [[ "$output" == *"X-Cache-Status:"* ]]
}

@test "GET /object_info serves stale cache when backend is down" {
    # Prime the cache with a good response.
    curl -sf "http://localhost:${UI_PORT}/object_info" >/dev/null

    # Kill the backend.
    docker stop comfyui-ui-fake-backend >/dev/null

    # Request again. Should still succeed from stale cache.
    run curl -sS "http://localhost:${UI_PORT}/object_info"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Kitty"* ]]
}

@test "GET /queue returns 502 when backend is down (not cached)" {
    docker stop comfyui-ui-fake-backend >/dev/null
    run curl -sS -o /dev/null -w "%{http_code}" \
        "http://localhost:${UI_PORT}/queue"
    [ "$output" = "502" ]
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
cd /Users/mailoarsac/Development/personal/containers
bats apps/comfyui-ui/test/test-build.bats
```

Expected: at least the `serves index.html` test passes (nginx default config serves from `/usr/share/nginx/html`), but the backend-proxy, cache, and COMFYUI_BACKEND-env-var tests all FAIL because Task 1's Dockerfile has no custom nginx.conf and the `COMFYUI_BACKEND` env var is unused. This is the expected failing state.

If the `setup()` function itself fails (image build, container start), fix that first. The tests themselves must be able to at least run.

- [ ] **Step 4: Commit the failing tests**

```bash
cd /Users/mailoarsac/Development/personal/containers
git add apps/comfyui-ui/test/test-build.bats
git commit -m "test(comfyui-ui): add bats tests for nginx proxy behavior (failing)"
```

---

### Task 3: Write the nginx config and entrypoint to make tests pass

**Files:**

- Create: `apps/comfyui-ui/nginx.conf`
- Create: `apps/comfyui-ui/docker-entrypoint.d/10-comfyui-backend.sh`
- Modify: `apps/comfyui-ui/Dockerfile`

The nginx config has four kinds of locations:
1. **Static frontend** (`/`, `/assets/*`, `/fonts/*`, etc.) — served from `/usr/share/nginx/html`, no backend touch
2. **Cacheable metadata** (`/object_info`, `/embeddings`, `/extensions`, `/system_stats`) — proxied to backend with `proxy_cache` + `proxy_cache_use_stale` so a warm cache survives backend scale-to-zero
3. **WebSocket** (`/ws`) — direct proxy with upgrade headers
4. **Dynamic API** (`/prompt`, `/queue`, `/history`, `/view`, `/upload`, `/free`, `/interrupt`, `/internal/*`, `/api/*`, `/userdata/*`) — direct proxy, no cache

The backend URL is configurable at runtime via `COMFYUI_BACKEND` env var. The official `nginx:alpine` base image supports drop-in entrypoint scripts at `/docker-entrypoint.d/` — any `.sh` file there runs before nginx starts. We use this to `envsubst` the env var into the config.

- [ ] **Step 1: Create `apps/comfyui-ui/nginx.conf`**

Create the file:

```nginx
# ComfyUI UI reverse proxy config.
#
# ${COMFYUI_BACKEND} is substituted at container startup by
# /docker-entrypoint.d/10-comfyui-backend.sh using envsubst.

proxy_cache_path /var/cache/nginx/comfyui_meta
    levels=1:2
    keys_zone=comfyui_meta:10m
    max_size=100m
    inactive=24h
    use_temp_path=off;

upstream comfyui_backend {
    server ${COMFYUI_BACKEND_HOST_PORT};
    keepalive 16;
}

server {
    listen 8188 default_server;
    listen [::]:8188 default_server;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    # --- Static frontend ---------------------------------------------------
    # Served directly, never proxied. Regex is an OR of the top-level
    # directories in the ComfyUI_frontend dist.zip plus the single
    # top-level CSS file. Anything not matched here falls through to
    # dynamic routing below.
    location ~ ^/(assets|cursor|extensions|fonts|scripts)/ {
        try_files $uri =404;
        access_log off;
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

    location = /materialdesignicons.min.css {
        try_files $uri =404;
        expires 1h;
        add_header Cache-Control "public, immutable";
    }

    location = / {
        try_files /index.html =404;
        add_header Cache-Control "no-store, must-revalidate" always;
    }

    # --- Cacheable metadata endpoints -------------------------------------
    # These are hit on page load. We cache them for 6h and serve stale
    # (for up to the inactive period above) when the backend is down.
    # This lets users load the UI even when comfyui-predictor is at 0.
    location ~ ^/(object_info|embeddings|extensions|system_stats)$ {
        proxy_pass http://comfyui_backend$request_uri;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_http_version 1.1;

        proxy_cache comfyui_meta;
        proxy_cache_valid 200 6h;
        proxy_cache_valid any 0;
        proxy_cache_use_stale error timeout updating invalid_header
                              http_500 http_502 http_503 http_504 http_429;
        proxy_cache_background_update on;
        proxy_cache_lock on;

        # The ComfyUI backend generates responses that depend on installed
        # custom nodes / models. They change only when the backend restarts,
        # so 6h validity is safe and errs on the side of freshness.

        add_header X-Cache-Status $upstream_cache_status always;
    }

    # --- WebSocket --------------------------------------------------------
    location = /ws {
        proxy_pass http://comfyui_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }

    # --- Dynamic API ------------------------------------------------------
    # All other paths (including /prompt, /queue, /history, /view,
    # /upload/image, /free, /interrupt, /internal/*, /api/*, /userdata/*)
    # are proxied straight through with no cache. When backend is down
    # these return 502; that is correct behavior — these are user-
    # initiated actions that require the backend.
    location / {
        proxy_pass http://comfyui_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # ComfyUI can upload large images / lora files via /upload/image.
        # Default nginx client_max_body_size is 1M which is too small.
        client_max_body_size 100m;

        # ComfyUI can take a while to reply to /prompt if flow-control
        # queues the request. Allow up to 5 minutes before nginx returns
        # a 504.
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
}
```

- [ ] **Step 2: Create the entrypoint script**

Create `apps/comfyui-ui/docker-entrypoint.d/10-comfyui-backend.sh`:

```bash
#!/bin/sh
# Substitute COMFYUI_BACKEND env var into nginx.conf before nginx starts.
#
# The official nginx:alpine image runs everything in
# /docker-entrypoint.d/*.sh before `nginx -g "daemon off;"`. We use that
# hook to convert the backend URL (which may be set at deploy time) into
# the host:port form nginx's upstream directive expects.

set -eu

: "${COMFYUI_BACKEND:=http://comfyui-predictor.ai.svc.cluster.local:80}"

# Strip the scheme so nginx's upstream directive gets host:port only.
# The upstream block doesn't accept a full URL.
host_port=$(printf '%s' "$COMFYUI_BACKEND" \
    | sed -E 's#^https?://##' \
    | sed -E 's#/$##')

# Default to port 80 if no port was specified.
case "$host_port" in
    *:*) : ;;  # has port
    *)   host_port="${host_port}:80" ;;
esac

echo "[comfyui-ui] Using backend: ${host_port}"

# The nginx.conf template is copied to /etc/nginx/conf.d/default.conf.
# Rewrite the ${COMFYUI_BACKEND_HOST_PORT} placeholder in place.
template=/etc/nginx/conf.d/default.conf
if ! grep -q '\${COMFYUI_BACKEND_HOST_PORT}' "$template"; then
    echo "[comfyui-ui] Template already rendered or missing placeholder; skipping" >&2
    exit 0
fi

COMFYUI_BACKEND_HOST_PORT="$host_port" \
    envsubst '${COMFYUI_BACKEND_HOST_PORT}' < "$template" > "${template}.rendered"
mv "${template}.rendered" "$template"

# Sanity check: nginx should be able to parse the rendered config.
nginx -t
```

- [ ] **Step 3: Update the Dockerfile to COPY both files and clear the default site config**

Replace `apps/comfyui-ui/Dockerfile` with:

```dockerfile
# syntax=docker/dockerfile:1.9

ARG FRONTEND_VERSION="v1.38.14"
ARG COMFYUI_VERSION="v0.14.2"

# =============================================================================
# Fetch stage - download the ComfyUI_frontend dist.zip matching FRONTEND_VERSION
# =============================================================================
FROM alpine:3.22 AS fetch

ARG FRONTEND_VERSION

RUN apk add --no-cache curl unzip ca-certificates

RUN mkdir -p /dist \
    && curl -fsSL --retry 3 --retry-delay 2 \
        -o /tmp/dist.zip \
        "https://github.com/Comfy-Org/ComfyUI_frontend/releases/download/${FRONTEND_VERSION}/dist.zip" \
    && unzip -q /tmp/dist.zip -d /dist \
    && rm /tmp/dist.zip \
    && test -f /dist/index.html \
    && echo "Fetched ComfyUI_frontend ${FRONTEND_VERSION}"

# =============================================================================
# Runtime stage
# =============================================================================
FROM nginx:1.27-alpine

ARG FRONTEND_VERSION
ARG COMFYUI_VERSION

LABEL org.opencontainers.image.title="comfyui-ui"
LABEL org.opencontainers.image.description="Static ComfyUI frontend served by nginx, paired with ComfyUI ${COMFYUI_VERSION}"

# envsubst for the entrypoint template substitution
RUN apk add --no-cache gettext \
    && rm -f /etc/nginx/conf.d/default.conf

COPY --from=fetch /dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY docker-entrypoint.d/10-comfyui-backend.sh /docker-entrypoint.d/10-comfyui-backend.sh

RUN chmod +x /docker-entrypoint.d/10-comfyui-backend.sh \
    && mkdir -p /var/cache/nginx/comfyui_meta \
    && chown -R nginx:nginx /var/cache/nginx/comfyui_meta

EXPOSE 8188
```

- [ ] **Step 4: Rebuild and re-run the tests**

```bash
cd /Users/mailoarsac/Development/personal/containers
# Remove the stale image so setup() rebuilds.
docker image rm comfyui-ui:test 2>/dev/null || true
bats apps/comfyui-ui/test/test-build.bats
```

Expected: all 6 tests pass.

If `serves static assets from /assets/ without touching backend` fails with "404", check that the dist.zip has the `assets` subdirectory (it does per earlier research). Run `docker run --rm comfyui-ui:test ls /usr/share/nginx/html/assets | head` to confirm.

If `GET /object_info serves stale cache when backend is down` fails on the second request with a 502 instead of returning the cached body, verify `proxy_cache_use_stale` includes `http_502` in your nginx.conf.

If `proxies POST /prompt to backend` fails with a 413 (Request Entity Too Large), the `client_max_body_size` directive is missing or too small.

- [ ] **Step 5: Commit**

```bash
cd /Users/mailoarsac/Development/personal/containers
git add apps/comfyui-ui/nginx.conf \
        apps/comfyui-ui/docker-entrypoint.d/10-comfyui-backend.sh \
        apps/comfyui-ui/Dockerfile
git commit -m "feat(comfyui-ui): add nginx config with static serving, proxy, and cache"
```

---

### Task 4: Add a Renovate packageRule grouping comfyui backend and ui bumps

**Files:**

- Modify: `.renovaterc.json5`

The ComfyUI backend version (`apps/comfyui/docker-bake.hcl` `VERSION`) and the paired frontend version (`apps/comfyui-ui/docker-bake.hcl` `FRONTEND_VERSION`) must move in lockstep. Renovate can't infer the frontend version from the backend, but we can at least GROUP the two PRs so a maintainer sees them together and bumps both in one review.

- [ ] **Step 1: Read the current .renovaterc.json5**

```bash
cat /Users/mailoarsac/Development/personal/containers/.renovaterc.json5
```

Note the existing structure: `extends`, `customManagers`, `customDatasources`, `packageRules`. You will add a new entry to `packageRules`.

- [ ] **Step 2: Add a packageRule grouping comfyui updates**

Edit `.renovaterc.json5`. Add this new object to the `packageRules` array, after the existing "Release Rules for Application Updates" rule:

```json5
{
  description: ["Group ComfyUI backend and UI bumps together"],
  matchPackageNames: [
    "comfyanonymous/ComfyUI",
    "Comfy-Org/ComfyUI_frontend"
  ],
  groupName: "comfyui",
  groupSlug: "comfyui",
  // Disable auto-merge for this group: a human should verify that
  // FRONTEND_VERSION in apps/comfyui-ui/docker-bake.hcl matches the
  // comfyui-frontend-package version pinned by the new ComfyUI tag's
  // requirements.txt.
  automerge: false,
},
```

The resulting file's `packageRules` array should have (in order):

1. "Release Rules for Application Updates" (unchanged)
2. "Auto-merge Application Updates" (unchanged)
3. **NEW: "Group ComfyUI backend and UI bumps together"**
4. "Allowed Ubuntu Version for Base Images" (unchanged)
5. "Allowed Alpine Version for Base Images" (unchanged)
6. "Allowed Python Version for Base Images" (unchanged)

**Important:** The auto-merge rule (rule #2) runs BEFORE your new rule. Renovate applies rules in order, and later rules override earlier ones for the same packages. Your new rule's `automerge: false` will take effect for the grouped packages.

- [ ] **Step 3: Validate the JSON5 parses**

```bash
cd /Users/mailoarsac/Development/personal/containers
# JSON5 is close enough to JSON that `jq` can't parse it, but node/python can.
# Use renovate-config-validator if available, else a minimal node parse:
npx --yes --package json5 -- json5 -c '.renovaterc.json5' >/dev/null && echo "OK"
```

Expected: `OK`. If you get a parse error, your trailing comma or quote placement is wrong.

- [ ] **Step 4: Commit**

```bash
cd /Users/mailoarsac/Development/personal/containers
git add .renovaterc.json5
git commit -m "chore(renovate): group comfyui backend and ui bumps together"
```

---

### Task 5: Add a README documenting the image's contract

**Files:**

- Create: `apps/comfyui-ui/README.md`

A short doc so a future maintainer (or the home-ops consumer plan) knows what env vars this image reads, what ports it listens on, and what backend it expects.

- [ ] **Step 1: Create the README**

Create `apps/comfyui-ui/README.md`:

```markdown
# comfyui-ui

Static ComfyUI frontend served by nginx, with reverse-proxying to a separate
GPU-backed ComfyUI backend pod. The point of this image is to decouple UI
availability from GPU availability: the UI stays reachable (and page loads
stay fast) while the backend scales from zero on demand.

## Paired versions

This image tracks **two** versions:

- `COMFYUI_VERSION` — the ComfyUI Python backend version this UI is paired
  with. Not shipped in this image; tracked here only for documentation and
  Renovate grouping.
- `FRONTEND_VERSION` — the `Comfy-Org/ComfyUI_frontend` git tag whose
  `dist.zip` is bundled as static files.

`FRONTEND_VERSION` must match the `comfyui-frontend-package` version that
`COMFYUI_VERSION`'s upstream `requirements.txt` pins. When Renovate bumps
ComfyUI, it groups the backend and UI PRs together (see
`.renovaterc.json5`) so a reviewer can update both.

To verify a pairing:

```sh
curl -sL https://raw.githubusercontent.com/comfyanonymous/ComfyUI/<COMFYUI_VERSION>/requirements.txt \
    | grep '^comfyui-frontend-package'
```

The output version (e.g. `1.38.14`) should match `FRONTEND_VERSION` with a
`v` prefix (`v1.38.14`).

## Runtime configuration

| Env var | Default | Description |
|---|---|---|
| `COMFYUI_BACKEND` | `http://comfyui-predictor.ai.svc.cluster.local:80` | URL of the backend Service. Scheme is stripped at startup; only host:port is used. |

## Endpoints

| Path | Handling |
|---|---|
| `/` | Static `index.html`, never proxied |
| `/assets/*`, `/fonts/*`, `/scripts/*`, `/extensions/*`, `/cursor/*`, `/materialdesignicons.min.css` | Static files from the bundled dist |
| `/object_info`, `/embeddings`, `/extensions`, `/system_stats` | Proxied to backend, cached 6h, stale-on-error up to 24h |
| `/ws` | WebSocket, direct proxy with upgrade headers |
| All other paths (`/prompt`, `/queue`, `/history`, `/view`, `/upload/*`, `/api/*`, `/userdata/*`, `/internal/*`, `/free`, `/interrupt`) | Direct proxy, no cache, 502 when backend is down |

## Port

`8188` (same as upstream ComfyUI, for consumer-side convenience).

## Volumes

None. All state lives on the backend pod.

## Building locally

```sh
cd apps/comfyui-ui
docker buildx bake image-local
```

Produces `comfyui-ui:<FRONTEND_VERSION>`.

## Running locally against a real backend

```sh
docker run --rm -p 8188:8188 \
    -e COMFYUI_BACKEND=http://host.docker.internal:8188 \
    comfyui-ui:v1.38.14
```

Then open http://localhost:8188.
```

- [ ] **Step 2: Commit**

```bash
cd /Users/mailoarsac/Development/personal/containers
git add apps/comfyui-ui/README.md
git commit -m "docs(comfyui-ui): add README with pairing and env var docs"
```

---

### Task 6: Verify the image builds cleanly via the CI path

**Files:** none (verification only)

The repo's CI builds each `apps/<name>/` directory via `docker buildx bake` calling `target "image"`. Run the same command CI runs to make sure nothing's wrong with the bake file or multi-arch support.

- [ ] **Step 1: Print the bake plan like CI does**

```bash
cd /Users/mailoarsac/Development/personal/containers/apps/comfyui-ui
docker buildx bake image-all --print --progress=quiet | jq '.target."image-all"'
```

Expected: a JSON object with `platforms: ["linux/amd64", "linux/arm64"]`, args, tags, etc. No errors.

- [ ] **Step 2: Dry-run the app-options action logic**

```bash
cd /Users/mailoarsac/Development/personal/containers/apps/comfyui-ui
PLATFORMS=$(docker buildx bake image-all --print --progress=quiet \
    | jq --raw-output --compact-output '.target."image-all".platforms')
SOURCE=$(docker buildx bake --list type=variables,format=json --progress=quiet \
    | jq --raw-output '.[] | select(.name == "SOURCE") | .value')
VERSION=$(docker buildx bake --list type=variables,format=json --progress=quiet \
    | jq --raw-output '.[] | select(.name == "FRONTEND_VERSION") | .value')
echo "platforms=${PLATFORMS}"
echo "source=${SOURCE}"
echo "version=${VERSION}"
```

Expected output:

```
platforms=["linux/amd64","linux/arm64"]
source=https://github.com/Comfy-Org/ComfyUI_frontend
version=v1.38.14
```

**Note:** The repo's `.github/actions/app-options/action.yaml` specifically looks for a variable named `VERSION`. This repo's existing apps all use a variable called `VERSION`. But our bake file uses `FRONTEND_VERSION` (because we have two versions to track). The app-options action will output an empty `version` for this app. That is a problem — the workflow uses this for tagging.

- [ ] **Step 3: Decide how to handle the VERSION naming mismatch**

Read `.github/actions/app-options/action.yaml:38-43`:

```bash
cat /Users/mailoarsac/Development/personal/containers/.github/actions/app-options/action.yaml | sed -n '30,45p'
```

The action extracts the variable named `VERSION`. Options:

**Option A (chosen):** Rename `FRONTEND_VERSION` → `VERSION` in `apps/comfyui-ui/docker-bake.hcl`. Keep `COMFYUI_VERSION` as the secondary variable. The Renovate annotation on `VERSION` points at `Comfy-Org/ComfyUI_frontend` so bumps come from the frontend repo.

This is simpler than modifying the shared action. The README already notes there are two coupled versions, and the image tag will reflect the frontend version (which is what matters for UI API compatibility).

Apply the rename:

```bash
cd /Users/mailoarsac/Development/personal/containers/apps/comfyui-ui
```

Edit `docker-bake.hcl`. Rename `variable "FRONTEND_VERSION"` to `variable "VERSION"` (leave the Renovate annotation and default value alone). Update the `args` block in `target "image"` from `FRONTEND_VERSION = "${FRONTEND_VERSION}"` to `FRONTEND_VERSION = "${VERSION}"` (the Dockerfile's ARG is still named `FRONTEND_VERSION`; we're passing the new variable value into it). Update `target "image-local"` tag from `"${APP}:${FRONTEND_VERSION}"` to `"${APP}:${VERSION}"`.

The final relevant portion of `apps/comfyui-ui/docker-bake.hcl` should look like:

```hcl
variable "COMFYUI_VERSION" {
  // renovate: datasource=github-releases depName=comfyanonymous/ComfyUI
  default = "v0.14.2"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=Comfy-Org/ComfyUI_frontend
  default = "v1.38.14"
}

# ...

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    FRONTEND_VERSION = "${VERSION}"
    COMFYUI_VERSION  = "${COMFYUI_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}"]
}
```

- [ ] **Step 4: Rebuild and re-run tests after rename**

```bash
cd /Users/mailoarsac/Development/personal/containers
docker image rm comfyui-ui:test comfyui-ui:v1.38.14 2>/dev/null || true
docker buildx bake --file apps/comfyui-ui/docker-bake.hcl image-local
bats apps/comfyui-ui/test/test-build.bats
```

Expected: build succeeds, produces `comfyui-ui:v1.38.14`, all 6 tests pass.

- [ ] **Step 5: Re-run the app-options dry-run**

```bash
cd /Users/mailoarsac/Development/personal/containers/apps/comfyui-ui
docker buildx bake --list type=variables,format=json --progress=quiet \
    | jq --raw-output '.[] | select(.name == "VERSION") | .value'
```

Expected: `v1.38.14`.

- [ ] **Step 6: Commit**

```bash
cd /Users/mailoarsac/Development/personal/containers
git add apps/comfyui-ui/docker-bake.hcl
git commit -m "fix(comfyui-ui): rename FRONTEND_VERSION to VERSION for CI app-options compatibility"
```

---

### Task 7: Push the branch and open a PR

**Files:** none (git only)

- [ ] **Step 1: Verify the commit history is clean**

```bash
cd /Users/mailoarsac/Development/personal/containers
git log --oneline -10
```

Expected (most recent first):

1. `fix(comfyui-ui): rename FRONTEND_VERSION to VERSION for CI app-options compatibility`
2. `docs(comfyui-ui): add README with pairing and env var docs`
3. `chore(renovate): group comfyui backend and ui bumps together`
4. `feat(comfyui-ui): add nginx config with static serving, proxy, and cache`
5. `test(comfyui-ui): add bats tests for nginx proxy behavior (failing)`
6. `feat(comfyui-ui): scaffold new image with ComfyUI frontend dist.zip`
7. ... (pre-existing commits)

If the order differs because earlier task steps were committed differently, that's fine — the logical units matter, not the exact sequence.

- [ ] **Step 2: Push to a feature branch**

```bash
cd /Users/mailoarsac/Development/personal/containers
git checkout -b feat/comfyui-ui-split-image
git push -u origin feat/comfyui-ui-split-image
```

- [ ] **Step 3: Open the PR**

```bash
gh pr create --title "feat(comfyui-ui): add new static frontend image" --body "$(cat <<'EOF'
## Summary

Adds a new `apps/comfyui-ui/` directory producing `ghcr.io/arsac/comfyui-ui:<version>`. The image is nginx:alpine serving the `Comfy-Org/ComfyUI_frontend` `dist.zip` as static files, with reverse-proxying and response caching to the ComfyUI backend pod.

The motivation is splitting comfyui's UI tier from its GPU backend tier so the backend can scale from zero without breaking the browser UI. A follow-up PR in `arsac/home-ops` will wire up the Deployment, Service, HTTPRoute, and ScaledObject that consume this image.

## Design notes

- **Version coupling**: `VERSION` tracks `Comfy-Org/ComfyUI_frontend` (the static files shipped in this image). `COMFYUI_VERSION` tracks `comfyanonymous/ComfyUI` (the backend this UI is paired with). Both are Renovate-managed and grouped via a new packageRule in `.renovaterc.json5` so a maintainer sees bumps together.
- **Why static files instead of deploying the existing comfyui image twice**: The existing RWO PVCs (`comfyui`, `comfyui-cache`, `comfyui-models`) can't be shared across nodes, and ComfyUI has in-memory state (queue, history, loaded models) that can't be shared across processes regardless. A dedicated nginx image is ~50MB vs ~4GB for a second ComfyUI Python process, and avoids the state-split entirely.
- **Caching strategy**: `/object_info`, `/embeddings`, `/extensions`, `/system_stats` are cached for 6h with `proxy_cache_use_stale` on any backend error, so the UI loads even when the backend is scaled to 0 (after the cache has been primed once). All other endpoints are direct-proxy.

## Test plan

- [x] `bats apps/comfyui-ui/test/test-build.bats` passes locally (6 tests cover static serving, proxy, cache, stale-on-backend-down, 502 for non-cached when backend is down)
- [x] `docker buildx bake image-local` succeeds
- [x] `docker buildx bake image-all --print` resolves cleanly for `linux/amd64` and `linux/arm64`
- [ ] CI build passes
- [ ] After merge: verify `ghcr.io/arsac/comfyui-ui:rolling` is tagged and pullable
- [ ] Follow-up in home-ops repo deploys the image and validates end-to-end against the real `comfyui-predictor` backend

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Expected: `gh` prints the PR URL.

- [ ] **Step 4: Return the PR URL**

Return the URL printed by the `gh pr create` command in the final response.

---

## Completion Criteria

This plan is done when ALL of the following are true:

1. The new `apps/comfyui-ui/` directory exists with all files from the File Map.
2. `docker buildx bake image-local` builds the image successfully from a clean checkout.
3. `bats apps/comfyui-ui/test/test-build.bats` passes all 6 tests.
4. The `docker-bake.hcl` file uses a variable named `VERSION` (not `FRONTEND_VERSION`) so the existing `.github/actions/app-options` action can extract it.
5. `.renovaterc.json5` has a `packageRule` grouping `comfyanonymous/ComfyUI` and `Comfy-Org/ComfyUI_frontend` bumps.
6. A PR is open against `arsac/containers:main` with all commits.

Anything beyond this — deploying the image in the home-ops cluster, wiring up Kubernetes resources, testing against the real comfyui-predictor — is out of scope for THIS plan. A separate plan will handle the downstream deployment.
