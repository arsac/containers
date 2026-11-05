# AGENTS.md: containers

Guidance for AI coding agents (and humans) writing Go in this repository.
There's no application code here: Go exists solely to test the container
images this repo builds, via `testcontainers-go`. There's no `main.go`, no
config to load, no CLI, no server; everything below is specific to this
repo's own shape.

## Layout

One `apps/<name>/container_test.go` per image, `package main`, testing the
image built from `apps/<name>/`. Shared helpers live in `tests/helpers.go`
(package `helpers`): check that file for what's already available (things
like `RequireCommandSucceeds`, `RequireHTTPEndpoint`, `RequireFileExists`
as of this writing) before hand-rolling container lifecycle code in an
individual `container_test.go`. Add a new capability to `helpers` instead;
that's the DRY boundary in this repo.

## Conventions

- `testify/require`, not `assert`: a failed image test should stop
  immediately rather than cascade into a second, confusing failure.
- Every helper takes `t *testing.T` first, calls `t.Helper()`, and
  registers cleanup via `testcontainers.CleanupContainer(t, c)`; never leak
  a container past the test.
- `TEST_IMAGE` overrides the default image under test
  (`helpers.GetTestImage`), so a local build task can point tests at a
  just-built image instead of the published tag; check `mise tasks` for the
  actual task name.
- Idempotent and side-effect-free: a test only asserts against the image
  under test (command exit code, HTTP response, file presence in the
  filesystem) and never depends on or mutates state from another test.
- Still idiomatic Go where it applies: `go vet`-clean, no unchecked errors
  outside the established `require.NoError` pattern, table-driven subtests
  (`t.Run`) if a single app's test grows multiple cases.
- `gofmt -s` runs via the lefthook config (`.lefthook.toml`) on every
  staged `.go` file; check `.github/workflows/` for whatever else
  CI enforces (e.g. `go vet`) before assuming lefthook's formatting pass is
  the only gate.

## Running

Run `mise tasks` for the actual local build+test task name and invocation;
don't assume it matches another repo's, and don't assume CI selects which
apps to build from `.github/labeler.yaml`, that file drives PR labels only.
Check `.github/workflows/` for the step that actually selects changed apps.
