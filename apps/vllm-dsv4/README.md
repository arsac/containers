# vllm-dsv4 (vLLM 0.27.1 + two sm_120 DeepGEMM guards)

Stock vLLM cannot load **DeepSeek-V4-Flash** on **RTX PRO 6000 Blackwell
(sm_120)**. Two DeepGEMM entry points are reached unconditionally on an
architecture DeepGEMM has no kernels for, and both abort during model load.
This image adds the missing guards so those paths take the fallbacks that
already exist upstream.

## The two failures

Both reproduced on bachelor, `vllm/vllm-openai:v0.27.1`, TP=2, weights from a
local cache:

1. **FP8 block-scaled linear** — `DeepGemmFp8BlockScaledMMKernel` is selected,
   then dies in `process_weights_after_loading`:

   ```
   transform_sf_into_required_layout ->
   Assertion error (deepgemm-src/csrc/apis/layout.hpp:60): Unknown SF transformation
   ```

2. **mHC pre-broadcast** — with DeepGEMM disabled the first failure goes away
   and the next one appears:

   ```
   Assertion error (deepgemm-src/csrc/apis/hyperconnection.hpp:56):
   Unsupported architecture
   ```

The second is the interesting one: `VLLM_USE_DEEP_GEMM=0` is honoured by
`mhc_pre_tilelang` and `mhc_fused_post_pre_tilelang`, which fall back to
`_tilelang_hc_prenorm_gemm` — but `mhc_pre_broadcast_tilelang` calls
`tf32_hc_prenorm_gemm` unconditionally. So no environment variable can avoid
it.

## Why patches rather than a flag

`is_deep_gemm_supported()` is architecture-blind: it checks the env flag, that
the import worked, and "Hopper or Blackwell". sm_120 satisfies all three while
lacking the kernels, so the predicate is the defect.

The blunt switch is also wrong on its own terms. DeepGEMM's **MoE** path works
on sm_120 — the same run logs `Using 'DEEPGEMM_MXFP4' Mxfp4 MoE backend` — and
for a 256-expert model that is the hot path. `VLLM_USE_DEEP_GEMM=0` would
discard it to work around a linear-layer bug. `patches/0002` therefore scopes
its exclusion to the one kernel class.

## How it's built

A **thin overlay** on the published vLLM image, not a source build: both
patches touch pure-Python files under `site-packages`, so nothing recompiles
and the layer delta is a few KB. That is the whole reason this app is ~40 lines
where `kserve-huggingfaceserver` is ~400 — there is no CUDA stage to vendor.

`patch --forward --dry-run` runs before the real apply, so an upstream refactor
fails the build rather than shipping a silently unpatched image (same intent as
the `git apply` guard in `kserve-huggingfaceserver`).

```sh
docker buildx bake image-all
```

## ⚠️ Status

**Unvalidated.** The patches are written against v0.27.1 and reasoned from the
tracebacks, but this image has not yet loaded the model end to end. Before
trusting it:

- confirm both asserts are gone and the server reaches `Application startup
  complete` with `--tensor-parallel-size=2 --kv-cache-dtype=fp8`
- confirm `DEEPGEMM_MXFP4` is still selected for MoE (patch 2 must not have
  disabled it)
- **check long-context recall, not just fluency.** `_tilelang_hc_prenorm_gemm`
  now runs on a path it did not before, and mHC feeds the residual stream. A
  numerically wrong fallback produces locally-coherent output that has quietly
  lost the middle of its context — the failure mode is invisible to a smoke
  test. Run a needle-in-haystack probe at depth before this serves anything.

## Retirement trigger

The day vLLM guards DeepGEMM's sm_120 gaps upstream, delete this app and go
back to stock `vllm/vllm-openai`. Both patches are small, use fallbacks that
already exist, and match the shape of `should_auto_disable_deep_gemm()` /
`_DEEPGEMM_BLACKWELL_EXCLUDED_MODEL_TYPES` — so they are worth proposing
upstream rather than carrying indefinitely.
