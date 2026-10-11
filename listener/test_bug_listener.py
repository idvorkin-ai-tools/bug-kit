"""Host tests for bug-listener's pure parts: uv run --with typer --with pytest pytest listener/"""

import importlib.machinery
import importlib.util
import json
from pathlib import Path

import pytest

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


@pytest.fixture
def listener_state(tmp_path, monkeypatch):
    for name, value in {"STATE": tmp_path, "LOG": tmp_path / "listener.log",
                        "SEEN": tmp_path / "seen.json", "INBOX": tmp_path / "inbox.jsonl", "DRY": False}.items():
        monkeypatch.setattr(bl, name, value)
    monkeypatch.setattr(bl, "notify", lambda *args: None)
    return tmp_path


@pytest.mark.parametrize("existing", [
    "<!-- bug:T -->\n<!-- bug-id:A -->",
    "<!-- bug:T -->\n<!-- bug-id:A -->\nThe same problem occurs after opening the settings screen",
])
def test_distinct_ids_are_not_deduped_by_timestamp_or_note(listener_state, monkeypatch, existing):
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (0, json.dumps([{"body": existing}]), ""))
    rec = {"id": "B", "reported_at": "T", "note": "The same problem occurs after opening the settings screen"}
    assert bl.Filer().check({"tracker": {"kind": "github", "repo": "owner/app"}}, rec) is None


@pytest.mark.parametrize("body", ["<!-- bug:T -->", "<!-- bug:T -->\n<!-- bug-id:A -->"])
def test_existing_legacy_and_uuid_markers_are_respected(listener_state, monkeypatch, body):
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (0, json.dumps([{"body": body}]), ""))
    assert bl.Filer().check({"tracker": {"kind": "github", "repo": "owner/app"}},
                           {"id": "A", "reported_at": "T"})[0] == "already_filed"


def test_marker_free_issues_still_match_the_note(listener_state, monkeypatch):
    note = "The timer stopped updating when I opened the settings screen"
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (0, json.dumps([{"body": f"> {note}"}]), ""))
    assert bl.Filer().check({"tracker": {"kind": "github", "repo": "owner/app"}},
                           {"id": "A", "note": note})[0] == "already_filed"


@pytest.mark.parametrize("response", ["not JSON", "{}", '[{"body": 7}]'])
def test_invalid_issue_lookup_stops_filing(listener_state, monkeypatch, response):
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (0, response, ""))
    assert bl.Filer().check({"tracker": {"kind": "github", "repo": "owner/app"}},
                           {"id": "A", "note": "A note"}) == ("error", None)


def test_a_created_issue_is_cached_by_id_without_a_timestamp(listener_state, monkeypatch):
    responses = iter([(0, "[]", ""), (0, "https://github.com/owner/app/issues/1\n", "")])
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: next(responses))
    filer = bl.Filer()
    a = {"name": "app", "tracker": {"kind": "github", "repo": "owner/app"}}
    rec = {"id": "A", "note": "A short note"}
    assert filer.check(a, rec) is None
    assert filer.file(a, rec, "A", {"type": "iPhone", "model": "phone"}, listener_state)[0] == "filed"
    assert filer.check(a, rec)[0] == "already_filed"


