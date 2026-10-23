target "docker-metadata-action" {}

variable "APP" {
  default = "gnhf"
}

variable "VERSION" {
  // renovate: datasource=npm depName=gnhf
  default = "0.1.51"
}

# The agent gnhf drives. Provider-agnostic on purpose - it takes an
# OpenAI-compatible base URL, which is what points it at a self-hosted model.
variable "OPENCODE_VERSION" {
  // renovate: datasource=npm depName=opencode-ai
  default = "1.19.3"
}

variable "NO_MISTAKES_VERSION" {
  // renovate: datasource=github-releases depName=kunchenguid/no-mistakes
  default = "v1.84.0"
}

variable "TREEHOUSE_VERSION" {
  // renovate: datasource=github-releases depName=kunchenguid/treehouse
  default = "v3.1.5"
}

variable "SOURCE" {
  default = "https://github.com/kunchenguid/gnhf"
}

# Injected by the Forgejo publish workflow (internal registry host/arsac).
variable "REGISTRY" {
  default = ""
}

# Dated calver tag set by the publish workflow (e.g. 2026.07.01-<sha7>).
variable "TAG" {
  default = ""
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION             = "${VERSION}"
    OPENCODE_VERSION    = "${OPENCODE_VERSION}"
    NO_MISTAKES_VERSION = "${NO_MISTAKES_VERSION}"
    TREEHOUSE_VERSION   = "${TREEHOUSE_VERSION}"
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

# Both Go tools publish linux amd64 and arm64 assets, so arm64 is real here.
target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}

target "forgejo" {
  inherits = ["image-all"]
  tags = [
    "${REGISTRY}/${APP}:${TAG}",
    "${REGISTRY}/${APP}:${VERSION}",
  ]
}
