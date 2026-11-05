package main

import (
	"testing"

	helpers "github.com/arsac/containers/tests"
)

func Test(t *testing.T) {
	image := helpers.GetTestImage("ghcr.io/arsac/honcho-mcp:rolling")

	t.Run("upstream entry present", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/app/src/http.ts")
	})
	t.Run("upstream lock shipped", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/app/bun.lock")
	})
	t.Run("frozen dependency install", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/app/node_modules/@honcho-ai/sdk")
	})
	t.Run("import graph resolves", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `bun`, `build`, `src/http.ts`, `--target`, `node`, `--outfile`, `/tmp/smoke.mjs`)
	})
	t.Run("runs as 65534:65534", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, `[ "$(id -u):$(id -g)" = "65534:65534" ]`)
	})
	t.Run("starts in /app", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, `[ "$PWD" = "/app" ]`)
	})
}