@pytest.mark.parametrize("failed_source", ["Documents/bugs/s", "Documents/logs/session.jsonl", None])
def test_poll_retries_required_evidence_and_files_duplicate_lines_once(listener_state, monkeypatch, failed_source):
    dev = {"id": "device-id", "dir": "iphone", "type": "iPhone", "model": "phone"}
    a = {"name": "app", "bundle": "app.bundle", "tracker": {"kind": "none"}, "crash_dir": "Documents/crashes"}
    rec = {"id": "A", "note": "A short note", "folder": "bugs/s", "log": "logs/session.jsonl"}
    monkeypatch.setattr(bl, "list_devices", lambda: [dev])
    monkeypatch.setattr(bl, "probe", lambda dev: {"locked": True})

    def copy(dev, a, source, dest, locked, **kwargs):
        dest.parent.mkdir(parents=True, exist_ok=True)
        if source == "Documents/bugs.jsonl":
            dest.write_text((json.dumps(rec) + "\n") * 2)
        # Crashes may never have occurred, so this missing directory must not block a report.
        return source != failed_source

    monkeypatch.setattr(bl, "copy", copy)
    summary = bl.poll({"apps": [a]}, backfill=True)
    keys = bl.load_seen()["app.bundle|device-id"]["keys"]
    if failed_source:
        assert keys == []
        assert summary["errors"] >= 1
        assert not bl.INBOX.exists()
        # The next poll succeeds and must deliver exactly one report.
        failed_source = None
        bl.poll({"apps": [a]}, backfill=False)
    assert bl.load_seen()["app.bundle|device-id"]["keys"] == ["A"]
    assert len(bl.INBOX.read_text().splitlines()) == 1


@pytest.fixture
def crash_device(listener_state, monkeypatch):
    dev = {"id": "device-id", "dir": "iphone", "type": "iPhone", "model": "phone", "pairing": "paired"}
    app = {"name": "app", "bundle": "app.bundle", "tracker": {"kind": "none"}}
    files = {}
    failures = set()
    monkeypatch.setattr(bl, "list_devices", lambda: [dev])
    monkeypatch.setattr(bl, "probe", lambda dev: {"locked": True})
    def copy(dev, a, source, dest, locked, **kwargs):
        if source in failures:
            return False
        if source == "Documents/crashes":
            dest.mkdir(parents=True, exist_ok=True)
            for name, content in files.items():
                (dest / name).write_text(content)
        elif source == "Documents/logs":
            dest.mkdir(parents=True, exist_ok=True)
            (dest / "previous.jsonl").write_text(json.dumps({
                "type": "session_start", "started": "2026-10-10T00:00:00Z", "build": "1 (2)"}) + "\n")
            (dest / "relaunch.jsonl").write_text(json.dumps({
                "type": "session_start", "started": "2026-10-10T01:00:00Z"}) + "\n")
        return True  # No bug index: crashes must still be discovered.
    monkeypatch.setattr(bl, "copy", copy)
    return {"apps": [app], "poll_seconds": 300}, files, failures


def test_crash_discovery_without_manual_reports_and_rename_dedup(crash_device, listener_state):
    cfg, files, _ = crash_device
    epoch = int(bl.parse_time("2026-10-10T00:01:00Z").timestamp())
    bl.poll(cfg, backfill=False)  # successful empty baseline
    files[f"signal-{epoch}.txt"] = "signal 11\nframe 0\n"
    summary = bl.poll(cfg, backfill=False)
    assert summary["crashes"] == 1
    assert len(bl.INBOX.read_text().splitlines()) == 1
    key = json.loads(bl.INBOX.read_text())["key"]
    files[f"signal-{epoch}.reported.txt"] = files.pop(f"signal-{epoch}.txt")
    bl.poll(cfg, backfill=False)
    assert len(bl.INBOX.read_text().splitlines()) == 1
    assert bl.load_seen()["app.bundle|device-id"]["crash_keys"] == [key]
    assert (listener_state / "app/iphone/crashes" / f"signal-{epoch}.txt").exists()
    metadata = json.loads((listener_state / "app/iphone/crashes" / f"signal-{epoch}.txt.report.json").read_text())
    assert metadata["id"] == key
    assert metadata["log"] == "logs/previous.jsonl"


def test_crashes_baseline_separately_from_older_manual_state(crash_device, listener_state):
    cfg, files, _ = crash_device
    bl.save_seen({"app.bundle|device-id": {"keys": [], "since": "old"}})
    files["exception-1791590400.txt"] = "exception NSRangeException\n"
    result = bl.poll(cfg, backfill=False)
    assert result["baselined"] == 1
    assert not bl.INBOX.exists()


