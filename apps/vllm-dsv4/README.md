# vllm-dsv4 (vLLM 0.27.1 + three sm_120 guards)

Stock vLLM cannot load **DeepSeek-V4-Flash** on **RTX PRO 6000 Blackwell
(sm_120)**. Several kernel paths claim support for an architecture they have no
kernels for, and abort during model load. This image adds the missing guards so
those paths take fallbacks that already exist upstream.

The image alone is not sufficient — see [Required runtime
flags](#required-runtime-flags).

## The failures

All reproduced on bachelor, `vllm/vllm-openai:v0.27.1`, TP=2, weights from a
local cache. Each was found by clearing the one before it, so the order is the
order the loader hits them.

1. **FP8 block-scaled linear** — `DeepGemmFp8BlockScaledMMKernel` is selected,
   then dies in `process_weights_after_loading`:

   ```
   transform_sf_into_required_layout ->
   Assertion error (deepgemm-src/csrc/apis/layout.hpp:60): Unknown SF transformation
   ```

2. **MXFP4 MoE weight prep** — `DeepGemmFP4Experts.is_supported_config()`
   answers yes, then its scale packing hits the *same* assert by a different
   route:

   ```
   convert_weight_to_mxfp4_moe_kernel_format -> _pack_deepgemm_mxfp4_scales ->
   deepgemm_post_process_weight_scale_block -> layout.hpp:60
   ```

3. **mHC pre-broadcast** — with DeepGEMM disabled the first two go away and
   this appears:

   ```
   Assertion error (deepgemm-src/csrc/apis/hyperconnection.hpp:56):
   Unsupported architecture
   ```

   This one is the reason a flag is not enough on its own.
   `VLLM_USE_DEEP_GEMM=0` is honoured by `mhc_pre_tilelang` and
   `mhc_fused_post_pre_tilelang`, which fall back to
   `_tilelang_hc_prenorm_gemm` — but `mhc_pre_broadcast_tilelang` called
   `tf32_hc_prenorm_gemm` unconditionally. `patches/0001` adds the guard its
   two siblings already had.

4. **ue8m0 weight scales** — once DeepGEMM is out of the picture, the only
   remaining block-scaled FP8 linear kernel is Triton's, and it cannot type the
   checkpoint's scales:

   ```
   canonicalize_ptr_dtype -> KeyError: 'float8_e8m0fnu'
   ```

   DeepSeek-V4 sets `scale_fmt: "ue8m0"`, so `weight_scale_inv` loads as
   `torch.float8_e8m0fnu`. `patches/0003` widens it to float32 after loading.
   e8m0 stores a bare power-of-two exponent, so the conversion is *exact*
   (verified by round-trip in-image) and lands on the float32-scale path
   DeepSeek-V3 already uses.

## Why patches rather than a flag

`is_deep_gemm_supported()` is architecture-blind: it checks the env flag, that
the import worked, and "Hopper or Blackwell". sm_120 satisfies all three while
lacking the kernels, so the predicate is the defect.

An earlier version of this file argued that `VLLM_USE_DEEP_GEMM=0` was too
blunt because DeepGEMM's MoE path worked on sm_120. **That was wrong.** The run
does log `Using 'DEEPGEMM_MXFP4' Mxfp4 MoE backend`, but selection is not
support — it fails immediately afterwards packing its scales (failure 2 above).
There was never a working DeepGEMM MoE path on this architecture to preserve.

## Required runtime flags

The patches are necessary but not sufficient. sm_120 also needs the kernel
oracles steered away from backends that mis-report support:

```
--moe-backend=marlin        # DeepGemmFP4Experts claims sm_120, cannot pack scales
--linear-backend=triton     # CUTLASS c3x is sm90/sm100; dies in dispatch_scaled_mm
VLLM_USE_DEEP_GEMM=0        # is_deep_gemm_supported() is arch-blind (see above)
```

`flashinfer_cutlass` is not an alternative: it has no block-scaled FP8 kernel
available in this build, and `flashinfer_b12x` is NvFP4-only despite the name.

## How it's built

A **thin overlay** on the published vLLM image, not a source build: every patch
touches pure-Python files under `site-packages`, so nothing recompiles and the
layer delta is a few KB. That is the whole reason this app is ~40 lines where
`kserve-huggingfaceserver` is ~400 — there is no CUDA stage to vendor.

`patch --forward --dry-run` runs before the real apply, so an upstream refactor
fails the build rather than shipping a silently unpatched image (same intent as
the `git apply` guard in `kserve-huggingfaceserver`).

```sh
docker buildx bake image-all
```

## ⚠️ Status

**Not yet loaded end to end.** Patches 1 and 2 are confirmed to clear their
asserts on real hardware — each failure above was observed, patched, and
replaced by the next one, which is why the list is trustworthy as far as it
goes. Patch 3 is verified only to apply cleanly and register its override; the
load has not yet got past it.

Before trusting this image:

- confirm the server reaches `Application startup complete` with
  `--tensor-parallel-size=2 --kv-cache-dtype=fp8`
- confirm `Using 'MARLIN' Mxfp4 MoE backend` — not DeepGEMM
- **check long-context recall, not just fluency.** `_tilelang_hc_prenorm_gemm`
  now runs on a path it did not before, and mHC feeds the residual stream. A
  numerically wrong fallback produces locally-coherent output that has quietly
  lost the middle of its context — the failure mode is invisible to a smoke
  test. Run a needle-in-haystack probe at depth before this serves anything.

## Retirement trigger

The day vLLM guards these sm_120 gaps upstream, delete this app and go back to
stock `vllm/vllm-openai`. Every patch is small and uses a fallback that already
exists, and they match the shape of `should_auto_disable_deep_gemm()` /
`_DEEPGEMM_BLACKWELL_EXCLUDED_MODEL_TYPES` — so they are worth proposing
upstream rather than carrying indefinitely.
