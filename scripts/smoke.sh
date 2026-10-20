#!/usr/bin/env bash
# Read-only smoke test against the default Herdr Session.
set -euo pipefail
export LC_ALL=C
cd "$(dirname "$0")/.."

duration="${SMOKE_DURATION:-60}"
python3 -I - "$duration" <<'PY'
import math
import sys
try:
    duration = float(sys.argv[1])
except ValueError:
    raise SystemExit("SMOKE_DURATION must be a positive number")
if not math.isfinite(duration) or duration <= 0:
    raise SystemExit("SMOKE_DURATION must be a positive number")
PY

tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/perch-smoke.XXXXXX")"
app_pid=""
watchdog_pid=""
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    set +e
    if [[ -n "$watchdog_pid" ]]; then
        kill -TERM "$watchdog_pid" 2>/dev/null
        wait "$watchdog_pid" 2>/dev/null
    fi
    if [[ -n "$app_pid" ]]; then
        if kill -0 "$app_pid" 2>/dev/null; then
            kill -TERM "$app_pid" 2>/dev/null
            for ((attempt = 0; attempt < 20; attempt++)); do
                kill -0 "$app_pid" 2>/dev/null || break
                sleep 0.1
            done
            if kill -0 "$app_pid" 2>/dev/null; then
                kill -KILL "$app_pid" 2>/dev/null
            fi
        fi
        wait "$app_pid" 2>/dev/null
    fi
    rm -rf "$tmp_dir"
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

CONFIG=release scripts/bundle.sh
app_binary="$PWD/dist/Herdr Perch.app/Contents/MacOS/PerchApp"
[[ -x "$app_binary" ]] || { echo "Missing app executable: $app_binary" >&2; exit 1; }
trace="$tmp_dir/trace.ndjson"
: > "$trace"
env -u HERDR_SESSION -u HERDR_SOCKET_PATH -u HERDR_CONFIG_PATH \
    PERCH_TRACE="$trace" "$app_binary" > "$tmp_dir/app.log" 2>&1 &
app_pid=$!

# Poll the latest complete trace line. Retry when the live state changes between samples.
python3 -I - "$trace" "$app_pid" <<'PY'
import json
import os
from pathlib import Path
import subprocess
import sys
import time

trace, pid = Path(sys.argv[1]), int(sys.argv[2])
environment = os.environ.copy()
for key in ("HERDR_SESSION", "HERDR_SOCKET_PATH", "HERDR_CONFIG_PATH"):
    environment.pop(key, None)
status_names = {"idle": "idle", "unknown": "idle", "working": "working", "blocked": "blocked", "done": "finished"}
deadline = time.monotonic() + 5
matched = False
reason = "no default Session rows appeared (the default Session needs at least one agent)"
while time.monotonic() < deadline:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        raise SystemExit("App exited before producing the expected trace")
    content = trace.read_bytes()
    # Discard an in-progress final write; completed lines must contain valid JSON.
    lines = content.split(b"\n")[:-1]
    if lines:
        try:
            document = json.loads(lines[-1])
            actual = {(row["pane"], row["status"]) for row in document["rows"] if row["session"] == "default"}
        except (ValueError, KeyError, TypeError) as error:
            raise SystemExit(f"Invalid completed trace line: {type(error).__name__}")
        if actual:
            try:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                result = subprocess.run(
                    ["herdr", "--session", "default", "agent", "list"], env=environment,
                    capture_output=True, text=True, check=True, timeout=min(0.5, remaining),
                )
                agents = json.loads(result.stdout)["result"]["agents"]
                expected = {(agent["pane_id"], status_names.get(agent.get("agent_status"), "idle"))
                            for agent in agents if all(isinstance(agent.get(key), str) for key in ("pane_id", "tab_id", "workspace_id", "agent"))}
                if actual == expected:
                    print(f"[smoke] default Session trace matches {len(actual)} agent(s)")
                    matched = True
                    break
                reason = "default Session pane/status sets did not match"
            except (subprocess.SubprocessError, OSError, ValueError, KeyError, TypeError) as error:
                reason = f"could not read default agent list: {type(error).__name__}"
    time.sleep(min(0.05, max(0, deadline - time.monotonic())))
if not matched:
    raise SystemExit(f"Trace check failed within 5s: {reason}")
PY

application_type="$(lsappinfo info -only ApplicationType -app "$app_pid")"
case "$application_type" in
    *UIElement*) echo "[smoke] ApplicationType is UIElement" ;;
    *) echo "Expected UIElement; got: $application_type" >&2; exit 1 ;;
esac

python3 -I - "$app_pid" "$duration" <<'PY'
import math
import statistics
import subprocess
import sys
import time

pid, duration = int(sys.argv[1]), float(sys.argv[2])
deadline = time.monotonic() + duration
samples = []
while time.monotonic() < deadline:
    result = subprocess.run(["ps", "-p", str(pid), "-o", "%cpu=,rss="], capture_output=True, text=True, timeout=1)
    values = result.stdout.split()
    if result.returncode != 0 or len(values) != 2:
        raise SystemExit("App exited during resource sampling")
    cpu, rss = map(float, values)
    if not all(math.isfinite(value) and value >= 0 for value in (cpu, rss)):
        raise SystemExit("Invalid ps CPU/RSS sample")
    samples.append((cpu, rss))
    time.sleep(min(1, max(0, deadline - time.monotonic())))
if not samples:
    raise SystemExit("No CPU/RSS samples collected")
average_cpu = statistics.fmean(cpu for cpu, _ in samples)
peak_rss = max(rss for _, rss in samples)
print(f"[smoke] {len(samples)} sample(s) over {duration:g}s: average CPU {average_cpu:.3f}%, peak RSS {peak_rss / 1024:.2f} MiB")
if average_cpu >= 0.5 or peak_rss >= 60 * 1024:
    raise SystemExit("Resource budget exceeded: average CPU must be < 0.5%, RSS < 60 MiB")
PY

# Bash owns the child and must reap it to observe the actual exit status. A separate
# watchdog bounds wait without confusing an exited, unreaped child for a live app.
kill -0 "$app_pid" 2>/dev/null || { echo "App exited before the termination check" >&2; exit 1; }
python3 -I - "$app_pid" "$tmp_dir/forced-kill" <<'PY' &
import os
from pathlib import Path
import signal
import sys
import time

time.sleep(2)
try:
    os.kill(int(sys.argv[1]), signal.SIGKILL)
except ProcessLookupError:
    pass
else:
    Path(sys.argv[2]).touch()
PY
watchdog_pid=$!
kill -TERM "$app_pid"
if wait "$app_pid"; then
    exit_code=0
else
    exit_code=$?
fi
app_pid=""
kill -TERM "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true
watchdog_pid=""
if [[ -f "$tmp_dir/forced-kill" || "$exit_code" -ne 0 ]]; then
    echo "App did not exit cleanly within 2s (exit code $exit_code)" >&2
    exit 1
fi
echo "[smoke] TERM exited within 2s with status 0"
echo "[smoke] passed"
