# syntax=docker/dockerfile:1

# ate-env's API server, built from a pinned agent-substrate/env commit against
# the kagent Substrate fork instead of the upstream Substrate commit its go.mod
# pins. Upstream builds with ko; the binary keeps ko's /ko-app/<name> path.
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
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} go build -trimpath -o /out/ate-env-api ./cmd/ate-env-api

FROM gcr.io/distroless/static-debian13:nonroot@sha256:25ac8f0c3b2334a9eb05452266bd4697864a8c8ef0ef71e5e6480d7f92868329
COPY --from=build /src/LICENSE /usr/share/doc/ate-env/LICENSE
COPY --from=build /out/ate-env-api /ko-app/ate-env-api
ENV PATH=${PATH}:/ko-app
USER 65534:65534
ENTRYPOINT ["/ko-app/ate-env-api"]
