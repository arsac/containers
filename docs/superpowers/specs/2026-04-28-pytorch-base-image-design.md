# `base/pytorch` — slim PyTorch base image (CUDA 13.0, Python 3.13)

**Date:** 2026-04-28
**Status:** Design approved, ready for implementation plan

## Overview

A new sibling base image at `base/pytorch/`, parallel to the existing `base/cuda-ml/`. Provides a slim PyTorch foundation on CUDA 13.0 + Python 3.13 + PyTorch 2.11.0, intended as the deployment target for downstream apps that need a CUDA-13 dev environment with PyTorch and uv preinstalled. Apps build on top of this image rather than reinstalling torch.

## Goals

- Standalone, deployable image (devel variant only — see non-goals).
- uv-managed Python 3.13 (`UV_PYTHON_PREFERENCE=only-managed`).
- PyTorch 2.11.0 + torchvision 0.26.0 + torchaudio 2.11.0 + xformers 0.0.35 + triton 3.6.0, all from the cu130 PyTorch index.
- All NVIDIA runtime libraries that torch dlopens at startup are present (cuDNN, cuSPARSELt, NVSHMEM, NCCL, CUDA toolkit pip umbrella).
- Full devel toolchain available for downstream apps that compile CUDA extensions (nvcc, NVRTC, CUPTI, cuDNN headers).
- Common build/utility helpers (`accelerate`, `numpy`, `safetensors`, `nvidia-ml-py`, `sympy`, `packaging`, `pybind11`, `ninja`, `psutil`, `wheel`).
- Constraints file at `/constraints.txt` for downstream apps to pin against.

## Non-goals

- **No runtime (slim) variant.** `nvidia/cuda:*-runtime-*` images deliberately omit nvcc / NVRTC / CUPTI, and these are required for `torch.compile` / Triton JIT and for downstream apps that compile CUDA extensions. Ship only the devel image as the deployment target.
- **No flash-attn.** v2.8.x has no upstream cu13 wheels and multiple open build-failure issues against CUDA 13. v4 is alpha and on consumer Blackwell (SM 12.0) it falls back to SM80 kernels (~5% slower than FA2 in the only published benchmark, with open crash reports). Apps that need flash attention install per-app or use `torch.nn.functional.scaled_dot_product_attention` (cuDNN-backed FA-style kernels via PyTorch SDPA on Blackwell).
- **No heavy ML extras.** No xformers-source-builds, hunyuan3d, diso, nvdiffrast, sageattention, opencv, librosa, ffmpeg, etc. Those stay in `base/cuda-ml/` (cu128/py312/full stack) and apps that need them either use `cuda-ml` directly or install on top of `base/pytorch/`.
- **No `pyproject.toml` + `uv.lock`.** A base image isn't a project; the lockfile pretense (`package = false`) adds two committed files for what amounts to a version-pin list. Pins live in `Dockerfile` `ARG`s, matching the existing `base/cuda-ml/` pattern.
- **No `--generate-hashes` / wheel-hash reproducibility.** Not conventional for ML/AI base images at this scale (`pytorch/pytorch`, `nvidia/cuda`, the existing `cuda-ml` all use plain version pins). Version pin + immutable index covers the realistic threat model.

## Validated requirements

| # | Requirement | How satisfied |
|---|---|---|
| 1 | Python 3.13 | `uv python install 3.13` to `/opt/python`, managed standalone build |
| 2 | CUDA 13.0 | `nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04` (13.0.0 tag does not exist on Docker Hub; .3 is the latest patch) |
| 3 | PyTorch 2.11 cu130 | `torch==2.11.0` from `https://download.pytorch.org/whl/cu130`, plus matching torchvision 0.26.0 + torchaudio 2.11.0 + xformers 0.0.35 + triton 3.6.0 |
| 4 | cuDNN | `cudnn-devel` base image variant ships system cuDNN at `/usr/lib/x86_64-linux-gnu/`. Torch additionally pulls `nvidia-cudnn-cu13==9.19.0.56` as a transitive dep — torch uses the wheel-bundled version at runtime |
| 5 | NVRTC | Present in `cuda-13-0` toolkit installed by the `*-devel-*` image. Torch also transitively pulls `cuda-toolkit[...nvrtc]==13.0.2` (PyPI umbrella) |
| 6 | cuSPARSELt | Torch declares `Requires-Dist: nvidia-cusparselt-cu13==0.8.0; platform_system == "Linux"`, auto-installed. Ships `libcusparseLt.so.0` at `site-packages/nvidia/cusparselt/lib/`. Torch's `__init__.py` adds the path to the loader |
| 7 | NVSHMEM | Same pattern: `Requires-Dist: nvidia-nvshmem-cu13==3.4.5; platform_system == "Linux"`. Ships `libnvshmem_host.so.3` at `site-packages/nvidia/nvshmem/lib/` |
| 8 | uv | `COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/`. Python managed by uv (`UV_PYTHON_PREFERENCE=only-managed`, `UV_PYTHON_INSTALL_DIR=/opt/python`); venv created by uv at `/opt/venv`; packages installed via `uv pip install --python /opt/venv/bin/python` |
| 9 | devel variant | `cudnn-devel` base includes nvcc, NVRTC, CUPTI, cuDNN headers, full toolkit. No runtime variant ships |