def test_crash_backfill_retries_after_log_copy_failure(crash_device, listener_state):
    cfg, files, failures = crash_device
    files["signal-1791590400.txt"] = "signal 6\n"
    failures.update({"Documents/logs", "Documents/bugs.jsonl"})
    bl.poll(cfg, backfill=True)
    entry = bl.load_seen()["app.bundle|device-id"]
    assert entry["crash_keys"] == []
    assert next(iter(entry["pending"].values()))["reason"] == "crash_logs"
    assert not bl.INBOX.exists()
    failures.clear()
    bl.poll(cfg, backfill=False)
    assert len(bl.INBOX.read_text().splitlines()) == 1
    assert not bl.load_seen()["app.bundle|device-id"]["pending"]


def test_crash_session_uses_preceding_start_not_relaunch(crash_device, listener_state, monkeypatch):
    cfg, files, _ = crash_device
    epoch = int(bl.parse_time("2026-10-10T00:01:00Z").timestamp())
    files[f"signal-{epoch}.txt"] = "signal 11\n"
    records = []
    monkeypatch.setattr(bl.Filer, "file", lambda self, a, rec, *args: (records.append(rec) or ("none", "inbox-only")))
    bl.poll(cfg, backfill=True)
    assert records[0]["log"] == "logs/previous.jsonl"
    assert records[0]["session_t_ms"] == 60000
    assert records[0]["build"] == "1 (2)"
    assert records[0]["context"]["session_match"].startswith("inferred")


def test_metrickit_hangs_file_without_claiming_delivery_is_crash_time(crash_device, listener_state, monkeypatch):
    cfg, files, _ = crash_device
    files["20261010-020000.json"] = json.dumps({"hangDiagnostics": [{"callStackTree": {}}]})
    records = []
    monkeypatch.setattr(bl.Filer, "file", lambda self, a, rec, *args: (records.append(rec) or ("none", "inbox-only")))
    bl.poll(cfg, backfill=True)
    assert records[0]["context"]["hang_count"] == 1
    assert "log" not in records[0]
    assert records[0]["context"]["time_basis"] == "payload interval end"
    assert records[0]["context"]["session_match"] == "unknown"


def test_dry_run_crashes_leave_delivery_and_health_state_unchanged(crash_device, listener_state, monkeypatch):
    cfg, files, _ = crash_device
    files["signal-1791590400.txt"] = "signal 6\n"
    monkeypatch.setattr(bl, "DRY", True)
    result = bl.poll(cfg, backfill=True)
    assert result["would_file"] == 1
    assert not bl.SEEN.exists() and not bl.INBOX.exists()
    assert not (listener_state / "status.json").exists()


def test_crash_ignores_stale_local_files_after_failed_copy(crash_device, listener_state):
    cfg, files, failures = crash_device
    stale = listener_state / "app/iphone/crashes/signal-1791590400.txt"
    stale.parent.mkdir(parents=True)
    stale.write_text("signal 6\n")
    failures.add("Documents/crashes")
    result = bl.poll(cfg, backfill=True)
    assert result["errors"] == 1
    assert not bl.INBOX.exists()


def test_pending_crash_lookup_retries(crash_device, listener_state, monkeypatch):
    cfg, files, _ = crash_device
    files["signal-1791590400.txt"] = "signal 6\n"
    monkeypatch.setattr(bl.Filer, "check", lambda *args: ("error", None))
    bl.poll(cfg, backfill=True)
    assert next(iter(bl.load_seen()["app.bundle|device-id"]["pending"].values()))["reason"] == "tracker_lookup"
    monkeypatch.setattr(bl.Filer, "check", lambda *args: None)
    bl.poll(cfg, backfill=False)
    assert len(bl.INBOX.read_text().splitlines()) == 1


