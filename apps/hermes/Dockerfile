# syntax=docker/dockerfile:1

# Hermes Agent (upstream's own image) plus three plugins installed at build time: the
# Hindsight memory provider, the official Home Assistant platform plugin, and hermes_otel for
# OpenTelemetry. Not built from PyPI: the `hermes-agent` distribution stops at 0.19.0 and these
# plugins require hermes >= 0.21.4 / >= 0.21.5, so the published image is the only base that
# satisfies them.
ARG VERSION="v0.23.0"
ARG SOURCE_IMAGE="nousresearch/hermes-agent"

FROM ${SOURCE_IMAGE}:${VERSION}

# global-scope ARGs are not visible inside stages without re-declaration
ARG VERSION
# The pins have no defaults: docker-bake.hcl owns them, so a standalone `docker build` fails at
# the step that uses them instead of quietly building whatever version was hardcoded here.
ARG HINDSIGHT_CLIENT_VERSION
ARG HINDSIGHT_TAG
ARG HERMES_OTEL_TAG
ARG HOMEASSISTANT_REF

# /bin/sh is dash here, so a piped RUN has no pipefail; declare it rather than trust the
# default shell (the freeze, the pin checks and the pin greps below all pipe).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Say that, instead of dying later inside uv or git with an empty pin.
RUN : "${HINDSIGHT_CLIENT_VERSION:?is a docker-bake.hcl pin}" \
      "${HINDSIGHT_TAG:?is a docker-bake.hcl pin}" \
      "${HERMES_OTEL_TAG:?is a docker-bake.hcl pin}" \
      "${HOMEASSISTANT_REF:?is a docker-bake.hcl pin}"

# The runtime account. Upstream bakes `hermes` as 10000 and starts as root so a boot hook can
# remap the UID and chown the data volume; its entrypoint refuses a --user UID that is not this
# account's. Remapping the account to 1000:1000 here lets the container start unprivileged with
# that entrypoint intact, and leaves /opt/data's ownership to whoever mounts it (fsGroup)
# rather than to a root boot hook.
RUN groupmod -o -g 1000 hermes \
 && usermod -o -u 1000 -g 1000 hermes \
 && chown -R hermes:hermes /opt/data

# Plugin dependencies, from the uv upstream already ships (arch-suffixed path, so no second
# copy is added): Hindsight's cloud client, pinned, and the OpenTelemetry packages hermes_otel
# declares, taken from the plugin's own ranges since they travel with the pinned commit.
# `hermes plugins install --yes-deps` is deliberately not used for them: it resolves into a
# package-manager generation under $HERMES_HOME/installs, which a volume mounted over /opt/data
# erases at runtime. What must not happen is an existing Hermes pin moving, so the
# environment's own pins are handed to the resolver as constraints: a spec that would upgrade
# or downgrade anything already installed is refused by uv, with the two conflicting
# requirements named, before the venv is touched.
# No PIP_*/UV_* prologue here, unlike home-operations' python images: those bring their own
# Python toolchain, this image inherits upstream's (which already sets PYTHONUNBUFFERED and
# PYTHONDONTWRITEBYTECODE) and never calls pip. Their `--only-binary` habit is kept: every one
# of these must resolve to a wheel, so nothing is compiled at build time and no plugin can
# quietly start depending on a compiler that will not exist at runtime.
RUN uv="$(echo /opt/hermes/tools/uv-*/uv)" \
 && "$uv" pip freeze --python /opt/hermes/.venv/bin/python \
      | grep -E '^[A-Za-z0-9_.-]+==' > /tmp/venv-constraints.txt \
 && "$uv" pip install --no-cache --only-binary=:all: --python /opt/hermes/.venv/bin/python \
      -c /tmp/venv-constraints.txt \
      "hindsight-client==${HINDSIGHT_CLIENT_VERSION}" \
      "opentelemetry-api>=1.35,<2" \
      "opentelemetry-sdk>=1.35,<2" \
      "opentelemetry-exporter-otlp-proto-http>=1.35,<2" \
      "opentelemetry-exporter-otlp-proto-grpc>=1.35,<2" \
      "PyYAML>=6,<7" \
 && rm -f /tmp/venv-constraints.txt

