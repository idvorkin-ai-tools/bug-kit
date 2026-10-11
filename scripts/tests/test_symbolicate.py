"""symbolicate.sh against a real dSYM: a tiny arm64 binary built here, and a MetricKit-shaped payload."""

import json
import re
import subprocess
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "symbolicate.sh"
SOURCE = "#include <stdlib.h>\nvoid boom_here(void) { abort(); }\nint main(void) { boom_here(); return 0; }\n"


def build(tmp: Path):
    (tmp / "crashy.c").write_text(SOURCE)
    subprocess.run(["clang", "-g", "-arch", "arm64", "-c", "crashy.c", "-o", "crashy.o"], cwd=tmp, check=True)
    subprocess.run(["clang", "-arch", "arm64", "crashy.o", "-o", "Crashy"], cwd=tmp, check=True)
    subprocess.run(["dsymutil", "Crashy", "-o", "Crashy.dSYM"], cwd=tmp, check=True, capture_output=True)
    uuid = re.search(r"UUID: (\S+)", subprocess.run(
        ["dwarfdump", "--uuid", "Crashy.dSYM"], cwd=tmp, capture_output=True, text=True).stdout).group(1)
    addr = next(int(line.split()[0], 16) for line in subprocess.run(
        ["nm", "Crashy"], cwd=tmp, capture_output=True, text=True).stdout.splitlines() if line.endswith("_boom_here"))
    return uuid, addr - 0x100000000


def payload(tmp: Path, frames):
    crash = {"crashDiagnostics": [{
        "diagnosticMetaData": {"exceptionType": 10, "signal": 6, "terminationReason": "abort"},
        "callStackTree": {"callStacks": [{"threadAttributed": True, "callStackRootFrames": [frames]}]},
    }]}
    path = tmp / "crash.json"
    path.write_text(json.dumps(crash))
    return path


def test_app_frames_get_symbols_and_system_frames_say_so(tmp_path):
    uuid, offset = build(tmp_path)
    frame = {"binaryName": "Crashy", "binaryUUID": uuid.lower(), "address": 1, "offsetIntoBinaryTextSegment": offset + 4,
             "subFrames": [{"binaryName": "libsystem_c.dylib", "binaryUUID": "AAAA", "address": 2,
                            "offsetIntoBinaryTextSegment": 123}]}
    out = subprocess.run([str(SCRIPT), str(payload(tmp_path, frame)), str(tmp_path)], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert "cause: exception 10 signal 6 reason abort" in out.stdout
    assert re.search(r"Crashy\s+boom_here", out.stdout), out.stdout
    assert "libsystem_c.dylib  +123 (system)" in out.stdout


def test_a_dsym_from_another_build_is_not_used(tmp_path):
    _, offset = build(tmp_path)
    frame = {"binaryName": "Crashy", "binaryUUID": "OTHER-BUILD", "address": 1,
             "offsetIntoBinaryTextSegment": offset}
    out = subprocess.run([str(SCRIPT), str(payload(tmp_path, frame)), str(tmp_path / "Crashy.dSYM")],
                         capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    assert "no dSYM for this build" in out.stdout
    assert "boom_here" not in out.stdout


def test_no_dsym_is_an_error(tmp_path):
    path = payload(tmp_path, {"binaryName": "X", "address": 1})
    out = subprocess.run([str(SCRIPT), str(path), str(tmp_path)], capture_output=True, text=True)
    assert out.returncode == 2
    assert "no .dSYM" in out.stderr


def test_multiline_watchdog_reason_does_not_become_frames(tmp_path):
    build(tmp_path)
    frame = {"binaryName": "libsystem_kernel.dylib", "binaryUUID": "SYSTEM", "address": 1,
             "offsetIntoBinaryTextSegment": 123}
    path = payload(tmp_path, frame)
    data = json.loads(path.read_text())
    data["hangDiagnostics"] = data.pop("crashDiagnostics")
    data["hangDiagnostics"][0]["diagnosticMetaData"]["terminationReason"] = (
        "watchdog transgression:\nProcessVisibility: Background\r\nProcessState: Running\nscene-update"
    )
    path.write_text(json.dumps(data))
    out = subprocess.run([str(SCRIPT), str(path), str(tmp_path)], capture_output=True, text=True)
    assert out.returncode == 0, out.stderr
    lines = out.stdout.splitlines()
    assert len([line for line in lines if line.startswith("cause:")]) == 1
    assert [line for line in lines if line.startswith("  ")] == ["  libsystem_kernel.dylib  +123 (system)"]
    assert "ProcessVisibility: Background" in next(line for line in lines if line.startswith("cause:"))
    assert "ProcessState: Running" in next(line for line in lines if line.startswith("cause:"))
