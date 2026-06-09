# Self-contained build of the kserve huggingfaceserver image on vLLM 0.22.1.
# This is a vendored copy of upstream kserve's huggingface_server.Dockerfile
# (pinned via KSERVE_REF) — see README.md for why we vendor vs fork, and the
# retirement trigger. Downstream edits are inline; the source change is in
# patches/.
ARG CUDA_VERSION=13.2.1
ARG VENV_PATH=prod_venv
ARG WORKSPACE_DIR=/kserve-workspace
ARG KSERVE_REF=11ad2ca18a2265b079bd140220572017ad06bdfc

#################### SOURCE (pinned upstream kserve + downstream patches) ####################
# Vendored from kserve's huggingface_server.Dockerfile at KSERVE_REF, with the
# Dockerfile-level edits (vLLM 0.22.1, transformers 5.5.3, nixl cu13 swap,
# lmcache dropped) applied inline below. This stage fetches the pinned upstream
# Python packages and applies patches/ (the vllm_model.py 0.22 API change), so
# the build-stage COPYs pull from here instead of the build context.
FROM alpine/git AS src
ARG KSERVE_REF
WORKDIR /s
RUN git init -q . \
 && git remote add origin https://github.com/kserve/kserve.git \
 && git fetch -q --depth 1 origin "${KSERVE_REF}" \
 && git checkout -q FETCH_HEAD
