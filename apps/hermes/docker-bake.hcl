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

# Pin naming: `*_TAG` holds an upstream release tag, which the Dockerfile resolves to a commit
# before installing (`plugins install --ref` accepts only a full SHA); `*_REF` holds the commit
# itself, as `ATE_ENV_REF` does elsewhere in this repo.

# The plugin's own release tag (vectorize-io/hindsight tags each integration separately:
# `integrations/hermes/v1.2.4`). Renovate tracks it through github-tags, so plugin releases
# land as automergeable PRs like every other pin here; the versioning regex extracts the
# semver from the tag and ignores the repo's own `vX.Y.Z` client/server tags.
variable "HINDSIGHT_TAG" {
  // renovate: datasource=github-tags depName=vectorize-io/hindsight versioning=regex:^integrations/hermes/v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
  default = "integrations/hermes/v1.2.4"
}

# Same pattern for the telemetry plugin, whose repo tags `hermes-otel-vX.Y.Z` and nothing else.
variable "HERMES_OTEL_TAG" {
  // renovate: datasource=github-tags depName=briancaffey/hermes-otel versioning=regex:^hermes-otel-v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
  default = "hermes-otel-v1.32.5"
}

# Commit pin: NousResearch/hermes-official-plugins publishes no tags and no releases, so there
# is nothing for Renovate to follow. The value is the commit the base image's plugin catalog
# ships (homeassistant 2.0.1); re-pinning it is a deliberate edit.
variable "HOMEASSISTANT_REF" {
  default = "4d492b1dc5326af3e38bb2cf3e4b9ad6d65f0072"
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
