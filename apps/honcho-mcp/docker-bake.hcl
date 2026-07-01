target "docker-metadata-action" {}

variable "APP" {
  default = "honcho-mcp"
}

# Image version → published tags. Tracks the Honcho release this image wraps.
variable "VERSION" {
  default = "3.0.11"
}

# Pinned upstream Honcho release tag. The Dockerfile fetches this ref's mcp/.
variable "HONCHO_REF" {
  // renovate: datasource=github-tags depName=plastic-labs/honcho
  default = "v3.0.11"
}

variable "SOURCE" {
  default = "https://github.com/plastic-labs/honcho"
}

# Injected by the Forgejo publish workflow (internal registry host/arsac).
variable "REGISTRY" {
  default = ""
}

# Dated calver tag set by the publish workflow (e.g. 2026.07.01-<sha7>).
variable "TAG" {
  default = ""
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    HONCHO_REF = "${HONCHO_REF}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${HONCHO_REF}"
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

# Built + pushed by the in-cluster Forgejo runner to the internal registry.
# Inherits image-all's platforms (amd64,arm64); only adds the registry tags.
target "forgejo" {
  inherits = ["image-all"]
  tags = [
    "${REGISTRY}/${APP}:${TAG}",
    "${REGISTRY}/${APP}:${VERSION}",
  ]
}
