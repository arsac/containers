target "docker-metadata-action" {}

variable "APP" {
  default = "kserve-huggingfaceserver"
}

# Pinned upstream kserve commit. prepare.sh clones this ref and applies
# patches/ before bake runs. Bumping it = re-test the patch applies (git apply
# fails loudly on drift) + re-validate on GPU.
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

# Context is the patched upstream tree produced by prepare.sh; we build kserve's
# OWN huggingface_server.Dockerfile (patched to vLLM 0.22.1 + transformers 5.5.3,
# lmcache dropped) — not a Dockerfile we vendor.
target "image" {
  inherits   = ["docker-metadata-action"]
  context    = ".src/python"
  dockerfile = "huggingface_server.Dockerfile"
  labels = {
    "org.opencontainers.image.source" = "${SOURCE}"
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
