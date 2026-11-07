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
ARG HINDSIGHT_REF="f14cc1eb5624b0374cb4d82768eb2e0b9c21ae24"

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

# Install the plugin at the reviewed catalog pin, into a throwaway home, then move it into
# the bundled memory tree. That is one of the two places Hermes discovers memory providers
# (`<install>/plugins/memory/<name>`, `$HERMES_HOME/plugins/<name>`) and the only one that
# survives a pod mounting a volume over /opt/data; it also keeps the plugin inside the
# root-owned, read-only /opt/hermes tree instead of a writable home.
# No --yes-deps: the dependency half of that install transaction resolves into the venv
# above (already done) and refuses rather than half-installing in a non-interactive build.
RUN mkdir -p /opt/hermes-seed \
 && HERMES_HOME=/opt/hermes-seed /opt/hermes/.venv/bin/hermes plugins install \
      --ref "${HINDSIGHT_REF}" vectorize-io/hindsight/hindsight-integrations/hermes \
 && mv /opt/hermes-seed/plugins/hindsight /opt/hermes/plugins/memory/hindsight \
 && rm -rf /opt/hermes-seed

# Build-time assertions: the client imports, and the plugin sits where discovery scans.
RUN /opt/hermes/.venv/bin/python -c "import hindsight_client" \
 && test -f /opt/hermes/plugins/memory/hindsight/plugin.yaml

USER 1000:1000
