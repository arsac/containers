# vllm-qwen4exp

vLLM for the `qwen4_exp` architecture (Qwen3.8-Flash-Next) on 2x RTX PRO 6000
(sm_120): a pinned upstream main commit plus the patches we are waiting on.

| pin | value | why |
| --- | --- | --- |
| base | `vllm-ci-postmerge-repo@f2e2936f` (main, 2026-09-06) | the exact commit PR #53899 is rebased on - patches apply by construction |
| patch 0001 | [vllm#53899](https://github.com/vllm-project/vllm/pull/53899) head `357e0544`, `vllm/` hunks only | `VLLM_PLE_CPU_OFFLOAD` - without it the FP8 checkpoint cannot fit 2x 96GB with usable KV |
| patch 0002 | ours (unsubmitted upstream) | short_conv_attn metadata builder: build the spec/decode/prefill group key on CPU - the device-side variant syncs per step (killed the engine under the CI image's `VLLM_GPU_SYNC_CHECK=error`; a latency wart under `warn`). Drop when upstream's sync-elimination campaign reaches short_conv |

Not based on the `nightly` tag: main's qwen4_exp churn conflicts with the PR
within days. Re-pin (see Dockerfile header) instead of hand-resolving
conflicts - if the patch no longer applies to the PR's own base, upstream has
rebased and both pins move together.

**Retirement trigger:** #53899 merges upstream. Delete this app; the
ServingRuntime in home-ops goes back to `vllm/vllm-openai:nightly@digest`
under the normal Renovate soak. Patch-count zero = no image.

Consumed by `kubernetes/apps/ai/qwen-next` in home-ops, gated by the qwen
verification script before the `chat` alias moves.
