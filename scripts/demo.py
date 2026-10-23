#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# ///
"""Record README demo clips from a disposable Herdr session with fictional agents.

    scripts/demo.py [--dry-run] [overview peek]

Quits the running Perch, starts a headless `herdr --session perch-demo` with four fake
agents (states set through `pane.report_agent`), launches dist/Herdr Perch.app with
PERCH_HERDR_ROOT pointing at that session only, then drives the pointer and records the
built-in display. Everything is torn down and the user's Perch reopened afterwards.

Moves the mouse: only run when the user has agreed not to touch the computer.
Needs Accessibility and Screen Recording permission for the terminal.
"""

import argparse
import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
APP = REPO / "dist/Herdr Perch.app"
EXECUTABLE = APP / "Contents/MacOS/PerchApp"
OUT = REPO / "docs/assets"
SESSION = "perch-demo"
SESSION_DIR = Path.home() / ".config/herdr/sessions" / SESSION
WORK = Path(tempfile.gettempdir()) / "perch-demo"

# Fictional agents only (the repository is public). Pi's tab stays focused so its idle
# stays idle; the others are unfocused, so working → idle becomes done.
AGENTS = {
    "pi": ("pi", "Write release notes", "website"),
    "claude": ("claude", "Refactor auth middleware", "acme-api"),
    "codex": ("codex", "Fix flaky upload test", "uploader"),
    "omp": ("omp", "Migrate config to TOML", "orbit-cli"),
}
HERO = {"codex": "blocked", "claude": "done", "omp": "working", "pi": "idle"}

# Crop around the notch, in points of the built-in display (top-left origin).
CROP_WIDTH, CROP_HEIGHT = 660, 360
GIF_WIDTH, GIF_FPS = 800, 20
# screencapture display number and global left edge (points) of the built-in display.
BUILT_IN_DISPLAY, BUILT_IN_LEFT = 2, 218.0


def herdr_env() -> dict[str, str]:
    env = os.environ.copy()
    for key in ("HERDR_SESSION", "HERDR_SOCKET_PATH", "HERDR_CONFIG_PATH"):
        env.pop(key, None)
    return env


def rpc(method: str, params: dict | None = None) -> dict:
    request = {"id": uuid.uuid4().hex, "method": method, "params": params or {}}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(3)
        connection.connect(str(SESSION_DIR / "herdr.sock"))
        connection.sendall((json.dumps(request) + "\n").encode())
        with connection.makefile("rb") as response:
            envelope = json.loads(response.readline())
    if "error" in envelope:
        raise RuntimeError(f"{method}: {envelope['error']}")
    return envelope["result"]


