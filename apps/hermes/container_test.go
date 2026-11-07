package main

import (
	"os"
	"testing"

	"github.com/stretchr/testify/require"

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
	t.Run("boots the supervised tree unprivileged", func(t *testing.T) {
		helpers.RequireBoots(t, image, helpers.BootConfig{
			User:      "1000:1000",
			Cmd:       servedCommand,
			Env:       dashboardEnv,
			Ready:     `HERMES_DASHBOARD_READY port=`,
			Forbidden: bootFatals,
		})
	})
	t.Run("boots the supervised tree as root", func(t *testing.T) {
		// Root is still upstream's default and a legitimate deployment; the /run fix must not
		// regress it. preinit re-chowns /run here, so this path never needed the fix.
		helpers.RequireBoots(t, image, helpers.BootConfig{
			User:      "0:0",
			Cmd:       servedCommand,
			Env:       dashboardEnv,
			Ready:     `HERMES_DASHBOARD_READY port=`,
			Forbidden: bootFatals,
		})
	})
	t.Run("plugins support the bundled hermes version", func(t *testing.T) {
		script, err := os.ReadFile("plugin_compat.py")
		require.NoError(t, err)
		helpers.RequireCommandSucceeds(t, image, nil, `/opt/hermes/.venv/bin/python`, `-c`, string(script))
	})
}

// bootFatals abort s6-overlay before any service starts. `s6-applyuidgid: fatal:` is deliberately
// not here: it is upstream's boot hook failing to drop privileges it does not need when it is
// already the runtime user, and the hook carries on.
var bootFatals = []string{"preinit: fatal", "s6-overlay-suexec: fatal"}

// servedCommand is the job a supervised deployment runs: it registers a profile gateway with s6
// and stays up, where the image's no-argument default finishes and shuts the container down.
var servedCommand = []string{"gateway", "run"}

// dashboardEnv starts the supervised dashboard, whose readiness line is how a deployment knows
// the tree is up; the credentials only satisfy the non-loopback auth gate.
var dashboardEnv = map[string]string{
	"HERMES_DASHBOARD":                     "1",
	"HERMES_DASHBOARD_BASIC_AUTH_USERNAME": "boot-test",
	"HERMES_DASHBOARD_BASIC_AUTH_PASSWORD": "boot-test",
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
