target "docker-metadata-action" {}

variable "APP" {
  default = "kserve-huggingfaceserver"
}

variable "VERSION" {
  // renovate: datasource=docker depName=kserve/huggingfaceserver versioning=semver-coerced
  default = "v0.19.0-rc0"
}

variable "SOURCE" {
  default = "https://github.com/kserve/kserve"
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
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = ["linux/amd64"]
}
