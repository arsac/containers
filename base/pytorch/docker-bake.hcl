target "docker-metadata-action" {}

variable "APP" {
  default = "pytorch"
}

variable "VERSION" {
  // Format: cuda{CUDA_VERSION}-torch{TORCH_VERSION}
  default = "cuda13.0-torch2.11"
}

variable "SOURCE" {
  default = "https://github.com/arsac/containers"
}

variable "VENDOR" {
  default = "arsac"
}

group "default" {
  targets = ["image-devel-local"]
}

target "image-devel" {
  inherits   = ["docker-metadata-action"]
  dockerfile = "Dockerfile"
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-devel-local" {
  inherits = ["image-devel"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}-devel", "${APP}:devel", "${APP}:latest"]
}

target "image-devel-all" {
  inherits  = ["image-devel"]
  platforms = ["linux/amd64"]
}

// `image-all` is a metadata stub — the CI `app-options` action reads platforms
// from it regardless of variant. The runtime build job is gated on
// Dockerfile.runtime existence in release.yaml, so this target is never
// actually built for base/pytorch (no Dockerfile.runtime exists).
target "image-all" {
  inherits  = ["image-devel"]
  platforms = ["linux/amd64"]
}
