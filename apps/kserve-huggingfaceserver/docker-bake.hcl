target "docker-metadata-action" {}

variable "APP" {
  default = "kserve-huggingfaceserver"
}

# Pinned upstream kserve commit. The Dockerfile's `src` stage fetches this ref
# and applies patches/. Bumping it = re-test the patch applies (git apply fails
# loudly on drift) + re-validate on GPU. Renovate tracks kserve commits.
variable "KSERVE_REF" {
  // renovate: datasource=git-refs depName=kserve packageName=https://github.com/kserve/kserve
  default = "11ad2ca18a2265b079bd140220572017ad06bdfc"
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
  tags     = ["${APP}:0.22.1"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64"]
}
