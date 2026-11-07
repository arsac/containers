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
