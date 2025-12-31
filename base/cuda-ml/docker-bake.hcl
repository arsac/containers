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

group "default" {
  targets = ["image-local", "image-devel-local"]
}

// Runtime target (default)
target "image" {
  inherits = ["docker-metadata-action"]
  target   = "runtime"
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}", "${APP}:latest"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}

// Devel target (for building CUDA extensions)
target "image-devel" {
  inherits = ["docker-metadata-action"]
  target   = "builder"
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
