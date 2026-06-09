target "docker-metadata-action" {}

variable "APP" {
  default = "kserve-huggingfaceserver"
}

# Image version → drives the published tags (app-options reads this VERSION
# variable; app-versions + docker/metadata-action emit 0.22.1 / 0.22 / 0). Track
# the vLLM version this image provides; bump alongside VLLM_VERSION in the patch.
variable "VERSION" {
  default = "0.22.1"
}

# Pinned upstream kserve commit. The Dockerfile's `src` stage fetches this ref
# and applies patches/. Bumping it = re-test the patch applies (git apply fails
# loudly on drift) + re-validate on GPU.
variable "KSERVE_REF" {
  // renovate: datasource=git-refs depName=kserve packageName=https://github.com/kserve/kserve
  default = "11ad2ca18a2265b079bd140220572017ad06bdfc"
}

variable "SOURCE" {
  default = "https://github.com/kserve/kserve"
}

# From-scratch CUDA 13.2 + vLLM 0.22.1 build (~13GB image, much larger devel
# intermediates) — free runner disk before building or CI runs out of space.
variable "FREE_DISK_SPACE" {
  default = "true"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    KSERVE_REF = "${KSERVE_REF}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${KSERVE_REF}"
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