## Architecture

```
base/pytorch/
├── Dockerfile          # devel image, deployment target
├── docker-bake.hcl     # build config + tags
└── .dockerignore       # ignore everything but the Dockerfile and bake file
```

**Single-stage Dockerfile** built `FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04`. uv installs Python 3.13 to `/opt/python`, creates a venv at `/opt/venv`, and installs torch + ecosystem from the cu130 index plus PyPI for the nvidia-* transitive deps. `/opt/venv/bin` is at the front of `PATH` so `python`, `pip` (via uv), and tools resolve correctly without explicit activation in `RUN`/`CMD` layers or `docker run`. Constraints file written to `/constraints.txt` for downstream apps to pin against.

### Image contents

**System packages (apt):** `build-essential`, `ninja-build`, `git`, `curl`, `ca-certificates`, `tini`. Plus the `cuda-13-0` toolkit + `libcudnn9-cuda-13` already provided by the base image.

**Python packages (cu130 index):**
- `torch==2.11.0`
- `torchvision==0.26.0`
- `torchaudio==2.11.0`
- `xformers==0.0.35` (abi3 wheel on cu130 index, requires torch≥2.10 ✓)
- `triton==3.6.0` (only on the PyTorch index — not on PyPI)

**Python packages (PyPI, pulled transitively by torch):**
- `nvidia-cudnn-cu13==9.19.0.56`
- `nvidia-cusparselt-cu13==0.8.0`
- `nvidia-nvshmem-cu13==3.4.5`
- `nvidia-nccl-cu13==2.28.9`
- `cuda-toolkit==13.0.2` (umbrella package: cublas, cudart, cufft, cufile, cupti, curand, cusolver, cusparse, nvjitlink, nvrtc, nvtx)

**Python packages (PyPI, explicit utility deps):**
- `accelerate`, `numpy`, `safetensors`, `nvidia-ml-py`, `sympy`, `packaging`, `pybind11`, `ninja`, `psutil`, `wheel`

### Environment

```
DEBIAN_FRONTEND=noninteractive
PYTHONDONTWRITEBYTECODE=1
PYTHONUNBUFFERED=1
CUDA_HOME=/usr/local/cuda
CPATH=/usr/local/cuda/include          # broader than CPLUS_INCLUDE_PATH; covers C and C++
TORCH_CUDA_ARCH_LIST="12.0"            # consumer Blackwell (RTX 5090, RTX PRO 6000 Workstation)
UV_COMPILE_BYTECODE=1
UV_LINK_MODE=copy                      # load-bearing — see Risks
UV_HTTP_TIMEOUT=300
UV_PYTHON_INSTALL_DIR=/opt/python
UV_PYTHON_PREFERENCE=only-managed
VIRTUAL_ENV=/opt/venv                  # directs uv pip to the venv without --python
PATH=/usr/local/cuda/bin:/opt/venv/bin:${PATH}
```

### Constraints file

Written by `uv pip freeze` (auto-targets `/opt/venv` via `VIRTUAL_ENV`) filtered through `grep -E` for the regex:

```
^(torch|torchvision|torchaudio|xformers|triton|numpy|safetensors|accelerate|nvidia-|cuda-toolkit)==
```

Wider than the existing `cuda-ml/constraints.txt` regex — adds `nvidia-` and `cuda-toolkit` so downstream apps inherit the locked NVIDIA library pins and don't accidentally upgrade `nvidia-cusparselt-cu13` or `cuda-toolkit` out from under torch.

## File-by-file design

### `base/pytorch/Dockerfile`

