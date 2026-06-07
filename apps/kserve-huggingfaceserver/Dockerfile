ARG VERSION="v0.19.0-rc0"

FROM kserve/huggingfaceserver:${VERSION}-gpu

# Overlay on the upstream GPU image with the fixes needed to serve
# google/gemma-4-31B-it (with lmcache + hybrid KV cache) and
# jinaai/jina-reranker-v3. Replaces the full-build fork at
# github.com/arsac/kserve (gemma4-stable / gemma4-cu130 branches).
ARG TRANSFORMERS_VERSION=5.5.3
ARG LMCACHE_VERSION=0.4.6

USER root

# The prod venv is uv-managed and ships neither pip nor uv; bring uv along.
# It targets the venv via the VIRTUAL_ENV env already set in the base image.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# transformers: the upstream image resolves 4.57.x, which has no gemma4 config;
#   vllm's gemma4 modules import transformers.models.gemma4 directly and fail
#   without 5.5+. 5.5.3 matches vllm v0.20.0's test lockfile.
# lmcache: the 0.4.4 wheel pinned upstream links cu12 libraries (cupy-cuda12x,
#   libcudart.so.12) that don't exist in the cu13 image (LMCache/LMCache#2843).
#   Uninstall cupy-cuda12x first: both cupy wheels ship the same `cupy` package
#   dir, so upgrading in place would leave mixed cu12/cu13 binaries behind.
#   lmcache's `nixl` meta-dep pulls both nixl-cu12 and nixl-cu13; the Python
#   module lives in the meta package and the cuNN packages only carry native
#   libs in separate dirs, so dropping nixl-cu12 alone is safe and sufficient.
# peft: required at runtime by jina-embeddings-v5's custom model code
#   (auto_map registration fails without it and vLLM can't find the module).
RUN uv pip uninstall cupy-cuda12x && \
    uv pip install --no-cache \
        transformers==${TRANSFORMERS_VERSION} \
        lmcache==${LMCACHE_VERSION} \
        peft && \
    uv pip uninstall nixl-cu12

# Patch vLLM's LMCacheConnectorV1 wrapper with SupportsHMA so the hybrid KV
# cache manager stays enabled alongside --kv-transfer-config. Without it,
# sliding-window models like Gemma 4 allocate full-context KV for every layer
# (~110GB at 128k context instead of ~10.6GB). This patch is the entire HMA
# story (not implemented upstream as of vLLM 0.22):
#  - vLLM's factory gates HMA on supports_hma(<wrapper class>), and the
#    scheduler then calls request_finished_all_groups(request, group_lists)
#    instead of request_finished(request, group_lists[0]).
#  - lmcache's multi-group data path (kv_layer_groups) already exists in
#    0.4.6; its request_finished takes a flat list[int] and returns the
#    exact tuple shape SupportsHMA requires, so flatten-and-delegate works.
RUN python3 -c "import vllm.distributed.kv_transfer.kv_connector.v1.lmcache_connector as m; p=m.__file__; s=open(p).read(); s=s.replace('from vllm.distributed.kv_transfer.kv_connector.v1.base import (','from vllm.distributed.kv_transfer.kv_connector.v1.base import (\n    SupportsHMA,'); s=s.replace('class LMCacheConnectorV1(KVConnectorBase_V1):','class LMCacheConnectorV1(KVConnectorBase_V1, SupportsHMA):'); s=s.replace('        return self._lmcache_engine.request_finished(request, block_ids)\n','        return self._lmcache_engine.request_finished(request, block_ids)\n\n    def request_finished_all_groups(self, request, block_ids):\n        flat_ids = [bid for group in block_ids for bid in group]\n        return self._lmcache_engine.request_finished(request, flat_ids)\n'); assert 'class LMCacheConnectorV1(KVConnectorBase_V1, SupportsHMA):' in s, 'HMA patch: class anchor not found'; assert 'request_finished_all_groups' in s, 'HMA patch: method not inserted'; open(p,'w').write(s); print(f'Patched {p}')"

# flashinfer AOT jit-cache matching the flashinfer-cubin version vllm pulls in:
# the image has no nvcc, so kernels missing from the AOT cache cannot be
# JIT-compiled at runtime. Only a cu130 wheel index exists; cu130 wheels are
# minor-version compatible with the CUDA 13.2 runtime.
# https://docs.flashinfer.ai/installation.html
RUN FLASHINFER_VERSION=$(uv pip show flashinfer-cubin | awk '/^Version:/{print $2}') && \
    uv pip install --no-cache flashinfer-jit-cache==${FLASHINFER_VERSION} \
        --extra-index-url https://flashinfer.ai/whl/cu130 && \
    flashinfer show-config

# PyTorch libs (libc10.so, libtorch_cpu.so, etc.) for lmcache's c_ops
# extension: the wheel links them without an RPATH, so loading c_ops before
# torch is imported fails otherwise. The venv interpreter is a uv-managed
# Python 3.12 (not Ubuntu 25.10's system 3.13).
ENV LD_LIBRARY_PATH="/kserve-workspace/prod_venv/lib/python3.12/site-packages/torch/lib:${LD_LIBRARY_PATH}"

USER 1000
