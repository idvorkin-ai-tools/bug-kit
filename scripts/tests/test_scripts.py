"""Host tests for scripts/: uv run --with pytest pytest scripts/tests/"""

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
TOOL = ROOT / "scripts" / "log-tool.sh"


def log_file(tmp_path: Path) -> Path:
    lines = [
        {"type": "session_start", "t": 0, "wall": "2026-10-10T15:09:50.000-07:00"},
        {"type": "frame", "t": 100, "wall": "2026-10-10T15:09:50.100-07:00"},
        {"type": "frame", "t": 200, "wall": "2026-10-10T15:09:50.200-07:00"},
        {"type": "bug_report", "t": 9_000, "wall": "2026-10-10T15:09:59.000-07:00"},
        {"type": "error", "t": 20_000, "wall": "2026-10-10T15:10:10.000-07:00", "where": "x"},
        {"type": "status", "t": 60_000, "wall": "2026-10-10T15:10:50.000-07:00"},
    ]
    p = tmp_path / "app-1.jsonl"
    text = "\n".join(json.dumps(l) for l in lines[:3]) + "\n" + '{"type":"broken", "note":"half\n' + "\n".join(
        json.dumps(l) for l in lines[3:]) + "\n"
    p.write_text(text)
    return p


def run(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run([str(TOOL), *args], capture_output=True, text=True)


def types(out: str) -> list[str]:
    return [json.loads(l)["type"] for l in out.splitlines() if l.strip()]


def test_summary_drops_noise_and_counts_it(tmp_path):
    r = run("summary", str(log_file(tmp_path)), "--drop", "frame")
    assert r.returncode == 0
    assert types(r.stdout.split("# dropped")[0]) == ["session_start", "bug_report", "error", "status"]
    assert "# dropped frame: 2" in r.stdout
    assert "not JSON" in r.stderr  # the broken line is named, not fatal


def test_around_a_wall_time(tmp_path):
    r = run("around", str(log_file(tmp_path)), "15:10:01", "10")
    assert types(r.stdout) == ["bug_report", "error"]


def test_around_reads_an_older_log_whose_t_is_the_wall_time(tmp_path):
    p = tmp_path / "mm.jsonl"
    p.write_text(json.dumps({"type": "bug", "t": "2026-10-10T15:10:01.000-07:00"}) + "\n"
                 + json.dumps({"type": "far", "t": "2026-10-10T16:00:00.000-07:00"}) + "\n")
    assert types(run("around", str(p), "15:10:00", "5").stdout) == ["bug"]


def test_at_a_reports_moment(tmp_path):
    assert types(run("at", str(log_file(tmp_path)), "9000", "1").stdout) == ["bug_report"]


def test_errors_and_types(tmp_path):
    p = log_file(tmp_path)
    assert types(run("errors", str(p)).stdout) == ["error"]
    counts = run("types", str(p)).stdout
    assert "2 frame" in counts and "1 bug_report" in counts


def test_a_folder_reads_its_newest_log(tmp_path):
    (tmp_path / "logs").mkdir()
    p = log_file(tmp_path / "logs")
    r = run("types", str(tmp_path))
    assert r.returncode == 0 and "frame" in r.stdout and str(p) in r.stderr
