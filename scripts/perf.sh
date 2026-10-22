#!/usr/bin/env bash
# Profile the already packaged app. Only header clicks and pointer movement are posted.
# --static: only the two stationary scenarios, with no pointer events at all; the notch is
# expanded through the app's test hook and a sample is retried if the user moves the pointer.
# The hook is opt-in (PERCH_TEST_HOOKS=1), so --static launches its own app instance.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."
static_only=0
case "${1:-}" in
    "") ;;
    --static) static_only=1 ;;
    *) echo "usage: scripts/perf.sh [--static]" >&2; exit 64 ;;
esac

app_binary="$PWD/dist/Herdr Perch.app/Contents/MacOS/PerchApp"
[[ -x "$app_binary" ]] || { echo "Package the app with scripts/bundle.sh first" >&2; exit 1; }
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/perch-perf.XXXXXX")"
driver="$tmp_dir/PointerDriver"
app_pid=""
move_pid=""
still_pid=""
owned=0
failures=0
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    if [[ -n "$move_pid" ]]; then
        kill -TERM "$move_pid" 2>/dev/null
        wait "$move_pid" 2>/dev/null
    fi
    if [[ -n "$still_pid" ]]; then
        kill -TERM "$still_pid" 2>/dev/null
        wait "$still_pid" 2>/dev/null
    fi
    if [[ -x "$driver" && "$static_only" -eq 1 ]]; then
        [[ -n "$app_pid" ]] && "$driver" post collapse
    elif [[ -x "$driver" ]]; then
        if [[ -n "$app_pid" ]]; then
            "$driver" collapse "$app_pid"
            if [[ $? -ne 0 && "$status" -eq 0 ]]; then status=1; fi
        fi
        "$driver" park
        if [[ $? -ne 0 && "$status" -eq 0 ]]; then status=1; fi
    fi
    if [[ "$owned" -eq 1 ]]; then
        kill -TERM "$app_pid" 2>/dev/null
        for ((attempt = 0; attempt < 20; attempt++)); do
            kill -0 "$app_pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$app_pid" 2>/dev/null
        wait "$app_pid" 2>/dev/null
    fi
    rm -rf "$tmp_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

swiftc -O -module-cache-path "$tmp_dir/module-cache" Tests/Support/PointerDriver.swift -o "$driver"
app_pid="$("$driver" pid "$app_binary")"
# A running instance can't be told whether it has the test hooks, so static mode never reuses one.
if [[ -n "$app_pid" && "$static_only" -eq 1 ]]; then
    app_pid=""
    echo "--static needs its own app instance with PERCH_TEST_HOOKS=1; quit the running Herdr Perch first" >&2
    exit 1
fi
if [[ -z "$app_pid" ]]; then
    env -u HERDR_SESSION -u HERDR_SOCKET_PATH -u HERDR_CONFIG_PATH PERCH_TEST_HOOKS="$static_only" \
        "$app_binary" > "$tmp_dir/app.log" 2>&1 &
    app_pid=$!
    owned=1
    sleep 2
fi
if [[ "$static_only" -eq 0 ]]; then
    # Confirm there are real rows to exercise before accepting collapsed-state measurements.
    "$driver" expand "$app_pid"
    "$driver" collapse "$app_pid"
fi

measure() {
    local label="$1" budget="$2" surface="$3" movement="$4"
    local path x0 y0 x1 y1 measurement cpu elapsed attempt
    "$driver" check "$app_pid" "$surface"
    if [[ "$static_only" -eq 1 ]]; then
        :
    elif [[ "$movement" == static ]]; then
        "$driver" park
    else
        path="$("$driver" path "$app_pid" "$movement")"
        read -r x0 y0 x1 y1 <<< "$path"
        "$driver" move "$x0" "$y0"
        "$driver" wiggle "$x0" "$y0" "$x1" "$y1" 15 &
        move_pid=$!
    fi
    echo "[perf] $label: warmup 5s, sample 8s"
    sleep 5
    for attempt in 1 2 3; do
        if [[ -n "$move_pid" ]]; then kill -0 "$move_pid"; fi
        if [[ "$static_only" -eq 1 ]]; then
            "$driver" still 8.5 &
            still_pid=$!
        fi
        measurement="$(python3 -I - "$app_pid" <<'PY'
import math
import subprocess
import sys
import time

def sample():
    result = subprocess.run(["ps", "-p", sys.argv[1], "-o", "cputime="],
                            capture_output=True, text=True, check=True, timeout=1)
    value = result.stdout.strip()
    if not value:
        raise SystemExit("App exited during profiling")
    seconds = 0.0
    for part in value.split(":"):
        seconds = seconds * 60 + float(part)
    if not math.isfinite(seconds) or seconds < 0:
        raise SystemExit("Invalid accumulated CPU time")
    return time.monotonic(), seconds

started, first = sample()
time.sleep(8)
ended, last = sample()
if last < first:
    raise SystemExit("Accumulated CPU time decreased")
print(f"{100 * (last - first) / (ended - started):.6f} {ended - started:.3f}")
PY
)"
        if [[ -n "$still_pid" ]]; then
            if wait "$still_pid"; then
                still_pid=""
            else
                still_pid=""
                echo "[perf] $label: pointer moved during sample (attempt $attempt/3)"
                measurement=""
                sleep 2
                continue
            fi
        fi
        break
    done
    if [[ -z "$measurement" ]]; then
        echo "[perf] $label: INCONCLUSIVE — the pointer kept moving; rerun when idle"
        failures=$((failures + 1))
        return
    fi
    if [[ -n "$move_pid" ]]; then
        kill -0 "$move_pid"
        kill -TERM "$move_pid"
        wait "$move_pid" 2>/dev/null || true
        move_pid=""
    fi
    "$driver" check "$app_pid" "$surface"
    read -r cpu elapsed <<< "$measurement"
    if python3 -I - "$label" "$cpu" "$budget" "$elapsed" <<'PY'
import sys
label, cpu, budget, elapsed = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
passed = cpu < budget
print(f"[perf] {label}: {cpu:.3f}% CPU over {elapsed}s; budget < {budget:g}% — {'PASS' if passed else 'FAIL'}", flush=True)
raise SystemExit(0 if passed else 1)
PY
    then
        :
    else
        failures=$((failures + 1))
    fi
}

if [[ "$static_only" -eq 1 ]]; then
    measure 'collapsed / stationary' 0.5 collapsed static
    "$driver" post expand
    measure 'expanded / stationary' 0.5 expanded static
    echo "[perf] $((2 - failures))/2 scenarios within budget"
    [[ "$failures" -eq 0 ]]
    exit
fi
measure 'collapsed / stationary' 0.5 collapsed static
measure 'collapsed / moving outside' 3 collapsed outside
"$driver" expand "$app_pid"
measure 'expanded / stationary' 0.5 expanded static
measure 'expanded / within one row' 5 expanded row
measure 'expanded / crossing rows' 10 expanded cross
# cleanup always collapses the notch, parks the pointer, and stops only an app we launched.
echo "[perf] $((5 - failures))/5 scenarios within budget"
[[ "$failures" -eq 0 ]]
