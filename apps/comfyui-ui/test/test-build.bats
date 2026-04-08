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
        -p "${UI_PORT}:80" \
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
