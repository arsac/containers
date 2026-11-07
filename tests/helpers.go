package helpers

import (
	"context"
	"fmt"
	"io"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	"github.com/testcontainers/testcontainers-go"
	tcexec "github.com/testcontainers/testcontainers-go/exec"
	"github.com/testcontainers/testcontainers-go/log"
	"github.com/testcontainers/testcontainers-go/wait"

	"github.com/moby/moby/api/types/container"
	dockerclient "github.com/moby/moby/client"
)

// GetTestImage returns the image to test from TEST_IMAGE env var or falls back to the default
func GetTestImage(defaultImage string) string {
	image := os.Getenv("TEST_IMAGE")
	if image == "" {
		return defaultImage
	}
	return image
}

// ContainerConfig holds optional container configuration
type ContainerConfig struct {
	Env map[string]string // Environment variables to set in the container
}

// applyContainerConfig applies optional container configuration
func applyContainerConfig(config *ContainerConfig) []testcontainers.ContainerCustomizer {
	var opts []testcontainers.ContainerCustomizer

	if config == nil {
		return opts
	}

	if len(config.Env) > 0 {
		opts = append(opts, testcontainers.WithEnv(config.Env))
	}

	return opts
}

// tLogConsumer pipes container stdout/stderr to t.Log so failing tests surface what the container said.
//
// Safe against the "Log in goroutine after Test completed" panic: the log-pump goroutine is joined
// before the test finishes. CleanupContainer registers a t.Cleanup that runs Terminate ->
// stopLogProduction(), which blocks on the pump's done channel synchronously (testcontainers-go
// v0.43.0). Re-verify this invariant on any major testcontainers upgrade.
type tLogConsumer struct{ t *testing.T }

func (c *tLogConsumer) Accept(l testcontainers.Log) {
	c.t.Helper()
	c.t.Logf("[%s] %s", l.LogType, l.Content)
}

// runContainer is a tiny helper to start a container with common patterns: log forwarding,
// CleanupContainer registration, and immediate error check.
func runContainer(t *testing.T, ctx context.Context, image string, opts ...testcontainers.ContainerCustomizer) testcontainers.Container {
	t.Helper()

	opts = append([]testcontainers.ContainerCustomizer{
		testcontainers.WithLogger(log.TestLogger(t)),
		testcontainers.WithLogConsumers(&tLogConsumer{t: t}),
	}, opts...)

	c, err := testcontainers.Run(ctx, image, opts...)
	testcontainers.CleanupContainer(t, c)
	require.NoError(t, err)
	return c
}

// requireExitZero waits for container exit (via wait strategy set by caller) and asserts the exit code is zero.
func requireExitZero(t *testing.T, ctx context.Context, c testcontainers.Container, what string) {
	t.Helper()
	state, err := c.State(ctx)
	require.NoError(t, err)
	require.Equal(t, 0, state.ExitCode, what)
}

// BootConfig describes one supervised boot: the image's own entrypoint under PID 1, the log line
// that means the tree finished coming up, and the identity to come up as.
type BootConfig struct {
	User string // "1000:1000": the identity the deployment declares
	// Cmd is the long-running job a deployment runs under supervision. The image's own default
	// finishes and takes the container with it, which /init treats as a shutdown.
	Cmd       []string
	Env       map[string]string // configuration the boot needs to reach readiness
	Ready     string            // log line that appears once the supervised tree is up
	Forbidden []string          // log lines that must not appear during the boot
}

const (
	bootTimeout = 120 * time.Second // a cold first boot seeds config and syncs upstream's skills
	bootPoll    = 500 * time.Millisecond
	bootSettle  = 5 * time.Second // after readiness, prove it keeps running on its own
)

// RequireBoots starts the image under its own entrypoint and asserts the boot reaches Ready, is
// still running afterwards, never logged one of Forbidden, and ends up running as User's uid.
//
// It always boots with no-new-privileges, which is what a hardened pod does
// (allowPrivilegeEscalation: false, set alongside runAsNonRoot). Without it a setuid helper in the
// image can escalate and repair state the image should have shipped correctly - a boot that only
// survives that way crash-loops where it is actually deployed, so a test that permits it proves
// nothing.
func RequireBoots(t *testing.T, image string, boot BootConfig) testcontainers.Container {
	t.Helper()

	ctx := t.Context()
	uid := strings.SplitN(boot.User, ":", 2)[0]

	opts := []testcontainers.ContainerCustomizer{
		testcontainers.WithConfigModifier(func(config *container.Config) { config.User = boot.User }),
		testcontainers.WithHostConfigModifier(func(config *container.HostConfig) {
			config.SecurityOpt = []string{"no-new-privileges"}
		}),
	}
	if len(boot.Cmd) > 0 {
		opts = append(opts, testcontainers.WithCmd(boot.Cmd...))
	}
	if len(boot.Env) > 0 {
		opts = append(opts, testcontainers.WithEnv(boot.Env))
	}

	c := runContainer(t, ctx, image, opts...)

	// Readiness is polled out of the container's own log rather than expressed as a wait strategy:
	// s6 takes the whole container down when the boot dies, and that exit is what a caller needs
	// (the crash log), not a startup timeout two minutes later.
	var drained string
	deadline := time.Now().Add(bootTimeout)
	for {
		logs, err := c.Logs(ctx)
		require.NoError(t, err)
		raw, err := io.ReadAll(logs)
		logs.Close()
		require.NoError(t, err)
		drained = string(raw)
		if strings.Contains(drained, boot.Ready) {
			break
		}
		state, err := c.State(ctx)
		require.NoError(t, err)
		require.True(t, state.Running, "container stopped with exit code %d before the boot reached readiness, log:\n%s", state.ExitCode, drained)
		require.True(t, time.Now().Before(deadline), "boot never logged %q within %s, log:\n%s", boot.Ready, bootTimeout, drained)
		time.Sleep(bootPoll)
	}

	for _, forbidden := range boot.Forbidden {
		require.NotContains(t, drained, forbidden, "boot logged a line it must not")
	}

	require.Never(t, func() bool {
		state, err := c.State(ctx)
		require.NoError(t, err)
		return !state.Running
	}, bootSettle, 250*time.Millisecond, "container stopped on its own after boot")

	code, reader, err := c.Exec(ctx, []string{"/bin/sh", "-c", `id -u`}, tcexec.Multiplexed())
	require.NoError(t, err)
	output, err := io.ReadAll(reader)
	require.NoError(t, err)
	require.Equal(t, 0, code, "id -u should succeed, output: %s", output)
	require.Equal(t, uid, strings.TrimSpace(string(output)), "booted container should run as %s", boot.User)

	return c
}

