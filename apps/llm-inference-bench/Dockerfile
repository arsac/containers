# syntax=docker/dockerfile:1

# renovate's docker manager resolves an ARG-interpolated FROM from this default,
# so the uv pin lives here and nowhere else (the same way subgen and cuda-ml
# own their CUDA_VERSION).
ARG UV_VERSION="0.13.1"

# Supplied by docker-bake.hcl, which carries the annotated upstream pin.
ARG VERSION

FROM ghcr.io/astral-sh/uv:${UV_VERSION} AS uv

FROM python:3.14.8-slim-bookworm

ARG VERSION

# A pinned copy must never offer to upgrade itself mid-experiment.
# LLM_BENCH_CACHE_DIR is where the baked tool-eval-bench venv lives; point it at
# a writable directory only when passing a --tool-eval-ref that is not the baked
# commit.
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    LLM_BENCH_NO_UPDATE_CHECK=1 \
    LLM_BENCH_CACHE_DIR=/opt/bench/cache \
    LLM_BENCH_VERSION=${VERSION#v}

# git: the bench resolves a --tool-eval-ref that names a branch or tag with
# `git ls-remote`, and pip needs git to install tool-eval-bench from GitHub.
# Without them only commit ids work as refs, which is the whole point of
# letting a job A/B an arbitrary tool-eval-bench revision.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

COPY --from=uv /uv /usr/local/bin/uv

# httpx, rich and psutil are upstream's stated install set; pynvml drives the
# live GPU panel, requests the CJK watchdog, and Pillow the --sched-soak-images
# vision requests. Versions deliberately follow upstream (the bench pins what
# matters for tool-eval-bench itself), so the image tag is the reproducibility
# handle for an experiment.
RUN uv pip install --system httpx rich psutil pynvml requests Pillow

WORKDIR /opt/bench

# Upstream source at the pinned tag. No sha256: GitHub's on-the-fly archive
# tarballs are not byte-stable, so integrity here is HTTPS plus the pinned
# release tag (the same approach every other app here uses).
ADD https://github.com/local-inference-lab/llm-inference-bench/archive/refs/tags/${VERSION}.tar.gz /tmp/bench.tgz
RUN tar -xz --strip-components=1 -f /tmp/bench.tgz \
    && rm -f /tmp/bench.tgz \
    && rm -rf tests .github screenshot.png

# Bake the pinned datasets next to the script. resolve_benchmark_dataset prefers
# a copy in <script dir>/data when it matches the pinned sha256, so GSM8K and
# MMLU-Pro (already in the tarball) simply short-circuit the download, and
# GPQA Diamond is built once here from the password-protected upstream zip
# rather than on the first job that asks for it. Everything goes through the
# bench's own resolver, so a dataset the tool would reject also fails the build.
# The digests land in the build log as provenance.
RUN python - <<'PY'
import json
import os
import shutil

import llm_decode_bench as bench

data_dir = os.path.join(os.path.dirname(os.path.abspath(bench.__file__)), "data")
provenance = []
for name in ("gsm8k_test", "mmlu_pro_1000", "gpqa_diamond"):
    path, digest = bench.resolve_benchmark_dataset(name)
    dest = os.path.join(data_dir, bench.BENCH_DATASETS[name]["filename"])
    if os.path.realpath(path) != os.path.realpath(dest):
        shutil.copyfile(path, dest)
    provenance.append({"name": name, "filename": bench.BENCH_DATASETS[name]["filename"],
                       "sha256": digest, "source": bench.BENCH_DATASETS[name].get("source", "")})
    print(f"baked dataset {name}: sha256={digest}", flush=True)

# All three redistributions are licensed (MIT, Apache-2.0, CC BY 4.0) and each
# asks for attribution, so the origin and pin travel with the copies.
with open(os.path.join(data_dir, "provenance.json"), "w", encoding="utf-8") as fh:
    json.dump({"datasets": provenance}, fh, indent=2)
    fh.write("\n")
PY

# tool-eval-bench's venv at the path ensure_tool_eval_install expects, built
# from the commit the bench itself pins, so --tool-eval runs with no network and
# still records the upstream commit in its JSON output. A runtime call reads
# install.json and returns before it would touch the cache directory, so this
# also survives a read-only root filesystem.
RUN python - <<'PY'
import llm_decode_bench as bench

install = bench.ensure_tool_eval_install(bench.TOOL_EVAL_PINNED_REF)
print(f"baked tool-eval-bench {install['version']} commit={install['commit']}", flush=True)
PY

COPY entrypoint.sh /usr/local/bin/llm-inference-bench

# Non-root nobody (repo convention). The image writes nothing at run time; a
# job's results go to the volume it mounts, normally at /results.
USER 65534:65534
ENTRYPOINT ["llm-inference-bench"]
