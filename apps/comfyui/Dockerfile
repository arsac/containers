ARG VERSION="v0.6.0"
ARG CUDA_VERSION="12.8.0"
ARG CUDA_DISTRO="ubuntu24.04"
ARG TORCH_CUDA="cu128"
ARG PYTHON_VERSION="3.12"
ARG TORCH_VERSION="2.9.1"
ARG XFORMERS_VERSION="v0.0.33.post2"
ARG SAGEATTENTION_VERSION="1.0.6"

# =============================================================================
# Builder stage - CUDA toolkit for compilation (must match PyTorch CUDA version)
# =============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-devel-${CUDA_DISTRO} AS builder

ARG VERSION
ARG TORCH_CUDA
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
    UV_HTTP_TIMEOUT=300 \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/${TORCH_CUDA}"

# Install Python and build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
    build-essential ninja-build git curl ca-certificates && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install Python packages
RUN uv pip install \
    torch==${TORCH_VERSION} torchvision torchaudio \
    xformers==${XFORMERS_VERSION} \
    --index-url https://download.pytorch.org/whl/${TORCH_CUDA} && \
    uv pip install \
    accelerate flatbuffers numpy onnxruntime-gpu \
    packaging protobuf nvidia-ml-py sympy pybind11 \
    sageattention==${SAGEATTENTION_VERSION} \
    pygltflib trimesh opencv-contrib-python-headless \
    soundfile librosa pymeshlab && \
    rm -rf /root/.cache/uv

# Clone ComfyUI and install requirements
RUN git clone --depth 1 --branch ${VERSION} --quiet \
    https://github.com/comfyanonymous/ComfyUI.git /app && \
    uv pip install --requirement /app/requirements.txt && \
    rm -rf /app/.git /root/.cache/uv && \
    echo "Installed torch version:" && \
    python -c "import torch; print(torch.__version__)"

# Build Hunyuan3D extensions from source
RUN git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git /tmp/hunyuan3d && \
    cd /tmp/hunyuan3d && \
    git sparse-checkout set hy3dgen/texgen/custom_rasterizer hy3dgen/texgen/differentiable_renderer && \
    # Build custom_rasterizer
    cd /tmp/hunyuan3d/hy3dgen/texgen/custom_rasterizer && \
    python setup.py bdist_wheel && \
    uv pip install dist/*.whl && \
    # Build mesh_processor (differentiable_renderer)
    cd /tmp/hunyuan3d/hy3dgen/texgen/differentiable_renderer && \
    python setup.py build_ext --inplace && \
    cp -r mesh_processor* /usr/local/lib/python${PYTHON_VERSION}/dist-packages/ && \
    # Clean up build artifacts
    rm -rf /tmp/hunyuan3d /root/.cache/uv && \
    echo "custom_rasterizer and mesh_processor installed"

# Generate constraints file to lock torch ecosystem packages
RUN uv pip freeze | grep -E \
    "^(torch|torchvision|torchaudio|xformers|triton|numpy|safetensors|tokenizers|accelerate|sageattention|custom-rasterizer)==" \
    > /app/constraints.txt && \
    echo "Generated constraints:" && cat /app/constraints.txt

# Clean up to reduce image size
RUN find /usr/local/lib/python${PYTHON_VERSION} -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -name '*.pyc' -delete 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -name '*.so' -exec strip --strip-unneeded {} \; 2>/dev/null || true

# =============================================================================
# Runtime stage - minimal CUDA runtime
# =============================================================================
FROM nvidia/cuda:${CUDA_VERSION}-runtime-${CUDA_DISTRO}

ARG TORCH_CUDA
ARG PYTHON_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    LD_LIBRARY_PATH=/usr/local/lib/python${PYTHON_VERSION}/dist-packages/torch/lib \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/${TORCH_CUDA}" \
    UV_LINK_MODE=copy \
    UV_CONSTRAINT=/app/constraints.txt \
    PIP_CONSTRAINT=/app/constraints.txt

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-venv \
    ffmpeg fonts-dejavu-core git libgl1 libopengl0 libglib2.0-0 libsndfile1 curl ca-certificates tini && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Copy all Python packages from builder
COPY --from=builder /usr/local/lib/python${PYTHON_VERSION} /usr/local/lib/python${PYTHON_VERSION}
COPY --from=builder /usr/lib/python3/dist-packages /usr/lib/python3/dist-packages

# Copy ComfyUI
COPY --from=builder /app /app

# Copy configuration files
COPY defaults/extra_model_paths.yaml /app/extra_model_paths.yaml
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Create directories and symlink for custom node web extensions
RUN mkdir -p /config /config/user /config/custom_nodes /config/.venv /config/web /input /output /models && \
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
    "--use-sage-attention"]
