target "docker-metadata-action" {}

variable "APP" {
  default = "comfyui-ui"
}

# This is the ComfyUI backend version that this UI image is paired with.
# When this changes, VERSION below must be updated to the
# comfyui-frontend-package version that ComfyUI's requirements.txt pins
# for this ComfyUI tag. The .renovaterc.json5 packageRule groups these
# together so Renovate bumps both in one PR and a human can verify.
variable "COMFYUI_VERSION" {
  // renovate: datasource=github-releases depName=comfyanonymous/ComfyUI
  default = "v0.14.2"
}

# ComfyUI frontend release that matches COMFYUI_VERSION's pinned
# comfyui-frontend-package. For ComfyUI v0.14.2 this is v1.38.14.
# Verify by reading:
#   https://raw.githubusercontent.com/comfyanonymous/ComfyUI/<COMFYUI_VERSION>/requirements.txt
# and finding the `comfyui-frontend-package==X.Y.Z` line.
# Named VERSION (not FRONTEND_VERSION) so the shared CI app-options action can
# extract it via `jq '.[] | select(.name == "VERSION") | .value'`.
variable "VERSION" {
  // renovate: datasource=github-releases depName=Comfy-Org/ComfyUI_frontend
  default = "v1.38.14"
}

variable "SOURCE" {
  default = "https://github.com/Comfy-Org/ComfyUI_frontend"
}

group "default" {
  targets = ["image-local"]
}

target "image" {
  inherits = ["docker-metadata-action"]
  args = {
    FRONTEND_VERSION = "${VERSION}"
    COMFYUI_VERSION  = "${COMFYUI_VERSION}"
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
    "linux/amd64",
    "linux/arm64"
  ]
}
