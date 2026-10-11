import BugKit
import CloudKit
import Foundation
import Security

@main struct BugCloudKitCLI {
  static func hasProvisionedContainer(_ identifier: String, environment: String? = nil) -> Bool {
    guard Bundle.main.bundleURL.pathExtension == "app",
          FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/embedded.provisionprofile").path) else { return false }
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecCodeCheckValidity(code, [], nil) == errSecSuccess else { return false }
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return false }
    var info: CFDictionary?
    guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
          let values = info as? [String: Any],
          let entitlements = values[kSecCodeInfoEntitlementsDict as String] as? [String: Any] else { return false }
    if let environment, entitlements["com.apple.developer.icloud-container-environment"] as? String != environment { return false }
    return (entitlements["com.apple.developer.icloud-services"] as? [String])?.contains("CloudKit") == true
      && (entitlements["com.apple.developer.icloud-container-identifiers"] as? [String])?.contains(identifier) == true
  }

  static func emit(_ event: String, _ fields: [String: JSONValue]) {
    var record = fields
    record["event"] = .string(event)
    if let data = try? JSONEncoder().encode(record), let line = String(data: data, encoding: .utf8) { print(line) }
  }

  static func main() async {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--help"] || args.isEmpty {
      print("Usage: BugKitCloudReader.app/Contents/MacOS/BugKitCloudReader --container iCloud.com.example.BugKitReports --inbox /absolute/path")
      print("Downloads private reports once. Requires an entitled app with an embedded provisioning profile and iCloud login.")
      print("Signing check only: --check-signing --container iCloud.com.example.BugKitReports")
      return
    }
    if (args.count == 3 || args.count == 5), args[0] == "--check-signing", args[1] == "--container" {
      guard args.count == 3 || (args[3] == "--environment" && ["Development", "Production"].contains(args[4])) else { exit(2) }
      let ok = hasProvisionedContainer(args[2], environment: args.count == 5 ? args[4] : nil)
      print("{\"signing_ok\":\(ok)}")
      exit(ok ? 0 : 1)
    }
    guard (args.count == 4 || args.count == 6), args[0] == "--container", args[2] == "--inbox",
          args[1].hasPrefix("iCloud."), args[3].hasPrefix("/") else {
      FileHandle.standardError.write(Data("Invalid arguments. Use --help.\n".utf8)); exit(2)
    }
    guard args.count == 4 || (args[4] == "--environment" && ["Development", "Production"].contains(args[5])) else { exit(2) }
    guard hasProvisionedContainer(args[1], environment: args.count == 6 ? args[5] : nil) else {
      emit("cloudkit_signing_error", ["reason": "run the provisioned headless app; a bare or unsigned CLI cannot access this container"])
      exit(1)
    }
    do {
      let receiver = CloudKitReportReceiver(containerIdentifier: args[1], logger: { event, fields in emit(event, fields) })
      let count = try await receiver.download(to: URL(fileURLWithPath: args[3], isDirectory: true))
      emit("cloudkit_sync", ["downloaded": .int(count), "ok": true])
    } catch {
      let code = (error as? CKError)?.errorCode ?? (error as NSError).code
      emit("cloudkit_sync", ["ok": false, "code": .int(code)])
      exit(1)
    }
  }
}
