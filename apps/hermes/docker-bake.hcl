target "docker-metadata-action" {}

variable "APP" {
  default = "hermes"
}

variable "VERSION" {
  // renovate: datasource=docker depName=nousresearch/hermes-agent
  default = "v0.23.0"
}

variable "SOURCE" {
  default = "https://github.com/NousResearch/hermes-agent"
}

variable "SOURCE_IMAGE" {
  default = "nousresearch/hermes-agent"
}

variable "HINDSIGHT_CLIENT_VERSION" {
  // renovate: datasource=pypi depName=hindsight-client
  default = "1.2.0"
}

# Pin naming: `*_TAG` holds an upstream release tag, which the build resolves to its commit
# before installing (`plugins install --ref` accepts only a full SHA); `*_REF` holds the commit,
# as `ATE_ENV_REF` does elsewhere in this repo.

# vectorize-io/hindsight tags each integration separately, and the repo's own `vX.Y.Z`
# client/server tags do not match this regex, so only integration releases are proposed.
variable "HINDSIGHT_TAG" {
  // renovate: datasource=github-tags depName=vectorize-io/hindsight versioning=regex:^integrations/hermes/v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
  default = "integrations/hermes/v1.2.4"
}

# hermes-otel tags `hermes-otel-vX.Y.Z` and nothing else.
variable "HERMES_OTEL_TAG" {
  // renovate: datasource=github-tags depName=briancaffey/hermes-otel versioning=regex:^hermes-otel-v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
  default = "hermes-otel-v1.32.5"
}

# NousResearch/hermes-official-plugins publishes no tags and no releases, so this pin follows
# the repo's `main` and Renovate proposes a digest update per commit - the shape commit pins
# take elsewhere in this repo. Those are held for review by .renovaterc.json5's own rule.
variable "HOMEASSISTANT_REF" {
  default = "13b2c1c9c8204bf333df240b2aacf98c3e6250b7" // renovate: datasource=git-refs depName=NousResearch/hermes-official-plugins packageName=https://github.com/NousResearch/hermes-official-plugins currentValue=main
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION                  = "${VERSION}"
    SOURCE_IMAGE             = "${SOURCE_IMAGE}"
    HINDSIGHT_CLIENT_VERSION = "${HINDSIGHT_CLIENT_VERSION}"
    HINDSIGHT_TAG            = "${HINDSIGHT_TAG}"
    HERMES_OTEL_TAG          = "${HERMES_OTEL_TAG}"
    HOMEASSISTANT_REF        = "${HOMEASSISTANT_REF}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${VERSION}"
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
