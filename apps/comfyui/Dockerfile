ARG VERSION="v0.6.0"
ARG PYTHON_VERSION="3.12"
ARG BASE_IMAGE="ghcr.io/arsac/cuda-ml"

# =============================================================================
# Builder stage - install ComfyUI and its requirements
# =============================================================================
FROM ${BASE_IMAGE}:devel AS builder

ARG VERSION

# Clone ComfyUI and install requirements
RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --branch ${VERSION} --quiet \
    https://github.com/comfyanonymous/ComfyUI.git /app && \
    uv pip install --requirement /app/requirements.txt && \
    rm -rf /app/.git && \
    echo "ComfyUI ${VERSION} installed"

# =============================================================================
# Runtime stage - use devel base for custom node CUDA compilation support
# =============================================================================
FROM ${BASE_IMAGE}:devel

ARG PYTHON_VERSION

# Copy ComfyUI-specific Python packages
COPY --from=builder /usr/local/lib/python${PYTHON_VERSION}/dist-packages /usr/local/lib/python${PYTHON_VERSION}/dist-packages

# Copy ComfyUI
COPY --from=builder /app /app

# Copy configuration files
COPY defaults/extra_model_paths.yaml /app/extra_model_paths.yaml
COPY entrypoint.sh /entrypoint.sh

USER root
RUN chmod +x /entrypoint.sh && \
    mkdir -p /config /config/user /config/custom_nodes /config/.venv /config/web /input /output /models && \
    chmod -R 755 /config /input /output /models && \
    ln -sf /config/web /app/web

# Environment variables
ENV CONFIG_DIR=/config \
    USER_DIR=/config/user \
    MODEL_DIR=/models \
    WORKFLOWS_DIR=/config/workflows \
    OUTPUT_DIR=/output \
    INPUT_DIR=/input \
    VIRTUAL_ENV=/config/.venv \
    HOME="/config"

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config", "/models", "/input", "/output"]

EXPOSE 8188
ENTRYPOINT ["/usr/bin/tini", "--", "/entrypoint.sh"]

CMD ["python", "/app/main.py", \
    "--listen", "0.0.0.0", "--port", "8188", \
    "--multi-user", \
    "--base-directory", "/config", \
    "--user-directory", "/config/user", \
    "--input-directory", "/input", \
    "--output-directory", "/output", \
    "--temp-directory", "/tmp", \
    "--extra-model-paths-config", "/app/extra_model_paths.yaml", \
    "--database-url", "sqlite:////config/user/comfyui.db", \
    "--use-sage-attention"]
