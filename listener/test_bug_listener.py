"""Host tests for bug-listener's pure parts: uv run --with typer --with pytest pytest listener/"""

import importlib.machinery
import importlib.util
import json
from pathlib import Path

HERE = Path(__file__).parent
loader = importlib.machinery.SourceFileLoader("bug_listener", str(HERE / "bug-listener"))
spec = importlib.util.spec_from_loader("bug_listener", loader)
bl = importlib.util.module_from_spec(spec)
loader.exec_module(bl)


def test_index_tolerates_broken_lines_and_keeps_u2028(tmp_path, monkeypatch):
    monkeypatch.setattr(bl, "STATE", tmp_path)
    monkeypatch.setattr(bl, "LOG", tmp_path / "listener.log")
    good = {"id": "A", "reported_at": "2026-10-10T00:00:00Z", "note": "line sep and \u0085 too"}
    old = {"reported_at": "2026-10-08T04:00:18Z", "note": "fine"}
    # An older app's note with a raw newline: two fragments, neither valid JSON.
    broken = '{"reported_at":"2026-10-09T00:00:00Z","note":"first half\nsecond half"}'
    index = tmp_path / "bugs.jsonl"
    index.write_text(json.dumps(good, ensure_ascii=False) + "\n" + broken + "\n" + json.dumps(old) + "\n\n")
    reports = bl.read_index(index, {"device": "d", "app": "a"})
    assert [k for k, _ in reports] == ["A", "2026-10-08T04:00:18Z"]
    assert reports[0][1]["note"] == good["note"]
    logged = [json.loads(l) for l in (tmp_path / "listener.log").read_text().splitlines()]
    assert [e["event"] for e in logged] == ["line_unreadable", "line_unreadable"]
    assert logged[0]["line"] == 2 and logged[1]["line"] == 3


def test_issue_body_names_the_screenshot_and_carries_both_markers(tmp_path):
    rec = {"id": "X1", "reported_at": "2026-10-10T00:00:00.000Z", "note": "a | b\nc", "screen": "home",
           "screenshot": "bugs/s/screen.png", "log": "logs/app-1.jsonl", "session_t_ms": 5, "context": {"k": 1}}
    dev = {"type": "iPhone", "model": "iPhone 17 Pro", "dir": "iphone-17-pro"}
    body = bl.issue_body(rec, "X1", dev, {"name": "app"}, tmp_path)
    assert "<!-- bug:2026-10-10T00:00:00.000Z -->" in body and "<!-- bug-id:X1 -->" in body
    assert "not uploaded" in body and "![" not in body
    assert "| k | 1 |" in body


def test_titles_skip_blank_lines_and_bullets():
    assert bl.title_of({"note": "\n\n- the timer skipped"}) == "the timer skipped"
    assert bl.title_of({"note": "", "reported_at": "T"}) == "Report from the device, T"


def test_report_keys_fall_back_to_reported_at():
    assert bl.report_key({"id": "U"}, "x") == "U"
    assert bl.report_key({"reported_at": "T"}, "x") == "T"
    assert bl.report_key({}, "x").startswith("sha1:")


AUTO = {"id": "AUTO1", "reported_at": "2026-10-10T12:00:00.000Z", "source": "auto", "reason": "call_failed",
        "note": "Automatic report: call_failed", "screen": "call", "files": ["bugs/x/call.jsonl"],
        "context": {"calls": 3}}
DEV = {"type": "iPhone", "model": "iPhone 17 Pro", "dir": "iphone-17-pro"}


def test_auto_reports_get_their_own_title_body_and_label(tmp_path):
    assert bl.title_of(AUTO) == "Automatic report: call_failed"
    assert bl.labels_of(AUTO) == ["bug", "auto"]
    assert bl.labels_of({"note": "x"}) == ["bug"]
    body = bl.issue_body(AUTO, "AUTO1", DEV, {"name": "app"}, tmp_path)
    assert body.startswith("**Automatic report from the iPhone**")
    assert "| Reason | call_failed |" in body and "<!-- bug-id:AUTO1 -->" in body
    assert "| source |" not in body  # source and reason are fixed fields, not context


def test_auto_reports_are_filed_with_the_auto_label(tmp_path, monkeypatch):
    monkeypatch.setattr(bl, "DRY", False)
    calls = []
    monkeypatch.setattr(bl, "run", lambda cmd, **kw: (calls.append(cmd), (0, "https://example.invalid/1\n", ""))[1])
    app = {"name": "app", "tracker": {"kind": "github", "repo": "owner/app"}}
    assert bl.Filer().file(app, AUTO, "AUTO1", DEV, tmp_path) == ("filed", "https://example.invalid/1")
    cmd = calls[0]
    assert cmd[cmd.index("--title") + 1] == "Automatic report: call_failed"
    assert [cmd[i + 1] for i, a in enumerate(cmd) if a == "--label"] == ["bug", "auto"]


def test_auto_reports_dedupe_by_id_not_by_their_shared_note(monkeypatch):
    filer = bl.Filer()
    filer.filed_markers["owner/app"] = "<!-- bug-id:AUTO1 -->"
    filer.bodies["owner/app"] = "Automatic report: call_failed_while_dialing at the start"
    app = {"name": "app", "tracker": {"kind": "github", "repo": "owner/app"}}
    assert filer.check(app, AUTO) == ("already_filed", "owner/app")
    second = {**AUTO, "id": "AUTO2", "reason": "call_failed_while_dialing",
              "note": "Automatic report: call_failed_while_dialing"}
    assert filer.check(app, second) is None  # the same note as an earlier auto issue is not a duplicate
