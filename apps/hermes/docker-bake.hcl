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

# The plugin's own release tag (vectorize-io/hindsight tags each integration separately:
# `integrations/hermes/v1.2.4`). Renovate tracks it through github-tags, so plugin releases
# land as automergeable PRs like every other pin here; the versioning regex extracts the
# semver from the tag and ignores the repo's own `vX.Y.Z` client/server tags.
variable "HINDSIGHT_TAG" {
  // renovate: datasource=github-tags depName=vectorize-io/hindsight versioning=regex:^integrations/hermes/v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$
  default = "integrations/hermes/v1.2.4"
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