def wait_until(predicate, timeout: float = 5.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if result := predicate():
                return result
        except OSError:
            pass
        time.sleep(0.05)
    raise TimeoutError("condition not reached")


class Driver:
    """Tests/Support/PointerDriver, compiled once."""

    def __init__(self, build: Path):
        self.binary = build / "PointerDriver"
        subprocess.run(["swiftc", "-O", "-module-cache-path", str(build / "module-cache"),
                        str(REPO / "Tests/Support/PointerDriver.swift"), "-o", str(self.binary)], check=True)

    def __call__(self, *args) -> str:
        return subprocess.run([str(self.binary), *map(str, args)], check=True,
                              capture_output=True, text=True).stdout.strip()

    def point(self, *args) -> tuple[float, float]:
        x, y = self("point", *args).split()
        return float(x), float(y)


class Demo:
    def __init__(self, driver: Driver, record: bool):
        self.driver = driver
        self.record = record
        self.server: subprocess.Popen | None = None
        self.perch_pid = 0
        self.panes: dict[str, str] = {}
        self.tabs: dict[str, str] = {}

    # Session and app

    def start_session(self) -> None:
        if SESSION_DIR.exists():
            raise SystemExit(f"{SESSION_DIR} exists; stop and delete the stale demo session first")
        shutil.rmtree(WORK, ignore_errors=True)
        for _, _, project in AGENTS.values():
            (WORK / "projects" / project).mkdir(parents=True)
        log = (WORK / "server.log").open("wb")
        self.server = subprocess.Popen(["herdr", "--session", SESSION, "server"], env=herdr_env(), cwd=WORK,
                                       stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        wait_until(lambda: rpc("ping"))
        workspace = None
        for name, (agent, title, project) in AGENTS.items():
            cwd = str(WORK / "projects" / project)
            if workspace is None:
                created = rpc("workspace.create", {"cwd": cwd, "focus": True})
                workspace = created["workspace"]["workspace_id"]
                tab, pane = created["tab"]["tab_id"], created["root_pane"]["pane_id"]
            else:
                created = rpc("tab.create", {"workspace_id": workspace, "cwd": cwd, "focus": False})
                tab = created["tab"]["tab_id"]
                pane = next(p["pane_id"] for p in rpc("session.snapshot")["snapshot"]["panes"] if p["tab_id"] == tab)
            self.tabs[name], self.panes[name] = tab, pane
            # The terminal title becomes the row title; a foreground process keeps an idle agent listed.
            rpc("pane.send_input", {"pane_id": pane, "text": f"printf '\\033]0;{title}\\007'; exec sleep 3600",
                                    "keys": ["enter"]})
            wait_until(lambda: self.report(name, "working") or self.agent(name).get("terminal_title") == title)
        rpc("tab.focus", {"tab_id": self.tabs["pi"]})

    def launch_perch(self) -> None:
        root = str(SESSION_DIR)
        subprocess.run(["open", "-n", str(APP), "--env", f"PERCH_HERDR_ROOT={root}", "--env", "PERCH_TEST_HOOKS=1",
                        "--args", "-listStyle", "grouped", "-compactStyle", "A"], check=True)
        self.perch_pid = int(wait_until(lambda: self.driver("pid", EXECUTABLE)))
        time.sleep(1.5)
        # Unfold the Idle group once (it stays open for this run) so every state shows a full row.
        # The header sits below one card per other state in the hero layout; offset measured on a screenshot of that layout.
        self.arrange(HERO)
        self.driver("post", "expand")
        time.sleep(1.0)
        x, y = self.driver.point("center")
        self.driver("move", x - 275, y + 274)
        time.sleep(0.3)
        self.driver("click")
        time.sleep(0.5)
        self.park()
        time.sleep(0.5)
        self.driver("post", "collapse")
        time.sleep(1.0)

    def agent(self, name: str) -> dict:
        agents = rpc("session.snapshot")["snapshot"]["agents"]
        return next((a for a in agents if a["pane_id"] == self.panes[name]), {})

    def report(self, name: str, state: str) -> None:
        rpc("pane.report_agent", {"pane_id": self.panes[name], "source": "hook",
                                  "agent": AGENTS[name][0], "state": state})

    def set(self, name: str, state: str) -> None:
        """Move one agent to a display state; done = working → idle in an unfocused tab."""
        if state == "done":
            if self.agent(name).get("agent_status") != "working":
                self.report(name, "working")
                time.sleep(0.3)
            self.report(name, "idle")
        else:
            self.report(name, state)

    def arrange(self, states: dict[str, str]) -> None:
        """Bring every agent to `states` off camera, then settle with the notch collapsed."""
        self.park()
        rpc("tab.focus", {"tab_id": self.tabs["pi"]})
        for name, state in states.items():
            if self.agent(name).get("agent_status") != state:
                self.set(name, state)
        time.sleep(1.5)  # Let any peek appear before closing it.
        self.driver("post", "collapse")
        time.sleep(1.0)

    # Pointer

    def park(self) -> None:
        x, y = self.driver.point("center")
        self.driver("move", x + 260, y + CROP_HEIGHT + 80)

    def glide(self, point: tuple[float, float], seconds: float) -> None:
        self.driver("glide", point[0], point[1], seconds)

    # Recording

    def crop(self, size: tuple[int, int]) -> tuple[int, int, int, int]:
        """Crop rectangle in pixels (2x) of the built-in display, centered on the notch."""
        width, height = size
        cx, _ = self.driver.point("center")
        left = cx - BUILT_IN_LEFT - width / 2
        return int(left * 2), 0, width * 2, height * 2

    def clip(self, name: str, seconds: float, timeline, size=(CROP_WIDTH, CROP_HEIGHT)) -> None:
        """Runs `timeline` ([(seconds, step)]) while recording, then holds until `seconds`."""
        print(f"• {name}")

        def action():
            started = time.monotonic()
            for at, step in timeline:
                time.sleep(max(0, at - (time.monotonic() - started)))
                step()
            time.sleep(max(0, seconds - (time.monotonic() - started)))

        if not self.record:
            action()
            return
        raw = WORK / f"{name}.mov"
        recorder = subprocess.Popen(["screencapture", "-v", "-C", f"-D{BUILT_IN_DISPLAY}",
                                     f"-V{seconds + LEAD + 1}", str(raw)])  # +1: it starts a little late
        time.sleep(LEAD)
        action()
        recorder.wait()
        to_gif(raw, OUT / f"{name}.gif", self.crop(size), start=LEAD - 0.3, duration=seconds)

    def teardown(self) -> None:
        if self.perch_pid:
            os.kill(self.perch_pid, signal.SIGTERM)
        if self.server is not None:
            subprocess.run(["herdr", "session", "stop", SESSION], env=herdr_env(), capture_output=True, timeout=10)
            try:
                self.server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.server.kill()
            subprocess.run(["herdr", "session", "delete", SESSION], env=herdr_env(), capture_output=True, timeout=10)


LEAD = 1.5  # Seconds recorded before the action starts; screencapture needs a moment to begin.


def to_gif(source: Path, target: Path, crop: tuple[int, int, int, int], *, start: float, duration: float) -> None:
    x, y, w, h = crop
    filters = (f"crop={w}:{h}:{x}:{y},fps={GIF_FPS},scale={GIF_WIDTH}:-1:flags=lanczos,split[a][b];"
               f"[a]palettegen=stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=3:diff_mode=rectangle")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", str(start), "-t", str(duration), "-i", str(source),
                    "-filter_complex", filters, str(target)], check=True)
    print(f"  {target} ({target.stat().st_size / 1e6:.1f} MB)")


