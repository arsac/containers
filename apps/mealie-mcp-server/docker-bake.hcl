target "docker-metadata-action" {}

variable "APP" {
  default = "mealie-mcp-server"
}

variable "VERSION" {
  // No tagged releases upstream; pinned to a commit on main, which Renovate
  // rewrites when that branch head moves.
  default = "86ebf379536cf2b3a07c2007798db02894c51f21" // renovate: datasource=git-refs depName=rldiao/mealie-mcp-server packageName=https://github.com/rldiao/mealie-mcp-server currentValue=main
}

variable "SOURCE" {
  default = "https://github.com/rldiao/mealie-mcp-server"
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
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits = ["image"]
  platforms = [
    "linux/amd64"
  ]
}
