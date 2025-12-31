target "docker-metadata-action" {}

variable "APP" {
  default = "cuda-ml-base"
}

variable "VERSION" {
  // Format: cuda{CUDA_VERSION}-torch{TORCH_VERSION}
  default = "cuda12.8-torch2.9"
}

variable "SOURCE" {
  default = "https://github.com/arsac/containers"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:${VERSION}", "${APP}:latest"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}