def test_crash_github_dedupe_never_uses_generic_note(listener_state, monkeypatch):
    note = "Automatic MetricKit diagnostics: 1 crash(es), 0 hang(s)"
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (0, json.dumps([{"body": note}]), ""))
    assert bl.Filer().check({"tracker": {"kind": "github", "repo": "owner/app"}},
                           {"id": "crash:new", "kind": "crash", "note": note}) is None


@pytest.fixture
def cli_config(listener_state):
    path = listener_state / "apps.json"
    path.write_text(json.dumps({"apps": [{"name": "app", "bundle": "b", "tracker": {"kind": "none"}}]}))
    return path


def invoke(args):
    from typer.testing import CliRunner
    return CliRunner().invoke(bl.app, args)


def test_old_cli_flags_still_poll(cli_config, monkeypatch):
    calls = []
    monkeypatch.setattr(bl, "poll", lambda cfg, backfill: (calls.append(backfill) or {"errors": 0}))
    result = invoke(["--config", str(cli_config), "--once", "--dry-run", "--backfill"])
    assert result.exit_code == 0, result.output
    assert calls == [True]


def test_doctor_json_checks_setup_without_filing(cli_config, monkeypatch):
    monkeypatch.setattr(bl, "poll", lambda *args: pytest.fail("doctor must not poll"))
    monkeypatch.setattr(bl, "list_devices", lambda: [])
    monkeypatch.setattr(bl.shutil, "which", lambda name: f"/fake/{name}")
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (0, "", ""))
    result = invoke(["doctor", "--config", str(cli_config), "--json"])
    assert result.exit_code == 0, result.output
    data = json.loads(result.output)
    assert data["ok"]
    assert {c["check"] for c in data["checks"]} >= {"config", "state_directory", "devicectl", "devices", "tracker:app"}
    assert not bl.INBOX.exists() and not bl.SEEN.exists()


def test_doctor_reports_bad_config_and_missing_tools(cli_config, monkeypatch):
    cli_config.write_text('{"apps": [{"name": "../bad", "bundle": "b"}]}')
    monkeypatch.setattr(bl.shutil, "which", lambda name: None)
    result = invoke(["--config", str(cli_config), "doctor", "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert not data["ok"]
    assert any(c["check"] == "config" and c["state"] == "error" for c in data["checks"])


def test_status_reads_pending_and_last_success_without_external_calls(cli_config, monkeypatch):
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: pytest.fail("status must be offline"))
    bl.save_status({"last_poll_completed": bl.now(), "last_successful_poll": bl.now(), "summary": {"reachable": 1, "errors": 0}})
    bl.save_seen({"b|d": {"pending": {"K": {"app": "app", "device": "phone", "key": "K", "reason": "evidence"}}}})
    result = invoke(["status", "--config", str(cli_config), "--json"])
    assert result.exit_code == 1
    data = json.loads(result.output)
    assert not data["stale"] and data["last_successful_poll"]
    assert data["pending"][0]["reason"] == "evidence"


def test_status_distinguishes_healthy_stale_and_never_run(cli_config):
    result = invoke(["status", "--config", str(cli_config), "--json"])
    assert result.exit_code == 1 and json.loads(result.output)["stale"]
    bl.save_status({"last_poll_completed": bl.now(), "summary": {"reachable": 1, "errors": 0}})
    result = invoke(["status", "--config", str(cli_config), "--json"])
    assert result.exit_code == 0 and json.loads(result.output)["ok"]
    bl.save_status({"last_poll_completed": "2000-01-01T00:00:00Z", "summary": {"reachable": 1}})
    result = invoke(["status", "--config", str(cli_config), "--json"])
    assert result.exit_code == 1 and json.loads(result.output)["stale"]


@pytest.mark.parametrize("reachable", [True, False])
def test_offline_paired_device_is_not_a_poll_error(cli_config, monkeypatch, reachable):
    phone = {"id": "phone-id", "dir": "iphone", "type": "iPhone", "model": "phone"}
    ipad = {"id": "ipad-id", "dir": "ipad", "type": "iPad", "model": "tablet"}
    monkeypatch.setattr(bl, "list_devices", lambda: [phone, ipad])
    monkeypatch.setattr(bl, "probe", lambda dev: {"locked": False} if reachable and dev is phone else None)
    monkeypatch.setattr(bl, "copy", lambda *args, **kwargs: True)
    summary = bl.poll({"apps": [{"name": "app", "bundle": "app.bundle", "tracker": {"kind": "none"}}],
                       "poll_seconds": 300}, backfill=False)
    assert summary["errors"] == 0 and summary["reachable"] == int(reachable)
    state = bl.read_status()
    assert [d["reachable"] for d in state["devices"]] == [reachable, False]
    assert ("last_successful_poll" in state) == reachable
    result = invoke(["status", "--config", str(cli_config), "--json"])
    assert result.exit_code == (0 if reachable else 1), result.output
    assert json.loads(result.output)["ok"] == reachable


def test_poll_failure_preserves_last_success_and_records_error(listener_state, monkeypatch):
    bl.save_status({"last_successful_poll": "before"})
    monkeypatch.setattr(bl, "list_devices", lambda: (_ for _ in ()).throw(RuntimeError("device lookup failed")))
    with pytest.raises(RuntimeError):
        bl.poll({"apps": []}, False)
    state = bl.read_status()
    assert state["last_successful_poll"] == "before"
    assert state["last_error"] == "device lookup failed"
    assert not state["in_progress"]


def test_crash_does_not_match_manual_report_at_same_second(listener_state, monkeypatch):
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (0, '[{"body":"<!-- bug:T -->"}]', ""))
    rec = {"id": "crash:new", "kind": "crash", "reported_at": "T", "note": "Automatic crash"}
    a = {"name": "app", "tracker": {"kind": "github", "repo": "owner/app"}}
    assert bl.Filer().check(a, rec) is None
    body = bl.issue_body(rec, rec["id"], {"type": "iPhone", "model": "phone"}, a, listener_state)
    assert "<!-- bug:T -->" not in body
    assert "<!-- bug-id:crash:new -->" in body


