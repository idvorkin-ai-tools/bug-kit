"""with-simulator.sh with a fake simctl; no simulator boots."""

import os
from pathlib import Path
import subprocess
import sys

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "with-simulator.sh"
UDID = "11111111-2222-3333-4444-555555555555"
OTHER = "99999999-2222-3333-4444-555555555555"


def env(tmp_path, booted_other=False):
    simctl = tmp_path / "simctl"
    simctl.write_text(f"#!{sys.executable}\n" + f"""
import os, sys
args = sys.argv[1:]
with open(os.environ['TEST_SIMCTL_CALLS'], 'a') as f:
    f.write(' '.join(args) + '\\n')
if args[:3] == ['list', 'devices', 'available']:
    print('-- iOS 27.0 --')
    print('    test-sim ({UDID}) (Shutdown)')
elif args[:3] == ['list', 'devices', 'booted']:
    if {booted_other!r}:
        print('    other-sim ({OTHER}) (Booted)')
""")
    simctl.chmod(0o755)
    return {**os.environ, "BUG_KIT_SIMCTL": str(simctl), "BUG_KIT_SIM_LOCKS": str(tmp_path / "locks"),
            "TEST_SIMCTL_CALLS": str(tmp_path / "calls")}


def run(tmp_path, *args, **kw):
    return subprocess.run(["/bin/bash", str(SCRIPT), *args], env=kw.pop("env", None) or env(tmp_path),
                          capture_output=True, text=True, timeout=30, **kw)


def calls(tmp_path):
    return (tmp_path / "calls").read_text().splitlines()


def test_the_command_runs_on_the_booted_simulator_and_it_shuts_down_after_a_failure(tmp_path):
    result = run(tmp_path, "test-sim", "--", "sh", "-c", 'echo "udid=$SIM_UDID"; exit 3')
    assert result.returncode == 3, result.stderr
    assert f"udid={UDID}" in result.stdout
    assert f"bootstatus {UDID} -b" in calls(tmp_path)
    assert calls(tmp_path)[-1] == f"shutdown {UDID}"


def test_two_runs_on_one_name_take_turns(tmp_path):
    log = tmp_path / "log"
    body = ["sh", "-c", f'echo start >> "{log}"; sleep 1; echo end >> "{log}"']
    e = env(tmp_path)
    runs = [subprocess.Popen(["/bin/bash", str(SCRIPT), "test-sim", "--", *body], env=e) for _ in range(2)]
    assert [r.wait(timeout=30) for r in runs] == [0, 0]
    assert log.read_text().split() == ["start", "end", "start", "end"]


def test_a_held_name_times_out_with_75_and_runs_nothing(tmp_path):
    e = env(tmp_path)
    (tmp_path / "locks").mkdir()
    holder = subprocess.Popen(["lockf", "-k", str(tmp_path / "locks" / "sim-test-sim.lock"), "sleep", "5"])
    try:
        subprocess.run(["sleep", "0.5"])
        result = run(tmp_path, "test-sim", "--wait", "1", "--", "touch", str(tmp_path / "ran"), env=e)
    finally:
        holder.kill()
    assert result.returncode == 75, result.stderr
    assert "another run held test-sim for 1 s; nothing ran" in result.stderr
    assert not (tmp_path / "ran").exists()


def test_another_booted_simulator_blocks_the_boot(tmp_path):
    result = run(tmp_path, "test-sim", "--wait", "0", "--", "touch", str(tmp_path / "ran"),
                 env=env(tmp_path, booted_other=True))
    assert result.returncode == 75, result.stderr
    assert "another simulator stayed booted" in result.stderr
    assert not (tmp_path / "ran").exists()
    assert not any(c.startswith("bootstatus") for c in calls(tmp_path))


def test_an_unknown_name_exits_2(tmp_path):
    result = run(tmp_path, "no-such-sim", "--", "true")
    assert result.returncode == 2
    assert "no simulator named no-such-sim" in result.stderr