# Plugins. `hermes plugins install` commits the plugin directory in one admission transaction
# and `--ref` wants the commit, not the tag, so tag pins are resolved first (peeled tag line)
# and printed for provenance. Installs land in a throwaway HERMES_HOME and the plugin directory
# is then moved into the bundled tree, which is what survives a volume mounted over /opt/data and
# matches where Hermes discovers each kind: plugins/memory/<name> for a memory provider,
# platforms/<name> for a platform, a top-level plugins/<name> for a hook plugin.
# No --yes-deps: the dependency half of that transaction is already done above.

# Hindsight: memory provider.
RUN ref="$(git ls-remote --tags https://github.com/vectorize-io/hindsight \
        "refs/tags/${HINDSIGHT_TAG}" "refs/tags/${HINDSIGHT_TAG}^{}" | tail -1 | cut -f1)" \
 && printf '%s\n' "$ref" | grep -Eqx '[0-9a-f]{40}' \
 && echo "hindsight ${HINDSIGHT_TAG} -> ${ref}" \
 && mkdir -p /opt/hermes-seed \
 && HERMES_HOME=/opt/hermes-seed /opt/hermes/.venv/bin/hermes plugins install \
      --ref "$ref" vectorize-io/hindsight/hindsight-integrations/hermes \
 && mv /opt/hermes-seed/plugins/hindsight /opt/hermes/plugins/memory/hindsight \
 && rm -rf /opt/hermes-seed \
 && grep -qx "version: ${HINDSIGHT_TAG##*/v}" /opt/hermes/plugins/memory/hindsight/plugin.yaml

# hermes_otel: hooks, so a top-level bundled plugin. Hooks are not a default-on kind, which is
# why this one also needs `plugins.enabled: [hermes_otel]` in the runtime config to load.
RUN ref="$(git ls-remote --tags https://github.com/briancaffey/hermes-otel \
        "refs/tags/${HERMES_OTEL_TAG}" "refs/tags/${HERMES_OTEL_TAG}^{}" | tail -1 | cut -f1)" \
 && printf '%s\n' "$ref" | grep -Eqx '[0-9a-f]{40}' \
 && echo "hermes_otel ${HERMES_OTEL_TAG} -> ${ref}" \
 && mkdir -p /opt/hermes-seed \
 && HERMES_HOME=/opt/hermes-seed /opt/hermes/.venv/bin/hermes plugins install \
      --ref "$ref" briancaffey/hermes-otel/hermes_otel \
 && mv /opt/hermes-seed/plugins/hermes_otel /opt/hermes/plugins/hermes_otel \
 && rm -rf /opt/hermes-seed \
 && grep -qx "version: ${HERMES_OTEL_TAG##*-v}" /opt/hermes/plugins/hermes_otel/plugin.yaml

# Home Assistant: official plugin, tracked on the upstream repo's main branch because it
# publishes no tags and no releases.
RUN printf '%s\n' "${HOMEASSISTANT_REF}" | grep -Eqx '[0-9a-f]{40}' \
 && mkdir -p /opt/hermes-seed \
 && HERMES_HOME=/opt/hermes-seed /opt/hermes/.venv/bin/hermes plugins install \
      --ref "${HOMEASSISTANT_REF}" NousResearch/hermes-official-plugins/homeassistant \
 && mv /opt/hermes-seed/plugins/homeassistant /opt/hermes/plugins/platforms/homeassistant \
 && rm -rf /opt/hermes-seed \
 && grep -qx "kind: platform" /opt/hermes/plugins/platforms/homeassistant/plugin.yaml

# What a build alone can check is checked here: each plugin is where its kind is discovered, and
# each tag points at the version it claims. Whether a plugin still *loads* - its declared
# `requires_hermes`, its imports, its registrations - is asserted by container_test.go against
# this image, because the release workflow runs those tests before it publishes anything.

USER 1000:1000
