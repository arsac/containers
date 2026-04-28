# CUDA 13.0 + PyTorch 2.11 + Python 3.13 base image.
#
# Slim PyTorch foundation. uv-managed Python; venv at /opt/venv.
# Devel variant only — provides nvcc, NVRTC, CUPTI, cuDNN headers for
# downstream apps that compile CUDA extensions.
#
# Build locally:
#   docker buildx bake image-devel-local
#
# Tags: pytorch:cuda13.0-torch2.11-devel, pytorch:devel, pytorch:latest

ARG CUDA_VERSION="13.0.3"
ARG CUDA_DISTRO="ubuntu24.04"
ARG UV_VERSION="0.11.8"

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM nvidia/cuda:${CUDA_VERSION}-cudnn-devel-${CUDA_DISTRO}

ARG PYTHON_VERSION="3.13"
ARG TORCH_VERSION="2.11.0"
ARG TORCHVISION_VERSION="0.26.0"
ARG TORCHAUDIO_VERSION="2.11.0"
ARG XFORMERS_VERSION="0.0.35"
ARG TRITON_VERSION="3.6.0"
ARG TORCH_INDEX="https://download.pytorch.org/whl/cu130"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    CUDA_HOME=/usr/local/cuda \
    CPATH=/usr/local/cuda/include \
    TORCH_CUDA_ARCH_LIST="12.0" \
    UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_HTTP_TIMEOUT=300 \
    UV_PYTHON_INSTALL_DIR=/opt/python \
    UV_PYTHON_PREFERENCE=only-managed \
    VIRTUAL_ENV=/opt/venv \
    PATH=/usr/local/cuda/bin:/opt/venv/bin:${PATH}

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential ninja-build git curl ca-certificates tini && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /uvx /usr/local/bin/

RUN uv python install ${PYTHON_VERSION} && \
    uv venv /opt/venv --python ${PYTHON_VERSION}

# Single resolve across all packages — internally consistent pins.
# `--index-strategy unsafe-best-match` makes resolution deterministic across
# the cu130 index + PyPI mix.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip install \
      --index-url ${TORCH_INDEX} \
      --extra-index-url https://pypi.org/simple \
      --index-strategy unsafe-best-match \
      torch==${TORCH_VERSION} \
      torchvision==${TORCHVISION_VERSION} \
      torchaudio==${TORCHAUDIO_VERSION} \
      xformers==${XFORMERS_VERSION} \
      triton==${TRITON_VERSION} \
      accelerate numpy safetensors nvidia-ml-py \
      sympy packaging pybind11 ninja psutil wheel

# Constraints file for downstream apps to inherit pins (torch ecosystem
# plus the nvidia-* transitive deps and the cuda-toolkit umbrella).
RUN uv pip freeze | grep -E \
    "^(torch|torchvision|torchaudio|xformers|triton|numpy|safetensors|accelerate|nvidia-|cuda-toolkit)==" \
    > /constraints.txt && \
    echo "Constraints:" && cat /constraints.txt

# Build-time validation. torch.cuda.is_available() requires --gpus all and is
# intentionally not checked here — only that torch was built against CUDA and
# that xformers' py3-none wheel imports against torch's C++ ABI on cp313.
RUN python -c "import torch; print(f'PyTorch {torch.__version__} CUDA {torch.version.cuda}'); assert torch.version.cuda is not None" && \
    python -c "import xformers; print(f'xformers {xformers.__version__}')"

ENTRYPOINT ["/usr/bin/tini", "--"]
