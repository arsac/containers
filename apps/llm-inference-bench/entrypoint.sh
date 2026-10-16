#!/usr/bin/env bash
# Job entrypoint for the llm-inference-bench image.
#
# Composes the bench command line from environment variables and appends argv,
# so a Kubernetes Job declares an experiment declaratively and still has an
# escape hatch: argparse keeps the last occurrence of a flag, which means every
# flag below can be overridden by passing it again in `command:`.
#
#   BENCH_HOST           --host    (accepts a full URL, e.g. https://vllm:8000)
#   BENCH_MODEL          --model
#   BENCH_API_KEY        --api-key (Bearer token; from a secretKeyRef)
#   BENCH_CONCURRENCY    --concurrency   e.g. "1,2,4,8"
#   BENCH_CONTEXTS       --contexts      e.g. "0,16k,32k,128k"
#   BENCH_DURATION       --duration      seconds per decode cell
#   BENCH_MAX_TOKENS     --max-tokens
#   BENCH_TEST_PROFILE   --test-profile  e.g. gsm8k, mmlu-pro, gpqa-diamond
#   BENCH_SCHEDULER      --scheduler     e.g. all, or arrivals,short-under-long
#   BENCH_RESUME         1 -> --resume, continue the checkpoint beside --output;
#                        the generated name swaps its timestamp for a digest of
#                        the experiment (env flags plus argv, never the API
#                        key), so a retried pod finds its own checkpoint even
#                        after a key rotation and different experiments never
#                        share one
#   BENCH_OUTPUT         --output verbatim; wins over BENCH_OUTPUT_DIR
#   BENCH_OUTPUT_DIR     directory for the generated result name (default /results);
#                        unused when argv carries its own --output
#   BENCH_DRY_RUN        1 -> print the composed command and exit 0
#
# Display defaults to plain: the Rich alternate-screen TUI has nothing to draw
# into a log collector. Override with BENCH_DISPLAY_MODE=screen|live when
# attaching to an interactive pod.

set -euo pipefail

# Prints the given tokens NUL-separated with every API key value replaced, in
# both the --api-key VALUE and --api-key=VALUE spellings.
redact() {
    local redact_next=0 token
    for token in "$@"; do
        if ((redact_next)); then
            token="<redacted>"
            redact_next=0
        elif [ "$token" = "--api-key" ]; then
            redact_next=1
        elif [[ "$token" == --api-key=* ]]; then
            token="--api-key=<redacted>"
        elif [[ -n "${BENCH_API_KEY:-}" ]] && [ "$token" = "$BENCH_API_KEY" ]; then
            token="<redacted>"
        fi
        printf '%s\0' "$token"
    done
}

args=(--display-mode "${BENCH_DISPLAY_MODE:-plain}")

[[ -n "${BENCH_HOST:-}" ]] && args+=(--host "$BENCH_HOST")
[[ -n "${BENCH_MODEL:-}" ]] && args+=(--model "$BENCH_MODEL")
[[ -n "${BENCH_API_KEY:-}" ]] && args+=(--api-key "$BENCH_API_KEY")
[[ -n "${BENCH_CONCURRENCY:-}" ]] && args+=(--concurrency "$BENCH_CONCURRENCY")
[[ -n "${BENCH_CONTEXTS:-}" ]] && args+=(--contexts "$BENCH_CONTEXTS")
[[ -n "${BENCH_DURATION:-}" ]] && args+=(--duration "$BENCH_DURATION")
[[ -n "${BENCH_MAX_TOKENS:-}" ]] && args+=(--max-tokens "$BENCH_MAX_TOKENS")
[[ -n "${BENCH_TEST_PROFILE:-}" ]] && args+=(--test-profile "$BENCH_TEST_PROFILE")
[[ -n "${BENCH_SCHEDULER:-}" ]] && args+=(--scheduler "$BENCH_SCHEDULER")
[[ "${BENCH_RESUME:-}" == "1" ]] && args+=(--resume)

argv_output=0
for arg in "$@"; do
    case "$arg" in
        --output | --output=*) argv_output=1 ;;
    esac
done

# Results must land on storage the job mounts, or they die with the pod.
if [[ -n "${BENCH_OUTPUT:-}" ]]; then
    args+=(--output "$BENCH_OUTPUT")
elif ((!argv_output)); then
    output_dir="${BENCH_OUTPUT_DIR:-/results}"
    if ! mkdir -p "$output_dir" 2>/dev/null || [[ ! -w "$output_dir" ]]; then
        echo "ERROR: ${output_dir} is not writable." >&2
        echo "Fix: mount a volume at ${output_dir}, or set BENCH_OUTPUT_DIR to a writable path." >&2
        exit 1
    fi
    label="${BENCH_MODEL:-bench}"
    label="${label//[^A-Za-z0-9._-]/_}"
    if [[ -n "${BENCH_TEST_PROFILE:-}" ]]; then
        label+="-${BENCH_TEST_PROFILE}"
    elif [[ -n "${BENCH_SCHEDULER:-}" ]]; then
        label+="-scheduler"
    fi
    if [[ "${BENCH_RESUME:-}" == "1" ]]; then
        label+="-$(redact "${args[@]}" "$@" \
            | grep -zvxE -- '--api-key(=<redacted>)?|<redacted>' \
            | sha256sum | cut -c1-8)"
    else
        label+="-$(date -u +%Y%m%dT%H%M%SZ)"
    fi
    args+=(--output "${output_dir}/${label}.json")
fi

# Log the exact experiment for the job record. The credential stays out of it:
# the bench records structured metadata rather than argv, so this line is the
# only place the invocation survives, and the key must not survive with it.
cmd=(python /opt/bench/llm_decode_bench.py "${args[@]}" "$@")
printf 'running:'
while IFS= read -r -d '' token; do
    printf ' %s' "$token"
done < <(redact "${cmd[@]}")
printf '\n'

if [[ "${BENCH_DRY_RUN:-}" == "1" ]]; then
    exit 0
fi

exec "${cmd[@]}"
