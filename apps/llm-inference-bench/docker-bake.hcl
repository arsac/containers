target "docker-metadata-action" {}

variable "APP" {
  default = "llm-inference-bench"
}

# Image version -> published tags. Tracks the upstream release this image wraps.
variable "VERSION" {
  // renovate: datasource=github-tags depName=local-inference-lab/llm-inference-bench
  default = "v0.8.0"
}

variable "SOURCE" {
  default = "https://github.com/local-inference-lab/llm-inference-bench"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION = "${VERSION}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${VERSION}"
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
    "linux/amd64",
    "linux/arm64",
  ]
}
