target "docker-metadata-action" {}

variable "APP" {
  default = "ate-env-api"
}

# Substrate fork release the cluster runs. ate-env's go.mod pins an upstream
# Substrate commit outside the fork's history, so the build replaces it with
# this tag and runs ate-env's test suite against it: this image is the
# compatibility pin. Keep in step with apps/ate-env-guest.
variable "SUBSTRATE_VERSION" {
  // renovate: datasource=github-tags depName=kagent-dev/substrate
  default = "v1.0.0-rc2"
}

# Pinned agent-substrate/env commit. Keep in step with apps/ate-env-guest.
variable "ATE_ENV_REF" {
  default = "56424de763f91daa6b6c38f6249bacef1d82e5e1" // renovate: datasource=git-refs depName=agent-substrate/env packageName=https://github.com/agent-substrate/env currentValue=main
}

# Published tag: <substrate version>-<ate-env sha7>, e.g. 1.0.0-rc2-56424de.
# The sha7 is always the last dash-separated field, so stripping it leaves the
# Substrate version to compare against the chart.
variable "VERSION" {
  default = "${trimprefix(SUBSTRATE_VERSION, "v")}-${substr(ATE_ENV_REF, 0, 7)}"
}

# VERSION is the only published tag: no semver aliases or rolling, which would
# drop one of the two pins.
variable "EXACT_TAG" {
  default = "true"
}

variable "SOURCE" {
  default = "https://github.com/agent-substrate/env"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    ATE_ENV_REF       = "${ATE_ENV_REF}"
    SUBSTRATE_VERSION = "${SUBSTRATE_VERSION}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${ATE_ENV_REF}"
    "org.opencontainers.image.licenses" = "Apache-2.0"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}
