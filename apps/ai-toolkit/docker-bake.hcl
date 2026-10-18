target "docker-metadata-action" {}

variable "APP" {
  default = "ai-toolkit"
}

variable "VERSION" {
  default = "8cf43dd2cc1fe828884001aceeda044649d9abd0" // renovate: datasource=git-refs depName=ostris/ai-toolkit packageName=https://github.com/ostris/ai-toolkit currentValue=main
}

variable "SOURCE" {
  default = "https://github.com/ostris/ai-toolkit"
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
    "org.opencontainers.image.source" = "${SOURCE}"
  }
}

target "image-local" {
  inherits = ["image"]
  output = ["type=docker"]
  tags = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}
