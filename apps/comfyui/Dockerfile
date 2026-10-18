ARG VERSION="v0.41.0"
# First-party PyTorch devel image: Python 3.12, torch 2.11.0, CUDA 12.8 with
# sm_120 (Blackwell RTX 5090 / RTX PRO 6000) support in the shipped kernels.
# Pinned to the cu128 line deliberately - cu13x images need a >= 580 host
# driver; bump only after checking `nvidia-smi` on the GPU hosts.
ARG BASE_IMAGE="mirror.gcr.io/pytorch/pytorch:2.11.0-cuda12.8-cudnn9-devel"
ARG UV_VERSION="0.13.1"

# uv comes from its own image; BuildKit cannot expand ARGs in COPY --from,
# so the image must be referenced from a named stage
FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

# =============================================================================
# Builder stage - install ComfyUI and its requirements
# =============================================================================
FROM ${BASE_IMAGE} AS builder

ARG VERSION
ARG UV_VERSION

# bash + pipefail: the default /bin/sh (dash) cannot express pipefail, which
# the constraint-generation pipes below rely on
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    TORCH_CUDA_ARCH_LIST="12.0" \
    UV_LINK_MODE=copy \
    UV_HTTP_TIMEOUT=300 \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu128" \
    UV_SYSTEM_PYTHON=1 \
    UV_BREAK_SYSTEM_PACKAGES=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ninja-build git curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

# Ensure the torch companion stack matches the base torch exactly, then freeze
# pins so nothing downstream upgrades the core stack
RUN uv pip install \
      torchvision==0.26.0 torchaudio==2.11.0 \
      --index-url https://download.pytorch.org/whl/cu128 \
      --extra-index-url https://pypi.org/simple && \
    uv pip freeze | grep -E "^(torch|torchvision|torchaudio|triton|safetensors|tokenizers|accelerate|numpy)==" > /constraints.txt && \
    cat /constraints.txt

# Clone ComfyUI and install requirements (constraints keep the torch stack)
RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --branch ${VERSION} --quiet \
    https://github.com/comfyanonymous/ComfyUI.git /app && \
    uv pip install --requirement /app/requirements.txt && \
    rm -rf /app/.git && \
    echo "ComfyUI ${VERSION} installed"

# SageAttention 2.2.0 wheel (sm_120) built by build-wheels against the same
# torch version
COPY --from=ghcr.io/arsac/python_wheels:python-3.12-cuda-12.9.1 /wheels/ /tmp/wheels/
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install /tmp/wheels/sageattention*.whl && \
    rm -rf /tmp/wheels

# Attention-adjacent source builds used by ComfyUI 3D workflows; pybind11 is
# a build dep of the Hunyuan3D and diso setup.py files (the upstream pytorch
# image does not ship it, unlike the old cuda-ml base)
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install pybind11 git+https://github.com/NVlabs/nvdiffrast.git --no-build-isolation && \
    git clone --depth 1 --filter=blob:none --sparse \
    https://github.com/Tencent-Hunyuan/Hunyuan3D-2.git /tmp/hunyuan3d && \
    cd /tmp/hunyuan3d && \
    git sparse-checkout set hy3dgen/texgen/custom_rasterizer hy3dgen/texgen/differentiable_renderer && \
    cd hy3dgen/texgen/custom_rasterizer && \
    python setup.py bdist_wheel && \
    uv pip install dist/*.whl && \
    cd /tmp/hunyuan3d/hy3dgen/texgen/differentiable_renderer && \
    python setup.py build_ext --inplace && \
    SITEDIR=$(python -c "import sysconfig; print(sysconfig.get_path('purelib'))") && \
    cp -r mesh_processor* "${SITEDIR}/" && \
    rm -rf /tmp/hunyuan3d

RUN --mount=type=cache,target=/root/.cache/uv \
    git clone --depth 1 --recursive https://github.com/SarahWeiii/diso.git /tmp/diso && \
    cd /tmp/diso && \
    FORCE_CUDA=1 python setup.py bdist_wheel && \
    uv pip install dist/*.whl && \
    rm -rf /tmp/diso

# Build-time contract tests: verify the stack is pinned, CUDA-built, and
# sageattention is importable. Driver-free on purpose - build runners have no
# GPU, and torch.cuda.get_arch_list() gates on driver availability; the sm_120
# kernel assertion runs in the gpu-smoke workflow on real hardware.
RUN python - <<'PY'
import torch
import torchvision
import torchaudio
import sageattention

assert torch.__version__.startswith("2.11.0"), torch.__version__
assert torch.version.cuda is not None, "torch is not CUDA-built"
assert torch.version.cuda.startswith("12.8"), torch.version.cuda
x = torch.rand(4, 4)
assert (x @ x.t()).shape == (4, 4)
from importlib.metadata import version
print(f"contract OK: torch {torch.__version__}+cu{torch.version.cuda}, sageattention {version('sageattention')}")
PY

# Generate the constraint file the runtime venv uses so custom nodes cannot
# change the torch ecosystem
RUN uv pip freeze | grep -E \
    "^(torch|torchvision|torchaudio|triton|numpy|safetensors|tokenizers|accelerate|sageattention)==" \
    > /constraints.txt && \
    echo "Generated constraints:" && cat /constraints.txt

# =============================================================================
# Runtime stage - devel base kept for custom node CUDA compilation support
# =============================================================================
FROM ${BASE_IMAGE}

ARG UV_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    UV_LINK_MODE=copy \
    UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu128" \
    UV_CONSTRAINT=/constraints.txt \
    PIP_CONSTRAINT=/constraints.txt \
    PYTORCH_ALLOC_CONF=expandable_segments:True

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg fonts-dejavu-core git libgl1 libopengl0 libglib2.0-0 libsndfile1 \
    curl ca-certificates tini gcc && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

# Copy ComfyUI-specific Python packages
COPY --from=builder /usr/local/lib/python3.12/ /usr/local/lib/python3.12/

# Copy ComfyUI
COPY --from=builder /app /app

# Copy configuration files
COPY defaults/extra_model_paths.yaml /app/extra_model_paths.yaml
COPY entrypoint.sh /entrypoint.sh
COPY --from=builder /constraints.txt /constraints.txt

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

USER 65534:65534
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
