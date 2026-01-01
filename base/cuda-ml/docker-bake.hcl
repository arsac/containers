target "docker-metadata-action" {}

variable "APP" {
  default = "cuda-ml"
}

variable "VERSION" {
  // Format: cuda{CUDA_VERSION}-torch{TORCH_VERSION}
  default = "cuda12.8-torch2.9"
}

variable "SOURCE" {
  default = "https://github.com/arsac/containers"
}

variable "VENDOR" {
  default = "arsac"
}

group "default" {
  targets = ["image-devel-local", "image-local"]
}

// Devel target - CUDA devel + PyTorch (for compiling CUDA extensions)
// Must be built and pushed BEFORE runtime
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
  tags     = ["${APP}:${VERSION}-devel", "${APP}:devel"]
}

target "image-devel-all" {
  inherits = ["image-devel"]
  platforms = [
    "linux/amd64"
  ]
}

// Runtime target - minimal CUDA runtime with Python packages
// Pulls from published devel image (not built locally)
target "image" {
  inherits   = ["docker-metadata-action"]
  dockerfile = "Dockerfile.runtime"
  args = {
    VENDOR = "${VENDOR}"
  }
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}", "${APP}:runtime", "${APP}:latest"]
  // For local builds, use local devel image
  args = {
    DEVEL_IMAGE = "${APP}:devel"
  }
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}
