target "docker-metadata-action" {}

variable "APP" {
  default = "mealie-mcp-server"
}

variable "VERSION" {
  // No tagged releases upstream; pin to a commit SHA. Renovate will bump
  // this when new commits land on rldiao/mealie-mcp-server@main.
  // renovate: datasource=git-refs depName=https://github.com/rldiao/mealie-mcp-server lookupName=https://github.com/rldiao/mealie-mcp-server currentValue=main
  default = "f7a2a5e21e68e223629393a5ad16f55dca6ea577"
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
