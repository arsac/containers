# `base/pytorch` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a new slim PyTorch base image at `base/pytorch/` (CUDA 13.0, Python 3.13, PyTorch 2.11.0, uv-managed Python and venv), parallel to the existing `base/cuda-ml/` but devel-only, smaller, and minimal.

**Architecture:** Single-stage Dockerfile `FROM nvidia/cuda:13.0.3-cudnn-devel-ubuntu24.04`. uv installs Python 3.13 (managed standalone build) to `/opt/python`, creates a venv at `/opt/venv`, and runs a single resolve installing torch + torchvision + torchaudio + xformers + triton from the cu130 PyTorch index plus PyPI for transitive `nvidia-*-cu13` deps. The existing CI workflow assumes every base image has both a devel and a runtime variant; we modify `release.yaml` to gate the runtime build job on the existence of a `Dockerfile.runtime` so that this devel-only image doesn't break the matrix.

**Tech Stack:** Docker buildx + bake (HCL), uv 0.11.8, Python 3.13, PyTorch 2.11.0+cu130, NVIDIA CUDA 13.0.3 cudnn-devel base image, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-04-28-pytorch-base-image-design.md`

---

## File structure

**New files (under `base/pytorch/`):**
- `Dockerfile` — single-stage devel image
- `docker-bake.hcl` — buildx bake config with devel-only targets
- `.dockerignore` — minimal, ignore everything but Dockerfile and bake file

**Modified files:**
- `.github/workflows/release.yaml` — add a `changed-bases-runtime` output to the `prepare` job that filters `changed-bases` to those that have a `Dockerfile.runtime`; switch the `build-bases` (runtime) job to use that filtered list

**Files NOT touched:**
- `base/cuda-ml/*` — sibling image stays untouched
- `.github/workflows/image-builder.yaml` — no changes needed; the gate happens in `release.yaml`
- `.renovaterc.json5` — no annotations on the new bake/Dockerfile (matches `cuda-ml` sibling pattern)
- `build-push-local.sh` — does not work for this image (assumes a `builder` target that doesn't exist in a single-stage Dockerfile); local builds use `docker buildx bake image-devel-local` instead. Out of scope for this plan.

---

### Task 1: Scaffold `base/pytorch/` directory with `.dockerignore` and `docker-bake.hcl`

**Files:**
- Create: `base/pytorch/.dockerignore`
- Create: `base/pytorch/docker-bake.hcl`

- [ ] **Step 1: Create the directory and `.dockerignore`**

```bash
mkdir -p base/pytorch
```

Write `base/pytorch/.dockerignore` with:

```
# Ignore everything except the files we explicitly need in the build context.
*

!Dockerfile
!docker-bake.hcl
```

- [ ] **Step 2: Create `base/pytorch/docker-bake.hcl`**

Write `base/pytorch/docker-bake.hcl`:

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

- [ ] **Step 3: Verify bake config parses**

Run:

```bash
cd base/pytorch && docker buildx bake image-devel-local --print
```

Expected: prints a JSON structure containing the `image-devel-local` target with `tags` `["pytorch:cuda13.0-torch2.11-devel","pytorch:devel","pytorch:latest"]` and `dockerfile` `"Dockerfile"`. No error.

If you see `target "image-devel-local" does not exist` or HCL parse errors, fix the bake file before continuing.

- [ ] **Step 4: Verify `app-options` GitHub action would parse `VERSION` and `SOURCE`**

Run from inside `base/pytorch/`:

```bash
docker buildx bake --list type=variables,format=json --progress=quiet | jq -r '.[] | select(.name == "VERSION" or .name == "SOURCE") | "\(.name)=\(.value)"'
```

Expected output:

```
VERSION=cuda13.0-torch2.11
SOURCE=https://github.com/arsac/containers
```

This is the exact extraction the CI's `.github/actions/app-options/action.yaml` does. If it fails, the CI integration will fail later.

---

### Task 2: Write `base/pytorch/Dockerfile`

**Files:**
- Create: `base/pytorch/Dockerfile`

- [ ] **Step 1: Write the Dockerfile**

Write `base/pytorch/Dockerfile`:

```dockerfile
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

# Named uv stage so ${UV_VERSION} can be expanded — `COPY --from=<image>:${VAR}`
# does not expand ARGs even when declared in global scope; only `FROM` does.
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
```

- [ ] **Step 2: Lint the Dockerfile syntactically**

Run:

```bash
docker buildx build --check base/pytorch/
```

Expected: no warnings other than possibly a hint about pinning the uv image to a digest. If you see syntax errors (e.g., bad heredoc, malformed `ENV`), fix them before building.

---

### Task 3: Build the image locally and run smoke tests

This task pulls ~6 GB of base image and downloads ~3 GB of wheels. First build can take 10-20 minutes; subsequent builds are cache-hot.

**Files:**
- None (verification only)

- [ ] **Step 1: Build the image**

Run:

```bash
cd base/pytorch && docker buildx bake image-devel-local
```

Expected: build completes, ending with three tags applied:
```
=> => naming to docker.io/library/pytorch:cuda13.0-torch2.11-devel
=> => naming to docker.io/library/pytorch:devel
=> => naming to docker.io/library/pytorch:latest
```

If any of the in-build `RUN python -c "import torch"` or `import xformers` smoke tests fail, the build will halt with the failing assertion. Read the error and fix the spec/Dockerfile before proceeding — do **not** patch around a real ABI mismatch.

- [ ] **Step 2: Verify Python version**

Run:

```bash
docker run --rm pytorch:latest python --version
```

Expected: `Python 3.13.x` (some patch version).

- [ ] **Step 3: Verify tini entrypoint**

Run:

```bash
docker run --rm pytorch:latest /bin/sh -c 'echo $$; ps -o pid,comm 1'
```

Expected: PID 1 is `tini` (or `tini-static`); the shell is PID 2 or higher. This confirms `ENTRYPOINT ["/usr/bin/tini", "--"]` is wired up.

- [ ] **Step 4: Verify nvcc and NVRTC are available**

Run:

```bash
docker run --rm pytorch:latest /bin/sh -c 'nvcc --version && ls /usr/local/cuda/lib64/libnvrtc.so*'
```

Expected: prints CUDA 13.0.x release info and lists at least `libnvrtc.so` and `libnvrtc.so.13`.

- [ ] **Step 5: Verify torch imports and CUDA libs are wired up**

Run:

```bash
docker run --rm pytorch:latest python -c "
import torch
print(f'torch {torch.__version__} CUDA {torch.version.cuda} cuDNN {torch.backends.cudnn.version()}')
import ctypes, os
nvidia_dir = os.path.join(os.path.dirname(torch.__file__), '..', 'nvidia')
print(f'nvidia/ libs dir: {os.path.realpath(nvidia_dir)}')
print(f'cusparselt present: {os.path.isdir(os.path.join(nvidia_dir, \"cusparselt\"))}')
print(f'nvshmem present: {os.path.isdir(os.path.join(nvidia_dir, \"nvshmem\"))}')
"
```

Expected:
- `torch 2.11.0+cu130 CUDA 13.0` (or similar)
- `cuDNN ...` prints a non-`None` integer (e.g., `91900` for 9.19.0)
- `cusparselt present: True`
- `nvshmem present: True`

If any of these are False or `None`, torch is missing a transitive nvidia-* package; re-check the cu130 wheel METADATA against the spec's "Validated requirements" table.

- [ ] **Step 6: Verify the constraints file**

Run:

```bash
docker run --rm pytorch:latest cat /constraints.txt
```

Expected: lines for at least:
```
torch==2.11.0+cu130
torchvision==0.26.0+cu130
torchaudio==2.11.0+cu130
xformers==0.0.35
triton==3.6.0
nvidia-cudnn-cu13==9.19.0.56
nvidia-cusparselt-cu13==0.8.0
nvidia-nvshmem-cu13==3.4.5
nvidia-nccl-cu13==2.28.9
cuda-toolkit==13.0.2
numpy==<some 2.x version>
safetensors==<some version>
accelerate==<some version>
```

Plus other `nvidia-*-cu13` transitive deps. If any of the explicit pins above are missing, the build's regex grep is wrong.

- [ ] **Step 7: Verify image size is in the expected range**

Run:

```bash
docker images pytorch:latest --format '{{.Size}}'
```

Expected: roughly 12-14 GB. If it's under 8 GB you've likely lost the cuDNN base or the torch wheel; if it's over 20 GB, an apt cache layer wasn't cleaned.

- [ ] **Step 8: Tag with the ghcr-ready name and verify**

Run:

```bash
docker tag pytorch:latest ghcr.io/arsac/pytorch:cuda13.0-torch2.11
docker images ghcr.io/arsac/pytorch
```

Expected: shows the new tag pointing at the same image ID as `pytorch:latest`. (Don't push yet — that's CI's job once the PR merges.)

---

### Task 4: Modify `.github/workflows/release.yaml` to gate runtime builds on `Dockerfile.runtime` existence

**Files:**
- Modify: `.github/workflows/release.yaml`

The current `prepare` job emits `changed-bases` (a JSON array of changed base directory names). The `build-bases` job (which builds runtime variants) iterates that list as a matrix. For `base/pytorch/`, no `Dockerfile.runtime` exists, so the runtime build would fail.

**Fix:** add a new step in `prepare` that filters `changed-bases` to only those with a `Dockerfile.runtime`, exposed as `changed-bases-runtime`. Switch `build-bases` to consume that filtered output.

- [ ] **Step 1: Read the current `prepare` job**

Open `.github/workflows/release.yaml` and locate the `prepare` job (around line 30-55 in the current file). Note its existing `outputs` block:

```yaml
outputs:
  changed-apps: ${{ steps.changed-apps.outputs.changed_files }}
  changed-bases: ${{ steps.changed-bases.outputs.changed_files }}
```

- [ ] **Step 2: Add a `changed-bases-runtime` output and a filter step**

Edit the `prepare` job. After the `Get Changed Bases` step, add a checkout step (so the filter can read `base/*/Dockerfile.runtime`) and a filter step. Update the `outputs` block.

Replace:

```yaml
  prepare:
    name: Prepare
    runs-on: ubuntu-latest
    outputs:
      changed-apps: ${{ steps.changed-apps.outputs.changed_files }}
      changed-bases: ${{ steps.changed-bases.outputs.changed_files }}
    steps:
      - name: Get Changed Apps
        id: changed-apps
        uses: bjw-s-labs/action-changed-files@930cef8463348e168cab7235c47fe95a7a235f65 # v0.3.3
        with:
          path: apps
          include_only_directories: true
          max_depth: 1

      - name: Get Changed Bases
        id: changed-bases
        uses: bjw-s-labs/action-changed-files@930cef8463348e168cab7235c47fe95a7a235f65 # v0.3.3
        with:
          path: base
          include_only_directories: true
          max_depth: 1
