# Slim one-package overlay on stock kserve/huggingfaceserver.
#
# vLLM 0.20.0 (in the stock image) natively registers JinaForRanking,
# Gemma4ForConditionalGeneration/ForCausalLM, and the gemma4 tool/reasoning
# parsers — so the only gap is transformers: the base resolves 4.57.1, which
# lacks transformers.models.gemma4 (Gemma 4 needs >=5.5). Everything else the
# prior overlay carried (lmcache, the SupportsHMA monkey-patch, the torch
# LD_LIBRARY_PATH hack, peft, flashinfer-jit-cache) is dropped:
#  - lmcache + SupportsHMA: root cause of the Gemma 4 multi-group KV livelock/
#    crash; replaced by vLLM-native HMA + (durably) OffloadingConnector.
#  - peft: not a huggingfaceserver dependency; jina-reranker-v3 modeling.py has
#    zero peft refs (embeddings run on TEI, a separate image).
#  - flashinfer-jit-cache: gemma4 uses TRITON_ATTN, the reranker uses
#    FLASH_ATTN; flashinfer-python is already in the base. Re-add ONLY if boot
#    raises a CUDA "no kernel image" error.
#
# Carrying zero patches against fast-moving vLLM internals is the point: the
# previous fork's source builds and monkey-patches are what crash-looped on
# rebuilds. This rides the stock base; when an upstream tag bundles
# transformers >=5.5, even this overlay disappears.

# Base tag is renovate-tracked via VERSION in docker-bake.hcl (repo's bake
# custom manager); passed in as a build ARG. v0.19.0-rc0 bundles vLLM 0.20.0.
ARG VERSION=v0.19.0-rc0
FROM kserve/huggingfaceserver:${VERSION}-gpu

ARG TRANSFORMERS_VERSION=5.5.3

USER root

# The prod venv is uv-managed (and ships neither pip nor uv); install with uv,
# the venv's native tool, targeting the active venv via the base's VIRTUAL_ENV.
COPY --from=ghcr.io/astral-sh/uv:latest /uv /usr/local/bin/uv

# The stock base bakes in lmcache 0.4.4 + its cu12 deps (cupy-cuda12x,
# nixl-cu12) via the upstream Dockerfile. We do NOT use lmcache (the durable
# fix is vLLM's native OffloadingConnector), and cupy-cuda12x links
# libcudart.so.12 — which does not exist in this cu13 image. Left in place it's
# a dormant landmine: any future --kv-transfer-config=LMCacheConnectorV1 would
# crash-loop on libcudart.so.12. Strip it so that failure mode is impossible
# and the image is cu13-coherent. (Package-level removal, not a patch against
# vLLM internals — robust across base bumps.) `|| true` so the build still
# succeeds if a future upstream base stops shipping these (nothing to remove).
RUN uv pip uninstall lmcache cupy-cuda12x nixl-cu12 || true

RUN uv pip install --no-cache "transformers==${TRANSFORMERS_VERSION}"

USER 1000