COPY patches/ /patches/
RUN set -e; for p in /patches/*.patch; do echo "Applying $(basename "$p")"; git apply "$p"; done
#################### SOURCE ####################

#################### CUDA RUNTIME (Ubuntu 25.10) ####################
# Custom CUDA runtime image since NVIDIA doesn't publish Ubuntu 25.10 images.
# Uses the ubuntu2404 apt repo — packages are compatible across Ubuntu versions.
FROM ubuntu:25.10 AS cuda-runtime

ENV DEBIAN_FRONTEND=noninteractive
ENV NVARCH=x86_64
ENV NV_CUDA_CUDART_VERSION=13.2.75-1
ENV CUDA_VERSION=13.2.1
ENV NV_CUDA_LIB_VERSION=13.2.1-1
ENV NV_NVTX_VERSION=13.2.75-1
ENV NV_LIBNPP_VERSION=13.1.0.48-1
ENV NV_LIBCUSPARSE_VERSION=12.7.10.1-1
ENV NV_LIBCUBLAS_VERSION=13.4.0.1-1

ENV NVIDIA_REQUIRE_CUDA="cuda>=13.2 brand=tesla,driver>=535,driver<536 brand=tesla,driver>=570,driver<571 brand=tesla,driver>=580,driver<581 brand=tesla,driver>=590,driver<591 brand=nvidia,driver>=535,driver<536 brand=nvidia,driver>=570,driver<571 brand=nvidia,driver>=580,driver<581 brand=nvidia,driver>=590,driver<591 brand=nvidiartx,driver>=535,driver<536 brand=nvidiartx,driver>=570,driver<571 brand=nvidiartx,driver>=580,driver<581 brand=nvidiartx,driver>=590,driver<591"

# Add NVIDIA CUDA apt repo (ubuntu2404 — no 2510 repo exists)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gnupg2 curl ca-certificates && \
    curl -fsSLO https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/${NVARCH}/cuda-keyring_1.1-1_all.deb && \
    dpkg -i cuda-keyring_1.1-1_all.deb && \
    rm cuda-keyring_1.1-1_all.deb && \
    apt-get purge --autoremove -y curl && \
    rm -rf /var/lib/apt/lists/*

# CUDA base packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-cudart-13-2=${NV_CUDA_CUDART_VERSION} \
    cuda-toolkit-13-2-config-common=${NV_CUDA_CUDART_VERSION} \
    cuda-toolkit-13-config-common=${NV_CUDA_CUDART_VERSION} \
    cuda-toolkit-config-common=${NV_CUDA_CUDART_VERSION} \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    if apt-cache policy cuda-compat-13-2 2>/dev/null | grep -q "Candidate:"; then \
        apt-get install -y --no-install-recommends cuda-compat-13-2; \
    fi && \
    rm -rf /var/lib/apt/lists/*

# CUDA runtime libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-libraries-13-2=${NV_CUDA_LIB_VERSION} \
    libnpp-13-2=${NV_LIBNPP_VERSION} \
    cuda-nvtx-13-2=${NV_NVTX_VERSION} \
    libcusparse-13-2=${NV_LIBCUSPARSE_VERSION} \
    libcublas-13-2=${NV_LIBCUBLAS_VERSION} \
    libnccl2 \
    && rm -rf /var/lib/apt/lists/*

RUN apt-mark hold libcublas-13-2 libnccl2

RUN echo "/usr/local/cuda/lib64" >> /etc/ld.so.conf.d/nvidia.conf

ENV PATH=/usr/local/nvidia/bin:/usr/local/cuda/bin:${PATH}
ENV LD_LIBRARY_PATH=/usr/local/nvidia/lib:/usr/local/nvidia/lib64:/usr/local/cuda/lib64
ENV NVIDIA_VISIBLE_DEVICES=all
ENV NVIDIA_DRIVER_CAPABILITIES=compute,utility

#################### CUDA RUNTIME (Ubuntu 25.10) ####################

#################### CUDA DEVEL (Ubuntu 25.10) ####################
FROM cuda-runtime AS cuda-devel

ENV NV_CUDA_CUDART_DEV_VERSION=13.2.75-1
ENV NV_NVML_DEV_VERSION=13.2.82-1
ENV NV_LIBCUSPARSE_DEV_VERSION=12.7.10.1-1
ENV NV_LIBNPP_DEV_VERSION=13.1.0.48-1
ENV NV_LIBCUBLAS_DEV_VERSION=13.4.0.1-1
ENV NV_CUDA_NSIGHT_COMPUTE_VERSION=13.2.1-1

RUN apt-get update && apt-get install -y --no-install-recommends \
    cuda-cudart-dev-13-2=${NV_CUDA_CUDART_DEV_VERSION} \
    cuda-command-line-tools-13-2=${NV_CUDA_LIB_VERSION} \
    cuda-minimal-build-13-2=${NV_CUDA_LIB_VERSION} \
    cuda-libraries-dev-13-2=${NV_CUDA_LIB_VERSION} \
    cuda-nvml-dev-13-2=${NV_NVML_DEV_VERSION} \
    libnpp-dev-13-2=${NV_LIBNPP_DEV_VERSION} \
    libcusparse-dev-13-2=${NV_LIBCUSPARSE_DEV_VERSION} \
    libcublas-dev-13-2=${NV_LIBCUBLAS_DEV_VERSION} \
    cuda-nsight-compute-13-2=${NV_CUDA_NSIGHT_COMPUTE_VERSION} \
    libnccl-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-mark hold libcublas-dev-13-2 libnccl-dev

ENV LIBRARY_PATH=/usr/local/cuda/lib64/stubs

#################### CUDA DEVEL (Ubuntu 25.10) ####################

#################### BASE BUILD IMAGE ####################
FROM cuda-devel AS base

ARG WORKSPACE_DIR
ARG CUDA_VERSION=13.2.1

RUN apt-get update -y \
    && apt-get install -y ccache software-properties-common git curl sudo gcc python3 python3-venv python3-pip python-is-python3 \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install uv and ensure it's in PATH
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && \
    ln -s /root/.local/bin/uv /usr/local/bin/uv

# Workaround for https://github.com/openai/triton/issues/2507 and
# https://github.com/pytorch/pytorch/issues/107960 -- hopefully
# this won't be needed for future versions of this docker image
# or future versions of triton.
RUN ldconfig /usr/local/cuda-$(echo $CUDA_VERSION | cut -d. -f1,2)/compat/

# cuda arch list used by torch
# can be useful for both `dev` and `test`
# explicitly set the list to avoid issues with torch 2.2
# see https://github.com/pytorch/pytorch/pull/123243
ARG torch_cuda_arch_list='7.0 7.5 8.0 8.6 8.9 9.0+PTX'
ENV TORCH_CUDA_ARCH_LIST=${torch_cuda_arch_list}
# Override the arch list for flash-attn to reduce the binary size
ARG vllm_fa_cmake_gpu_arches='80-real;90-real'
ENV VLLM_FA_CMAKE_GPU_ARCHES=${vllm_fa_cmake_gpu_arches}

WORKDIR ${WORKSPACE_DIR}

#################### BASE BUILD IMAGE ####################

#################### WHEEL BUILD IMAGE ####################
FROM base AS build

ARG WORKSPACE_DIR
ARG VLLM_VERSION=0.22.1

WORKDIR ${WORKSPACE_DIR}

ARG VENV_PATH

ENV UV_PYTHON_INSTALL_DIR=/opt/uv_python

RUN python3 -m venv ${VENV_PATH}
# Activate virtual env by setting VIRTUAL_ENV
ENV VIRTUAL_ENV=${WORKSPACE_DIR}/${VENV_PATH}
ENV PATH="${WORKSPACE_DIR}/${VENV_PATH}/bin:$PATH"

# From this point, all Python packages will be installed in the virtual environment and copied to the final image

# Copy storage metadata for editable dependency resolution
COPY --from=src /s/python/storage/pyproject.toml /s/python/storage/uv.lock storage/

COPY --from=src /s/python/kserve/pyproject.toml /s/python/kserve/uv.lock kserve/
RUN --mount=type=cache,target=/root/.cache/uv cd kserve && uv sync --active --no-cache
COPY --from=src /s/python/kserve kserve
RUN --mount=type=cache,target=/root/.cache/uv cd kserve && uv sync --active --no-cache

# Install kserve-storage
COPY --from=src /s/python/storage storage
RUN --mount=type=cache,target=/root/.cache/uv cd storage && uv pip install . --no-cache

COPY --from=src /s/python/huggingfaceserver/pyproject.toml /s/python/huggingfaceserver/uv.lock /s/python/huggingfaceserver/health_check.py huggingfaceserver/
RUN --mount=type=cache,target=/root/.cache/uv cd huggingfaceserver && uv sync --active --no-cache
COPY --from=src /s/python/huggingfaceserver huggingfaceserver
RUN --mount=type=cache,target=/root/.cache/uv cd huggingfaceserver && uv sync --active --no-cache

# Install vllm
# https://docs.vllm.ai/en/latest/models/extensions/runai_model_streamer.html, https://docs.vllm.ai/en/latest/models/extensions/tensorizer.html
# https://docs.vllm.ai/en/latest/models/extensions/fastsafetensor.html
RUN --mount=type=cache,target=/root/.cache/uv uv pip install vllm[runai,tensorizer,fastsafetensors]==${VLLM_VERSION}

# Gemma 4 needs transformers 5.5.x (the lock resolves 4.57.1, which has no
# gemma4 config; vllm 0.22.1 tests against 5.5.3 and gemma4_mm imports
# transformers.models.gemma4 at module load).
RUN --mount=type=cache,target=/root/.cache/uv uv pip install transformers==5.5.3

# vLLM 0.22.1's fused_moe loads nixl_ep, and the stock nixl-cu12 wheel links
# libcudart.so.12 (absent in this CUDA 13 image) -> ImportError that crashes
# model architecture inspection at engine init. Swap to the cu13 nixl build so
# nixl_ep resolves libcudart.so.13.
RUN --mount=type=cache,target=/root/.cache/uv \
    uv pip uninstall nixl-cu12 || true && \
    uv pip install nixl-cu13

# Build-time smoke tests: fail the BUILD (not the cluster) on the two
# regressions that took 2026.06.09-gpu down --
#   import nixl_ep                 -> the cu13 nixl / libcudart.so.13 swap
#   import ...models.gemma4_mm     -> transformers gemma4 support
RUN python3 -c "import nixl_ep" \
    && python3 -c "import vllm.model_executor.models.gemma4_mm"

# lmcache install removed: this image uses vLLM's native OffloadingConnector
# (SupportsHMA in 0.22.1) for HMA-correct CPU KV offload, not lmcache. lmcache
# 0.4.4 also links cu12 libs that break on the CUDA 13.2 base (LMCache#2843).

# Generate third-party licenses
COPY --from=src /s/python/pyproject.toml pyproject.toml
COPY --from=src /s/python/third_party/pip-licenses.py pip-licenses.py
RUN mkdir -p third_party/library && python3 pip-licenses.py

#################### WHEEL BUILD IMAGE ####################

#################### PROD IMAGE ####################
FROM cuda-runtime AS prod

ARG WORKSPACE_DIR
ARG CUDA_VERSION=13.2.1
ENV DEBIAN_FRONTEND=noninteractive

WORKDIR ${WORKSPACE_DIR}

# Install runtime dependencies
RUN apt-get update -y \
    && apt-get upgrade -y \
    && apt-get install -y software-properties-common curl \
    && apt-get install -y ffmpeg libsm6 libxext6 libgl1 gcc libibverbs-dev \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

ARG VENV_PATH
# Activate virtual env by setting VIRTUAL_ENV
ENV VIRTUAL_ENV=${WORKSPACE_DIR}/${VENV_PATH}
ENV PATH="${WORKSPACE_DIR}/${VENV_PATH}/bin:$PATH"

# Create non-root user
RUN userdel -r ubuntu && useradd kserve -m -u 1000 -d /home/kserve

COPY --from=build /opt/uv_python /opt/uv_python
COPY --from=build --chown=kserve:kserve ${WORKSPACE_DIR}/third_party third_party
COPY --from=build --chown=kserve:kserve ${WORKSPACE_DIR}/$VENV_PATH $VENV_PATH
COPY --from=build ${WORKSPACE_DIR}/kserve kserve
COPY --from=build ${WORKSPACE_DIR}/storage storage
COPY --from=build ${WORKSPACE_DIR}/huggingfaceserver huggingfaceserver

# Set a writable Hugging Face home folder to avoid permission issue. See https://github.com/kserve/kserve/issues/3562
ENV HF_HOME="/tmp/huggingface"
# https://huggingface.co/docs/safetensors/en/speed#gpu-benchmark
ENV SAFETENSORS_FAST_GPU="1"
# https://huggingface.co/docs/huggingface_hub/en/package_reference/environment_variables#hfhubdisabletelemetry
ENV HF_HUB_DISABLE_TELEMETRY="1"
# NCCL Lib path for vLLM. https://github.com/vllm-project/vllm/blob/ec784b2526219cd96159a52074ab8cd4e684410a/vllm/utils.py#L598-L602
ENV VLLM_NCCL_SO_PATH="/lib/x86_64-linux-gnu/libnccl.so.2"
# https://github.com/vllm-project/vllm/issues/6152
# Set the multiprocess method to spawn to avoid issues with cuda initialization for `mp` executor backend.
ENV VLLM_WORKER_MULTIPROC_METHOD="spawn"

USER 1000
ENV PYTHONPATH=${WORKSPACE_DIR}/huggingfaceserver
ENTRYPOINT ["python3", "-m", "huggingfaceserver"]
#################### PROD IMAGE ####################
