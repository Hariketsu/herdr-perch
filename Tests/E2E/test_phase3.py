"""Phase 3 acceptance tests. Collection alone never builds or starts Herdr."""
import json
import math
import signal
import subprocess
import time

import pytest

from herdr_support import HerdrEvents, rows_for_session, wait_until


@pytest.mark.parametrize("state", ["working", "blocked", "idle"])
def test_status_latency_p95_uses_herdr_event_as_baseline(herdr_session, watch, state):
    session = herdr_session
    events = HerdrEvents(session, session.pane)
    samples = []
    try:
        for _ in range(20):
            previous = "blocked" if state == "working" else "working"
            before = time.monotonic()
            session.report(previous)
            events.status(session.pane, previous, after=before)
            watch.row(session.name, session.pane, previous, after=before)
            after = time.monotonic()
            session.report(state)
            event_at, _ = events.status(session.pane, state, after=after)
            displayed_at, _ = watch.row(session.name, session.pane, state, after=after)
            samples.append(displayed_at - event_at)
    finally:
        events.close()
    assert len(samples) == 20
    p95 = sorted(samples)[math.ceil(0.95 * len(samples)) - 1]
    print(f"{state} p95 latency: {p95 * 1000:.1f} ms ({len(samples)} samples)")
    assert p95 <= 0.300, f"{state} p95 latency was {p95:.3f}s"


def test_unfocused_idle_is_finished_and_tab_focus_clears_it(herdr_session, watch):
    session = herdr_session
    tab, pane = session.new_tab(focus=False)
    assert session.snapshot()["focused_tab_id"] != tab
    session.report("working", pane)
    watch.row(session.name, pane, "working")
    after = time.monotonic()
    session.report("idle", pane)
    watch.row(session.name, pane, "finished", after=after)
    snapshot = session.snapshot()
    agent = next(a for a in snapshot["agents"] if a["pane_id"] == pane)
    assert agent["agent_status"] == "done"
    after = time.monotonic()
    session.rpc("tab.focus", {"tab_id": tab})
    watch.row(session.name, pane, "idle", after=after)
    assert next(a for a in session.snapshot()["agents"] if a["pane_id"] == pane)["agent_status"] == "idle"


def test_new_pane_and_agent_arrive_without_waiting_for_poll(herdr_session, watch):
    session = herdr_session
    _, pane = session.new_tab(prepare=False)
    session.rpc("pane.send_input", {"pane_id": pane, "text": "exec sleep 600", "keys": ["enter"]})
    after = time.monotonic()
    session.report("working", pane)
    received, _ = watch.row(session.name, pane, "working", after=after, timeout=0.300)
    assert received - after <= 0.300


def test_new_session_appears_within_one_and_half_seconds(session_factory, watch):
    # Clock starts before socket creation, so this includes the scanner's next cycle.
    after = time.monotonic()
    second = session_factory("perch-e2e-2")
    received, _ = watch.lines.wait(lambda body: any(r.get("session") == second.name for r in body["rows"]),
                                  after=after, timeout=max(0.001, 1.5 - (time.monotonic() - after)))
    assert received - after <= 1.5


def test_stopped_session_rows_disappear_within_one_and_half_seconds(herdr_session, watch):
    session = herdr_session
    after = time.monotonic()
    session.stop()
    received, _ = watch.lines.wait(lambda body: not rows_for_session(body, session.name), after=after,
                                  timeout=max(0.001, 1.5 - (time.monotonic() - after)))
    assert received - after <= 1.5


def test_frozen_owned_server_becomes_stale_then_recovers(herdr_session, watch):
    session = herdr_session
    after = time.monotonic()
    session.signal(signal.SIGSTOP)
    try:
        received, _ = watch.lines.wait(lambda body: bool(rows_for_session(body, session.name)) and
                                      all(r["stale"] for r in rows_for_session(body, session.name)), after=after, timeout=6)
        assert received - after <= 6
    finally:
        # Resume even if the assertion fails, so teardown can stop/delete the session.
        recovery_start = time.monotonic()
        session.signal(signal.SIGCONT)
    received, _ = watch.lines.wait(lambda body: bool(rows_for_session(body, session.name)) and
                                  all(not r["stale"] for r in rows_for_session(body, session.name)), after=recovery_start, timeout=3)
    assert received - recovery_start <= 3


def test_jump_focuses_target_pane_and_its_tab(perchctl, herdr_session):
    session = herdr_session
    tab, pane = session.new_tab(focus=False)
    assert session.snapshot()["focused_tab_id"] != tab
    result = subprocess.run([str(perchctl), "jump", session.name, pane], capture_output=True, text=True, timeout=5)
    assert result.returncode == 0, result.stderr
    lines = result.stdout.splitlines()
    assert len(lines) == 1
    assert json.loads(lines[0])["outcome"] == "focused"

    def focused():
        snapshot = session.snapshot()
        return snapshot["focused_pane_id"] == pane and snapshot["focused_tab_id"] == tab

    wait_until(focused)


def test_dump_matches_agent_list_for_only_the_test_session(perchctl, herdr_session):
    session = herdr_session
    session.report("blocked")
    snapshot = session.snapshot()
    expected = next(a for a in snapshot["agents"] if a["pane_id"] == session.pane)
    assert expected["agent_status"] == "blocked"
    # rpc unwraps result and connects directly to this fixture's named-session socket.
    agents = session.rpc("agent.list")["agents"]
    dumped = subprocess.run([str(perchctl), "dump"], capture_output=True, text=True, check=True, timeout=10)
    lines = dumped.stdout.splitlines()
    assert len(lines) == 1
    document = json.loads(lines[0])
    assert isinstance(document["t"], (int, float))
    rows = rows_for_session(document, session.name)
    assert {r["pane"] for r in rows} == {a["pane_id"] for a in agents if a.get("agent")}
    statuses = {"idle": "idle", "unknown": "idle", "working": "working", "blocked": "blocked", "done": "finished"}
    by_pane = {r["pane"]: r for r in rows}
    for agent in agents:
        if not agent.get("agent"):
            continue
        row = by_pane[agent["pane_id"]]
        assert row["status"] == statuses.get(agent.get("agent_status"), "idle")
        assert row["title"] == next((agent[key] for key in ("name", "title", "terminal_title_stripped", "display_agent", "agent")
                                    if agent.get(key) is not None), None)
        assert row["stale"] is False
    sessions = [s for s in document["sessions"] if s["name"] == session.name]
    assert sessions == [{"name": session.name, "health": "live"}]