```

with:

```yaml
  prepare:
    name: Prepare
    runs-on: ubuntu-latest
    outputs:
      changed-apps: ${{ steps.changed-apps.outputs.changed_files }}
      changed-bases: ${{ steps.changed-bases.outputs.changed_files }}
      changed-bases-runtime: ${{ steps.filter-runtime.outputs.bases }}
    steps:
      - name: Get Changed Apps
        id: changed-apps
        uses: bjw-s-labs/action-changed-files@930cef8463348e168cab7235c47fe95a7a235f65 # v0.3.3
        with:
          path: apps
          include_only_directories: true
          max_depth: 1

      - name: Get Changed Bases
        id: changed-bases
        uses: bjw-s-labs/action-changed-files@930cef8463348e168cab7235c47fe95a7a235f65 # v0.3.3
        with:
          path: base
          include_only_directories: true
          max_depth: 1

      - name: Checkout (for runtime filter)
        uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2
        with:
          persist-credentials: false

      - name: Filter Bases With Runtime Variant
        id: filter-runtime
        env:
          CHANGED_BASES: ${{ steps.changed-bases.outputs.changed_files }}
          DISPATCH_TYPE: ${{ github.event_name == 'workflow_dispatch' && inputs.type || '' }}
          DISPATCH_IMAGE: ${{ github.event_name == 'workflow_dispatch' && inputs.image || '' }}
        shell: bash
        run: |
          set -euo pipefail
          if [[ "$DISPATCH_TYPE" == "base" ]]; then
            candidates=$(jq -nc --arg b "$DISPATCH_IMAGE" '[$b]')
          else
            candidates="${CHANGED_BASES:-[]}"
          fi
          bases='[]'
          for b in $(echo "$candidates" | jq -r '.[]'); do
            if [[ -f "base/$b/Dockerfile.runtime" ]]; then
              bases=$(echo "$bases" | jq --arg b "$b" '. + [$b]')
            fi
          done
          echo "Runtime-variant bases: $bases"
          echo "bases=$bases" >> "$GITHUB_OUTPUT"
