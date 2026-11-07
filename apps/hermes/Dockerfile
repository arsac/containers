# syntax=docker/dockerfile:1

# Hermes Agent (upstream's own image) plus three plugins installed at build time: the
# Hindsight memory provider, the official Home Assistant platform plugin, and hermes_otel for
# OpenTelemetry. Not built from PyPI: the `hermes-agent` distribution stops at 0.19.0 and
# these plugins require hermes >= 0.21.4 / >= 0.21.5, so the published image is the only base
# that satisfies them.
ARG VERSION="v0.23.0"
ARG SOURCE_IMAGE="nousresearch/hermes-agent"

FROM ${SOURCE_IMAGE}:${VERSION}

# global-scope ARGs are not visible inside stages without re-declaration
ARG VERSION
ARG HINDSIGHT_CLIENT_VERSION="1.2.0"
ARG HINDSIGHT_TAG="integrations/hermes/v1.2.4"
ARG HERMES_OTEL_TAG="hermes-otel-v1.32.5"
ARG HOMEASSISTANT_REF="4d492b1dc5326af3e38bb2cf3e4b9ad6d65f0072"

# /bin/sh is dash here, so a piped RUN has no pipefail; declare it rather than trust the
# default shell (the tag lookups below pipe through tail/cut).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The runtime account. Upstream bakes `hermes` as 10000 and starts as root so a boot hook
# can remap the UID and chown the data volume; its entrypoint refuses a --user UID that is
# not this account's. Remapping the account to 1000:1000 here lets the container start
# unprivileged with that entrypoint intact, and leaves /opt/data's ownership to whoever
# mounts it (fsGroup) rather than to a root boot hook.
RUN groupmod -o -g 1000 hermes \
 && usermod -o -u 1000 -g 1000 hermes \
 && chown -R hermes:hermes /opt/data

# Plugin dependencies, from the uv upstream already ships (arch-suffixed path, so no second
# copy is added): Hindsight's cloud client, pinned, and the OpenTelemetry packages hermes_otel
# declares, taken from the plugin's own ranges since they travel with the tag pinned below.
# `hermes plugins install --yes-deps` is deliberately not used for them: it resolves into a
# package-manager generation under $HERMES_HOME/installs, which a volume mounted over
# /opt/data erases at runtime. What must not happen is an existing Hermes pin moving, so the
# environment's own pins are handed to the resolver as constraints: a spec that would upgrade
# or downgrade anything already installed is refused by uv, with the two conflicting
# requirements named, before the venv is touched.
RUN uv="$(echo /opt/hermes/tools/uv-*/uv)" \
 && "$uv" pip freeze --python /opt/hermes/.venv/bin/python \
      | grep -E '^[A-Za-z0-9_.-]+==' > /tmp/venv-constraints.txt \
 && "$uv" pip install --no-cache --python /opt/hermes/.venv/bin/python \
      -c /tmp/venv-constraints.txt \
      "hindsight-client==${HINDSIGHT_CLIENT_VERSION}" \
      "opentelemetry-api>=1.35,<2" \
      "opentelemetry-sdk>=1.35,<2" \
      "opentelemetry-exporter-otlp-proto-http>=1.35,<2" \
      "opentelemetry-exporter-otlp-proto-grpc>=1.35,<2" \
      "PyYAML>=6,<7"

# Plugins. `hermes plugins install` commits the plugin directory in one admission transaction;
# `--ref` accepts only a full commit SHA, so each release tag is resolved first (peeled tag
# line) and printed for provenance. Installs land in a throwaway HERMES_HOME and the plugin
# directory is then moved into the bundled tree, which is what survives a volume mounted over
# /opt/data and matches where Hermes discovers each kind: plugins/memory/<name> for a memory
# provider, platforms/<name> for a platform, and a top-level plugins/<name> for a hook plugin.
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

# Home Assistant: official plugin, and the only one of the three pinned by commit rather than
# by release tag - NousResearch/hermes-official-plugins publishes neither tags nor releases,
# so there is no ref to follow, and installing by catalog name is not reproducible: the CLI
# resolves the live catalog, not the copy in this image. The commit below is the one the base
# image's catalog ships (homeassistant 2.0.1, unchanged on main), and re-pinning it is a
# deliberate edit.
RUN printf '%s\n' "${HOMEASSISTANT_REF}" | grep -Eqx '[0-9a-f]{40}' \
 && mkdir -p /opt/hermes-seed \
 && HERMES_HOME=/opt/hermes-seed /opt/hermes/.venv/bin/hermes plugins install \
      --ref "${HOMEASSISTANT_REF}" NousResearch/hermes-official-plugins/homeassistant \
 && mv /opt/hermes-seed/plugins/homeassistant /opt/hermes/plugins/platforms/homeassistant \
 && rm -rf /opt/hermes-seed \
 && grep -qx "kind: platform" /opt/hermes/plugins/platforms/homeassistant/plugin.yaml

# Build-time assertions: every plugin is where its kind is discovered and everything it
# declares is installed at a satisfying version. An update that needs a newer client, or a new
# dependency we do not install, fails here instead of shipping a plugin that errors on load.
RUN /opt/hermes/.venv/bin/python - <<'PY'
import importlib.metadata as metadata
import tomllib
from pathlib import Path

import yaml
from packaging.requirements import Requirement

# hindsight-embed is only for local_embedded mode, which this image does not run.
OPTIONAL = ("hindsight-embed",)
PLUGINS = (
    Path("/opt/hermes/plugins/memory/hindsight"),
    Path("/opt/hermes/plugins/hermes_otel"),
    Path("/opt/hermes/plugins/platforms/homeassistant"),
)


def declared(directory):
    """Requirements a plugin declares, from its pyproject (preferred by Hermes' installer) or
    from python_dependencies in its manifest (the only place hermes_otel declares them)."""
    project = directory / "pyproject.toml"
    if project.exists():
        yield from tomllib.loads(project.read_text())["project"].get("dependencies") or ()
    manifest = yaml.safe_load((directory / "plugin.yaml").read_text()) or {}
    yield from manifest.get("python_dependencies") or ()


for plugin in PLUGINS:
    if not (plugin / "plugin.yaml").is_file():
        raise SystemExit(f"{plugin} has no plugin.yaml")
    for raw in declared(plugin):
        requirement = Requirement(raw)
        try:
            installed = metadata.version(requirement.name)
        except metadata.PackageNotFoundError:
            if requirement.name in OPTIONAL:
                print(f"{plugin.name}: {requirement.name} not installed, optional ({raw})")
                continue
            raise SystemExit(f"{plugin.name}: {requirement.name} is declared but not installed ({raw})")
        if installed not in requirement.specifier:
            raise SystemExit(f"{plugin.name}: {requirement.name} {installed} does not satisfy {raw}")
        print(f"{plugin.name}: {requirement.name} {installed} satisfies {requirement.specifier}")
PY

USER 1000:1000
