"""Reader environment preflight and Development build configuration regressions.

The Swift fixture compiles during validation; run only during a granted build turn.
"""
import json
import plistlib
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
ENVIRONMENT_KEY = "com.apple.developer.icloud-container-environment"


@pytest.fixture(scope="module")
def environment_check(tmp_path_factory):
    folder = tmp_path_factory.mktemp("reader-environment")
    main = folder / "main.swift"
    main.write_text('''import Foundation
let entitlements = try JSONSerialization.jsonObject(with: Data(CommandLine.arguments[1].utf8)) as! [String: Any]
let expected: String? = CommandLine.arguments[2] == "none" ? nil : CommandLine.arguments[2]
print(cloudKitEnvironmentMatches(entitlements, expected: expected))
''')
    executable = folder / "environment-check"
    subprocess.run(["swiftc", "-swift-version", "6",
                    str(ROOT / "Tools/CloudKitReader/Sources/CloudKitSigning.swift"), str(main),
                    "-o", str(executable)], check=True, capture_output=True, text=True)
    return executable


@pytest.mark.parametrize("entitlements,expected,matches", [
    ({}, "Development", True),
    ({}, "Production", False),
    ({ENVIRONMENT_KEY: "Development"}, "Development", True),
    ({ENVIRONMENT_KEY: "Production"}, "Production", True),
    ({ENVIRONMENT_KEY: "Production"}, "Development", False),
    ({ENVIRONMENT_KEY: "Development"}, "Production", False),
    ({ENVIRONMENT_KEY: False}, "Development", False),
    ({ENVIRONMENT_KEY: ["Development"]}, "Development", False),
    ({}, "invalid", False),
    ({}, "none", True),
])
def test_reader_environment_preflight(environment_check, entitlements, expected, matches):
    result = subprocess.run([str(environment_check), json.dumps(entitlements), expected],
                            check=True, capture_output=True, text=True)
    assert result.stdout.strip() == str(matches).lower()


def test_development_entitlements_preserve_cloudkit_container_without_distribution_environment():
    # This plist is itself the signing configuration, not a proxy for implementation behavior.
    with (ROOT / "Tools/CloudKitReader/CloudKitReader.entitlements").open("rb") as source:
        entitlements = plistlib.load(source)
    assert entitlements["com.apple.developer.icloud-services"] == ["CloudKit"]
    assert entitlements["com.apple.developer.icloud-container-identifiers"] == ["$(BUGKIT_CLOUD_CONTAINER)"]
    assert ENVIRONMENT_KEY not in entitlements


def test_development_build_refuses_production_config_before_running_xcode(tmp_path):
    config = tmp_path / "cloudkit.json"
    config.write_text(json.dumps({
        "team": "YOURTEAMID", "bundle": "com.example.BugKitCloudReader",
        "container": "iCloud.com.example.BugKitReports", "environment": "Production",
        "app": str(tmp_path / "Reader.app"),
    }))
    result = subprocess.run([sys.executable, str(ROOT / "scripts/build-cloudkit-reader.py"),
                             "--config", str(config)], capture_output=True, text=True)
    assert result.returncode == 2
    assert "this build uses Apple Development signing" in result.stderr
    assert "Production requires a separately provisioned distribution reader" in result.stderr
    assert not (tmp_path / "Reader.app").exists()


@pytest.fixture(scope="module")
def reader_failure_check(tmp_path_factory):
    folder = tmp_path_factory.mktemp("reader-failure")
    main = folder / "main.swift"
    main.write_text('''import CloudKit
import Foundation
let code = Int(CommandLine.arguments[1])!
let error = NSError(domain: CommandLine.arguments[2], code: code,
                    userInfo: [NSLocalizedDescriptionKey: CommandLine.arguments[3]])
let failure = CloudKitSyncFailure(error)
var result: [String: Any] = ["code": failure.code, "reason": failure.reason]
if let hint = failure.hint { result["hint"] = hint }
if CommandLine.arguments.last == "diagnostics" { result["details"] = cloudKitErrorDetails(error) }
print(String(data: try JSONSerialization.data(withJSONObject: result), encoding: .utf8)!)
''')
    executable = folder / "reader-failure"
    subprocess.run(["swiftc", "-swift-version", "6",
                    str(ROOT / "Tools/CloudKitReader/Sources/CloudKitDiagnostics.swift"), str(main),
                    "-o", str(executable)], check=True, capture_output=True, text=True)
    return executable


@pytest.mark.parametrize("domain,code,message,index", [
    ("CKErrorDomain", 12, "Field 'recordName' is not marked queryable", True),
    ("CKErrorDomain", 12, "Invalid request with private account information", False),
    ("CKErrorDomain", 12, "Field 'bundle' is not marked queryable", False),
    ("CKErrorDomain", 11, "Record type not found", False),
    ("unrelated.domain", 12, "Field 'recordName' is not marked queryable", False),
])
def test_reader_failure_diagnostics_are_actionable_and_sanitized(reader_failure_check, domain, code, message, index):
    result = subprocess.run([str(reader_failure_check), str(code), domain, message],
                            check=True, capture_output=True, text=True)
    failure = json.loads(result.stdout)
    assert failure["code"] == code
    assert failure["reason"] == ("missing_query_index" if index else "sync_failed")
    assert ("hint" in failure) == index
    if index:
        assert "recordName > Queryable > Save" in failure["hint"]
    assert "details" not in failure and "private account" not in result.stdout


def test_full_reader_diagnostics_preserve_server_message_only_when_explicit(reader_failure_check):
    message = "Field 'recordName' is not marked queryable; private fixture context"
    result = subprocess.run([str(reader_failure_check), "12", "CKErrorDomain", message, "diagnostics"],
                            check=True, capture_output=True, text=True)
    details = json.loads(result.stdout)["details"]
    assert message in details and "CKErrorDomain" in details and "code=12" in details
