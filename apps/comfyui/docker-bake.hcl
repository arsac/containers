target "docker-metadata-action" {}

variable "APP" {
  default = "comfyui"
}

variable "VERSION" {
  // renovate: datasource=github-releases depName=comfyanonymous/ComfyUI
  default = "v0.3.40"
}


variable "MANAGER_VERSION" {
  // renovate: datasource=github-releases depName=Comfy-Org/ComfyUI-Manager
  default = "3.32.5"
}

variable "CLI_VERSION" {
  // renovate: datasource=github-releases depName=Comfy-Org/comfy-cli
  default = "v1.4.1"
}

variable "SOURCE" {
  default = "https://github.com/comfyanonymous/ComfyUI"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION = "${VERSION}"
    MANAGER_VERSION = "${MANAGER_VERSION}"
    CLI_VERSION = "${CLI_VERSION}"
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
