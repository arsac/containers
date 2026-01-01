# CUDA ML Devel Image
# Provides CUDA devel environment + PyTorch for compiling CUDA extensions
#
# Build locally:
#   docker buildx bake image-devel-local
#
# Tags: cuda-ml:devel

ARG CUDA_VERSION="12.8.0"
ARG CUDA_DISTRO="ubuntu24.04"
ARG TORCH_CUDA="cu128"
ARG PYTHON_VERSION="3.12"
ARG TORCH_VERSION="2.9.1"
ARG XFORMERS_VERSION="v0.0.33.post2"
ARG SAGEATTENTION_VERSION="1.0.6"

FROM nvidia/cuda:${CUDA_VERSION}-devel-${CUDA_DISTRO}

ARG TORCH_CUDA
ARG PYTHON_VERSION
ARG TORCH_VERSION
ARG XFORMERS_VERSION
ARG SAGEATTENTION_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:${PATH} \
    CPLUS_INCLUDE_PATH=/usr/local/cuda/include \
    TORCH_CUDA_ARCH_LIST="12.0" \
    UV_SYSTEM_PYTHON=1 \
    UV_BREAK_SYSTEM_PACKAGES=1 \
    UV_LINK_MODE=copy \
    UV_HTTP_TIMEOUT=300 \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/${TORCH_CUDA}"

# Install Python, build dependencies, and runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    python${PYTHON_VERSION} python${PYTHON_VERSION}-dev python${PYTHON_VERSION}-venv \
    build-essential ninja-build git curl ca-certificates \
    ffmpeg fonts-dejavu-core libgl1 libopengl0 libglib2.0-0 libsndfile1 tini && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python && \
    ln -sf /usr/bin/python${PYTHON_VERSION} /usr/bin/python3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# Install PyTorch ecosystem and common ML dependencies
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=cache,target=/root/.cache/pip \
    uv pip install \
    torch==${TORCH_VERSION} torchvision torchaudio \
    xformers==${XFORMERS_VERSION} \
    --index-url https://download.pytorch.org/whl/${TORCH_CUDA} && \
    uv pip install \
    accelerate flatbuffers numpy onnxruntime-gpu \
    packaging protobuf nvidia-ml-py sympy pybind11 ninja psutil wheel \
    sageattention==${SAGEATTENTION_VERSION} \
    pygltflib trimesh opencv-contrib-python-headless \
    soundfile librosa pymeshlab insightface && \
    uv pip install flash-attn --no-build-isolation && \
    echo "Installed torch version:" && \
    python -c "import torch; print(torch.__version__)"

# Build Hunyuan3D extensions from source
ARG PYTHON_VERSION
RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --filter=blob:none --sparse \
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
    rm -rf /tmp/hunyuan3d && \
    echo "Hunyuan3D: custom_rasterizer and mesh_processor installed"

# Build diso (Differentiable Marching Cubes) for Hunyuan3D dmc algorithm
RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --recursive https://github.com/SarahWeiii/diso.git /tmp/diso && \
    cd /tmp/diso && \
    FORCE_CUDA=1 python setup.py bdist_wheel && \
    uv pip install dist/*.whl && \
    rm -rf /tmp/diso && \
    echo "diso installed"

# Generate constraints file
RUN uv pip freeze | grep -E \
    "^(torch|torchvision|torchaudio|xformers|triton|numpy|safetensors|tokenizers|accelerate|sageattention)==" \
    > /constraints.txt && \
    echo "Generated constraints:" && cat /constraints.txt

# Cleanup to reduce devel image size
ARG PYTHON_VERSION
RUN rm -rf /usr/local/lib/python${PYTHON_VERSION}/dist-packages/torch/test && \
    rm -rf /usr/local/lib/python${PYTHON_VERSION}/dist-packages/torch/benchmarks && \
    find /usr/local/lib/python${PYTHON_VERSION} -name "*.so" -exec strip --strip-unneeded {} + 2>/dev/null || true && \
    find /usr/local/lib/python${PYTHON_VERSION} -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    rm -rf /tmp/* /var/tmp/*

# Verify installation
RUN python -c "import torch; print(f'PyTorch {torch.__version__} with CUDA {torch.version.cuda}')"
