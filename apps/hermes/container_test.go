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
	t.Run("hindsight is the active, available memory provider", func(t *testing.T) {
		script := `printf 'memory:\n  provider: hindsight\n' > "$HERMES_HOME/config.yaml"
status="$(hermes memory status)"
printf '%s\n' "$status" | grep -q 'Status: *available' &&
  printf '%s\n' "$status" | grep -q '← active'`
		helpers.RequireCommandSucceeds(t, image, &helpers.ContainerConfig{Env: map[string]string{
			"HINDSIGHT_API_KEY": "test-key",
			"HINDSIGHT_API_URL": "https://hindsight.invalid",
		}}, `/bin/sh`, `-c`, script)
	})
}
