ARG VERSION="v25.12.0"
ARG SOURCE_IMAGE="nvcr.io/nvidia/k8s-dra-driver-gpu"

# =============================================================================
# Builder stage: clone upstream source, apply Talos support patch, build binaries
# =============================================================================
FROM golang:1.26.1-bookworm AS builder

ARG VERSION

RUN mkdir -p /out && \
    git clone --depth 1 --branch ${VERSION} \
        https://github.com/NVIDIA/k8s-dra-driver-gpu.git /src

WORKDIR /src

# Apply Talos OS support (upstream PR #695):
# - adds /usr/local/glibc/usr/lib to library search paths
# - adds /usr/local/bin to binary search paths
RUN sed -i \
        's/^\(\t\t"\/lib\/aarch64-linux-gnu",\)$/\1\n\t\t"\/usr\/local\/glibc\/usr\/lib",/' \
        cmd/gpu-kubelet-plugin/root.go \
        cmd/compute-domain-kubelet-plugin/root.go && \
    sed -i \
        's/^\(\t\t"\/sbin",\)$/\1\n\t\t"\/usr\/local\/bin",/' \
        cmd/gpu-kubelet-plugin/root.go \
        cmd/compute-domain-kubelet-plugin/root.go && \
    sed -i \
        's/^\(            \/driver-root\/bin \\\)$/\1\n            \/driver-root\/usr\/local\/bin \\/' \
        hack/kubelet-plugin-prestart.sh && \
    sed -i \
        's/^\(            \/driver-root\/usr\/lib\/aarch64-linux-gnu \\\)$/\1\n            \/driver-root\/usr\/local\/glibc\/usr\/lib \\/' \
        hack/kubelet-plugin-prestart.sh

# Build patched kubelet plugin binaries.
# CGO_LDFLAGS_ALLOW: vendor packages set -Wl,--unresolved-symbols=ignore-in-object-files
# which Go's security check rejects unless explicitly allowed.
RUN CGO_LDFLAGS_ALLOW='-Wl,--unresolved-symbols=ignore-in-object-files' \
    CGO_ENABLED=1 GOOS=linux \
    go build -mod=vendor -o /out/gpu-kubelet-plugin ./cmd/gpu-kubelet-plugin/ && \
    CGO_LDFLAGS_ALLOW='-Wl,--unresolved-symbols=ignore-in-object-files' \
    CGO_ENABLED=1 GOOS=linux \
    go build -mod=vendor -o /out/compute-domain-kubelet-plugin ./cmd/compute-domain-kubelet-plugin/

# =============================================================================
# Final stage: official image with patched binaries and prestart script
# =============================================================================
FROM ${SOURCE_IMAGE}:${VERSION}

COPY --from=builder /out/gpu-kubelet-plugin /usr/bin/gpu-kubelet-plugin
COPY --from=builder /out/compute-domain-kubelet-plugin /usr/bin/compute-domain-kubelet-plugin
COPY --from=builder /src/hack/kubelet-plugin-prestart.sh /usr/bin/kubelet-plugin-prestart.sh
