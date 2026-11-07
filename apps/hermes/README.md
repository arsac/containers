# hermes

[Hermes Agent](https://github.com/NousResearch/hermes-agent) on upstream's own image,
with the [Hindsight](https://hindsight.vectorize.io/sdks/integrations/hermes) memory
provider installed at build time and a `1000:1000` runtime.

## Why this exists

Upstream publishes an image but no image with a memory backend, and the distribution
cannot stand in for it: `hermes-agent` stopped being published to PyPI at **0.19.0**, while
the Hindsight plugin requires **hermes >= 0.21.4**. So this is upstream's image plus three
additions, nothing rebuilt:

| Added at build time                                   | Why                                                                                  |
| ----------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `hindsight-client` in `/opt/hermes/.venv`             | The plugin imports it for cloud mode; the image venv is immutable at runtime.        |
| The plugin, at `/opt/hermes/plugins/memory/hindsight` | Installed from its release tag, then moved into the bundled memory tree (see below). |
| `hermes` remapped from `10000` to `1000`              | Lets upstream's entrypoint run unprivileged without remapping UIDs at boot.          |

Nothing else is layered on top: same entrypoint, same supervision tree, same `/opt/hermes`.

## Where the plugin lives, and why

Hermes discovers a memory provider in exactly two places: the bundled
`<install>/plugins/memory/<name>` and the user `$HERMES_HOME/plugins/<name>`. This image
uses the **bundled** one:

- it survives a pod that mounts a volume over `/opt/data` (`$HERMES_HOME`'s default), which
  would hide a plugin baked into the user tree;
- it needs no start-time copy or symlink into the runtime home, so the deployment stays a
  plain `Deployment` with no init container or command wrapper;
- it stays inside the root-owned `/opt/hermes` tree, so the agent cannot rewrite its own
  memory backend.

Evidence, from a container running as `1000:1000` with only
`memory.provider: hindsight`, `HINDSIGHT_API_KEY` and `HINDSIGHT_API_URL` set:

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

`hermes plugins list` does **not** show it: memory providers are exclusive plugins, not
toggleable ones, and are listed by `hermes memory status` instead. `apps/hermes/container_test.go`
asserts that the provider is active and available in this image.

## Activation

Activation is **not** `hermes plugins enable`. A memory provider is selected by config,
one at a time:

```yaml
# $HERMES_HOME/config.yaml
memory:
  provider: hindsight
```

The provider reads its own settings from `$HERMES_HOME/hindsight/config.json`, else the
environment:

| Env var             | Notes                                                                                       |
| ------------------- | ------------------------------------------------------------------------------------------- |
| `HINDSIGHT_API_URL` | Hindsight API base URL (default `https://api.hindsight.vectorize.io`).                      |
| `HINDSIGHT_API_KEY` | Required in cloud mode; `hermes memory status` reports the provider unavailable without it. |
| `HINDSIGHT_MODE`    | `cloud` (default), `local_external`, or `local_embedded`.                                   |

`local_embedded` is **not** supported by this image: it needs `hindsight-embed`, which is
deliberately not installed. Everything else in `HERMES_HOME` the deployment normally sets
(model provider keys, gateway settings) is untouched by this image.

## Runtime

- **User `1000:1000`.** The group and user `hermes` are remapped from upstream's `10000` at
  build time, because upstream's entrypoint rejects a `--user` UID that is not its own
  account's. Do not override the user with a different UID.
- **`/opt/data` is a volume and its ownership is the cluster's business.** The image does
  not chown it at start and does not depend on owning it: mount it with an `fsGroup` that
  can write, and the upstream bootstrap (config seeding, skills sync) runs as `1000`.
- **`/opt/hermes` stays root-owned and read-only**, which is upstream's immutability
  property: the agent cannot modify its installed source, venv, or plugins.
- **Supervision is upstream's.** The image inherits upstream's `s6-overlay` tree (gateway,
  dashboard, profile gateways) behind `/opt/hermes/docker/entrypoint-dispatch.sh`; it is
  not restructured here, and services log to stdout as upstream ships them.
- Starting unprivileged skips the root-only parts of upstream's boot hook. Those print
  warnings (`could not chown XDG_RUNTIME_DIR`, `dependency refresh failed; continuing`)
  and the boot still exits 0 - nothing this image needs depends on them.

## Pins

| Pin                             | Where                                        | Tracked by                          |
| ------------------------------- | -------------------------------------------- | ----------------------------------- |
| `nousresearch/hermes-agent` tag | `docker-bake.hcl` `VERSION`                  | Renovate (`datasource=docker`)      |
| `hindsight-client` version      | `docker-bake.hcl` `HINDSIGHT_CLIENT_VERSION` | Renovate (`datasource=pypi`)        |
| Plugin release tag              | `docker-bake.hcl` `HINDSIGHT_TAG`            | Renovate (`datasource=github-tags`) |

All three are automergeable: a plugin or client release arrives as a PR and ships on green
CI. That is deliberate - the plugin is versioned and tagged on its own cadence
(`integrations/hermes/vX.Y.Z`, independently of the base image and of the client), so
pinning it to a commit would only put a human with a git client in the loop.

Two things make those unattended bumps safe rather than hopeful:

- **The tag is the plugin's release ref**, not a branch head: the `versioning` regex only
  ever proposes `integrations/hermes/vX.Y.Z`. `hermes plugins install --ref` accepts only a
  full commit SHA, so the Dockerfile resolves the tag to its commit (`git ls-remote`, peeled
  tag line), installs by that SHA, prints it in the build log for provenance, and asserts
  the installed `plugin.yaml` carries the tag's version. The base image's tag is resolved at
  build time under the same trust.
- **The build checks the plugin's declared requirements against what the image installed**
  (`hindsight-client`, plus `hindsight-embed` as the known-optional local_embedded one), so
  a release that needs a newer client - or a new dependency we do not install - fails the
  build instead of shipping a provider that errors at runtime.

`hindsight-client` is pinned inside the plugin's declared window, currently `>=0.10.1,<2`.
The floor is not cosmetic: 0.10.0's probe ran `asyncio.run` on the caller's thread, so the
next client call failed against a dead aiohttp session.

## Build-time assertions

The Dockerfile fails the build if the client does not import, if the plugin is not where
discovery scans, or if the plugin's declared requirements are not satisfied by what the
image installed; it is not possible to publish an image that quietly has no memory backend,
or one whose provider would fail on its first call.

## Local development

```sh
mise run local-build hermes   # build for the native arch, then run the testcontainers test
```

`TEST_IMAGE` overrides the image under test, as in every app here.

## Licensing

No upstream source is vendored: the image is a `FROM` plus packages installed from
upstream's own catalog pin. Hermes Agent and the Hindsight plugin carry their own licenses.
