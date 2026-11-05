package main

import (
	"testing"

	helpers "github.com/arsac/containers/tests"
)

func Test(t *testing.T) {
	image := helpers.GetTestImage("ghcr.io/arsac/ate-env-api:rolling")

	t.Run("api at the ko path", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/ko-app/ate-env-api")
	})
	t.Run("upstream license shipped", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/usr/share/doc/ate-env/LICENSE")
	})
	t.Run("api starts", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/ko-app/ate-env-api`, `-help`)
	})
}
