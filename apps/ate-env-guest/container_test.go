package main

import (
	"testing"

	helpers "github.com/arsac/containers/tests"
)

func Test(t *testing.T) {
	image := helpers.GetTestImage("ghcr.io/arsac/ate-env-guest:rolling")

	t.Run("guest at the ko path", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/ko-app/ate-env-guest")
	})
	t.Run("upstream license shipped", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/usr/share/doc/ate-env/LICENSE")
	})
	t.Run("guest starts", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/ko-app/ate-env-guest`, `-help`)
	})
	t.Run("guest is static", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, `! ldd /ko-app/ate-env-guest`)
	})
}
