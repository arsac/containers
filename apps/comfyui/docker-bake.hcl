target "docker-metadata-action" {}

variable "APP" {
  default = "comfyui"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=comfyanonymous/ComfyUI
  default = "v0.41.0"
}

variable "SOURCE" {
  default = "https://github.com/comfyanonymous/ComfyUI"
}

variable "BASE_IMAGE" {
  # First-party PyTorch devel image (Python 3.12, torch 2.11.0, CUDA 12.8 with
  # sm_120 Blackwell support). Pinned to the cu128 line deliberately: cu13x
  # images need a >= 580 host driver - check `nvidia-smi` on the GPU hosts
  # before moving up.
  default = "mirror.gcr.io/pytorch/pytorch:2.11.0-cuda12.8-cudnn9-devel"
}

variable "UV_VERSION" {
  // renovate: datasource=github-releases depName=astral-sh/uv
  default = "0.13.5"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION    = "${VERSION}"
    BASE_IMAGE = "${BASE_IMAGE}"
    UV_VERSION = "${UV_VERSION}"
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