```

- [ ] **Step 3: Switch `build-bases` to consume the filtered output**

Locate the `build-bases` job. Replace its `if:` and `strategy.matrix.base`:

Replace:

```yaml
  build-bases:
    if: ${{ always() && !failure() && !cancelled() && (needs.prepare.outputs.changed-bases != '[]' || (github.event_name == 'workflow_dispatch' && inputs.type == 'base')) }}
    name: Build Base ${{ matrix.base }}
    needs: ["prepare", "build-bases-devel"]
    uses: ./.github/workflows/image-builder.yaml
    permissions:
      attestations: write
      contents: write
      id-token: write
      packages: write
      security-events: write
    secrets: inherit
    strategy:
      matrix:
        base: ${{ github.event_name == 'workflow_dispatch' && fromJSON(format('["{0}"]', inputs.image)) || fromJSON(needs.prepare.outputs.changed-bases) }}
      fail-fast: false
    with:
      image: ${{ matrix.base }}
      path: base
      release: ${{ github.event_name == 'workflow_dispatch' && inputs.release || github.event_name == 'push' }}
```

with:

```yaml
  build-bases:
    if: ${{ always() && !failure() && !cancelled() && needs.prepare.outputs.changed-bases-runtime != '[]' }}
    name: Build Base ${{ matrix.base }}
    needs: ["prepare", "build-bases-devel"]
    uses: ./.github/workflows/image-builder.yaml
    permissions:
      attestations: write
      contents: write
      id-token: write
      packages: write
      security-events: write
    secrets: inherit
    strategy:
      matrix:
        base: ${{ fromJSON(needs.prepare.outputs.changed-bases-runtime) }}
      fail-fast: false
    with:
      image: ${{ matrix.base }}
      path: base
      release: ${{ github.event_name == 'workflow_dispatch' && inputs.release || github.event_name == 'push' }}
