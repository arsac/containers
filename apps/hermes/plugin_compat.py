"""Assert every bundled plugin loads on the hermes version this image carries.

Run by apps/hermes/container_test.go inside the built image, next to the plugin
trees and the venv that will actually serve them - it is not part of the image,
and it is never run on a developer's machine.

Why a version comparison rather than a load: `hermes plugins install` refuses an
incompatible *installer* format, but nothing refuses a release whose manifest
asks for a newer hermes than the base image provides, and the plugin would then
fail somewhere inside its own import. This names the mismatch instead, and it
sweeps every bundled manifest, so the base image's own plugins are covered too.
"""

# PyYAML and packaging come from the image venv (PyYAML is a plugin dependency the Dockerfile
# installs). A host-side analyzer cannot resolve them, and this file is not meant to run there.
# pyright: reportMissingImports=false, reportMissingModuleSource=false

import re
import subprocess
from pathlib import Path

import yaml
from packaging.specifiers import SpecifierSet
from packaging.version import Version

reported = subprocess.run(
    ["/opt/hermes/.venv/bin/hermes", "--version"], capture_output=True, text=True, check=True
).stdout

match = re.search(r"v(\d+\.\d+\.\d+)", reported)
if match is None:
    raise SystemExit(f"no version in `hermes --version` output: {reported!r}")
hermes = Version(match.group(1))

root = Path("/opt/hermes/plugins")
manifests = sorted(root.glob("*/plugin.yaml")) + sorted(root.glob("*/*/plugin.yaml"))

for manifest in manifests:
    declared = yaml.safe_load(manifest.read_text()) or {}
    floor = declared.get("requires_hermes")
    if floor and hermes not in SpecifierSet(str(floor)):
        raise SystemExit(f"{manifest.parent} requires hermes {floor}, this image is {hermes}")

print(f"{len(manifests)} bundled plugins support hermes {hermes}")
