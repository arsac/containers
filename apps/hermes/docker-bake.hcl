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

# Nous' reviewed catalog pin for plugin 1.2.4 (plugin-catalog/hindsight.yaml in
# NousResearch/hermes-agent). Deliberately NOT renovate-tracked: a plugin bump is a code
# review of what the agent runs, not a version bump, so re-pin it by hand.
variable "HINDSIGHT_REF" {
  default = "f14cc1eb5624b0374cb4d82768eb2e0b9c21ae24"
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
    HINDSIGHT_REF            = "${HINDSIGHT_REF}"
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
