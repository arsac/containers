# comfyui-ui

Static ComfyUI frontend served by nginx, with reverse-proxying to a separate
GPU-backed ComfyUI backend pod. The point of this image is to decouple UI
availability from GPU availability: the UI stays reachable (and page loads
stay fast) while the backend scales from zero on demand.

## Paired versions

This image tracks **two** versions:

- `COMFYUI_VERSION` — the ComfyUI Python backend version this UI is paired
  with. Not shipped in this image; tracked here only for documentation and
  Renovate grouping.
- `FRONTEND_VERSION` — the `Comfy-Org/ComfyUI_frontend` git tag whose
  `dist.zip` is bundled as static files.

`FRONTEND_VERSION` must match the `comfyui-frontend-package` version that
`COMFYUI_VERSION`'s upstream `requirements.txt` pins. When Renovate bumps
ComfyUI, it groups the backend and UI PRs together (see
`.renovaterc.json5`) so a reviewer can update both.

To verify a pairing:

```sh
curl -sL https://raw.githubusercontent.com/comfyanonymous/ComfyUI/<COMFYUI_VERSION>/requirements.txt \
    | grep '^comfyui-frontend-package'
```

The output version (e.g. `1.38.14`) should match `FRONTEND_VERSION` with a
`v` prefix (`v1.38.14`).

## Runtime configuration

| Env var | Default | Description |
|---|---|---|
| `COMFYUI_BACKEND` | `http://comfyui-predictor.ai.svc.cluster.local:80` | URL of the backend Service. Scheme is stripped at startup; only host:port is used. |

## Endpoints

| Path | Handling |
|---|---|
| `/` | Static `index.html`, never proxied |
| `/assets/*`, `/fonts/*`, `/scripts/*`, `/extensions/*`, `/cursor/*`, `/materialdesignicons.min.css` | Static files from the bundled dist |
| `/object_info`, `/embeddings`, `/extensions`, `/system_stats` | Proxied to backend, cached 6h, stale-on-error up to 24h |
| `/ws` | WebSocket, direct proxy with upgrade headers |
| All other paths (`/prompt`, `/queue`, `/history`, `/view`, `/upload/*`, `/api/*`, `/userdata/*`, `/internal/*`, `/free`, `/interrupt`) | Direct proxy, no cache, 502 when backend is down |

## Port

`8188` (same as upstream ComfyUI, for consumer-side convenience).

## Volumes

None. All state lives on the backend pod.

## Building locally

```sh
cd apps/comfyui-ui
docker buildx bake image-local
```

Produces `comfyui-ui:<FRONTEND_VERSION>`.

## Running locally against a real backend

```sh
docker run --rm -p 8188:8188 \
    -e COMFYUI_BACKEND=http://host.docker.internal:8188 \
    comfyui-ui:v1.38.14
```

Then open http://localhost:8188.
