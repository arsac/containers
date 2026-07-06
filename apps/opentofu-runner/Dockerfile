# OpenTofu runner for flux-iac/tofu-controller.
#
# The controller ships only a Terraform (BSL) runner, and its runner binary invokes
# `terraform` — so we drop the OpenTofu binary in AT that path, and the controller
# transparently runs OpenTofu (tofu is a drop-in for the terraform CLI). Proven
# approach; mirrors joryirving/containers for the same controller version.
#
# The tf-runner base tag MUST track the deployed tofu-controller chart version (the
# runner and controller speak a versioned gRPC contract) — bump it in lockstep.
# VERSION (OpenTofu) is supplied by docker-bake.hcl.
ARG VERSION

FROM docker.io/library/alpine:3.23 AS builder
ARG VERSION
ARG TARGETARCH
RUN apk add --no-cache curl \
    && curl -fsSL "https://github.com/opentofu/opentofu/releases/download/v${VERSION}/tofu_${VERSION}_linux_${TARGETARCH}.tar.gz" \
        | tar -xz -C /tmp tofu

# renovate: datasource=docker depName=ghcr.io/flux-iac/tf-runner
FROM ghcr.io/flux-iac/tf-runner:v0.16.4@sha256:fc3af4d9b99f54cc92d4aec51d83117dcf373b79d8ed1dc6f69a4ac154184725
USER root
# Replace the base's `terraform` with `tofu` so the runner invokes OpenTofu.
COPY --from=builder --chown=65532:65532 --chmod=755 /tmp/tofu /usr/local/bin/terraform
# Distroless nonroot uid the tf-runner base is built around (NOT the 1000:1000 app
# convention — this is a tool image with an upstream contract).
USER 65532:65532
