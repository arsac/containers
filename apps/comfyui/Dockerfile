ARG VERSION="v0.3.40"
ARG MANAGER_VERSION="3.32.5"
ARG CLI_VERSION="v1.4.1"

# Runtime stage
FROM ghcr.io/astral-sh/uv:python3.12-bookworm-slim

ENV UV_SYSTEM_PYTHON=1

ARG VERSION
ARG MANAGER_VERSION
ARG CLI_VERSION

# Install only runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libgl1 libglib2.0-0 fonts-dejavu-core ffmpeg libgl1-mesa-glx git && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives

# Install system-level Python packages first (before creating user)
RUN uv pip install --upgrade pip && \
    uv pip install torch torchvision torchaudio --pre --index-url https://download.pytorch.org/whl/nightly/cu128 && \
    uv pip install comfy-cli==${CLI_VERSION} pynvml flatbuffers numpy packaging protobuf sympy

COPY --from=ghcr.io/arsac/containers/python-wheels:latest /wheels /tmp/wheels
RUN find /tmp/wheels -name "*.whl" -exec uv pip install {} \; && \
    rm -rf /tmp/wheels && \
    uv pip install --system onnxruntime-gpu

# Clone ComfyUI and ComfyUI-Manager as root, then change ownership
RUN git clone --depth 1 --branch ${VERSION} --quiet https://github.com/comfyanonymous/ComfyUI.git /app/comfyui && \
    git clone --depth 1 --branch ${MANAGER_VERSION} --quiet https://github.com/Comfy-Org/ComfyUI-Manager.git /app/comfyui-manager

# Install ComfyUI requirements at system level too
RUN uv pip install --system \
    --requirement /app/comfyui/requirements.txt \
    --requirement /app/comfyui-manager/requirements.txt

# Link ComfyUI Manager to ComfyUI's custom_nodes directory
RUN ln -s /app/comfyui-manager /app/comfyui/custom_nodes/ComfyUI-Manager

# Set environment variables

ENV COMFY_HOME=/app/comfyui
ENV COMFYUI_MANAGER_HOME=/app/comfyui-manager
ENV MODEL_DIR=${COMFY_HOME}/models
ENV OUTPUT_DIR=${COMFY_HOME}/output
ENV INPUT_DIR=${COMFY_HOME}/input
ENV WORKFLOWS_DIR=${COMFY_HOME}/workflows

ENV VIRTUAL_ENV=/config/.venv
ENV PATH="/config/.venv/bin:$PATH"
ENV HOME="/config"

WORKDIR /config

# Create virtual environment that inherits system packages
RUN uv venv --system-site-packages /config/.venv

# Configure comfy CLI
RUN comfy --skip-prompt tracking disable && \
    comfy --skip-prompt set-default ${COMFY_HOME} && \
    comfy node registry-install comfyui-model-manager

RUN chown -R nobody:nogroup /config && \
    chmod -R 777 /config && \
    chown -R nobody:nogroup /app/comfyui && \
    chmod -R 755 /app/comfyui && \
    chown -R nobody:nogroup /app/comfyui-manager && \
    chmod -R 777 /app/comfyui-manager

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER nobody:nogroup
WORKDIR /config
VOLUME ["/config"]

EXPOSE 8188
ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]

CMD ["uv", "run", "/app/comfyui/main.py", "--listen", "0.0.0.0", "--port", "8188"]
