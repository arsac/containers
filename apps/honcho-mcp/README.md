# honcho-mcp

A stdio [Model Context Protocol](https://modelcontextprotocol.io/) server that
wraps a **self-hosted** [Honcho](https://honcho.dev) v3 instance. Fronted by
ToolHive (stdin/stdout → streamable-HTTP) for clients such as kagent.

## Provenance

Vendored from [`plastic-labs/honcho`](https://github.com/plastic-labs/honcho)
subdirectory `mcp/`, pinned to tag **`v3.0.11`** (license: AGPL-3.0). Only
`mcp/` is used; the upstream Cloudflare-Worker entry (`src/index.ts`) is removed
and replaced by `src/stdio.ts` (this repo). The Dockerfile fetches the upstream
tarball at the pinned tag and overlays our entry — see `Dockerfile`. To re-sync:
bump `HONCHO_REF` in `docker-bake.hcl` (renovate proposes tag bumps via
`datasource=github-tags`).

## Runtime contract

| Env var | Default | Notes |
| --- | --- | --- |
| `HONCHO_API_URL` | **required** | Self-hosted URL, e.g. `http://honcho.<ns>.svc.cluster.local:8000`. Server exits 1 if unset. |
| `HONCHO_WORKSPACE_ID` | **required** | Explicit workspace; prevents silent cross-tenant memory co-mingling. Server exits 1 if unset. |
| `HONCHO_API_KEY` | `""` | Throwaway while Honcho runs `AUTH_USE_AUTH=false`. When auth is enabled, inject a workspace-scoped JWT (minted out-of-band). |
| `HONCHO_USER_NAME` | `User` | Optional. |
| `HONCHO_ASSISTANT_NAME` | `Assistant` | Optional. |
| `HONCHO_SKIP_PREFLIGHT` | unset | Set `1` to skip the startup reachability check (lazy connect). |

- **Stateless.** Peers, sessions, and the workspace auto-provision on first use.
  No seed/migration/bootstrap.
- **Fail-closed + preflight.** Missing required env → exit 1. At startup the
  server runs `honcho.getMetadata()` (5× 2s bounded retry); if Honcho is
  unreachable it exits 1 → visible as CrashLoopBackOff at deploy time instead of
  a silent failure on first tool call. This couples pod startup to Honcho
  liveness; set `HONCHO_SKIP_PREFLIGHT=1` to opt out.
- **Runs non-root** (`65534:65534`) and writes nothing (read-only-rootfs safe).

## Deployment / image pinning

Image: `<registry-host>/arsac/honcho-mcp`. Pin by digest in the HelmRelease:

```yaml
# renovate: datasource=docker
image: <registry-host>/arsac/honcho-mcp:3.0.11@sha256:<digest>
```

The publish workflow emits the pushed `sha256` digest in its job summary.

**Data-plane hardening (deploy responsibility):** with `AUTH_USE_AUTH=false`,
Honcho has no authN — add a `NetworkPolicy` restricting ingress to Honcho so
only the ToolHive/MCP pod can reach it.

## Tools

Workspace, peer, session, conclusion, and system tools are registered verbatim
from upstream `mcp/src/tools/`. Note: upstream's `instructions.md` tool-use
guide is **not** surfaced to clients in this build; agent tool-misuse before it
is wired is a known limitation, not a model-quality bug.

## License

AGPL-3.0 (`LICENSE`). This is a **modified** work served over a network: the
Corresponding Source is this repository (`github.com/arsac/containers`,
`apps/honcho-mcp/`), and the exact built dependency set is pinned in `bun.lock`.
Per-file modification notice is in `src/stdio.ts`.

## Local development

The upstream `src/` (config/server/types/tools) exists only at Docker build
time. To type-check locally, replicate the overlay:

```bash
curl -fsSL https://github.com/plastic-labs/honcho/archive/refs/tags/v3.0.11.tar.gz \
  | tar -xz --strip-components=2 "honcho-3.0.11/mcp" -C .
rm src/index.ts
bun install --frozen-lockfile && bunx tsc --noEmit && bun run build
```
