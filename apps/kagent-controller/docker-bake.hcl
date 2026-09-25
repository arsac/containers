target "docker-metadata-action" {}

variable "APP" {
  default = "kagent-controller"
}

# The kagent release this compat image rebuilds. Published tags track it, so the
# tag says which upstream version the patch was written against.
variable "VERSION" {
  default = "1.0.0-alpha4"
}

# Pinned upstream kagent commit (the v1.0.0-alpha4 tag). Deliberately not
# Renovate-tracked: bumping it means checking that patches/ still applies (git
# apply fails loudly on drift) and, more importantly, whether kagent has fixed
# the credential grammar upstream — in which case this image should be deleted
# rather than rebase.
variable "KAGENT_REF" {
  default = "8be872b231d09f762435dc8296556c0ffef6ce6d"
}

# Upstream image whose final stage is reused. Keep this in step with the digest
# the deployment pins for this controller, otherwise "patched image" and the
# intended upstream baseline drift apart.
variable "BASE_IMAGE" {
  default = "ghcr.io/kagent-dev/kagent/controller@sha256:99bb9ae31aa799d7dcfcf01562f706af6681c9f968529aa3cd83566a7516ef0d"
}

variable "SOURCE" {
  default = "https://github.com/kagent-dev/kagent"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    KAGENT_REF = "${KAGENT_REF}"
    BASE_IMAGE = "${BASE_IMAGE}"
    VERSION    = "${VERSION}"
  }
  labels = {
    "org.opencontainers.image.source"   = "${SOURCE}"
    "org.opencontainers.image.revision" = "${KAGENT_REF}"
  }
}

target "image-local" {
  inherits = ["image"]
  output   = ["type=docker"]
  tags     = ["${APP}:${VERSION}"]
}

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}
