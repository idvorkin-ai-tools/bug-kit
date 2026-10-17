"""bugs-monitor.sh with a stub check that replays a script of outputs, one per round."""

import os
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "bugs-monitor.sh"

# Round n prints rounds/<n>.out and exits with rounds/<n>.rc.
STUB = """#!/bin/bash
n=$(( $(cat "{dir}/n" 2>/dev/null || echo 0) + 1 )); echo $n > "{dir}/n"
echo "$@" >> "{dir}/args"
cat "{dir}/$n.out" 2>/dev/null; cat "{dir}/$n.err" >&2 2>/dev/null
exit $(cat "{dir}/$n.rc" 2>/dev/null || echo 0)
"""


def monitor(tmp: Path, rounds: list[tuple[str, int, str]], *args: str):
    for i, (out, rc, err) in enumerate(rounds, 1):
        (tmp / f"{i}.out").write_text(out)
        (tmp / f"{i}.rc").write_text(str(rc))
        (tmp / f"{i}.err").write_text(err)
    stub = tmp / "check"
    stub.write_text(STUB.format(dir=tmp))
    stub.chmod(0o755)
    env = {**os.environ, "BUG_KIT_CHECK": str(stub), "TMPDIR": str(tmp)}
    run = subprocess.run([str(SCRIPT), *args, "--every", "0", "--rounds", str(len(rounds))],
                         capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stderr
    return run.stdout.splitlines()


A = "new demo iphone-17-pro 2026-10-10T15:00:00.000Z the timer skipped"
B = "new demo ipad-pro 2026-10-10T15:05:00.000Z rest did not start"


def test_each_report_once_and_nothing_else(tmp_path):
    lines = monitor(tmp_path, [
        (f"== demo / iphone-17-pro\n{A}\n1 unfiled report(s)\n", 1, ""),
        (f"{A}\n{B}\n2 unfiled report(s)\n", 1, ""),
        ("no unfiled reports\n", 0, ""),
    ], "demo")
    assert lines == [A, B]
    assert (tmp_path / "args").read_text().splitlines() == ["--check demo"] * 3


def test_a_failing_check_is_said_once_then_its_recovery(tmp_path):
    lines = monitor(tmp_path, [
        ("", 2, "demo: could not read owner/demo's issues (HTTP 502)\n"),
        ("", 2, "demo: could not read owner/demo's issues (HTTP 502)\n"),
        (f"{A}\n", 1, ""),
    ])
    assert lines == ["check_failed demo: could not read owner/demo's issues (HTTP 502)", "check_ok", A]
    assert (tmp_path / "args").read_text().splitlines() == ["--check"] * 3


def test_a_stale_listener_is_said_once_until_it_polls_again(tmp_path):
    stale = "no unfiled reports\nbut the listener's last poll was 2026-10-17T17:29:00.000Z: reports waiting for it\n"
    lines = monitor(tmp_path, [(stale, 3, ""), (stale, 3, ""), ("no unfiled reports\n", 0, "")])
    assert lines == ["listener_stale but the listener's last poll was 2026-10-17T17:29:00.000Z: reports waiting for it",
                     "listener_ok"]
