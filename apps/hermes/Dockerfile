# syntax=docker/dockerfile:1

# Hermes Agent (upstream's own image) plus the Hindsight memory provider installed at
# build time. Not built from PyPI: the `hermes-agent` distribution stops at 0.19.0 and
# the plugin requires hermes >= 0.21.4, so the published image is the only base that
# satisfies it.
ARG VERSION="v0.23.0"
ARG SOURCE_IMAGE="nousresearch/hermes-agent"

FROM ${SOURCE_IMAGE}:${VERSION}

# global-scope ARGs are not visible inside stages without re-declaration
ARG VERSION
ARG HINDSIGHT_CLIENT_VERSION="1.2.0"
ARG HINDSIGHT_TAG="integrations/hermes/v1.2.4"

# /bin/sh is dash here, so a piped RUN has no pipefail; declare it rather than trust the
# default shell (the tag lookup below pipes through tail/cut).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The runtime account. Upstream bakes `hermes` as 10000 and starts as root so a boot hook
# can remap the UID and chown the data volume; its entrypoint refuses a --user UID that is
# not this account's. Remapping the account to 1000:1000 here lets the container start
# unprivileged with that entrypoint intact, and leaves /opt/data's ownership to whoever
# mounts it (fsGroup) rather than to a root boot hook.
RUN groupmod -o -g 1000 hermes \
 && usermod -o -u 1000 -g 1000 hermes \
 && chown -R hermes:hermes /opt/data

# Hindsight's cloud-mode client into the image venv, using the uv upstream already ships
# (arch-suffixed path, so no second copy is added). hindsight-embed - the other half of
# the plugin's dependency list - stays out: it is imported for local_embedded only.
RUN uv="$(echo /opt/hermes/tools/uv-*/uv)" \
 && "$uv" pip install --no-cache --python /opt/hermes/.venv/bin/python \
      "hindsight-client==${HINDSIGHT_CLIENT_VERSION}"

# Install the plugin at its own release tag, into a throwaway home, then move it into the
# bundled memory tree. That is one of the two places Hermes discovers memory providers
# (`<install>/plugins/memory/<name>`, `$HERMES_HOME/plugins/<name>`) and the only one that
# survives a pod mounting a volume over /opt/data; it also keeps the plugin inside the
# root-owned, read-only /opt/hermes tree instead of a writable home.
# `plugins install --ref` only accepts a full commit SHA, so the tag is resolved here (the
# peeled tag line, so an annotated tag yields its commit). The resolved SHA is printed for
# provenance in the build log, and the installed manifest must carry the tag's version.
# No --yes-deps: the dependency half of that install transaction resolves into the venv
# above (already done) and refuses rather than half-installing in a non-interactive build.
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

# Build-time assertions: the client imports, and the plugin sits where discovery scans.
RUN /opt/hermes/.venv/bin/python -c "import hindsight_client" \
 && test -f /opt/hermes/plugins/memory/hindsight/plugin.yaml

# The plugin's declared requirements, checked against what this image actually installed. A
# plugin release that needs something newer - or something we do not install at all - fails
# here, so an unattended version bump cannot ship a provider whose calls error at runtime.
# hindsight-embed is the one mode-specific extra (local_embedded), reported and skipped.
RUN /opt/hermes/.venv/bin/python - <<'PY'
import importlib.metadata as metadata
import tomllib
from pathlib import Path

from packaging.requirements import Requirement

OPTIONAL = ("hindsight-embed",)
manifest = Path("/opt/hermes/plugins/memory/hindsight/pyproject.toml")
for declared in tomllib.loads(manifest.read_text())["project"]["dependencies"]:
    requirement = Requirement(declared)
    try:
        installed = metadata.version(requirement.name)
    except metadata.PackageNotFoundError:
        if requirement.name in OPTIONAL:
            print(f"{requirement.name}: not installed, optional ({declared})")
            continue
        raise SystemExit(f"{requirement.name} is declared by the plugin but not installed ({declared})")
    if installed not in requirement.specifier:
        raise SystemExit(f"{requirement.name} {installed} does not satisfy the plugin's {declared}")
    print(f"{requirement.name} {installed} satisfies {requirement.specifier}")
PY

USER 1000:1000
