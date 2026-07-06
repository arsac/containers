# OpenTofu runner for flux-iac/tofu-controller.
#
# The controller ships ONLY a Terraform-based runner (ghcr.io/flux-iac/tf-runner,
# BSL-licensed). To run OpenTofu instead, bake the `tofu` binary into the matching
# tf-runner base — the upstream-documented way (there is no official OpenTofu runner).
#
# VERSION (OpenTofu) is supplied by docker-bake.hcl. TF_RUNNER_TAG MUST track the
# tofu-controller chart version deployed in the cluster (`<chart>-base`) — the runner
# and controller speak a versioned gRPC contract; bump them in lockstep.
ARG VERSION
# renovate: datasource=docker depName=ghcr.io/flux-iac/tf-runner
ARG TF_RUNNER_TAG="v0.16.4-base"

FROM ghcr.io/opentofu/opentofu:${VERSION}-minimal AS tofu

FROM ghcr.io/flux-iac/tf-runner:${TF_RUNNER_TAG}
COPY --from=tofu /usr/local/bin/tofu /usr/local/bin/tofu
# tofu-controller runs the runner as this non-root uid (distroless nonroot).
USER 65532:65532
