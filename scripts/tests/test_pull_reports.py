"""pull-reports.sh with a stub xcrun: one fake iPhone whose containers are folders here, one per domain."""

import json
import os
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "pull-reports.sh"

DEVICES = {"result": {"devices": [{"identifier": "core-1", "hardwareProperties": {
    "reality": "physical", "udid": "hw-1", "deviceType": "iPhone", "marketingName": "iPhone 17 Pro"}}]}}

# `devicectl list devices --json-output F` writes the list; `devicectl device copy from … --source S --destination D`
# copies <containers>/<domain type>/<domain identifier>/S to D (a folder lands as D itself, as devicectl does) and
# logs "<domain type> <domain identifier> <source>".
STUB = """#!/bin/bash
if [ "$2" = list ]; then for a; do last=$a; done; cp "{devices}" "$last"; exit 0; fi
while [ $# -gt 0 ]; do case $1 in --source) src=$2; shift;; --destination) dst=$2; shift;;
  --domain-type) type=$2; shift;; --domain-identifier) id=$2; shift;; esac; shift; done
echo "$type $id $src" >> "{copies}"
container="{containers}/$type/$id"
[ -e "$container/$src" ] || {{ echo "error: No such file $src" >&2; exit 1; }}
rm -rf "$dst"; cp -R "$container/$src" "$dst"
"""
GH = """#!/bin/bash
echo "<!-- bug:{filed} -->"
"""
DEFAULT = ("appDataContainer", "com.example.demo")
GROUP = ("appGroupDataContainer", "group.com.example.demo")


def setup(tmp: Path, app: dict, domain=DEFAULT, filed="none"):
    container = tmp / "containers" / domain[0] / domain[1]
    (container / "Documents/logs").mkdir(parents=True)
    (container / "Documents/logs/app-20261010-150000.jsonl").write_text('{"type":"session_start","t":0}\n')
    (container / "Documents/bugs.jsonl").write_text(json.dumps({"reported_at": "2026-10-10T15:00:00.000Z",
                                                                "note": "x"}) + "\n")
    inbox = container / "Documents/Inbox/com.apple.watchconnectivity"
    inbox.mkdir(parents=True)
    (inbox / "set-1.json").write_text("{}")
    (tmp / "devices.json").write_text(json.dumps(DEVICES))
    bin_dir = tmp / "bin"
    bin_dir.mkdir()
    (bin_dir / "xcrun").write_text(STUB.format(devices=tmp / "devices.json", containers=tmp / "containers",
                                               copies=tmp / "copies"))
    (bin_dir / "gh").write_text(GH.format(filed=filed))
    for tool in ("xcrun", "gh"):
        (bin_dir / tool).chmod(0o755)
    config = tmp / "apps.json"
    config.write_text(json.dumps({"apps": [{"name": "demo", "bundle": "com.example.demo", **app}]}))
    env = {**os.environ, "PATH": f"{bin_dir}:{os.environ['PATH']}", "BUG_KIT_CONFIG": str(config),
           "BUG_KIT_ROOT": str(tmp / "out")}
    return env, tmp / "out/demo/iphone-17-pro"


