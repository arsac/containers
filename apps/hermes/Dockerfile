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
ARG HINDSIGHT_CLIENT_VERSION="1.2.0"
ARG HINDSIGHT_TAG="integrations/hermes/v1.2.4"
ARG HERMES_OTEL_TAG="hermes-otel-v1.32.5"
ARG HOMEASSISTANT_REF="13b2c1c9c8204bf333df240b2aacf98c3e6250b7"

# /bin/sh is dash here, so a piped RUN has no pipefail; declare it rather than trust the
# default shell (the freeze, the pin checks and the pin greps below all pipe).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

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

# Build-time assertions: every plugin is where its kind is discovered, it loads on the hermes
# version in this image (`requires_hermes`), and everything it declares is installed at a
# satisfying version. A plugin release that outruns the base image, or that needs a dependency
# we do not install, fails here instead of shipping something that errors on load.
RUN /opt/hermes/.venv/bin/python - "${VERSION#v}" <<'PY'
import importlib.metadata as metadata
import sys
import tomllib
from pathlib import Path

import yaml
from packaging.requirements import Requirement
from packaging.specifiers import SpecifierSet
from packaging.version import Version

# hindsight-embed is only for local_embedded mode, which this image does not run.
OPTIONAL = ("hindsight-embed",)
PLUGINS = (
    Path("/opt/hermes/plugins/memory/hindsight"),
    Path("/opt/hermes/plugins/hermes_otel"),
    Path("/opt/hermes/plugins/platforms/homeassistant"),
)

hermes = Version(sys.argv[1])


def manifest_of(directory):
    return yaml.safe_load((directory / "plugin.yaml").read_text()) or {}


def declared(directory):
    """Requirements a plugin declares, from its pyproject (preferred by Hermes' installer) or
    from python_dependencies in its manifest (the only place hermes_otel declares them)."""
    project = directory / "pyproject.toml"
    if project.exists():
        yield from tomllib.loads(project.read_text())["project"].get("dependencies") or ()
    yield from manifest_of(directory).get("python_dependencies") or ()


for plugin in PLUGINS:
    manifest = manifest_of(plugin)
    floor = manifest.get("requires_hermes")
    if floor and hermes not in SpecifierSet(str(floor)):
        raise SystemExit(f"{plugin.name} {manifest.get('version')} requires hermes {floor}, this image is {hermes}")
    print(f"{plugin.name} {manifest.get('version')} on hermes {hermes} (requires {floor or 'nothing'})")
    for raw in declared(plugin):
        requirement = Requirement(raw)
        if requirement.marker is not None and not requirement.marker.evaluate():
            continue  # e.g. tzdata, which homeassistant needs on Windows only
        try:
            installed = metadata.version(requirement.name)
        except metadata.PackageNotFoundError:
            if requirement.name in OPTIONAL:
                print(f"  {requirement.name} not installed, optional ({raw})")
                continue
            raise SystemExit(f"  {requirement.name} is declared but not installed ({raw})")
        if installed not in requirement.specifier:
            raise SystemExit(f"  {requirement.name} {installed} does not satisfy {raw}")
PY

USER 1000:1000