```dockerfile
ARG CUDA_VERSION="13.0.3"
ARG CUDA_DISTRO="ubuntu24.04"
ARG UV_VERSION="0.11.8"

# Named uv stage so ${UV_VERSION} can be expanded — `COPY --from=<image>:${VAR}`
# does not expand ARGs even when they're declared in global scope; only `FROM`
# does. The named-stage indirection is the canonical Docker workaround.
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
# `--index-strategy unsafe-best-match` makes resolution deterministic across the
# cu130 index + PyPI mix (default `first-index` stops at the first index that has
# a candidate, which is brittle when transitive deps live on PyPI only).
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

RUN uv pip freeze | grep -E \
    "^(torch|torchvision|torchaudio|xformers|triton|numpy|safetensors|accelerate|nvidia-|cuda-toolkit)==" \
    > /constraints.txt && \
    echo "Constraints:" && cat /constraints.txt

# Build-time validation. `torch.cuda.is_available()` requires `--gpus all` and is
# intentionally not checked here — only that torch was built against CUDA and that
# xformers' py3-none wheel imports against torch's C++ ABI on cp313.
RUN python -c "import torch; print(f'PyTorch {torch.__version__} CUDA {torch.version.cuda}'); assert torch.version.cuda is not None" && \
    python -c "import xformers; print(f'xformers {xformers.__version__}')"

ENTRYPOINT ["/usr/bin/tini", "--"]
```

### `base/pytorch/docker-bake.hcl`

```hcl
target "docker-metadata-action" {}

variable "APP" {
  default = "pytorch"
}

variable "VERSION" {
  // Format: cuda{CUDA_VERSION}-torch{TORCH_VERSION}
  default = "cuda13.0-torch2.11"
}

variable "SOURCE" {
  default = "https://github.com/arsac/containers"
}

variable "VENDOR" {
  default = "arsac"
}

group "default" {
  targets = ["image-devel-local"]
}

target "image-devel" {
  inherits   = ["docker-metadata-action"]
  dockerfile = "Dockerfile"
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-devel-local" {
  inherits = ["image-devel"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}-devel", "${APP}:devel", "${APP}:latest"]
}

target "image-devel-all" {
  inherits  = ["image-devel"]
  platforms = ["linux/amd64"]
}
```

Notes:
- Only devel targets exist (no `image` / `image-local` / `image-all` runtime targets).
- `image-devel-local` adds `${APP}:latest` so a freshly-built local image is reachable as `pytorch:latest` for downstream-app local builds.
- `cudnn-devel` adds ~3.5 GB to the base layer vs. plain `devel`. Estimated final image ~12-14 GB. Acceptable since this is the deployment target and the CUDA libs are required.

## Build & CI

**Local build:**
```
cd base/pytorch
docker buildx bake image-devel-local
```

**Root `build-push-local.sh`:** existing script handles base images by directory walk; should work without modification. Verify during implementation.

**GitHub Actions:** `.github/workflows/release.yaml` auto-detects new directories under `base/**` via `bjw-s-labs/action-changed-files` and dispatches to `image-builder.yaml`. The existing `build-bases-devel` job builds devel targets; the `build-bases` job builds runtime targets.

**Implication for CI:** the existing `release.yaml` calls `build-bases` (runtime) for every changed base. Since `base/pytorch/`'s bake file has no runtime targets, that job will fail at `docker buildx bake --print` for the missing target.

**Resolution:** modify `.github/workflows/release.yaml` to gate the `build-bases` (runtime) job on the existence of a `Dockerfile.runtime` in the base directory. A small composite-action or inline check at the matrix level — e.g., a `runtime-bases` job output that filters `changed-bases` by whether `base/<name>/Dockerfile.runtime` exists — keeps the workflow declarative and avoids publishing duplicate-tag aliases (which would be misleading: `:runtime` consumers would receive the full 12-14 GB devel image). The earlier alternative (stub `image` targets in the bake file aliasing `:devel`) is rejected because publishing identical content under different tag suffixes hides the fact that this image has no runtime variant.

**Renovate:** existing `.renovaterc.json5` regex manager scans for `# datasource=X depName=Y` annotations next to bake variables. The existing `base/cuda-ml/` doesn't use these (manual bumps). Match the pattern: no annotations on the new bake file — manual bumps via PR.

## Risks & open questions

**`cuda-toolkit` PyPI umbrella + system toolkit duplication.**
The base image installs the CUDA 13 toolkit via apt (in `/usr/local/cuda`), and torch's transitive deps install the `cuda-toolkit==13.0.2` PyPI umbrella into `site-packages/nvidia/`. They coexist; torch loads from `site-packages/nvidia/`, while `nvcc` and CUDA headers come from `/usr/local/cuda`. Disk overhead ~1-2 GB. Eliminating it would require either (a) skipping the apt toolkit and relying entirely on the pip-installed one (loses nvcc, headers — fails req #5/#9), or (b) excluding the pip umbrella from torch's deps (would break torch). Accept the duplication; document in the Dockerfile.

