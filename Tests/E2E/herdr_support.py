"""Socket/process drivers for the two disposable, explicitly named test sessions."""
from __future__ import annotations

import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import threading
import time
import uuid
from collections.abc import Callable
from typing import Any

SESSION_NAMES = frozenset({"perch-e2e", "perch-e2e-2"})
REPO = Path(__file__).resolve().parents[2]
HERDR_ROOT = Path.home() / ".config/herdr"


def herdr_environment() -> dict[str, str]:
    environment = os.environ.copy()
    for key in ("HERDR_SESSION", "HERDR_SOCKET_PATH", "HERDR_CONFIG_PATH"):
        environment.pop(key, None)
    return environment


def wait_until(predicate: Callable[[], Any], timeout: float = 3.0) -> Any:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(0.01)
    raise AssertionError(f"Condition not reached within {timeout}s")


class HerdrSession:
    def __init__(self, name: str, directory: Path):
        if name not in SESSION_NAMES:
            raise ValueError(f"Test writes forbidden for session {name!r}")
        self.name = name
        self.directory = directory
        self.session_dir = HERDR_ROOT / "sessions" / name
        self.socket_path = self.session_dir / "herdr.sock"
        self.process: subprocess.Popen | None = None
        self.log = None
        self.workspace = ""
        self.tab = ""
        self.pane = ""

    def start(self) -> None:
        # Never stop/delete a session that this fixture did not create.
        if self.session_dir.exists() or self.session_dir.is_symlink():
            raise AssertionError(f"Refusing to overwrite existing test session: {self.session_dir}")
        self.log = (self.directory / f"{self.name}.server.log").open("wb")
        self.process = subprocess.Popen(
            ["herdr", "--session", self.name, "server"], env=herdr_environment(),
            stdout=self.log, stderr=subprocess.STDOUT, start_new_session=True,
        )

        def ready():
            if self.process.poll() is not None:
                raise AssertionError(f"Test server exited; see {self.log.name}")
            try:
                return self.rpc("ping", timeout=0.2)
            except (OSError, TimeoutError):
                return False

        wait_until(ready, 5)
        created = self.rpc("workspace.create", {"cwd": str(self.directory), "focus": True})
        self.workspace = created["workspace"]["workspace_id"]
        snapshot = self.snapshot()
        pane = next(p for p in snapshot["panes"] if p["workspace_id"] == self.workspace)
        self.tab, self.pane = pane["tab_id"], pane["pane_id"]
        self.keep_foreground_process(self.pane)
        self.focus(self.workspace, self.tab, self.pane)

    def rpc(self, method: str, params: dict | None = None, *, timeout: float = 3) -> dict:
        if self.name not in SESSION_NAMES:  # Defensive at the write boundary too.
            raise ValueError("Only disposable E2E sessions may receive RPCs")
        request_id = uuid.uuid4().hex
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.settimeout(timeout)
            connection.connect(str(self.socket_path))
            connection.sendall((json.dumps({"id": request_id, "method": method, "params": params or {}}) + "\n").encode())
            with connection.makefile("rb") as response:
                line = response.readline()
        if not line.endswith(b"\n"):
            raise AssertionError("Herdr closed before a complete response")
        envelope = json.loads(line)
        assert envelope.get("id") == request_id
        if "error" in envelope:
            raise AssertionError(f"{method}: {envelope['error']}")
        return envelope["result"]

    def snapshot(self) -> dict:
        return self.rpc("session.snapshot")["snapshot"]

    def report(self, state: str, pane: str | None = None) -> None:
        self.rpc("pane.report_agent", {"pane_id": pane or self.pane, "source": "hook", "agent": "claude", "state": state})

    def keep_foreground_process(self, pane: str) -> None:
        self.rpc("pane.send_input", {"pane_id": pane, "text": "exec sleep 600", "keys": ["enter"]})
        # Readiness is observable: idle removes an agent while the pane has no foreground process.
        def ready():
            self.report("idle", pane)
            return any(a.get("pane_id") == pane for a in self.snapshot()["agents"])
        wait_until(ready)

    def new_tab(self, *, focus: bool = False, prepare: bool = True) -> tuple[str, str]:
        created = self.rpc("tab.create", {"workspace_id": self.workspace, "cwd": str(self.directory), "focus": focus})
        tab = created["tab"]["tab_id"]
        snapshot = self.snapshot()
        pane = next(p["pane_id"] for p in snapshot["panes"] if p["tab_id"] == tab)
        if prepare:
            self.keep_foreground_process(pane)
        return tab, pane

    def focus(self, workspace: str, tab: str, pane: str) -> None:
        for method, key, value in (("workspace.focus", "workspace_id", workspace), ("tab.focus", "tab_id", tab), ("pane.focus", "pane_id", pane)):
            self.rpc(method, {key: value})

    def signal(self, value: int) -> None:
        assert self.process is not None and self.process.poll() is None
        self.process.send_signal(value)

    def stop(self) -> None:
        subprocess.run(["herdr", "session", "stop", self.name], env=herdr_environment(), check=True,
                       capture_output=True, timeout=5)

    def close(self) -> None:
        if self.process is None:
            if self.log is not None:
                self.log.close()
            return
        try:
            if self.process.poll() is None:
                self.process.send_signal(signal.SIGCONT)
            try:
                subprocess.run(["herdr", "session", "stop", self.name], env=herdr_environment(),
                               capture_output=True, timeout=5, check=False)
            finally:
                # Ensure the owned child exits before attempting deletion, even if stop failed.
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.terminate()
                    try:
                        self.process.wait(timeout=1)
                    except subprocess.TimeoutExpired:
                        self.process.kill()
                        self.process.wait(timeout=1)
        finally:
            try:
                deleted = subprocess.run(["herdr", "session", "delete", self.name], env=herdr_environment(),
                                         capture_output=True, timeout=5, check=False)
                assert deleted.returncode == 0, f"Could not delete owned test session {self.name}"
            finally:
                self.log.close()


