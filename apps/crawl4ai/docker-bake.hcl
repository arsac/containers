target "docker-metadata-action" {}

variable "APP" {
  default = "crawl4ai"
}

variable "VERSION" {
  default = "v0.6.3"
}

variable "SOURCE" {
  default = "https://github.com/unclecode/crawl4ai"
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
