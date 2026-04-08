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

Built in the existing Go builder stage and installed to `/usr/bin/mps-daemon` in the final image. Built with `CGO_ENABLED=0` (no CGO dependencies) to produce a static binary.

**Startup sequence:**

1. Create symlink `/usr/local/glibc` → `/driver-root/usr/local/glibc`
   - Makes the `PT_INTERP` path (`/usr/local/glibc/usr/lib/ld-linux-x86-64.so.2`) resolvable in the container's filesystem for both `nvidia-cuda-mps-control` and any child processes it forks (`nvidia-cuda-mps-server`)
   - A symlink requires no mount syscalls and no extra capabilities
   - Before calling `os.Symlink`, stat the path and remove it if it already exists (handles pod rescheduling)
2. `os.Remove` the old startup log at `$NVIDIA_MPS_LOG_DIRECTORY/startup.log`
3. `exec.Command` → `/driver-root/usr/local/bin/nvidia-cuda-mps-control -d`
   - Env includes `NVIDIA_MPS_PIPE_DIRECTORY=/driver-root/tmp/nvidia-mps` and `NVIDIA_MPS_LOG_DIRECTORY=/driver-root/var/log/nvidia-mps`
   - The `-d` flag daemonizes; the exec returns quickly
4. If `MPS_DEFAULT_ACTIVE_THREAD_PERCENTAGE` is set, send `set_default_active_thread_percentage <value>` via stdin to a second invocation of the binary in client mode
5. For each `MPS_DEFAULT_PINNED_MEM_LIMIT_<uuid>=<limit>` env var, send `set_default_device_pinned_mem_limit <uuid> <limit>` to the control binary in client mode
6. Write `"startup complete"` to `$NVIDIA_MPS_LOG_DIRECTORY/startup.log`
7. Poll until `$NVIDIA_MPS_LOG_DIRECTORY/control.log` exists (the daemon creates it on first write), then exec `tail --retry -n +1 -f $NVIDIA_MPS_LOG_DIRECTORY/control.log` to keep the container alive

**Open question to resolve during implementation:** Whether `nvidia-cuda-mps-control` locates `nvidia-cuda-mps-server` via `argv[0]`-relative path (`/driver-root/usr/local/bin/nvidia-cuda-mps-server` — exists) or via a hardcoded absolute path (`/usr/local/bin/nvidia-cuda-mps-server` — does not exist in the container). Verify with `strings /driver-root/usr/local/bin/nvidia-cuda-mps-control | grep mps-server` during implementation. If the absolute path form is used, add a second symlink at step 1: `/usr/local/bin/nvidia-cuda-mps-server` → `/driver-root/usr/local/bin/nvidia-cuda-mps-server`.

### MPS daemon template

**Important:** The template (`templates/mps-control-daemon.tmpl.yaml`) is a **runtime file** loaded from the image filesystem at `/templates/mps-control-daemon.tmpl.yaml` — it is NOT embedded in any Go binary. It is present in the upstream image via `COPY /templates /templates` in the upstream Dockerfile.

This means:

- The template is patched in the builder stage (via sed or file write)
- The patched file must be explicitly copied into the final image stage

**Changes to the template:**

| Field | Before | After |
| ----- | ------ | ----- |
| `command` | `[chroot, /driver-root, sh, -c]` | `[/usr/bin/mps-daemon]` |
| `args` | shell script block | removed |
| `env` | `CUDA_VISIBLE_DEVICES`, `FEATURE_GATES` | add `NVIDIA_MPS_PIPE_DIRECTORY`, `NVIDIA_MPS_LOG_DIRECTORY`, optional thread % and memory limit vars |

`startupProbe`, all `volumeMounts`, and all `volumes` are unchanged.

### Environment variables passed in the template

| Var | Value in template | Purpose |
| --- | ----------------- | ------- |
| `CUDA_VISIBLE_DEVICES` | `{{ .CUDA_VISIBLE_DEVICES }}` | GPU device selection |
| `NVIDIA_MPS_PIPE_DIRECTORY` | `/driver-root/tmp/nvidia-mps` (hardcoded container mountPath) | MPS UNIX socket directory |
| `NVIDIA_MPS_LOG_DIRECTORY` | `/driver-root/var/log/nvidia-mps` (hardcoded container mountPath) | MPS log directory |
| `MPS_DEFAULT_ACTIVE_THREAD_PERCENTAGE` | `{{ .DefaultActiveThreadPercentage }}` (optional) | Thread limit |
| `MPS_DEFAULT_PINNED_MEM_LIMIT_<uuid>` | `{{ range .DefaultPinnedDeviceMemoryLimits }}` (optional, one var per device) | Per-device memory limit |

Note: `NVIDIA_MPS_PIPE_DIRECTORY` and `NVIDIA_MPS_LOG_DIRECTORY` are set to the container-side volume mountPaths (prefixed with `/driver-root/`), not the host paths from `{{ .MpsPipeDirectory }}`/`{{ .MpsLogDirectory }}`. This ensures the `startupProbe` (`cat /driver-root/var/log/nvidia-mps/startup.log`) continues to work correctly.

### Dockerfile changes

In the builder stage (after existing sed patches):

1. Patch `templates/mps-control-daemon.tmpl.yaml` — replace command/args/env block
2. Write `cmd/mps-daemon/main.go` into the source tree
3. Build: `CGO_ENABLED=0 GOOS=linux go build -o /out/mps-daemon ./cmd/mps-daemon/`

In the final stage:

1. `COPY --from=builder /out/mps-daemon /usr/bin/mps-daemon`
2. `COPY --from=builder /src/templates/mps-control-daemon.tmpl.yaml /templates/mps-control-daemon.tmpl.yaml`

## What Does Not Change

- Volume mounts (`driver-root`, `mps-shm-directory`, `mps-pipe-directory`, `mps-log-directory`)
- `hostPath` source paths for all volumes
- `startupProbe` (`cat /driver-root/var/log/nvidia-mps/startup.log`)
- `hostPID: true`, `privileged: true`
- `CUDA_VISIBLE_DEVICES` env var
- The `MpsImageName` (still uses the custom image)