class JSONLines:
    """Read stdout/events continuously, timestamping receipt in the pytest process."""
    def __init__(self):
        self.condition = threading.Condition()
        self.records: list[tuple[float, dict]] = []
        self.error: Exception | None = None
        self.ended = False

    def read(self, source) -> None:
        try:
            for line in source:
                at = time.monotonic()
                body = json.loads(line)
                with self.condition:
                    self.records.append((at, body))
                    self.condition.notify_all()
        except Exception as error:
            with self.condition:
                self.error = error
        finally:
            with self.condition:
                self.ended = True
                self.condition.notify_all()

    def wait(self, predicate: Callable[[dict], bool], *, after: float = 0, timeout: float = 3) -> tuple[float, dict]:
        deadline = time.monotonic() + timeout
        with self.condition:
            while True:
                if self.error:
                    raise AssertionError("Invalid JSON line in stream") from self.error
                for at, body in self.records:
                    if at >= after and predicate(body):
                        return at, body
                if self.ended:
                    raise AssertionError("Stream ended before the expected state")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise AssertionError(f"Expected stream state not received within {timeout}s")
                self.condition.wait(remaining)


class PerchWatch:
    def __init__(self, binary: Path, directory: Path):
        self.log = (directory / f"watch-{uuid.uuid4().hex[:8]}.stderr").open("wb")
        self.process = subprocess.Popen([str(binary), "watch"], stdout=subprocess.PIPE, stderr=self.log, text=True, bufsize=1)
        self.lines = JSONLines()
        self.thread = threading.Thread(target=self.lines.read, args=(self.process.stdout,), daemon=True)
        self.thread.start()

    def row(self, session: str, pane: str, status: str, *, after: float = 0, timeout: float = 3):
        return self.lines.wait(lambda body: any(r.get("session") == session and r.get("pane") == pane and
                                               r.get("status") == status for r in body["rows"]), after=after, timeout=timeout)

    def close(self) -> None:
        try:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.wait(timeout=2)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.wait(timeout=1)
        finally:
            self.thread.join(timeout=1)
            self.process.stdout.close()
            self.log.close()


class HerdrEvents:
    def __init__(self, session: HerdrSession, pane: str):
        self.connection = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.connection.settimeout(3)
        self.source = None
        try:
            self.connection.connect(str(session.socket_path))
            self.connection.sendall((json.dumps({"id": "events", "method": "events.subscribe", "params": {
                "subscriptions": [{"type": "pane.agent_status_changed", "pane_id": pane}]
            }}) + "\n").encode())
            self.source = self.connection.makefile("rb")
            ack = json.loads(self.source.readline())
            assert ack["result"]["type"] == "subscription_started"
            self.connection.settimeout(None)
            self.lines = JSONLines()
            self.thread = threading.Thread(target=self.lines.read, args=(self.source,), daemon=True)
            self.thread.start()
        except BaseException:
            if self.source is not None:
                self.source.close()
            self.connection.close()
            raise

    def status(self, pane: str, state: str, *, after: float):
        return self.lines.wait(lambda body: body.get("data", {}).get("pane_id") == pane and
                               body.get("data", {}).get("agent_status") == state, after=after)

    def close(self) -> None:
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        self.thread.join(timeout=1)
        self.source.close()
        self.connection.close()


def rows_for_session(document: dict, session: str) -> list[dict]:
    return [row for row in document["rows"] if row.get("session") == session]
