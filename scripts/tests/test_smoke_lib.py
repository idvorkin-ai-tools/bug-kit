"""smoke-lib.sh against a stub simctl whose `launch` writes the log a scripted app would."""

import os
import subprocess
from pathlib import Path

LIB = Path(__file__).resolve().parents[1] / "smoke-lib.sh"

# `launch` writes a new log: the events in $SIMCTL_CHILD_EVENTS ("type;type…", each `{"type":…}`), or none when
# it is empty (a crash before the first line). Each new log is a second newer than the last, as an app's are.
STUB = r"""#!/bin/bash
case $1 in
  terminate) exit 0 ;;
  launch)
    n=$(( $(cat "$LOGS/../n" 2>/dev/null || echo 0) + 1 )); echo $n > "$LOGS/../n"
    [ -n "${SIMCTL_CHILD_EVENTS:-}" ] || exit 0
    f="$LOGS/app-$n.jsonl"
    IFS=';' read -ra evs <<<"$SIMCTL_CHILD_EVENTS"
    for e in "${evs[@]}"; do echo "$e" >> "$f"; done
    touch -t "$(date -v+${n}S +%Y%m%d%H%M.%S)" "$f" ;;
esac
"""


def smoke(tmp: Path, body: str, only: str = "", old_log: str = ""):
    docs = tmp / "Documents"
    (docs / "logs").mkdir(parents=True, exist_ok=True)
    if old_log:
        (docs / "logs/app-0.jsonl").write_text(old_log)
    stub = tmp / "simctl"
    stub.write_text(STUB)
    stub.chmod(0o755)
    script = f'source "{LIB}"\nsmoke_init SIM com.example.app\n{body}\nsmoke_done\n'
    env = {**os.environ, "SMOKE_DOCS": str(docs), "SMOKE_SIMCTL": str(stub), "SMOKE_POLL": "1",
           "LOGS": str(docs / "logs"), "ONLY": only}
    return subprocess.run(["/bin/bash", "-c", script], capture_output=True, text=True, env=env)


REPORT = '{"type":"bug_report","note":"the note"}'
FINISHED = '{"type":"selftest_finished"}'
ERROR = '{"type":"error","where":"save","message":"disk full"}'


def test_a_passing_check(tmp_path):
    out = smoke(tmp_path, f"""
      launch 'EVENTS={REPORT};{FINISHED}'
      wait_for bug_report 3
      require_event bug_report 'select(.note == "the note")' "report has the note"
      require_event selftest_finished
      fail_on_errors""")
    assert out.returncode == 0, out.stdout + out.stderr
    assert "ok    report has the note" in out.stdout
    assert "smoke: all passed" in out.stdout


def test_an_old_log_never_satisfies_a_new_launch(tmp_path):
    out = smoke(tmp_path, "launch EVENTS=\nwait_for bug_report 2\nrequire_event bug_report", old_log=REPORT + "\n")
    assert out.returncode == 1
    assert "timed out after 2 s waiting for bug_report" in out.stdout
    assert "FAIL  bug_report: no bug_report in a new log" in out.stdout


def test_a_missing_finish_marker_fails(tmp_path):
    out = smoke(tmp_path, f"launch 'EVENTS={REPORT}'\nwait_for bug_report 3\nrequire_event selftest_finished")
    assert out.returncode == 1
    assert "FAIL  selftest_finished" in out.stdout


def test_any_error_event_fails_even_when_the_feature_passed(tmp_path):
    out = smoke(tmp_path, f"""
      launch 'EVENTS={REPORT};{ERROR}'
      wait_for bug_report 3
      require_event bug_report
      fail_on_errors check_report""")
    assert out.returncode == 1
    assert "ok    bug_report" in out.stdout
    assert "FAIL  check_report: error events in app-1.jsonl" in out.stdout
    assert "      save: disk full" in out.stdout


def test_stash_puts_data_back_even_when_the_run_is_cut_short(tmp_path):
    docs = tmp_path / "Documents"
    (docs / "workouts").mkdir(parents=True)
    (docs / "workouts/w1.json").write_text("{}")
    out = smoke(tmp_path, """
      stash workouts recents/index.json
      [ -e "$SMOKE_DOCS/workouts" ] && echo "still there"
      mkdir -p "$SMOKE_DOCS/recents"; echo made > "$SMOKE_DOCS/recents/index.json"
      exit 3""")
    assert out.returncode == 3
    assert "still there" not in out.stdout
    assert (docs / "workouts/w1.json").exists()
    assert not (docs / "recents/index.json").exists()  # absent before the check, absent after
    assert not (docs / ".smoke-stash").exists()


def test_a_stash_left_by_a_killed_run_is_put_back_first(tmp_path):
    docs = tmp_path / "Documents"
    (docs / ".smoke-stash").mkdir(parents=True)
    (docs / ".smoke-stash/.paths").write_text("workouts.json\n")
    (docs / ".smoke-stash/workouts.json").write_text("mine")
    (docs / "workouts.json").write_text("the check's")
    out = smoke(tmp_path, "stash workouts.json\nunstash")
    assert out.returncode == 0, out.stderr
    assert (docs / "workouts.json").read_text() == "mine"


def test_only_runs_the_matching_checks(tmp_path):
    out = smoke(tmp_path, "a_check() { echo ran-a; }\nb_check() { echo ran-b; }\nrun a_check\nrun b_check", only="b_")
    assert "ran-a" not in out.stdout
    assert "ran-b" in out.stdout
