#!/usr/bin/env bash
# Profile the already packaged app. Only header clicks and pointer movement are posted.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

app_binary="$PWD/dist/Herdr Perch.app/Contents/MacOS/PerchApp"
[[ -x "$app_binary" ]] || { echo "Package the app with scripts/bundle.sh first" >&2; exit 1; }
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/perch-perf.XXXXXX")"
driver="$tmp_dir/PointerDriver"
app_pid=""
move_pid=""
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
    if [[ -x "$driver" ]]; then
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
if [[ -z "$app_pid" ]]; then
    env -u HERDR_SESSION -u HERDR_SOCKET_PATH -u HERDR_CONFIG_PATH \
        "$app_binary" > "$tmp_dir/app.log" 2>&1 &
    app_pid=$!
    owned=1
    sleep 2
fi
# Confirm there are real rows to exercise before accepting collapsed-state measurements.
"$driver" expand "$app_pid"
"$driver" collapse "$app_pid"

measure() {
    local label="$1" budget="$2" surface="$3" movement="$4"
    local path x0 y0 x1 y1 measurement cpu elapsed
    "$driver" check "$app_pid" "$surface"
    if [[ "$movement" == static ]]; then
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
    if [[ -n "$move_pid" ]]; then kill -0 "$move_pid"; fi
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

measure 'collapsed / stationary' 0.5 collapsed static
measure 'collapsed / moving outside' 3 collapsed outside
"$driver" expand "$app_pid"
measure 'expanded / stationary' 0.5 expanded static
measure 'expanded / within one row' 5 expanded row
measure 'expanded / crossing rows' 10 expanded cross
# cleanup always collapses the notch, parks the pointer, and stops only an app we launched.
echo "[perf] $((5 - failures))/5 scenarios within budget"
[[ "$failures" -eq 0 ]]