# Clips. Each starts and ends collapsed with the pointer off camera, so it loops cleanly.

def overview(demo: Demo) -> None:
    """Agents at work; Codex gets blocked and peeks; the pointer opens the full list, one agent per state."""
    demo.arrange({"codex": "working", "omp": "working", "claude": "done", "pi": "idle"})
    center = demo.driver.point("center")
    # Leaves sideways along the top strip, so it never crosses (and highlights) a card.
    off_camera = (center[0] + CROP_WIDTH / 2 + 40, center[1])
    demo.clip("overview", 7.2, [
        (0.8, lambda: demo.set("codex", "blocked")),
        (2.3, lambda: demo.glide(center, 0.6)),   # rests on the top strip, off the cards
        (5.5, lambda: demo.glide(off_camera, 0.5)),
    ])


def peek(demo: Demo) -> None:
    """Two cards stack (blocked above done) and leave together once handled."""
    demo.arrange({"codex": "working", "claude": "working", "omp": "working", "pi": "idle"})

    def handled():
        demo.set("codex", "working")
        # Looking at Claude's tab turns Done into Idle.
        rpc("tab.focus", {"tab_id": demo.tabs["claude"]})

    demo.clip("peek", 5.0, [
        (0.8, lambda: demo.set("claude", "done")),
        (2.0, lambda: demo.set("codex", "blocked")),
        (3.8, handled),
    ], size=(520, 190))


CLIPS = {"overview": overview, "peek": peek}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("clips", nargs="*", default=list(CLIPS), help=", ".join(CLIPS))
    parser.add_argument("--dry-run", action="store_true", help="run the clips without recording")
    args = parser.parse_args()
    if unknown := set(args.clips) - set(CLIPS):
        parser.error(f"unknown clips: {', '.join(sorted(unknown))}")
    if not EXECUTABLE.exists():
        raise SystemExit("dist/Herdr Perch.app is missing; run scripts/bundle.sh first")

    build = Path(tempfile.mkdtemp(prefix="perch-demo-build-"))
    driver = Driver(build)
    # The user's Perch would also see the demo session; quit it and reopen the same app afterwards.
    running = subprocess.run(["pgrep", "-x", "PerchApp"], capture_output=True, text=True).stdout.split()
    user_apps = [subprocess.run(["ps", "-o", "comm=", "-p", pid], capture_output=True, text=True).stdout.strip()
                 for pid in running]
    for pid in running:
        os.kill(int(pid), signal.SIGTERM)
    wait_until(lambda: subprocess.run(["pgrep", "-x", "PerchApp"], capture_output=True).returncode != 0)
    OUT.mkdir(parents=True, exist_ok=True)
    demo = Demo(driver, record=not args.dry_run)
    try:
        demo.start_session()
        demo.launch_perch()
        for name in args.clips:
            CLIPS[name](demo)
    finally:
        demo.teardown()
        for executable in user_apps:
            subprocess.run(["open", executable.split("/Contents/MacOS/")[0]])
        shutil.rmtree(build, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
