ARG VERSION="v0.6.0"
ARG CUDA_VERSION="12.8.0"
ARG PYTHON_VERSION="3.12"
ARG TORCH_VERSION="2.9.1"
ARG XFORMERS_VERSION="v0.0.33.post2"
ARG SAGEATTENTION_VERSION="1.0.6"

# =============================================================================
# Builder stage - CUDA toolkit for compilation
# =============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu24.04 AS builder

ARG VERSION
ARG PYTHON_VERSION
ARG TORCH_VERSION
ARG XFORMERS_VERSION
ARG SAGEATTENTION_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TORCH_CUDA_ARCH_LIST="12.0" \
    UV_SYSTEM_PYTHON=1 \
    UV_BREAK_SYSTEM_PACKAGES=1 \
    UV_LINK_MODE=copy \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu128"

# Install Python and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
    build-essential ninja-build git curl ca-certificates && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install Python packages (no cache to save disk space in CI)
RUN uv pip install torch==${TORCH_VERSION} torchvision torchaudio xformers==${XFORMERS_VERSION} --index-url https://download.pytorch.org/whl/cu128 && \
    uv pip install accelerate flatbuffers numpy onnxruntime-gpu packaging protobuf nvidia-ml-py sympy sageattention==${SAGEATTENTION_VERSION} && \
    rm -rf /root/.cache/uv

# Clone ComfyUI and install requirements
RUN git clone --depth 1 --branch ${VERSION} --quiet https://github.com/comfyanonymous/ComfyUI.git /app && \
    uv pip install --requirement /app/requirements.txt && \
    rm -rf /app/.git /root/.cache/uv && \
    find /usr/local/lib/python${PYTHON_VERSION}/dist-packages -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true

# =============================================================================
# Runtime stage - minimal CUDA runtime
# =============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-runtime-ubuntu24.04

ARG PYTHON_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu128" \
    UV_LINK_MODE=copy

# Install runtime dependencies (no cache mount - avoids dpkg corruption issues)
RUN apt-get update && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-venv \
    ffmpeg fonts-dejavu-core git libgl1 libglib2.0-0 curl ca-certificates && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy Python packages from builder
COPY --from=builder /usr/local/lib/python${PYTHON_VERSION}/dist-packages /usr/local/lib/python${PYTHON_VERSION}/dist-packages
COPY --from=builder /usr/lib/python3/dist-packages /usr/lib/python3/dist-packages

# Copy ComfyUI
COPY --from=builder /app /app

# Copy configuration files
COPY defaults/extra_model_paths.yaml /app/extra_model_paths.yaml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create directories and set permissions
RUN mkdir -p /config /config/user /config/custom_nodes /input /output /models && \
    chown -R nobody:nogroup /config && \
    chmod -R 755 /config /input /output /models

# Environment variables
ENV CONFIG_DIR=/config \
    USER_DIR=/config/user \
    MODEL_DIR=/models \
    WORKFLOWS_DIR=/config/workflows \
    OUTPUT_DIR=/output \
    INPUT_DIR=/input \
    VIRTUAL_ENV=/config/.venv \
    PATH="/config/.venv/bin:$PATH" \
    HOME="/config"

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config"]

EXPOSE 8188
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

CMD ["python", "/app/main.py", \
    "--listen", "0.0.0.0", "--port", "8188", \
    "--base-directory", "/config", \
    "--user-directory", "/config/user", \
    "--input-directory", "/input", \
    "--output-directory", "/output", \
    "--temp-directory", "/tmp", \
    "--extra-model-paths-config", "/app/extra_model_paths.yaml"]
