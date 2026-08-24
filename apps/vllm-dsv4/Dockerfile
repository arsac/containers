# vLLM with three sm_120 guards, for DeepSeek-V4-Flash on RTX PRO 6000
# Blackwell. See README.md for the failures these fix, the runtime flags they
# must be paired with, and the retirement trigger.
#
# A thin overlay, not a source build: every patch touches pure-Python files in
# site-packages, so nothing needs recompiling and the layer delta is a few KB
# on top of the stock image.
ARG VLLM_VERSION=v0.27.1
ARG VLLM_DIGEST=sha256:0a51ea5b4ae2dc5d81890e5173f54203d2a3ae0cfffe51b8fd2afd4391bfd967

FROM docker.io/vllm/vllm-openai:${VLLM_VERSION}@${VLLM_DIGEST}

ARG SITE_PACKAGES=/usr/local/lib/python3.12/dist-packages

COPY patches/ /patches/

# --forward --dry-run first so a patch that no longer applies fails the build
# rather than silently shipping an unpatched image. Same intent as the
# `git apply` guard in kserve-huggingfaceserver: upstream drift breaks the
# build, it does not degrade the artefact.
RUN set -eux; \
    cd "${SITE_PACKAGES}"; \
    for p in /patches/*.patch; do \
        echo "Applying $(basename "$p")"; \
        patch -p1 --forward --dry-run < "$p"; \
        patch -p1 < "$p"; \
    done; \
    rm -rf /patches; \
    python3 -c "import ast,sys; [ast.parse(open(f).read()) for f in ['vllm/model_executor/kernels/mhc/tilelang.py','vllm/model_executor/kernels/linear/scaled_mm/deep_gemm.py','vllm/model_executor/kernels/linear/scaled_mm/triton.py']]"

# Inherited from the base image; restated so it survives a base-image change.
ENTRYPOINT ["vllm", "serve"]