**Triton 3.6.0 not on PyPI.**
PyPI's latest is triton 3.5.x; 3.6.0 only exists on the PyTorch index. Resolved deterministically by `--index-strategy unsafe-best-match` on `uv pip install`: uv considers all configured indexes and selects the best version match for each name, regardless of which index it was found on first. (Default `first-index` strategy stops at the first index with any candidate, which works coincidentally today because triton is on the torch index but is brittle.)

**xformers 0.0.35 abi3 vs cp313.**
The cu130 index ships xformers as a `py3-none-manylinux_2_28_x86_64.whl` (universal py3 stable-ABI wheel), not a cp313-tagged one. py3-none wheels still link against torch's C++ ABI, which is cp-version-sensitive — if xformers' published wheel was built against a different torch ABI hash than 2.11+cu130/cp313 ships, you get import-time `_C` symbol errors. Mitigated by the `import xformers` smoke test in the Dockerfile build, which fails the image build if the ABI doesn't line up.

**`cuda-toolkit` PyPI umbrella patch-version skew.**
The apt-installed system toolkit is 13.0.3 (in `/usr/local/cuda`), the wheel-installed toolkit is `cuda-toolkit==13.0.2` (in `site-packages/nvidia/`). Downstream extensions built against `/usr/local/cuda/include` and then dlopening from `site-packages/nvidia/` at runtime can hit subtle ABI skew in `nvjitlink`/`nvrtc` minor versions. Low impact in practice (NVIDIA maintains intra-13.0.x ABI), but worth knowing when debugging extension build failures. Future cu130 patch updates may close the gap.

**`LD_LIBRARY_PATH` not set; wheel-side libs found only via torch's loader.**
`libcusparseLt.so.0` (in `site-packages/nvidia/cusparselt/lib/`) and `libnvshmem_host.so.3` (in `site-packages/nvidia/nvshmem/lib/`) are added to the dlopen path by `torch/__init__.py` at import time. Code that calls `ctypes.CDLL("libcusparseLt.so.0")` *before* importing torch — uncommon but possible in profiling/diagnostic code — will not find these libraries. If a downstream app needs this guarantee, set `LD_LIBRARY_PATH` to include both directories in its own image layer.

**`UV_LINK_MODE=copy` is load-bearing.**
`uv venv` and `uv pip install` default to `hardlink`, which fails when the venv (`/opt/venv`) and the uv cache (`/root/.cache/uv`) are on different filesystems — common in Docker layered storage. `UV_LINK_MODE=copy` is set explicitly to avoid this. A future "drop it for speed" change would silently break the build; do not remove without re-verifying both build paths.

**Image-rebuild cache invalidation when uv version bumps.**
The `UV_VERSION` ARG pin to `0.11.8` (vs `:latest`) means uv version is part of the layer cache key — bumping it invalidates the apt layer below. This is the right tradeoff: silent bumps via `:latest` defeat reproducibility and can change resolver behavior under your feet. Bump `UV_VERSION` deliberately via PR; expect a full rebuild.

## Out of scope / future work

- **`base/cuda-ml/` cu130 migration.** Currently cu128/py312 with a heavy stack. A future PR could either bump it in place or layer it `FROM ghcr.io/arsac/pytorch:cuda13.0-torch2.11` once both share cu130/py313, eliminating duplicate torch installs across the base family.
- **Adding flash-attn back** when v4 has functional SM 12.0 kernels (PRs #2349, #2406, #2499 merged) or when v2.x publishes confirmed cu13 wheels.
- **Multi-arch CUDA support.** Currently `TORCH_CUDA_ARCH_LIST="12.0"`. If the cluster adds Hopper (H100, SM 9.0) or Ada (L40, SM 8.9) nodes, expand the list and rebuild.
- **Renovate annotations** on the bake file and Dockerfile `ARG`s once added to `base/cuda-ml/` too — keep siblings consistent.
- **`--torch-backend=cu130` flag.** uv's modern torch-CUDA selection flag (`uv pip install torch --torch-backend=cu130`) is declined here because it only handles `torch` itself; we still need `torchvision`, `torchaudio`, `xformers`, and `triton` from the same cu130 index. Sticking with `--index-url` + `--index-strategy unsafe-best-match` covers all five names uniformly. Re-evaluate if uv extends `--torch-backend` to cover the broader ecosystem.
