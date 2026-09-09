target "docker-metadata-action" {}

variable "APP" {
  default = "vllm-qwen4exp"
}

# Date of the pinned upstream main commit (BASE_SHA in the Dockerfile), plus a
# revision that bumps when the patch set changes on the same base. Bump the
# date with a re-pin so tags stay ordered.
variable "VERSION" {
  default = "20260906.1"
}

variable "SOURCE" {
  default = "https://github.com/vllm-project/vllm"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  labels = {
    "org.opencontainers.image.source"      = "${SOURCE}"
    "org.opencontainers.image.description" = "vLLM main (pinned) + PR #53899 PLE CPU offload for Qwen3.8-Flash-Next on sm_120"
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
