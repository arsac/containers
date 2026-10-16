# syntax=docker/dockerfile:1

# gnhf drives a coding agent in a loop: build prompt (with notes.md context) ->
# invoke agent -> commit on success, `git reset --hard` on failure, abort after
# three consecutive failures. It ships no model backend of its own and shells
# out to an agent CLI, so this image is gnhf + one agent + the git it needs.
#
# The agent is OpenCode, chosen because it is provider-agnostic: it takes a
# plain OpenAI-compatible base URL with no vendor sign-in to work around, which
# is what lets this point at a self-hosted model.

FROM node:22-slim

# renovate: datasource=npm depName=gnhf
ARG GNHF_VERSION="0.1.45"
# renovate: datasource=npm depName=opencode-ai
ARG OPENCODE_VERSION="1.18.23"
# renovate: datasource=github-releases depName=kunchenguid/no-mistakes
ARG NO_MISTAKES_VERSION="v1.57.0"
# renovate: datasource=github-releases depName=kunchenguid/treehouse
ARG TREEHOUSE_VERSION="v2.3.0"

ARG TARGETARCH

# git is not optional - the loop *is* commit-and-reset. ca-certificates for the
# model endpoint and the git remote; curl only to fetch the two Go binaries.
RUN apt-get update \
 && apt-get install -y --no-install-recommends git ca-certificates curl \
 && rm -rf /var/lib/apt/lists/*

# acpx (the ACP runtime) is vendored into gnhf's dist/cli.mjs bundle rather
# than shipped as a dependency, so it is present without being on PATH.
RUN npm install -g "gnhf@${GNHF_VERSION}" "opencode-ai@${OPENCODE_VERSION}" \
 && npm cache clean --force

# Static Go binaries, published per-arch. No Go toolchain needed, so these stay
# a download rather than a build stage.
RUN set -eux; \
    for t in "no-mistakes:${NO_MISTAKES_VERSION}" "treehouse:${TREEHOUSE_VERSION}"; do \
        name="${t%%:*}"; ver="${t##*:}"; \
        curl -fsSL -o /tmp/t.tgz \
          "https://github.com/kunchenguid/${name}/releases/download/${ver}/${name}-${ver}-linux-${TARGETARCH}.tar.gz"; \
        tar -xzf /tmp/t.tgz -C /usr/local/bin "${name}"; \
        rm /tmp/t.tgz; \
        chmod +x "/usr/local/bin/${name}"; \
    done

# gnhf writes worktrees as a *sibling* of the repo (<repo>-gnhf-worktrees/), so
# the mount has to be this parent directory, never the repo itself.
WORKDIR /workspace

# Non-root, but not `nobody`: gnhf writes .gnhf/runs, notes.md, worktrees and
# git objects, so it needs a real writable HOME for npm/opencode state too.
RUN useradd --uid 1001 --create-home --shell /bin/bash gnhf \
 && chown gnhf:gnhf /workspace
USER gnhf
ENV HOME=/home/gnhf

ENTRYPOINT ["gnhf"]
