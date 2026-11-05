# syntax=docker/dockerfile:1

# ate-env's in-actor exec/file daemon, built from a pinned agent-substrate/env
# commit against the kagent Substrate fork instead of the upstream Substrate
# commit its go.mod pins. The binary must stay at /ko-app/ate-env-guest (ko's
# layout): ActorTemplates run that path, and rootfs mode mounts this image and
# runs <mount>/ko-app/ate-env-guest.
FROM --platform=$BUILDPLATFORM mirror.gcr.io/library/golang:1.27 AS build
# Pins come from docker-bake.hcl, the only place Renovate updates them.
ARG ATE_ENV_REF
ARG SUBSTRATE_VERSION
ARG TARGETOS
ARG TARGETARCH
ENV CGO_ENABLED=0
WORKDIR /src
RUN git init -q . \
 && git remote add origin https://github.com/agent-substrate/env.git \
 && git fetch -q --depth 1 origin "${ATE_ENV_REF}" \
 && git checkout -q FETCH_HEAD
# The whole suite runs against the fork; a failure fails the build, so no image
# is published for an incompatible pair. go list -m logs the resolved replace.
RUN go mod edit -replace "go.ate.dev/substrate=github.com/kagent-dev/substrate@${SUBSTRATE_VERSION}" \
 && go mod tidy \
 && go list -m go.ate.dev/substrate \
 && go test ./...
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -trimpath -o /out/ate-env-guest ./cmd/ate-env-guest

# Base from upstream's .ko.yaml. Runs as the base's root user, as upstream's
# image does: the daemon binds :80 and execs workloads inside the actor.
FROM mirror.gcr.io/library/bash:5.3@sha256:61962062d969cb46dfc2bad061d36342406fa485f64f246aa7e95693ca07df1f
COPY --from=build /src/LICENSE /usr/share/doc/ate-env/LICENSE
COPY --from=build /out/ate-env-guest /ko-app/ate-env-guest
ENV PATH=${PATH}:/ko-app
ENTRYPOINT ["/ko-app/ate-env-guest"]

