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

# sha256 of the upstream release tarball (verified in the Dockerfile ADD).
# Refresh MANUALLY alongside a HONCHO_REF bump — the docker-bake renovate
# manager captures a single value per annotation and will not co-bump this.
variable "HONCHO_SHA256" {
  default = "be832a84f8bbdddcfb38f5dd1777414512d9be6a576e860a96a2371a00929eab"
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
    HONCHO_REF    = "${HONCHO_REF}"
    HONCHO_SHA256 = "${HONCHO_SHA256}"
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
target "forgejo" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
  tags = [
    "${REGISTRY}/${APP}:${TAG}",
    "${REGISTRY}/${APP}:${VERSION}",
  ]
}
