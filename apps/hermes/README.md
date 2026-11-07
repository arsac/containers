# hermes

[Hermes Agent](https://github.com/NousResearch/hermes-agent) on upstream's own image, with
three plugins installed at build time - the [Hindsight](https://hindsight.vectorize.io/sdks/integrations/hermes)
memory provider, the official Home Assistant platform plugin, and
[hermes_otel](https://briancaffey.github.io/hermes-otel/) for OpenTelemetry - and a
`1000:1000` runtime.

## Why this exists

Upstream publishes an image but no image with a memory backend, and the distribution cannot
stand in for it: `hermes-agent` stopped being published to PyPI at **0.19.0**, while these
plugins require **hermes >= 0.21.4 / >= 0.21.5**. So this is upstream's image plus three
kinds of addition, nothing rebuilt:

| Added at build time                          | Why                                                                         |
| -------------------------------------------- | --------------------------------------------------------------------------- |
| Plugin dependencies in `/opt/hermes/.venv`   | The plugins import them; the image venv is immutable at runtime.            |
| The three plugins, in `/opt/hermes/plugins/` | Installed at pinned refs, then moved into the bundled tree (see below).     |
| `hermes` remapped from `10000` to `1000`     | Lets upstream's entrypoint run unprivileged without remapping UIDs at boot. |

Nothing else is layered on top: same entrypoint, same supervision tree, same `/opt/hermes`.

## Plugins

| Plugin          | Installed at                      | Activation                                                  |
| --------------- | --------------------------------- | ----------------------------------------------------------- |
| `hindsight`     | `plugins/memory/hindsight`        | `memory.provider: hindsight` (see below)                    |
| `homeassistant` | `plugins/platforms/homeassistant` | already on: a bundled platform needs no allow-list entry    |
| `hermes_otel`   | `plugins/hermes_otel`             | `plugins.enabled: [hermes_otel]` - hooks are not default-on |

- **Home Assistant** ships the gateway platform adapter plus the `homeassistant` toolset
  (`ha_list_entities`, `ha_get_state`, `ha_list_services`, `ha_call_service`). The toolset
  registers with no configuration; the manifest's `HASS_TOKEN` (required) and `HASS_URL`
  (optional) environment variables are what it needs to reach an instance.
- **hermes_otel** is hook-based, so it stays inert until the deployment names it in
  `plugins.enabled`. With no OTLP backend configured it runs live-only and sends nothing;
  shaping lives in `$HERMES_HOME/hermes_otel.yaml`, backends in `OTEL_*` variables or a
  `backends:` list.
- **hindsight** is selected by `memory.provider`; `hermes plugins list` does not even show
  memory providers, since they are exclusive plugins rather than toggleable ones.

## Where the plugins live, and why

Hermes discovers plugins in the bundled `<install>/plugins/` tree or in
`$HERMES_HOME/plugins/`. This image uses the **bundled** tree, and places each plugin where
its kind is discovered:

- `plugins/memory/<name>` for a memory provider, `plugins/platforms/<name>` for a platform,
  a plain `plugins/<name>` for a hook plugin;
- it survives a pod that mounts a volume over `/opt/data` (`$HERMES_HOME`'s default), which
  would hide anything baked into the user tree;
- it needs no start-time copy or symlink into the runtime home, so the deployment stays a
  plain `Deployment` with no init container or command wrapper;
- it stays inside the root-owned `/opt/hermes` tree, so the agent cannot rewrite its own
  plugins.

Evidence, from a container running as `1000:1000` with only `memory.provider: hindsight`,
`HINDSIGHT_API_KEY` and `HINDSIGHT_API_URL` set:

```
$ hermes memory status
Memory status
────────────────────────────────────────
  Built-in (MEMORY.md / USER.md):
    Memory injection:   enabled ✓
    User profile:       enabled ✓
    Memory tool:        enabled ✓
  Provider:  hindsight

  Plugin:    installed ✓
  Status:    available ✓

  Installed plugins:
    • byterover  (API key / local)
    • hindsight  (API key / local) ← active
    • retaindb  (API key / local)
```

For the other two, `hermes plugins list` reports `homeassistant ... enabled` and
`hermes_otel ... not enabled` until the config names it, `hermes tools list` shows the
`homeassistant` toolset, and `hermes plugins doctor /opt/hermes/plugins/hermes_otel` reports
"runtime discovery, manifest parsing, import, and registration passed" with 34 hooks.
`apps/hermes/container_test.go` asserts all of that.

## Installing plugins at runtime

The dashboard has a Plugins hub and the CLI has the same installer, so a user can add a plugin to
the running container. That works, unprivileged, and it never touches the image:

| What                | Where it goes                                                                                                                         |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Plugin tree         | `$HERMES_HOME/plugins/<name>` (the volume, e.g. `/opt/data/plugins/anki`)                                                             |
| Selection           | `plugins.enabled` in `$HERMES_HOME/config.yaml`                                                                                       |
| Python dependencies | a package-manager generation under `$HERMES_HOME/installs/<hash>/environments/<hash>` - never `/opt/hermes/.venv`, which is read-only |

Dependencies still import: verified in the base image with the packages genuinely absent from the
venv, where a runtime install of `hermes_otel` resolved into a generation and then registered all
34 of its hooks.

Two consequences worth knowing:

- **A runtime copy of a name this image pins wins over the bundled one.** Installing
  `hermes_otel` 1.18.2 into the volume and selecting it makes the image's pinned 1.32.5 lose:
  `hermes plugins list` then shows `git / 1.18.2`, and 15 hooks load instead of 34. Memory
  providers are the exception - their discovery prefers the bundled copy, so a runtime `hindsight`
  would not take. Anything installed this way is outside the image's pins, its `requires_hermes`
  sweep and its tests, and it disappears with the volume; changing the plugin set belongs in a PR
  against the pins instead.
- **It can be forbidden** by mounting `$HERMES_HOME/plugins` read-only. Attempts then fail with
  `OSError: [Errno 30] Read-only file system` and nothing is written (a traceback rather than a
  friendly message, since that path is not upstream's expected state).

## Hindsight settings

Activation is **not** `hermes plugins enable`. A memory provider is selected by config, one
at a time:

```yaml
# $HERMES_HOME/config.yaml
memory:
  provider: hindsight
```

The provider reads its own settings from `$HERMES_HOME/hindsight/config.json`, else the
environment:

| Env var             | Notes                                                                                                                                                                  |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `HINDSIGHT_MODE`    | `cloud` (default), `local_external` (a Hindsight server you run), or `local_embedded` (not supported in this image, see below).                                        |
| `HINDSIGHT_API_URL` | API base URL. Defaults to `https://api.hindsight.vectorize.io` in cloud mode and `http://localhost:8888` in `local_external`, so a self-hosted deployment must set it. |
| `HINDSIGHT_API_KEY` | Required in cloud mode, optional in `local_external`, sent when set.                                                                                                   |

`local_external` is the mode for pointing at your own Hindsight: it needs nothing beyond the
client this image already installs, and `hermes memory status` reports it available with only
a URL.

`local_embedded` is the one mode this image **cannot** run: it needs `hindsight-embed` and a
Hindsight server process started inside the container (downloaded on first use, plus an LLM
key and a writable home), which is deliberately not installed. Asked for it, the provider
reports itself unavailable instead of failing every turn. The dashboard still offers the mode
as a choice; picking it there lands on the same refusal. Supported modes are `cloud` and
`local_external`. Everything else in `HERMES_HOME` the
deployment normally sets (model provider keys, gateway settings) is untouched by this image.

## Runtime

- **User `1000:1000`.** The group and user `hermes` are remapped from upstream's `10000` at
  build time, because upstream's entrypoint rejects a `--user` UID that is not its own
  account's. Do not override the user with a different UID.
- **Run as `1000:1000` with `fsGroup: 1000`, and chown an inherited volume once.** A volume
  first populated by upstream's image carries `10000` uids. `fsGroup` only ever fixes the
  _group_, so those files end up `10000:1000` and the gateway cannot write `state.db` or
  `auth.json` - which presents as a crash loop rather than as a permission error. One
  `chown -R 1000:1000` on the volume settles it; a fresh volume needs nothing, and the image
  never chowns `/opt/data` itself.
- **`HERMES_HOME=/opt/data`, pointing at that volume.** The plugins live in the bundled tree
  under `/opt/hermes`; config, secrets, sessions and `state.db` live on the volume. Pointing
  `HERMES_HOME` anywhere else detaches the state from the deployment.
- **`/opt/hermes` stays root-owned and read-only**, which is upstream's immutability
  property: the agent cannot modify its installed source, venv, or plugins.
- **Supervision is upstream's.** The image inherits upstream's `s6-overlay` tree (gateway,
  dashboard, profile gateways) behind `/opt/hermes/docker/entrypoint-dispatch.sh`; it is
  not restructured here, and services log to stdout as upstream ships them.
- Starting unprivileged skips the root-only parts of upstream's boot hook. Those print
  warnings (`could not chown XDG_RUNTIME_DIR`, `dependency refresh failed; continuing`)
  and the boot still exits 0 - nothing this image needs depends on them.
- **On-demand dependency installation is off.** `HERMES_DISABLE_LAZY_INSTALLS=1` is the
  image-level bridge `pm` reads, set here for the same reason upstream's image sets it for its
  children: an implicit install (a plugin's packages, a skill's extras) is refused with "not
  installed and lazy installs are disabled", pointing at `security.allow_lazy_installs` /
  `hermes pm install`. Dependencies arrive at build time; `container_test.go` asserts the flag
  is in force. It does not silence the boot's `dependency refresh failed; continuing`: that is
  `s6-setuidgid hermes` failing to set supplementary groups when the hook already runs as
  `1000` (as root it logs `[stage2] dependency environment: base` instead), and it installs
  nothing either way.
- Hermes also prints `install out of sync (venv: out of sync with uv.lock)` before command
  output. That is its stamp check comparing the venv against upstream's `uv.lock`, which no
  longer describes a venv this image added plugin dependencies to. It is a diagnostic, not an
  error, and it does not appear in the base image.

## Pins

| Pin                             | Where                      | Tracked by                       |
| ------------------------------- | -------------------------- | -------------------------------- |
| `nousresearch/hermes-agent` tag | `VERSION`                  | Renovate (`datasource=docker`)   |
| `hindsight-client` version      | `HINDSIGHT_CLIENT_VERSION` | Renovate (`datasource=pypi`)     |
| `hindsight` plugin commit       | `HINDSIGHT_REF`            | Renovate (`datasource=git-refs`) |
| `hermes_otel` plugin commit     | `HERMES_OTEL_REF`          | Renovate (`datasource=git-refs`) |
| `homeassistant` plugin commit   | `HOMEASSISTANT_REF`        | Renovate (`datasource=git-refs`) |

Every plugin pin is a **commit**, which is what `hermes plugins install --ref` takes, so the
build resolves nothing over the network: what the file says is what installs. Each annotation
carries the release ref the commit came from (`currentValue`), which is what Renovate follows -
`git-refs` proposes the next ref **and** its commit in one line edit - and the `versioning`
regex keeps `integrations/hermes/vX.Y.Z` / `hermes-otel-vX.Y.Z` releases apart from the repos'
other tags.

Two wrinkles worth knowing:

- `vectorize-io/hindsight` tags with **annotated** tags, so `git-refs` tracks the tag object
  (`c6f7a651…`), not the commit it closes over (`f14cc1eb…`, the one the base image's plugin
  catalog pins for the same release). Both denote 1.2.4 and both install it; the difference is
  only what a reviewer diffing against upstream's catalog will see.
- `NousResearch/hermes-official-plugins` has **no tags and no releases**, so its pin follows
  `main` and Renovate proposes a commit per merge there: a `digest` update, which this repo's
  rules hold for review. Expect a PR per merge upstream if you want to stay current;
  everything else here automerges.

Three things make unattended bumps safe rather than hopeful:

- **A tag pin is a release ref, never a branch head**, and `main` is the only branch followed:
  the `versioning` regex only ever proposes integration/plugin releases.
- **A release can outrun the installer as well as the hermes version**: manifests carry a
  `manifest_version` (this image supports v2) and `hermes plugins install` refuses a newer one
  outright, so such a release fails the build instead of installing half a plugin. Other hermes
  images are pinned to old plugin commits for exactly that reason.
- **The container tests check each plugin's `requires_hermes` against the base image's version,
  and every declared requirement against what the image installed.** A plugin release that
  outruns the base image, needs a newer client, or introduces a dependency we do not install
  fails the build instead of shipping something that errors on load.

`hindsight-client` is pinned inside the plugin's declared window, currently `>=0.10.1,<2`.
The floor is not cosmetic: 0.10.0's probe ran `asyncio.run` on the caller's thread, so the
next client call failed against a dead aiohttp session. `hermes_otel`'s OpenTelemetry
packages are installed from the plugin's own declared ranges, which travel with the pinned
commit, and the venv's existing pins are passed to uv as **constraints**: a range that would
upgrade or downgrade anything Hermes already pinned is refused by the resolver, naming both
conflicting requirements, before the venv is touched.

## What is checked, and where

The build checks what only a build can: that each plugin lands where its kind is discovered,
under the manifest name/kind it should have.

Whether a plugin still **loads** is asserted by `apps/hermes/container_test.go` against the built
image: `requires_hermes` against the hermes version this image reports - swept over every bundled
manifest, so there is no list of names to keep in step with the Dockerfile - plus the plugins'
imports, hook/tool registration, provider availability, and that the venv refuses on-demand
installations. That split is deliberate - the release
workflow runs those tests before it publishes anything (this app has no Forgejo target, and the
GitHub build loads the image and runs `go test` whenever a `container_test.go` exists), so a
published image cannot be one that failed to load. A laptop build that skips the tests can be, and
that is the accepted trade for keeping the logic in the test file rather than in the Dockerfile.

The manifest-wide dependency sweep that started life in the build is gone for the same reason it
was never enough on its own: every dependency that matters at load is imported by one of the
subtests, and the install itself is pinned by constraints (see above), so a second expression of
it was just another thing to keep true.

## Local development

```sh
mise run local-build hermes   # build for the native arch, then run the testcontainers test
```

`TEST_IMAGE` overrides the image under test, as in every app here.

## Licensing

No upstream source is vendored: the image is a `FROM` plus packages installed from upstream
refs. Hermes Agent and each plugin carry their own licenses.
