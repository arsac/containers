target "docker-metadata-action" {}

variable "APP" {
  default = "nvidia-dra-driver-gpu"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=NVIDIA/k8s-dra-driver-gpu
  default = "v25.12.0"
}

variable "SOURCE" {
  default = "https://github.com/NVIDIA/k8s-dra-driver-gpu"
}

variable "SOURCE_IMAGE" {
  default = "nvcr.io/nvidia/k8s-dra-driver-gpu"
}

variable "FREE_DISK_SPACE" {
  default = "false"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION      = "${VERSION}"
    SOURCE_IMAGE = "${SOURCE_IMAGE}"
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