// HTTPTestConfig holds the configuration for HTTP endpoint tests
type HTTPTestConfig struct {
	Port       string
	Path       string
	StatusCode int
	Timeout    time.Duration // optional startup timeout for the port and HTTP wait strategies (0 = library default)
}

// RequireHTTPEndpoint tests that an HTTP endpoint is accessible and returns the expected status code.
// It returns the running container so further checks can be run against it.
func RequireHTTPEndpoint(t *testing.T, image string, httpConfig HTTPTestConfig, containerConfig *ContainerConfig) testcontainers.Container {
	t.Helper()

	if httpConfig.Path == "" {
		httpConfig.Path = "/"
	}
	if httpConfig.StatusCode == 0 {
		httpConfig.StatusCode = 200
	}

	portStr := httpConfig.Port + "/tcp"

	portWait := wait.ForListeningPort(portStr)
	httpWait := wait.ForHTTP(httpConfig.Path).WithPort(portStr).WithStatusCodeMatcher(func(status int) bool {
		return status == httpConfig.StatusCode
	})
	deadline := 60 * time.Second
	if httpConfig.Timeout > 0 {
		portWait = portWait.WithStartupTimeout(httpConfig.Timeout)
		httpWait = httpWait.WithStartupTimeout(httpConfig.Timeout)
		deadline = max(httpConfig.Timeout, deadline)
	}

	opts := []testcontainers.ContainerCustomizer{
		testcontainers.WithExposedPorts(portStr),
		testcontainers.WithWaitStrategyAndDeadline(deadline, portWait, httpWait),
	}

	opts = append(opts, applyContainerConfig(containerConfig)...)

	return runContainer(t, t.Context(), image, opts...)
}

// RequireExecSucceeds runs a command inside an already running container and asserts it exits 0
func RequireExecSucceeds(t *testing.T, c testcontainers.Container, cmd ...string) {
	t.Helper()

	code, reader, err := c.Exec(t.Context(), cmd, tcexec.Multiplexed())
	require.NoError(t, err)
	output, err := io.ReadAll(reader)
	require.NoError(t, err)
	require.Equal(t, 0, code, "command %v should succeed, output: %s", cmd, output)
}

// RequireFileExists tests that a file exists in the image by inspecting its filesystem directly,
// without starting the container. Works for images with no shell or executables.
func RequireFileExists(t *testing.T, image string, filePath string) {
	t.Helper()

	ctx := t.Context()

	ctr, err := testcontainers.Run(ctx, image,
		testcontainers.WithNoStart(),
		testcontainers.WithCmd("/"),
		testcontainers.WithLogger(log.TestLogger(t)),
	)
	testcontainers.CleanupContainer(t, ctr)
	require.NoError(t, err)

	cli, err := testcontainers.NewDockerClientWithOpts(ctx)
	require.NoError(t, err)
	defer cli.Close()

	_, err = cli.ContainerStatPath(ctx, ctr.GetContainerID(), dockerclient.ContainerStatPathOptions{Path: filePath})
	require.NoError(t, err, "file %q should exist in image %q", filePath, image)
}

// RequireCommandSucceeds tests that a command runs successfully in the container (exit code 0)
func RequireCommandSucceeds(t *testing.T, image string, config *ContainerConfig, entrypoint string, args ...string) {
	t.Helper()

	opts := []testcontainers.ContainerCustomizer{
		testcontainers.WithEntrypoint(entrypoint),
		testcontainers.WithWaitStrategy(wait.ForExit()),
	}

	if len(args) > 0 {
		opts = append(opts, testcontainers.WithEntrypointArgs(args...))
	}

	opts = append(opts, applyContainerConfig(config)...)

	ctx := t.Context()
	container := runContainer(t, ctx, image, opts...)
	requireExitZero(t, ctx, container, fmt.Sprintf("command '%s %v' should succeed", entrypoint, args))
}
