# MPS Talos Support Design

**Date:** 2026-03-20
**Status:** Approved

## Problem

The NVIDIA MPS (Multi-Process Service) daemon in the upstream `k8s-dra-driver-gpu` uses this container command:

```yaml
command: [chroot, /driver-root, sh, -c]
args: ["nvidia-cuda-mps-control -d; tail -f ..."]
```

On Talos Linux, the host root filesystem has no shell (`sh`, `bash`, or `busybox` are absent). The chroot succeeds but the subsequent `sh` exec fails. MPS sharing is therefore unusable on Talos even after the existing Talos path patches (PR #695) are applied.

**Host filesystem facts (confirmed via kubectl exec):**
- `nvidia-cuda-mps-control` and `nvidia-cuda-mps-server` are at `/usr/local/bin/`
- NVIDIA libraries are at `/usr/local/glibc/usr/lib/` (Talos bundles its own glibc because the host uses musl)
- Dynamic linker is at `/usr/local/glibc/usr/lib/ld-linux-x86-64.so.2`
- No shell exists anywhere on the host root

## Solution

Replace the `chroot + host shell` approach with a small Go binary (`mps-daemon`) baked into the custom image. The binary performs the same startup sequence natively without requiring a host shell.

**Why Go binary over a shell script in the image:**
- Consistent with the existing Dockerfile pattern (already builds `gpu-kubelet-plugin` and `compute-domain-kubelet-plugin` in a Go builder stage)
- No shell dependency whatsoever
- Config values (thread %, memory limits) passed cleanly as env vars rather than rendered into a shell script body
- Process lifecycle (exec, env, file I/O, log tailing) handled idiomatically

## Architecture

### New binary: `cmd/mps-daemon/main.go`

Built in the existing Go builder stage and installed to `/usr/bin/mps-daemon` in the final image.

**Startup sequence:**

1. Create symlink `/usr/local/glibc` → `/driver-root/usr/local/glibc`
   - Makes the `PT_INTERP` path (`/usr/local/glibc/usr/lib/ld-linux-x86-64.so.2`) resolvable in the container's filesystem for both `nvidia-cuda-mps-control` and any child processes it forks (`nvidia-cuda-mps-server`)
   - A symlink requires no mount syscalls and no `CAP_SYS_ADMIN` beyond what the container already has
2. `os.Remove` the old startup log at `$NVIDIA_MPS_LOG_DIRECTORY/startup.log`
3. `exec.Command` → `/driver-root/usr/local/bin/nvidia-cuda-mps-control -d`
   - Env includes `NVIDIA_MPS_PIPE_DIRECTORY` and `NVIDIA_MPS_LOG_DIRECTORY`
   - The `-d` flag daemonizes; the exec returns quickly
4. If `MPS_DEFAULT_ACTIVE_THREAD_PERCENTAGE` is set, pipe the control command to a second invocation of the binary in client mode
5. For each `MPS_DEFAULT_PINNED_MEM_LIMIT_<uuid>=<limit>` env var, send the per-device memory limit command
6. Write `"startup complete"` to `$NVIDIA_MPS_LOG_DIRECTORY/startup.log`
7. Exec `tail -n +1 -f $NVIDIA_MPS_LOG_DIRECTORY/control.log` to keep the container alive

**Open question:** Whether `nvidia-cuda-mps-control` locates `nvidia-cuda-mps-server` via `argv[0]`-relative path (finds it at `/driver-root/usr/local/bin/nvidia-cuda-mps-server` — exists) or via a hardcoded absolute path (`/usr/local/bin/nvidia-cuda-mps-server` — does not exist in the container). The symlink resolves `PT_INTERP` in both cases. If the absolute path form is used, a second symlink `/usr/local/bin/nvidia-cuda-mps-server` → `/driver-root/usr/local/bin/nvidia-cuda-mps-server` can be added as a follow-up once tested.

### MPS daemon template patch

The template (`templates/mps-control-daemon.tmpl.yaml`) is embedded in the `gpu-kubelet-plugin` binary at build time. It must be patched before the binary is compiled.

**Changes to the template:**

| Field | Before | After |
|-------|--------|-------|
| `command` | `[chroot, /driver-root, sh, -c]` | `[/usr/bin/mps-daemon]` |
| `args` | shell script block | removed |
| `env` | `CUDA_VISIBLE_DEVICES`, `FEATURE_GATES` | add `NVIDIA_MPS_PIPE_DIRECTORY`, `NVIDIA_MPS_LOG_DIRECTORY`, optional thread % and memory limit vars |

`startupProbe`, all `volumeMounts`, and all `volumes` are unchanged.

### Dockerfile changes

In the builder stage, after the existing sed patches:

1. Patch `templates/mps-control-daemon.tmpl.yaml` — replace command/args/env block
2. Add `cmd/mps-daemon/main.go` to the source tree
3. Build the `mps-daemon` binary with ldflags (same pattern as existing binaries)
4. In the final stage, `COPY --from=builder /out/mps-daemon /usr/bin/mps-daemon`

## Environment Variables

| Var | Source | Purpose |
|-----|--------|---------|
| `CUDA_VISIBLE_DEVICES` | existing template field | GPU device selection |
| `NVIDIA_MPS_PIPE_DIRECTORY` | `{{ .MpsPipeDirectory }}` | MPS UNIX socket directory (replaces chroot-relative `/tmp/nvidia-mps`) |
| `NVIDIA_MPS_LOG_DIRECTORY` | `{{ .MpsLogDirectory }}` | MPS log directory (replaces chroot-relative `/var/log/nvidia-mps`) |
| `MPS_DEFAULT_ACTIVE_THREAD_PERCENTAGE` | `{{ .DefaultActiveThreadPercentage }}` (optional) | Thread limit |
| `MPS_DEFAULT_PINNED_MEM_LIMIT_<uuid>` | `{{ range .DefaultPinnedDeviceMemoryLimits }}` (optional) | Per-device memory limit |

## What Does Not Change

- Volume mounts (`driver-root`, `mps-shm-directory`, `mps-pipe-directory`, `mps-log-directory`)
- `hostPath` source paths for all volumes
- `startupProbe` (`cat /driver-root/var/log/nvidia-mps/startup.log`)
- `hostPID: true`, `privileged: true`
- `CUDA_VISIBLE_DEVICES` env var
- The `MpsImageName` (still uses the custom image)
