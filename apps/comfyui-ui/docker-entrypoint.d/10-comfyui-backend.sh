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

# COMFYUI_BACKEND must be host[:port], no path. Reject paths explicitly
# so the operator gets a clear error instead of a cryptic nginx -t failure.
case "$host_port" in
    */*)
        echo "[comfyui-ui] ERROR: COMFYUI_BACKEND must not contain a path component: ${COMFYUI_BACKEND}" >&2
        exit 1
        ;;
esac

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
