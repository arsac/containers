target "docker-metadata-action" {}

variable "APP" {
  default = "subgen"
}

variable "VERSION" {
  default = "5f98ed611dcb46844e8d671bd5c17e1d092261f5" // renovate: datasource=git-refs depName=McCloudS/subgen packageName=https://github.com/McCloudS/subgen currentValue=main
}

variable "SOURCE" {
  default = "https://github.com/McCloudS/subgen"
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
  platforms = ["linux/amd64"]
}
