"""Host tests for scripts/test-ios-diagnostics.sh, with fake xcodegen, xcrun, xcodebuild and xcbeautify on PATH."""

import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPT = ROOT / "scripts" / "test-ios-diagnostics.sh"


def fake_tools(tmp_path: Path, beautifier: bool) -> Path:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    tools = {
        "xcodegen": "exit 0",
        "xcrun": "exit 0",
        "xcodebuild": 'echo "Test Case passed"; [ -n "$FAKE_NOISE" ] && seq 1 "$FAKE_NOISE"; echo "** TEST $FAKE_RESULT **"; '
                      'exit "${FAKE_XCODEBUILD_EXIT:-0}"',
    }
    if beautifier:
        tools["xcbeautify"] = ('[ -n "$FAKE_BEAUTIFY_QUITS" ] && exit "$FAKE_BEAUTIFY_QUITS"; '
                               'while IFS= read -r line; do echo "pretty: $line"; done; exit "${FAKE_BEAUTIFY_EXIT:-0}"')
    for name, body in tools.items():
        path = bin_dir / name
        path.write_text(f"#!/bin/bash\n{body}\n")
        path.chmod(0o755)
    return bin_dir


def run(tmp_path: Path, beautifier: bool, **env: str) -> tuple[subprocess.CompletedProcess, Path]:
    log = tmp_path / "logs" / "test.log"
    environment = {"PATH": f"{fake_tools(tmp_path, beautifier)}:/usr/bin:/bin", "BUG_KIT_TEST_LOG": str(log),
                   "HOME": os.environ.get("HOME", str(tmp_path)), "FAKE_RESULT": "SUCCEEDED", **env}
    if not beautifier:
        environment["XCBEAUTIFY"] = "xcbeautify-not-installed"
    result = subprocess.run([str(SCRIPT), "SIM-UDID"], capture_output=True, text=True, env=environment)
    return result, log


def test_a_passing_run_shows_the_summary_and_keeps_the_raw_log(tmp_path):
    result, log = run(tmp_path, beautifier=True)
    assert result.returncode == 0
    assert "pretty: ** TEST SUCCEEDED **" in result.stdout
    assert log.read_text().splitlines() == ["Test Case passed", "** TEST SUCCEEDED **"]


def test_a_failing_xcodebuild_fails_the_script_through_the_beautifier(tmp_path):
    result, log = run(tmp_path, beautifier=True, FAKE_XCODEBUILD_EXIT="65", FAKE_RESULT="FAILED")
    assert result.returncode == 65
    assert "pretty: ** TEST FAILED **" in result.stdout
    assert f"xcodebuild failed (65); the raw log is {log}" in result.stderr
    assert "** TEST FAILED **" in log.read_text()


def test_a_failing_beautifier_keeps_xcodebuilds_status(tmp_path):
    result, log = run(tmp_path, beautifier=True, FAKE_BEAUTIFY_EXIT="3")
    assert result.returncode == 0
    assert f"xcbeautify failed (3); the raw log is {log}" in result.stderr
    assert "** TEST SUCCEEDED **" in log.read_text()


def test_a_beautifier_that_quits_unread_keeps_the_whole_log_and_xcodebuilds_status(tmp_path):
    # Far more output than a pipe buffer holds, so an unread pipe would SIGPIPE tee and xcodebuild.
    result, log = run(tmp_path, beautifier=True, FAKE_BEAUTIFY_QUITS="3", FAKE_NOISE="200000")
    assert result.returncode == 0
    assert f"xcbeautify failed (3); the raw log is {log}" in result.stderr
    assert log.read_text().splitlines()[-1] == "** TEST SUCCEEDED **"


def test_without_xcbeautify_the_raw_output_shows(tmp_path):
    result, log = run(tmp_path, beautifier=False)
    assert result.returncode == 0
    assert "** TEST SUCCEEDED **" in result.stdout and "pretty:" not in result.stdout
    assert "xcbeautify not found" in result.stderr
    assert "** TEST SUCCEEDED **" in log.read_text()


def test_without_xcbeautify_a_failing_xcodebuild_still_fails(tmp_path):
    result, _ = run(tmp_path, beautifier=False, FAKE_XCODEBUILD_EXIT="65", FAKE_RESULT="FAILED")
    assert result.returncode == 65
    assert "** TEST FAILED **" in result.stdout