```

The `build-bases-devel` job stays unchanged — every base still needs a devel build.

The downstream `build-apps` and `status` jobs both reference `build-bases` in `needs:`. When the runtime matrix is empty, `build-bases` resolves to `skipped`. The existing `status` job's checks (`contains(needs.*.result, 'failure')`) treat `skipped` as not-failure, so it still passes. No further changes required to those jobs.

- [ ] **Step 4: Verify YAML parses**

Run:

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/release.yaml'))"
```

Expected: no output (parses cleanly). If it errors with a `yaml.scanner.ScannerError` or `yaml.parser.ParserError`, the indentation or quoting is wrong.

- [ ] **Step 5: Sanity-check the matrix-filter logic locally with mock data**

Run:

```bash
# Simulate: changed-bases=["cuda-ml","pytorch"], DISPATCH_TYPE empty
CHANGED_BASES='["cuda-ml","pytorch"]'
candidates="$CHANGED_BASES"
bases='[]'
for b in $(echo "$candidates" | jq -r '.[]'); do
  if [[ -f "base/$b/Dockerfile.runtime" ]]; then
    bases=$(echo "$bases" | jq --arg b "$b" '. + [$b]')
  fi
done
echo "$bases"
```

Expected: `["cuda-ml"]` — `cuda-ml` has a `Dockerfile.runtime`, `pytorch` does not.

If the output is `[]` or `["cuda-ml","pytorch"]`, the filter logic is wrong; re-check the `[[ -f ... ]]` test.

---

### Task 5: Commit all changes

**Files:**
- All files from tasks 1, 2, and 4

- [ ] **Step 1: Review the diff**

Run:

```bash
git status
git diff --stat
```

Expected file changes:

- `base/pytorch/.dockerignore` (new)
- `base/pytorch/Dockerfile` (new)
- `base/pytorch/docker-bake.hcl` (new)
- `.github/workflows/release.yaml` (modified)
- `docs/superpowers/specs/2026-04-28-pytorch-base-image-design.md` (new — already exists from brainstorming)
- `docs/superpowers/plans/2026-04-28-pytorch-base-image.md` (new — this file)

- [ ] **Step 2: Stage and commit**

Run:

```bash
git checkout -b feat/base-pytorch
git add base/pytorch/Dockerfile base/pytorch/docker-bake.hcl base/pytorch/.dockerignore \
        .github/workflows/release.yaml \
        docs/superpowers/specs/2026-04-28-pytorch-base-image-design.md \
        docs/superpowers/plans/2026-04-28-pytorch-base-image.md
git commit -m "$(cat <<'EOF'
feat(base): add slim pytorch image (cuda13.0, py3.13, torch2.11)

New base/pytorch/ image: CUDA 13.0.3 + cuDNN devel + Python 3.13 (uv-managed) +
PyTorch 2.11.0+cu130 + xformers 0.0.35 + triton 3.6.0, plus the nvidia-* runtime
libraries torch dlopens at startup (cuSPARSELt, NVSHMEM, cuDNN, NCCL).
Devel-only — no Dockerfile.runtime, since downstream apps need nvcc/NVRTC/CUPTI.

Also gates the release.yaml `build-bases` (runtime) job on the existence of a
Dockerfile.runtime in each changed base directory, so the new devel-only image
doesn't break the matrix.
EOF
)"
```

- [ ] **Step 3: Verify the commit looks right**

Run:

```bash
git log -1 --stat
```

Expected: shows the six file changes listed above and the commit message.

