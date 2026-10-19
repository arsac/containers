target "docker-metadata-action" {}

variable "APP" {
  default = "honcho-mcp"
}

# Image version → published tags; the Dockerfile fetches this tag's mcp/
# (v-prefix stripped for the tarball path).
variable "VERSION" {
  // renovate: datasource=github-tags depName=plastic-labs/honcho
  default = "v3.3.0"
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
    VERSION = "${VERSION}"
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

# Built + pushed by the in-cluster Forgejo runner to the internal registry.
# Inherits image-all's platforms (amd64,arm64); only adds the registry tags.
target "forgejo" {
  inherits = ["image-all"]
  tags = [
    "${REGISTRY}/${APP}:${TAG}",
    "${REGISTRY}/${APP}:${VERSION}",
  ]
}
