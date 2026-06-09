# kserve-huggingfaceserver (vLLM 0.22.1 self-build)

A self-built kserve huggingfaceserver GPU image on **vLLM 0.22.1**, because
aggressive CPU KV offload needs vLLM's native `OffloadingConnector` — which only
implements `SupportsHMA` (works with HMA enabled, required for Gemma 4's 128k
window) on **0.22+**, and no stock kserve image ships >0.20.0.

## How it's built

`Dockerfile` is a **vendored copy of upstream kserve's
`huggingface_server.Dockerfile`** (pinned via `KSERVE_REF`), with our downstream
changes:

- **Inline edits** (Dockerfile): `VLLM_VERSION` 0.20.0 → 0.22.1; drop the
  `lmcache==0.4.4` install (root cause of the Gemma 4 multi-group KV livelock —
  native `OffloadingConnector` replaces it); add `transformers==5.5.3` (kserve's
  lock pins 4.57.1, which lacks `transformers.models.gemma4`); swap nixl-cu12 →
  nixl-cu13 (vLLM 0.22.1's fused_moe loads `nixl_ep`, which links
  libcudart.so.13); a build-time `import nixl_ep && import gemma4_mm` smoke test.
- **Source patches** (`patches/`):
  - `0001` — the vLLM 0.22 serving-constructor API change in `vllm_model.py`
    (`ChatTemplateConfig`, `supported_tasks`).
  - `0002` — `pyproject.toml` license allowlist: ignore `pyelftools` (Public
    Domain) and `nvidia-cutlass-dsl-libs-cu13` (proprietary), two new 0.22.1
    transitive deps that otherwise fail kserve's `pip-licenses.py` gate.

The `src` stage fetches the pinned kserve tree (shallow, by SHA) and applies
`patches/`; the build stage's `COPY`s pull from that stage (`--from=src`) instead
of the build context. So it's a **single self-contained app Dockerfile** — no
clone-first CI hook; `image-builder` bakes it like any other app.

```sh
docker buildx bake image-all              # KSERVE_REF default is in docker-bake.hcl
```

`git apply` in the `src` stage fails loudly if the patch doesn't match the
pinned ref, so an upstream refactor breaks the build rather than shipping a
broken image.

## Why vendor (vs the patch-not-fork / vs the arsac/kserve fork)

The downstream change is small, but kserve builds from its own complex
multi-stage CUDA Dockerfile. We vendor it (rather than orchestrate a
clone-then-build-their-Dockerfile) so the build is a normal app Dockerfile with
no CI hook. Trade-off: the ~170 lines of CUDA/base stages we *don't* modify are
frozen at `KSERVE_REF` until we bump it — acceptable because (a) the prod stage
runs `apt-get upgrade -y` so OS CVEs are still picked up, and (b) this image is
temporary.

## ⚠️ Status

- The patch is pending confirmation by the in-flight build + GPU validation
  (gemma4 TRITON_ATTN >256-token + multimodal + tool-calling, jina-reranker-v3
  `/v1/rerank`).
- **Offload follow-up (home-ops):** once live, add
  `--no-disable-hybrid-kv-cache-manager` + `--kv-transfer-config` with
  `OffloadingConnector` / `CPUOffloadingSpec` (`cpu_bytes_to_use ~64GiB`,
  `store_threshold 0`, `eviction_policy`) + a pod memory bump.

## Retirement trigger

The day kserve ships a stock vLLM 0.22+ GPU image, delete this whole app and go
back to a thin overlay (or fully stock) on that base.
