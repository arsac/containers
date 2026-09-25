# gnhf

[gnhf](https://github.com/kunchenguid/gnhf) runs a coding agent in a loop:

```
build prompt (inject notes.md) -> invoke agent -> success?
  |- yes -> git commit + append notes.md
  |- no  -> git reset --hard;  3 consecutive failures -> abort
```

It ships **no model backend** and shells out to an agent CLI, so this image is
gnhf plus one agent plus the git it depends on.

## Why this exists

Upstream publishes no container, and neither does anyone else - across 280+
forks there is not one Dockerfile, and no `gnhf docker` or `gnhf kubernetes`
usage in public code. The only prior art is a personal dev sandbox pinned to
Claude Code and vendor auth. This image exists to run gnhf **unattended against
a self-hosted model**, which is the case nobody had packaged.

## Contents

| Tool | Why |
|---|---|
| `gnhf` | the loop |
| `opencode` | the agent. Provider-agnostic: takes a plain OpenAI-compatible base URL, so it needs no vendor sign-in to point at a local model |
| `no-mistakes` | pre-push validation pipeline; gnhf's own repo uses it and its summary suggests it for reviewing a night's output |
| `treehouse` | worktree manager. Note gnhf has a built-in `--worktree` mode, so this may be redundant - included because it was asked for, not because gnhf requires it |
| `git` | not optional. The loop *is* commit-and-reset |

`acpx` (the ACP runtime) is vendored into gnhf's `dist/cli.mjs` bundle, so it
is present but deliberately not on `PATH`.

## Pointing it at a self-hosted model

OpenCode reads a project-local `opencode.json`, so the model choice lives with
the repo rather than in the image:

```json
{
  "provider": {
    "litellm": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "https://<your-litellm>/v1",
        "apiKey": "{env:LITELLM_KEY}"
      },
      "models": { "chat": {} }
    }
  },
  "model": "litellm/chat"
}
```

Verified end to end against a self-hosted DeepSeek-V4-Flash behind LiteLLM:
one bounded iteration read the repo, edited a file with its own tools, and
committed the result on a `gnhf/` branch with `notes.md` written.

## ⚠ Mount the parent, not the repo

`--worktree` creates directories **as a sibling of the repo**:

```
<repo>-gnhf-worktrees/
  |- <run-slug-1>/
  |- <run-slug-2>/
```

Mounting only the repo makes worktree mode fail or write outside the volume.
Mount the directory *containing* the repo at `/workspace`.

Persistence is not optional either: worktrees **with commits are preserved**
for review, re-running a prompt resumes a matching worktree, and
`.gnhf/runs/<runId>/` holds the prompts, logs and `notes.md` that carry context
between iterations. An `emptyDir` discards exactly the output you ran it for.

## Bounding an unattended run

This is an autonomous agent with write access to a repo. Always bound it:

- `--max-iterations <n>` - hard iteration cap
- `--max-tokens <n>` - abort on total input+output tokens. Expect this to
  matter: one *trivial* one-line change cost ~259K input tokens, because the
  agent re-sends context every turn
- `--stop-when <condition>` - end when the agent reports a condition

gnhf aborts on its own after three consecutive failures and backs off on rate
limits. On Kubernetes, pair those with `activeDeadlineSeconds`,
`backoffLimit: 0` (never silently re-run an autonomous loop) and
`concurrencyPolicy: Forbid`.

## Credentials

Three separate things, none baked into the image:

1. the model API key, via the agent's provider config
2. git push credentials, if using `--push` (push failure aborts the run)
3. a git identity (`user.name` / `user.email`) for the commits
