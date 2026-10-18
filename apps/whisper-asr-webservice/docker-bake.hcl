target "docker-metadata-action" {}

variable "APP" {
  default = "whisper-asr-webservice"
}

variable "VERSION" {
  // renovate: datasource=github-tags depName=ahmetoner/whisper-asr-webservice
  default = "v1.10.0"
}

variable "SOURCE" {
  default = "https://github.com/ahmetoner/whisper-asr-webservice"
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
