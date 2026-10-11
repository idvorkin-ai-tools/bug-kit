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
