package main

import (
	"testing"

	helpers "github.com/arsac/containers/tests"
)

func Test(t *testing.T) {
	image := helpers.GetTestImage("ghcr.io/arsac/llm-inference-bench:rolling")

	t.Run("bench script", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/bench/llm_decode_bench.py")
	})
	t.Run("lil-bench orchestrator", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/bench/lil_bench/standard.py")
	})
	t.Run("gsm8k dataset", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/bench/data/gsm8k_test.jsonl")
	})
	t.Run("mmlu-pro dataset", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/bench/data/mmlu_pro_1000.jsonl")
	})
	t.Run("gpqa diamond dataset", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/bench/data/gpqa_diamond.jsonl")
	})
	t.Run("dataset attribution record", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/bench/data/provenance.json")
	})
	t.Run("p2pmark fabric diagnostic", func(t *testing.T) {
		helpers.RequireFileExists(t, image, "/opt/bench/tools/p2pmark/llm_p2pmark")
	})
	t.Run("shipped code matches the pinned version", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `python`, `-c`, `import os, sys
sys.path.insert(0, "/opt/bench")
import llm_decode_bench as bench
want = os.environ["LLM_BENCH_VERSION"]
assert bench.VERSION == want, (bench.VERSION, want)
print(bench.VERSION)
`)
	})
	t.Run("benchmark dependencies import", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `python`, `-c`, `import httpx, rich, psutil, pynvml, requests, PIL; print('ok')`)
	})
	t.Run("accuracy profiles resolve offline", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `env`, `-i`, `PATH=/usr/local/bin:/usr/bin:/bin`, `HOME=/nonexistent`, `LLM_BENCH_CACHE_DIR=/proc/1/llm-bench-cache`, `python`, `-c`, `import sys
sys.path.insert(0, "/opt/bench")
import llm_decode_bench as bench
for name in ("gsm8k_test", "mmlu_pro_1000", "gpqa_diamond"):
    path, digest = bench.resolve_benchmark_dataset(name)
    assert path.startswith("/opt/bench/data/"), (name, path)
    print(name, digest[:12])
`)
	})
	t.Run("tool-eval-bench is baked at the pinned commit", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `env`, `-i`, `PATH=/usr/local/bin:/usr/bin:/bin`, `HOME=/nonexistent`, `LLM_BENCH_CACHE_DIR=/opt/bench/cache`, `python`, `-c`, `import sys
sys.path.insert(0, "/opt/bench")
import llm_decode_bench as bench
ref = bench.TOOL_EVAL_PINNED_REF
marker = bench.tool_eval_cache_root() / ref / "install.json"
assert marker.is_file(), str(marker)
install = bench.ensure_tool_eval_install(ref)
assert install["commit"] == ref, install
print("tool-eval-bench", install["version"])
`)
	})
	t.Run("entrypoint composes the bench command from the environment", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `bash`, `-c`, `env BENCH_DRY_RUN=1 BENCH_HOST=https://vllm:8000 \
    BENCH_MODEL=Qwen3.5/AWQ BENCH_API_KEY=sup3rsecret \
    BENCH_CONTEXTS=0,32k BENCH_TEST_PROFILE=gsm8k \
    BENCH_OUTPUT=/tmp/results.json \
    llm-inference-bench --concurrency 1,8 --display-mode live \
    | tr ' ' '\n' >/tmp/composed
cat >/tmp/expected <<'EXP'
running:
python
/opt/bench/llm_decode_bench.py
--display-mode
plain
--host
https://vllm:8000
--model
Qwen3.5/AWQ
--api-key
<redacted>
--contexts
0,32k
--test-profile
gsm8k
--output
/tmp/results.json
--concurrency
1,8
--display-mode
live
EXP
diff -u /tmp/expected /tmp/composed
`)
	})
	t.Run("entrypoint names results after the model and profile", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `bash`, `-c`, `env BENCH_DRY_RUN=1 BENCH_MODEL=Qwen3.5/AWQ \
    BENCH_TEST_PROFILE=gpqa-diamond BENCH_OUTPUT_DIR=/tmp/r \
    llm-inference-bench \
    | tr ' ' '\n' \
    | sed 's|.*/||' \
    | grep -qxE 'Qwen3\.5_AWQ-gpqa-diamond-[0-9]{8}T[0-9]{6}Z\.json'
`)
	})
	t.Run("entrypoint refuses an unwritable results directory", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `bash`, `-c`, `env BENCH_DRY_RUN=1 BENCH_OUTPUT_DIR=/proc/1/nope \
    llm-inference-bench 2>&1 | grep -q 'is not writable' &&
env BENCH_DRY_RUN=1 BENCH_OUTPUT_DIR=/proc/1/nope \
    llm-inference-bench 2>&1 | grep -q BENCH_OUTPUT_DIR &&
! env BENCH_DRY_RUN=1 BENCH_OUTPUT_DIR=/proc/1/nope \
    llm-inference-bench 2>/dev/null
`)
	})
	t.Run("entrypoint resumes into a stable per-experiment result name", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `bash`, `-c`, `env BENCH_DRY_RUN=1 BENCH_RESUME=1 BENCH_MODEL=Qwen3.5/AWQ \
    BENCH_TEST_PROFILE=gsm8k BENCH_OUTPUT_DIR=/tmp/r \
    llm-inference-bench --concurrency 1,2 --api-key=argvkeyA \
    | tr ' ' '\n' >/tmp/first &&
sleep 1 &&
env BENCH_DRY_RUN=1 BENCH_RESUME=1 BENCH_MODEL=Qwen3.5/AWQ \
    BENCH_TEST_PROFILE=gsm8k BENCH_OUTPUT_DIR=/tmp/r \
    llm-inference-bench --concurrency 1,2 --api-key=argvkeyA \
    | tr ' ' '\n' >/tmp/second &&
env BENCH_DRY_RUN=1 BENCH_RESUME=1 BENCH_MODEL=Qwen3.5/AWQ \
    BENCH_TEST_PROFILE=gsm8k BENCH_OUTPUT_DIR=/tmp/r \
    BENCH_API_KEY=envkeyB \
    llm-inference-bench --concurrency 1,2 --api-key argvkeyB \
    | tr ' ' '\n' >/tmp/rotated &&
env BENCH_DRY_RUN=1 BENCH_RESUME=1 BENCH_MODEL=Qwen3.5/AWQ \
    BENCH_TEST_PROFILE=gsm8k BENCH_OUTPUT_DIR=/tmp/r \
    llm-inference-bench --concurrency 4,8 --api-key=argvkeyA \
    | tr ' ' '\n' >/tmp/argv &&
env BENCH_DRY_RUN=1 BENCH_RESUME=1 BENCH_MODEL=Qwen3.5/AWQ \
    BENCH_TEST_PROFILE=gsm8k BENCH_OUTPUT_DIR=/tmp/r \
    BENCH_CONCURRENCY=4,8 \
    llm-inference-bench --concurrency 1,2 --api-key=argvkeyA \
    | tr ' ' '\n' >/tmp/env &&
diff -u /tmp/first /tmp/second &&
grep -qx -- --resume /tmp/first &&
grep '^/tmp/r/' /tmp/first >/tmp/first.path &&
grep '^/tmp/r/' /tmp/rotated >/tmp/rotated.path &&
grep '^/tmp/r/' /tmp/argv >/tmp/argv.path &&
grep '^/tmp/r/' /tmp/env >/tmp/env.path &&
cat /tmp/first.path /tmp/rotated.path /tmp/argv.path /tmp/env.path \
    | grep -cxE '/tmp/r/Qwen3\.5_AWQ-gsm8k-[0-9a-f]{8}\.json' | grep -qx 4 &&
cmp /tmp/first.path /tmp/rotated.path &&
! cmp -s /tmp/first.path /tmp/argv.path &&
! cmp -s /tmp/first.path /tmp/env.path &&
! cmp -s /tmp/argv.path /tmp/env.path &&
! grep -q -e argvkey -e envkey /tmp/first /tmp/rotated /tmp/argv /tmp/env
`)
	})
	t.Run("entrypoint lets argv choose the output path", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `bash`, `-c`, `! env BENCH_DRY_RUN=1 llm-inference-bench >/dev/null 2>&1 &&
env BENCH_DRY_RUN=1 llm-inference-bench --output /tmp/run.json \
    >/tmp/spaced 2>/tmp/spaced.err &&
env BENCH_DRY_RUN=1 llm-inference-bench --output=/tmp/run.json \
    >/tmp/joined 2>/tmp/joined.err &&
! grep -q results /tmp/spaced /tmp/spaced.err /tmp/joined /tmp/joined.err &&
tr ' ' '\n' </tmp/spaced | grep -cx -- --output | grep -qx 1 &&
tr ' ' '\n' </tmp/spaced | tail -n 1 | grep -qx /tmp/run.json &&
tr ' ' '\n' </tmp/joined | grep -c -- --output | grep -qx 1 &&
tr ' ' '\n' </tmp/joined | tail -n 1 | grep -qx -- --output=/tmp/run.json
`)
	})
	t.Run("entrypoint never logs a key passed through argv", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `bash`, `-c`, `env BENCH_DRY_RUN=1 BENCH_OUTPUT=/tmp/results.json \
    llm-inference-bench --api-key argvs3cret >/tmp/spaced 2>&1 &&
env BENCH_DRY_RUN=1 BENCH_OUTPUT=/tmp/results.json \
    llm-inference-bench --api-key=argvs3cret >/tmp/joined 2>&1 &&
env BENCH_DRY_RUN=1 BENCH_OUTPUT=/tmp/results.json BENCH_API_KEY=envkey \
    llm-inference-bench --api-key argvs3cret >/tmp/both 2>&1 &&
! grep -q -e argvs3cret -e envkey /tmp/spaced /tmp/joined /tmp/both &&
tr ' ' '\n' </tmp/spaced | tail -n 1 | grep -qx '<redacted>' &&
tr ' ' '\n' </tmp/joined | tail -n 1 | grep -qx -- '--api-key=<redacted>'
`)
	})
	t.Run("runs as 65534:65534", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, `[ "$(id -u):$(id -g)" = "65534:65534" ]`)
	})
	t.Run("starts in /opt/bench", func(t *testing.T) {
		helpers.RequireCommandSucceeds(t, image, nil, `/bin/sh`, `-c`, `[ "$PWD" = "/opt/bench" ]`)
	})
}
