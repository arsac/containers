target "docker-metadata-action" {}

variable "APP" {
  default = "vllm-dsv4"
}

# Tracks the upstream vLLM version this image patches. Bump alongside
# VLLM_VERSION/VLLM_DIGEST below, and re-validate on GPU: the patches are
# diffed against this exact tree.
variable "VERSION" {
  default = "0.27.1"
}

variable "VLLM_VERSION" {
  // renovate: datasource=docker depName=docker.io/vllm/vllm-openai
  default = "v0.27.1"
}

variable "VLLM_DIGEST" {
  default = "sha256:0a51ea5b4ae2dc5d81890e5173f54203d2a3ae0cfffe51b8fd2afd4391bfd967"
}

variable "SOURCE" {
  default = "https://github.com/vllm-project/vllm"
}

# Thin overlay on a prebuilt image - no CUDA compilation, so unlike
# kserve-huggingfaceserver this does not need the runner disk freed.
variable "FREE_DISK_SPACE" {
  default = "false"
}

# The base image is ~20GB. Pulling it from a WAN registry onto the GPU node
# has tripped kubelet's ephemeral-storage eviction threshold before, so the
# cluster pulls from the LAN registry. REGISTRY is injected from a CI secret.
variable "REGISTRY" {
  default = ""
}

variable "TAG" {
  default = ""
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VLLM_VERSION = "${VLLM_VERSION}"
    VLLM_DIGEST  = "${VLLM_DIGEST}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${VLLM_VERSION}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64"]
}

target "forgejo" {
  inherits  = ["image"]
  platforms = ["linux/amd64"]
  tags = [
    "${REGISTRY}/${APP}:${TAG}",
    "${REGISTRY}/${APP}:${VERSION}",
  ]
}
