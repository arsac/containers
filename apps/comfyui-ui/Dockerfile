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