@pytest.mark.parametrize("rc,err,expected", [(1, "No such file or directory", True),
    (127, "No such file or directory: xcrun", False), (124, "timed out", False), (1, "device unreachable", False)])
def test_optional_copy_distinguishes_missing_evidence_from_tool_failures(listener_state, monkeypatch, rc, err, expected):
    monkeypatch.setattr(bl, "run", lambda *args, **kwargs: (rc, "", err))
    assert bl.copy({"id": "d", "dir": "phone"}, {"bundle": "b", "name": "app"}, "Documents/crashes",
                   listener_state / "copy", False, allow_missing=True) is expected


@pytest.mark.parametrize("rc", [0, 1])
def test_doctor_checks_github_auth_without_creating_issues(cli_config, monkeypatch, rc):
    cli_config.write_text(json.dumps({"apps": [{"name": "app", "bundle": "b",
        "tracker": {"kind": "github", "repo": "owner/app"}}]}))
    commands = []
    monkeypatch.setattr(bl.shutil, "which", lambda name: f"/fake/{name}" if name != "xcrun" else None)
    def run(command, **kwargs):
        commands.append(command)
        return (rc if command[:3] == ["gh", "auth", "status"] else 0), "[]", ""
    monkeypatch.setattr(bl, "run", run)
    data = bl.doctor_checks(cli_config)
    check = next(c for c in data["checks"] if c["check"] == "tracker:app")
    assert check["state"] == ("ok" if rc == 0 else "error")
    assert all("create" not in command for command in commands)
    assert any(command[:3] == ["gh", "auth", "status"] for command in commands)


def test_status_corrupt_state_exits_two(cli_config, listener_state):
    bl.SEEN.write_text("[]")
    result = invoke(["status", "--config", str(cli_config), "--json"])
    assert result.exit_code == 2
    assert not json.loads(result.output)["ok"]
