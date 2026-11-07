target "docker-metadata-action" {}

variable "APP" {
  default = "hermes"
}

variable "VERSION" {
  // renovate: datasource=docker depName=nousresearch/hermes-agent
  default = "v0.23.0"
}

variable "SOURCE" {
  default = "https://github.com/NousResearch/hermes-agent"
}

variable "SOURCE_IMAGE" {
  default = "nousresearch/hermes-agent"
}

variable "HINDSIGHT_CLIENT_VERSION" {
  // renovate: datasource=pypi depName=hindsight-client
  default = "1.2.0"
}

# Plugin pins are commits - what `hermes plugins install --ref` takes, and what every other
# hermes image pins - with the release ref they came from in the annotation, so Renovate's
# git-refs datasource proposes the next ref *and* its commit in one edit. Nothing is resolved
# over the network at build time.

# vectorize-io/hindsight tags each integration separately; the repo's own vX.Y.Z client/server
# tags do not match this regex, so only integration releases are proposed. Its tags are
# annotated, so git-refs tracks the tag object - the commit it closes over is what the base
# image's plugin catalog pins for the same release.
variable "HINDSIGHT_REF" {
  default = "c6f7a651e962c476edbd9c0fa37cf25d20fc86b7" // renovate: datasource=git-refs depName=vectorize-io/hindsight packageName=https://github.com/vectorize-io/hindsight versioning=regex:^integrations/hermes/v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$ currentValue=integrations/hermes/v1.2.4
}

# hermes-otel tags hermes-otel-vX.Y.Z, lightly, so the pinned commit is the tag's target.
variable "HERMES_OTEL_REF" {
  default = "c68366655d4b24ea3e82090aeb70a8d1382cc416" // renovate: datasource=git-refs depName=briancaffey/hermes-otel packageName=https://github.com/briancaffey/hermes-otel versioning=regex:^hermes-otel-v(?<major>\d+)\.(?<minor>\d+)\.(?<patch>\d+)$ currentValue=hermes-otel-v1.32.5
}

# NousResearch/hermes-official-plugins publishes no tags and no releases, so this follows main
# and Renovate proposes a commit per merge there.
variable "HOMEASSISTANT_REF" {
  default = "13b2c1c9c8204bf333df240b2aacf98c3e6250b7" // renovate: datasource=git-refs depName=NousResearch/hermes-official-plugins packageName=https://github.com/NousResearch/hermes-official-plugins currentValue=main
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    VERSION                  = "${VERSION}"
    SOURCE_IMAGE             = "${SOURCE_IMAGE}"
    HINDSIGHT_CLIENT_VERSION = "${HINDSIGHT_CLIENT_VERSION}"
    HINDSIGHT_REF            = "${HINDSIGHT_REF}"
    HERMES_OTEL_REF          = "${HERMES_OTEL_REF}"
    HOMEASSISTANT_REF        = "${HOMEASSISTANT_REF}"
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

target "image-all" {
  inherits  = ["image"]
  platforms = ["linux/amd64", "linux/arm64"]
}
