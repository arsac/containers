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
