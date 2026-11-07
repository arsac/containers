package main

import (
	"testing"

	helpers "github.com/arsac/containers/tests"
)

func Test(t *testing.T) {
	image := helpers.GetTestImage("ghcr.io/arsac/hermes:rolling")

	t.Run("upstream entrypoint kept", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/hermes/docker/entrypoint-dispatch.sh")
	})
	t.Run("runs as 1000:1000", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, `[ "$(id -u):$(id -g)" = "1000:1000" ]`)
	})
	t.Run("install tree is read-only for the runtime user", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, `[ ! -w /opt/hermes/plugins ]`)
	})
	t.Run("hindsight client imports", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/opt/hermes/.venv/bin/python`, `-c`, `import hindsight_client`)
	})
	t.Run("plugin shipped in the bundled memory tree", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/hermes/plugins/memory/hindsight/plugin.yaml")
	})
	t.Run("active and available, cloud mode", func(t *testing.T) {
		requireActiveProvider(t, image, map[string]string{
			"HINDSIGHT_API_KEY": "test-key",
			"HINDSIGHT_API_URL": "https://hindsight.invalid",
		})
	})
	t.Run("active and available, local_external mode", func(t *testing.T) {
		// A self-hosted server: url only, key optional.
		requireActiveProvider(t, image, map[string]string{
			"HINDSIGHT_MODE":    "local_external",
			"HINDSIGHT_API_URL": "http://hindsight.invalid:8888",
		})
	})
	t.Run("home assistant plugin discovered", func(t *testing.T) {
		// A bundled platform loads without a plugins.enabled entry.
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`,
			`hermes plugins list | grep -qE 'homeassistant +│ enabled'`)
	})
	t.Run("home assistant toolset registered", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`,
			`hermes tools list | grep -q homeassistant`)
	})
	t.Run("otel plugin imports and registers its hooks", func(t *testing.T) {
		script := `doctor="$(hermes plugins doctor /opt/hermes/plugins/hermes_otel)"
printf '%s\n' "$doctor" | grep -qE 'registration passed' &&
  printf '%s\n' "$doctor" | grep -qE 'registrations: .*[1-9][0-9]* hook'`
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, script)
	})
	t.Run("otel dependencies import", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/opt/hermes/.venv/bin/python`, `-c`,
			`import opentelemetry.sdk, opentelemetry.exporter.otlp.proto.http, opentelemetry.exporter.otlp.proto.grpc, yaml`)
	})
	t.Run("otel plugin loads once enabled", func(t *testing.T) {
		// Hooks are not a default-on kind, so the deployment has to name it.
		script := `hermes plugins list | grep -qE 'hermes_otel +│ not enabled'
printf 'plugins:\n  enabled: [hermes_otel]\n' > "$HERMES_HOME/config.yaml"
hermes plugins list | grep -qE 'hermes_otel +│ enabled'`
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, script)
	})
	t.Run("plugins support the bundled hermes version", func(t *testing.T) {
		// requires_hermes in every bundled manifest vs the version this image reports - no list to
		// maintain, and it covers the base image's own plugins too. This is what keeps an
		// unattended plugin bump aligned with the base image.
		script := `/opt/hermes/.venv/bin/python - <<'PY'
import re
import subprocess
from pathlib import Path

import yaml
from packaging.specifiers import SpecifierSet
from packaging.version import Version

reported = subprocess.run(
    ["/opt/hermes/.venv/bin/hermes", "--version"], capture_output=True, text=True, check=True
).stdout
hermes = Version(re.search(r"v(\d+\.\d+\.\d+)", reported).group(1))
root = Path("/opt/hermes/plugins")
manifests = sorted(root.glob("*/plugin.yaml")) + sorted(root.glob("*/*/plugin.yaml"))
checked = 0
for manifest in manifests:
    declared = yaml.safe_load(manifest.read_text()) or {}
    floor = declared.get("requires_hermes")
    if floor and hermes not in SpecifierSet(str(floor)):
        raise SystemExit(f"{manifest.parent} requires hermes {floor}, this image is {hermes}")
    checked += 1
print(f"{checked} bundled plugins support hermes {hermes}")
PY`
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, script)
	})
}

// requireActiveProvider asserts `hermes memory status` reports hindsight as both the selected
// and the available provider under env.
func requireActiveProvider(t *testing.T, image string, env map[string]string) {
	t.Helper()

	script := `printf 'memory:\n  provider: hindsight\n' > "$HERMES_HOME/config.yaml"
status="$(hermes memory status)"
printf '%s\n' "$status" | grep -q 'Status: *available' &&
  printf '%s\n' "$status" | grep -q '← active'`
	helpers.RequireCommandSucceeds(t, image, &helpers.ContainerConfig{Env: env}, `/bin/sh`, `-c`, script)
}
