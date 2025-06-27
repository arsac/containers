ARG VERSION="v0.3.43"

# Runtime stage
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ARG VERSION

ENV PIP_BREAK_SYSTEM_PACKAGES=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_NO_CACHE=true \
    UV_SYSTEM_PYTHON=1 \
    UV_LINK_MODE=copy \
    UV_BREAK_SYSTEM_PACKAGES=true \
    TORCH_CUDA_ARCH_LIST="12.0" \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu128" \
    UV_PYTHON_PREFERENCE=system

# Install runtime dependencies and system-level Python packages
RUN --mount=type=cache,target=/var/cache/apt \
    --mount=type=cache,target=/var/lib/apt/lists \
    apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg fonts-dejavu-core git libgl1 libgl1-mesa-glx libglib2.0-0 curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

COPY --from=ghcr.io/arsac/containers/python-wheels:latest /wheels /tmp/wheels

RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install --upgrade pip && \
    uv pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 && \
    find /tmp/wheels -name "*.whl" -exec uv pip install {} \; && \
    rm -rf /tmp/wheels && \
    uv pip install flatbuffers numpy onnxruntime-gpu packaging protobuf pynvml sympy accelerate && \
    git clone --recursive --branch ${VERSION} --quiet https://github.com/comfyanonymous/ComfyUI.git /app && \
    uv pip install --requirement /app/requirements.txt && \
    mkdir -p /config /config/user /config/custom_nodes /input /output /models && \
    chown -R nobody:nogroup /config && \
    chmod -R 755 /config /input /output /models

COPY defaults/extra_model_paths.yaml /app/extra_model_paths.yaml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set environment variables
ENV CONFIG_DIR=/config
ENV USER_DIR=/config/user
ENV MODEL_DIR=/models
ENV WORKFLOWS_DIR=/config/workflows
ENV OUTPUT_DIR=/output
ENV INPUT_DIR=/input

ENV VIRTUAL_ENV=/config/.venv
ENV PATH="/config/.venv/bin:$PATH"
ENV HOME="/config"

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config"]

EXPOSE 8188
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

CMD ["uv", "run", "/app/main.py", \
    "--listen", "0.0.0.0", "--port", "8188", \
    "--base-directory", "/config", \
    "--user-directory", "/config/user", \
    "--input-directory", "/input", \
    "--output-directory", "/output", \
    "--temp-directory", "/tmp"]
