# Compat rebuild of kagent's controller image.
#
# kagent compiles injected-credential URIs as
# ate-secret://kubernetes.io/<namespace>/<secret>/<key>, while substrate's
# kubernetes credential provider serves only its own authority and requires its
# "default" locator ahead of the namespace. Every credential kagent emits is
# therefore rejected by the provider at fetch time, long after the revision
# carrying it was stored. patches/ rewrites both the URI kagent emits and the
# validator that accepts it.
#
# Retire this image when kagent ships the same fix upstream; BASE_IMAGE records
# the upstream build this was rebuilt against.
ARG KAGENT_REF=8be872b231d09f762435dc8296556c0ffef6ce6d
ARG BASE_IMAGE=ghcr.io/kagent-dev/kagent/controller@sha256:99bb9ae31aa799d7dcfcf01562f706af6681c9f968529aa3cd83566a7516ef0d

#################### SOURCE (pinned upstream kagent + downstream patches) ####################
FROM alpine/git AS src
ARG KAGENT_REF
WORKDIR /s
RUN git init -q . \
 && git remote add origin https://github.com/kagent-dev/kagent.git \
 && git fetch -q --depth 1 origin "${KAGENT_REF}" \
 && git checkout -q FETCH_HEAD
COPY patches/ /patches/
RUN set -e; for p in /patches/*.patch; do echo "Applying $(basename "$p")"; git apply "$p"; done
#################### SOURCE ####################

#################### BUILD ####################
# Upstream builds with the repo's go/ directory as the module root (its go.mod
# requires Go 1.27) and stamps its version package through ldflags, so
# `kagent version` keeps reporting a release.
FROM docker.io/library/golang:1.27 AS builder
ARG VERSION
ARG KAGENT_REF
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src
COPY --from=src /s/go ./
ENV CGO_ENABLED=0
RUN GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build \
      -ldflags "-X github.com/kagent-dev/kagent/go/core/internal/version.Version=${VERSION} \
                -X github.com/kagent-dev/kagent/go/core/internal/version.GitCommit=${KAGENT_REF}" \
      -o /out/controller ./core/cmd/controller/main.go
#################### BUILD ####################

# Upstream's final stage (alpine with bash, ca-certificates and git, the
# /skills, /plugins and /data directories, uid 65532) is inherited rather than
# reproduced, so the only delta shipped is the binary.
FROM ${BASE_IMAGE}
COPY --from=builder --chmod=0755 /out/controller /app
