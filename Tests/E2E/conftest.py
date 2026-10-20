from contextlib import ExitStack
from pathlib import Path
import subprocess

import pytest

from herdr_support import REPO, HerdrSession, PerchWatch


@pytest.fixture(scope="session")
def perchctl() -> Path:
    subprocess.run(["swift", "build", "--product", "perchctl"], cwd=REPO, check=True, timeout=120)
    result = subprocess.run(["swift", "build", "--show-bin-path"], cwd=REPO, check=True,
                            capture_output=True, text=True, timeout=30)
    binary = Path(result.stdout.strip()) / "perchctl"
    assert binary.is_file()
    return binary


@pytest.fixture
def session_factory(tmp_path):
    with ExitStack() as cleanup:
        created = set()

        def create(name="perch-e2e"):
            assert name not in created, "Each test may own only one server per test session name"
            session = HerdrSession(name, tmp_path)
            cleanup.callback(session.close)  # Also runs if startup/setup fails midway.
            session.start()
            created.add(name)
            return session

        yield create


@pytest.fixture
def herdr_session(perchctl, session_factory):
    # Build first: compilation failures must not leave a running test server.
    return session_factory()


@pytest.fixture
def watch(perchctl, herdr_session, tmp_path):
    process = PerchWatch(perchctl, tmp_path)
    try:
        process.row(herdr_session.name, herdr_session.pane, "idle")
        yield process
    finally:
        process.close()
