# kserve-huggingfaceserver (vLLM 0.22.1 self-build)

A self-built kserve huggingfaceserver GPU image on **vLLM 0.22.1**, because
aggressive CPU KV offload needs vLLM's native `OffloadingConnector` — which only
implements `SupportsHMA` (so it works with HMA enabled, required for Gemma 4's
128k window) on **0.22+**, and no stock kserve image ships >0.20.0.

## Why a patch, not a fork

The downstream change vs upstream kserve is tiny — a ~90-line patch across 2
files (`patches/0001-vllm-0.22.1-gemma4.patch`):

- `python/huggingface_server.Dockerfile`: `VLLM_VERSION` 0.20.0 → 0.22.1, drop
  the `lmcache==0.4.4` install (root cause of the Gemma 4 multi-group KV
  livelock; we use native `OffloadingConnector` instead), add
  `transformers==5.5.3` (kserve's lock pins 4.57.1, which lacks
  `transformers.models.gemma4`).
- `python/huggingfaceserver/huggingfaceserver/vllm/vllm_model.py`: vLLM 0.22
  serving-constructor API (`ChatTemplateConfig`, `supported_tasks`).

So instead of maintaining the whole `arsac/kserve` fork + Forgejo, we pin the
upstream commit and carry the patch — same model as `apps/subgen`.

## Build

kserve builds from its **own** multi-stage Dockerfile, so `prepare.sh` clones
upstream at the pinned ref and applies the patch into `.src/` (gitignored),
then bake builds `.src/python/huggingface_server.Dockerfile`:

```sh
KSERVE_REF=$(grep -oP '(?<=default = ")[0-9a-f]{40}(?=")' docker-bake.hcl) ./prepare.sh
docker buildx bake image-all
```

`git apply` fails loudly if the patch doesn't match the pinned ref, so an
upstream refactor breaks the build rather than silently shipping a broken image.

## ⚠️ Status / open items

- **CI integration is not wired yet.** The generic `image-builder` workflow bakes
  an app Dockerfile directly; this app needs `prepare.sh` run *before* bake (a
  clone-first hook). That's the remaining integration step.
- **The patch is provisional** until the port is confirmed by the in-flight
  build + GPU validation (gemma4 TRITON_ATTN >256-token + multimodal +
  tool-calling, jina-reranker-v3 `/v1/rerank`). If validation surfaces a port
  fix, update the patch.
- **Offload follow-up (home-ops):** once this image is live, add
  `--no-disable-hybrid-kv-cache-manager` + `--kv-transfer-config` with
  `OffloadingConnector` / `CPUOffloadingSpec` (`cpu_bytes_to_use ~64GiB`,
  `store_threshold 0`, `eviction_policy`) + a pod memory bump.

## Retirement trigger

The day kserve ships a stock vLLM 0.22+ GPU image, delete the patch and this
whole app — go back to a thin overlay (or fully stock) on that base.