---

### Task 6: Open the PR and verify CI

**Files:**
- None (CI verification only)

- [ ] **Step 1: Push the branch**

Run:

```bash
git push -u origin feat/base-pytorch
```

- [ ] **Step 2: Open the PR**

Run:

```bash
gh pr create --title "feat(base): add slim pytorch image (cuda13.0, py3.13, torch2.11)" --body "$(cat <<'EOF'
## Summary
- New `base/pytorch/` slim PyTorch base image: CUDA 13.0.3 + Python 3.13 (uv-managed) + PyTorch 2.11.0+cu130 + xformers + triton + utility deps. Devel-only (deployment target), no Dockerfile.runtime.
- Gates `release.yaml` runtime-build matrix on `Dockerfile.runtime` existence so devel-only images don't break the matrix.

## Test plan
- [ ] `docker buildx bake image-devel-local --print` succeeds locally
- [ ] `docker buildx bake image-devel-local` builds successfully locally
- [ ] In-image: `python -c "import torch; assert torch.version.cuda is not None"` passes
- [ ] In-image: `python -c "import xformers"` passes
- [ ] In-image: `cat /constraints.txt` shows expected pins
- [ ] CI `Build Base pytorch (devel)` job succeeds and pushes `ghcr.io/arsac/pytorch:cuda13.0-torch2.11-devel` etc.
- [ ] CI `Build Base pytorch` (runtime) is skipped (no `Dockerfile.runtime`)
- [ ] CI `Build Base cuda-ml` (runtime) still runs and succeeds (regression check on the workflow change)

Spec: `docs/superpowers/specs/2026-04-28-pytorch-base-image-design.md`
Plan: `docs/superpowers/plans/2026-04-28-pytorch-base-image.md`
EOF
)"
```

- [ ] **Step 3: Watch CI**

Run:

```bash
gh pr checks --watch
```

Expected:

- `Build Base pytorch (devel)` job runs and succeeds. This pushes `ghcr.io/arsac/pytorch:cuda13.0-torch2.11-devel`, `:devel`, plus semver-derived tags.
- `Build Base pytorch` (the runtime matrix) is **skipped** because `pytorch` is not in `changed-bases-runtime`.
- If `cuda-ml` is in the changed-bases list (it shouldn't be unless its files were touched), its `Build Base cuda-ml` runtime job should still run normally — confirms the workflow change didn't break the existing image.

If the devel build fails: read the job logs, fix locally, push again. Do **not** disable the smoke tests inside the Dockerfile to "make CI pass" — the smoke tests catch real ABI/install issues.

If the runtime job is *not* skipped for `pytorch`: the `changed-bases-runtime` filter or the `build-bases` `if:` conditional is wrong; re-check Task 4 Step 2 and Step 3.

- [ ] **Step 4: Verify the published image is reachable**

Once CI is green:

```bash
docker pull ghcr.io/arsac/pytorch:cuda13.0-torch2.11-devel
docker run --rm ghcr.io/arsac/pytorch:cuda13.0-torch2.11-devel python -c "import torch, xformers; print(torch.__version__, xformers.__version__)"
```

Expected: `2.11.0+cu130 0.0.35`.

- [ ] **Step 5: Merge**

Run:

```bash
gh pr merge --merge --auto
```

Or merge via GitHub UI per repo policy. Once merged, the published `:latest` tag will be pinned to the new build.

---

## Self-review notes

**Spec coverage:**
- Goals 1-9 (Python 3.13, CUDA 13.0, PyTorch 2.11 cu130, cuDNN, NVRTC, cuSPARSELt, NVSHMEM, uv, devel variant) — all satisfied by Task 2's Dockerfile and verified in Task 3 Steps 4-6.
- Architecture (single-stage, uv-managed Python, venv at /opt/venv, constraints file, ENTRYPOINT tini) — Task 2.
- File-by-file (Dockerfile + docker-bake.hcl + .dockerignore) — Tasks 1 and 2.
- Build & CI section's runtime-gating fix — Task 4.
- All five Risks have mitigations baked into the Dockerfile (in-build smoke tests for ABI; UV_VERSION pinned; UV_LINK_MODE=copy; constraints regex includes nvidia- and cuda-toolkit).

**No placeholders detected.** Every step has concrete commands, code, or file paths.

**Type/name consistency:** target names (`image-devel`, `image-devel-local`, `image-devel-all`), env var names (`UV_*`, `VIRTUAL_ENV`, `CPATH`), and ARG names match across Tasks 1, 2, and the spec. Output names (`changed-bases-runtime`) match between Task 4 Steps 2 and 3.
