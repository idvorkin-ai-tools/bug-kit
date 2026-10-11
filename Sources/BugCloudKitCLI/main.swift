import BugKit
import Foundation
#if os(macOS)
import CloudKit

@main struct BugCloudKitCLI {
  static func main() async {
    let args = Array(CommandLine.arguments.dropFirst())
    if args == ["--help"] || args.isEmpty {
      print("Usage: bug-cloudkit --container iCloud.com.example.BugKit --inbox /absolute/path")
      print("Download private reports once. Requires a signed binary with CloudKit entitlements and iCloud login.")
      return
    }
    guard args.count == 4, args[0] == "--container", args[2] == "--inbox",
          args[1].hasPrefix("iCloud."), args[3].hasPrefix("/") else {
      fputs("Invalid arguments. Use --help.\n", stderr); exit(2)
    }
    do {
      let receiver = CloudKitReportReceiver(containerIdentifier: args[1])
      let count = try await receiver.download(to: URL(fileURLWithPath: args[3], isDirectory: true))
      print("{\"downloaded\":\(count)}")
    } catch {
      // CloudKit errors may contain record details: report a code, never the payload or account identifier.
      let code = (error as? CKError)?.errorCode ?? (error as NSError).code
      fputs("CloudKit download failed (code \(code)); local inbox retained.\n", stderr); exit(1)
    }
  }
}
#else
@main struct BugCloudKitCLI {
  static func main() { print("bug-cloudkit requires macOS") }
}
#endif
