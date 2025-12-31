target "docker-metadata-action" {}

variable "APP" {
  default = "comfyui"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=comfyanonymous/ComfyUI
  default = "v0.6.0"
}

variable "SOURCE" {
  default = "https://github.com/comfyanonymous/ComfyUI"
}

variable "BASE_IMAGE" {
  default = "ghcr.io/arsac/cuda-ml"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION    = "${VERSION}"
    BASE_IMAGE = "${BASE_IMAGE}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}
