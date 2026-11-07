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
# The pins have no defaults: docker-bake.hcl owns them, so a standalone `docker build` stops at
# the step that needs one instead of quietly building whatever version was hardcoded here.
ARG HINDSIGHT_CLIENT_VERSION
ARG HINDSIGHT_REF
ARG HERMES_OTEL_REF
ARG HOMEASSISTANT_REF

# /bin/sh is dash here, so a piped RUN has no pipefail; declare it rather than trust the
# default shell (the freeze, the pin checks and the pin greps below all pipe).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The runtime account. Upstream bakes `hermes` as 10000 and starts as root so a boot hook can
# remap the UID and chown the data volume; its entrypoint refuses a --user UID that is not this
# account's. Remapping the account to 1000:1000 here lets the container start unprivileged with
# that entrypoint intact, and leaves /opt/data's ownership to whoever mounts it (fsGroup)
# rather than to a root boot hook.
# /run is handed to that account at build time, which is what s6-overlay calls "correctly
# prepared by the container manager for a privilegeless execution": its preinit fixes /run only
# by escalating through s6-overlay-suexec, and a hardened pod (no-new-privileges, which is what
# allowPrivilegeEscalation: false sets) denies that, so the boot dies with exit 100 on a /run
# still owned by root. Owning it here makes the unprivileged path work with no privilege to
# spare, and a root boot simply chowns it back at preinit.
RUN groupmod -o -g 1000 hermes \
 && usermod -o -u 1000 -g 1000 hermes \
 && chown -R hermes:hermes /opt/data \
 && install -d -o hermes -g hermes -m 0755 /run

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

# Plugins. `hermes plugins install` commits the plugin directory in one admission transaction and
# `--ref` takes the commit itself, which is what the pins hold - so the build resolves nothing
# over the network. Installs land in a throwaway HERMES_HOME and the plugin directory is then
# moved into the bundled tree, which is what survives a volume mounted over /opt/data and
# matches where Hermes discovers each kind: plugins/memory/<name> for a memory provider,
# platforms/<name> for a platform, a top-level plugins/<name> for a hook plugin.
# No --yes-deps: the dependency half of that transaction is already done above.

# Hindsight: memory provider.
RUN printf '%s\n' "${HINDSIGHT_REF}" | grep -Eqx '[0-9a-f]{40}' \
 && mkdir -p /opt/hermes-seed \
 && HERMES_HOME=/opt/hermes-seed /opt/hermes/.venv/bin/hermes plugins install \
      --ref "${HINDSIGHT_REF}" vectorize-io/hindsight/hindsight-integrations/hermes \
 && mv /opt/hermes-seed/plugins/hindsight /opt/hermes/plugins/memory/hindsight \
 && rm -rf /opt/hermes-seed \
 && grep -qx "name: hindsight" /opt/hermes/plugins/memory/hindsight/plugin.yaml

# hermes_otel: hooks, so a top-level bundled plugin. Hooks are not a default-on kind, which is
# why this one also needs `plugins.enabled: [hermes_otel]` in the runtime config to load.
RUN printf '%s\n' "${HERMES_OTEL_REF}" | grep -Eqx '[0-9a-f]{40}' \
 && mkdir -p /opt/hermes-seed \
 && HERMES_HOME=/opt/hermes-seed /opt/hermes/.venv/bin/hermes plugins install \
      --ref "${HERMES_OTEL_REF}" briancaffey/hermes-otel/hermes_otel \
 && mv /opt/hermes-seed/plugins/hermes_otel /opt/hermes/plugins/hermes_otel \
 && rm -rf /opt/hermes-seed \
 && grep -qx "name: hermes_otel" /opt/hermes/plugins/hermes_otel/plugin.yaml

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

# The venv is the image's, not the runtime's: `pm` reads this flag and refuses every on-demand
# install (plugin deps, skill extras, the boot-time dependency refresh), which is the state
# upstream's Docker image declares and the only one under which "immutable venv" is true.
# The user-facing switch is security.allow_lazy_installs in config.yaml; this one is the
# image-level bridge `pm/client.py` sets for its own children.
ENV HERMES_DISABLE_LAZY_INSTALLS=1

USER 1000:1000