def test_pulls_logs_reports_and_the_extra_folders(tmp_path):
    env, out = setup(tmp_path, {"pull_extra": ["Documents/Inbox/com.apple.watchconnectivity"]})
    run = subprocess.run([str(SCRIPT), "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stderr
    assert (out / "logs/app-20261010-150000.jsonl").exists()
    assert (out / "bugs.jsonl").exists()
    assert (out / "com.apple.watchconnectivity/set-1.json").exists()
    assert "1 logs, 1 reports" in run.stdout


def test_a_missing_extra_folder_is_named_not_fatal(tmp_path):
    env, out = setup(tmp_path, {"pull_extra": ["Documents/Nope"]})
    run = subprocess.run([str(SCRIPT), "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stderr
    assert "Documents/Nope not copied" in run.stdout
    assert (out / "logs").exists()


def test_no_extra_folders_by_default(tmp_path):
    env, out = setup(tmp_path, {})
    run = subprocess.run([str(SCRIPT), "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stderr
    assert not (out / "com.apple.watchconnectivity").exists()


def copied_domains(tmp: Path):
    return {tuple(line.split()[:2]) for line in (tmp / "copies").read_text().splitlines()}


def test_an_app_group_entry_pulls_every_copy_from_the_group(tmp_path):
    extra = "Documents/Inbox/com.apple.watchconnectivity"
    env, out = setup(tmp_path, {"app_group": GROUP[1], "pull_extra": [extra]}, domain=GROUP)
    (tmp_path / "containers" / GROUP[0] / GROUP[1] / "Documents/crashes").mkdir()
    (tmp_path / "containers" / GROUP[0] / GROUP[1] / "Documents/crashes/c.ips").write_text("{}")
    (tmp_path / "containers" / GROUP[0] / GROUP[1] / "Documents/bugs").mkdir()
    run = subprocess.run([str(SCRIPT), "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stderr
    assert copied_domains(tmp_path) == {GROUP}
    sources = [line.split()[2] for line in (tmp_path / "copies").read_text().splitlines()]
    assert sources == ["Documents/bugs.jsonl", "Documents/logs", "Documents/bugs", "Documents/crashes", extra]
    assert (out / "logs/app-20261010-150000.jsonl").exists()
    assert (out / "crashes/c.ips").exists()
    assert (out / "com.apple.watchconnectivity/set-1.json").exists()
    assert "1 logs, 1 reports, 1 crash files" in run.stdout


def test_without_app_group_copies_use_the_app_container(tmp_path):
    env, out = setup(tmp_path, {"pull_extra": ["Documents/Inbox/com.apple.watchconnectivity"]})
    run = subprocess.run([str(SCRIPT), "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stderr
    assert copied_domains(tmp_path) == {DEFAULT}
    assert (out / "bugs.jsonl").exists()


def test_check_lists_unfiled_reports_from_the_group(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, {**github, "app_group": GROUP[1]}, domain=GROUP)
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 1, run.stdout + run.stderr
    assert "new demo iphone-17-pro 2026-10-10T15:00:00.000Z x" in run.stdout.splitlines()
    assert copied_domains(tmp_path) == {GROUP}


def test_check_with_the_report_filed_finds_nothing_new(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, {**github, "app_group": GROUP[1]}, domain=GROUP, filed="2026-10-10T15:00:00.000Z")
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stdout + run.stderr
    assert "no unfiled reports" in run.stdout


# The signed CloudKit reader, stubbed: `--inbox D` installs the reports in CLOUD_REPORTS as D/<id>/report.json and
# prints cloudkit_sync, or fails when CLOUD_FAIL is set (#66).
READER = """#!/bin/bash
while [ $# -gt 0 ]; do case $1 in --inbox) inbox=$2; shift;; esac; shift; done
[ -n "${CLOUD_FAIL:-}" ] && { echo '{"event":"cloudkit_sync","ok":false,"code":9,"reason":"sync_failed"}'; exit 1; }
python3 - "$inbox" <<'PY'
import json, os, pathlib, sys
for rec in json.loads(os.environ.get("CLOUD_REPORTS", "[]")):
    folder = pathlib.Path(sys.argv[1]) / rec["id"]
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "report.json").write_text(json.dumps(rec))
PY
echo '{"ok":true,"event":"cloudkit_sync","downloaded":1}'
"""
CLOUD_ID = "6F1C2B9A-0000-4000-8000-000000000066"


# The listener's shape (listener/apps.example.json, docs/ops/listener.md): apps.json names a separate cloudkit.json by
# a ~ path, and that file's app is a ~ path too. HOME is the test folder, so the reader is found only if both expand.
def with_cloud(tmp: Path, env: dict, reports, fail=False, inline=False, cloud=None):
    reader = tmp / "Applications/Reader.app/Contents/MacOS/BugKitCloudReader"
    reader.parent.mkdir(parents=True)
    reader.write_text(READER)
    reader.chmod(0o755)
    config = json.loads(Path(env["BUG_KIT_CONFIG"]).read_text())
    if cloud is None:
        cloud = {"app": "~/Applications/Reader.app", "container": "iCloud.com.example.BugKitReports",
                 "inbox": "~/listener-inbox", "environment": "Development"}
    if inline:
        config["cloudkit"] = {**cloud, "app": str(tmp / "Applications/Reader.app")}
    else:
        (tmp / ".config/bug-kit").mkdir(parents=True)
        (tmp / ".config/bug-kit/cloudkit.json").write_text(json.dumps(cloud))
        config["cloudkit_config"] = "~/.config/bug-kit/cloudkit.json"
    Path(env["BUG_KIT_CONFIG"]).write_text(json.dumps(config))
    return {**env, "HOME": str(tmp), "CLOUD_REPORTS": json.dumps(reports), **({"CLOUD_FAIL": "1"} if fail else {})}


def test_check_lists_unfiled_cloudkit_reports(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, github, filed="2026-10-10T15:00:00.000Z")
    env = with_cloud(tmp_path, env, [{"id": CLOUD_ID, "bundle": "com.example.demo",
                                      "reported_at": "2026-10-17T19:00:00.000Z", "note": "sent from the phone"}])
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 1, run.stdout + run.stderr
    assert "new demo cloudkit 2026-10-17T19:00:00.000Z sent from the phone" in run.stdout.splitlines()
    assert not (tmp_path / "listener-inbox").exists()  # the listener's own inbox is left to the listener


def test_check_reads_cloudkit_from_an_inline_cloudkit_block(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, github, filed="2026-10-10T15:00:00.000Z")
    env = with_cloud(tmp_path, env, [{"id": CLOUD_ID, "bundle": "com.example.demo",
                                      "reported_at": "2026-10-17T19:00:00.000Z", "note": "inline"}], inline=True)
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 1, run.stdout + run.stderr
    assert "new demo cloudkit 2026-10-17T19:00:00.000Z inline" in run.stdout.splitlines()


def test_check_fails_when_the_cloudkit_config_lacks_a_key(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, github, filed="2026-10-10T15:00:00.000Z")
    env = with_cloud(tmp_path, env, [], cloud={"app": "~/Applications/Reader.app", "environment": "Development"})
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 2, run.stdout + run.stderr
    assert "could not read the CloudKit config" in run.stderr


def test_check_fails_when_the_cloudkit_config_file_is_missing(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, github, filed="2026-10-10T15:00:00.000Z")
    env = with_cloud(tmp_path, env, [])
    (tmp_path / ".config/bug-kit/cloudkit.json").unlink()
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 2, run.stdout + run.stderr
    assert "could not read the CloudKit config" in run.stderr


def test_check_counts_a_cloudkit_report_with_its_id_marker_as_filed(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, github, filed="2026-10-10T15:00:00.000Z -->\n<!-- bug-id:" + CLOUD_ID)
    env = with_cloud(tmp_path, env, [{"id": CLOUD_ID, "bundle": "com.example.demo",
                                      "reported_at": "2026-10-17T19:00:00.000Z", "note": "filed already"}])
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 0, run.stdout + run.stderr
    assert "no unfiled reports" in run.stdout


def test_check_fails_rather_than_reading_clean_when_cloudkit_cannot_be_read(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, github, filed="2026-10-10T15:00:00.000Z")
    env = with_cloud(tmp_path, env, [], fail=True)
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 2, run.stdout + run.stderr
    assert "could not read CloudKit" in run.stderr


def test_check_with_a_stale_listener_does_not_read_clean(tmp_path):
    github = {"tracker": {"kind": "github", "repo": "owner/demo"}}
    env, _ = setup(tmp_path, github, filed="2026-10-10T15:00:00.000Z")
    (tmp_path / "out").mkdir(exist_ok=True)
    (tmp_path / "out/status.json").write_text(json.dumps(
        {"last_poll_completed": "2026-10-17T17:29:00.000Z", "poll_seconds": 300}))
    run = subprocess.run([str(SCRIPT), "--check", "demo"], capture_output=True, text=True, env=env)
    assert run.returncode == 3, run.stdout + run.stderr
    assert "listener's last poll was 2026-10-17T17:29:00.000Z" in run.stdout
