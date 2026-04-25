target "docker-metadata-action" {}

variable "APP" {
  default = "subgen"
}

variable "VERSION" {
  default = "1d959b16cc99683824aa849744a95d8ac6c8952a"
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
