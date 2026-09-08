# vLLM for Qwen3.8-Flash-Next (arch qwen4_exp) on sm_120, carrying the one
# change we are waiting on upstream: PR #53899 (VLLM_PLE_CPU_OFFLOAD - the 51B
# n-gram table in pinned host RAM, without which the FP8 checkpoint does not
# fit 2x 96GB with usable KV).
#
# Base: vLLM's per-commit post-merge CI image at the EXACT main commit the PR
# is rebased on, so patches/ applies by construction and the result matches
# what the PR's own CI tests. Not the nightly tag: main's qwen4_exp churn
# conflicts with the PR within days (ple_layer.py was 4 conflicts deep against
# main two days after the PR's last rebase).
#
# Re-pin procedure (when the PR rebases, or for fresher main):
#   1. BASE_SHA  = the PR's current base.sha (gh api .../pulls/53899)
#   2. BASE_DIGEST = manifest digest of vllm-ci-postmerge-repo:<BASE_SHA>
#   3. regenerate the patch: compare/<base>...<head>.diff, vllm/ hunks only
#   4. `git apply --check` against the base tree before committing
#
# RETIREMENT: when #53899 merges, delete this app and point the ServingRuntime
# back at vllm/vllm-openai:nightly@digest. Patch-count zero = no image.
ARG BASE_SHA=f2e2936f91a794513af74d009286c69e3fb2592b
ARG BASE_DIGEST=sha256:249f724bfb5af5dd4e53bfcb0208e27d691f2db772346f2097fa070e249dceb3

FROM public.ecr.aws/q9t5s3a7/vllm-ci-postmerge-repo@${BASE_DIGEST}

COPY patches/ /tmp/patches/
RUN set -eu; \
    command -v git >/dev/null || { apt-get update && apt-get install -y --no-install-recommends git && rm -rf /var/lib/apt/lists/*; }; \
    SITE=$(python3 -c "import vllm, os; print(os.path.dirname(os.path.dirname(vllm.__file__)))"); \
    cd "${SITE}"; \
    for p in /tmp/patches/*.patch; do \
        echo "Applying $(basename "${p}")"; \
        git apply --verbose "${p}"; \
    done; \
    rm -rf /tmp/patches

# Fail the BUILD, not the cluster: the offload worker must import, the env
# knob must exist, and the OpenAI server entrypoint + CLI + compiled CUDA
# kernels must be intact (CI images are not the openai-image build, so prove
# the serving surface is there). No `vllm --help`: building the arg parser
# infers the device, which fails on GPU-less CI runners.
RUN python3 -c "import vllm.v1.ple_offload.worker" \
    && python3 -c "import vllm.envs as e; assert hasattr(e, 'VLLM_PLE_CPU_OFFLOAD')" \
    && python3 -c "import vllm.entrypoints.openai.api_server" \
    && python3 -c "import vllm.entrypoints.cli.main" \
    && python3 -c "import importlib.util as u; assert u.find_spec('vllm._C_stable_libtorch')" \
    && command -v vllm >/dev/null

# The CI base bakes test-mode env: VLLM_GPU_SYNC_CHECK=error turns any
# GPU<->CPU sync warning into an engine kill (took chat down twice in 34m).
# Docker ENV cannot unset a variable and empty string fails vLLM's choice
# validation, so scrub it at interpreter startup instead - sitecustomize runs
# before vllm reads the env, and works under any command/entrypoint override.
RUN SITE=$(python3 -c "import vllm, os; print(os.path.dirname(os.path.dirname(vllm.__file__)))") \
 && printf 'import os\nos.environ.pop("VLLM_GPU_SYNC_CHECK", None)\n' >> "${SITE}/sitecustomize.py" \
 && VLLM_GPU_SYNC_CHECK=error python3 -c "import vllm.envs as e; assert e.VLLM_GPU_SYNC_CHECK is None, 'scrub failed'"

# Match vllm/vllm-openai so the KServe ServingRuntime contract is identical
# (it sets `command: [vllm, serve]` anyway; this keeps docker-run parity).
ENTRYPOINT ["vllm", "serve"]
