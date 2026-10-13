import CloudKit
import Foundation

/// Stable, safe fields for the listener. Raw server errors are available only with --diagnostics.
struct CloudKitSyncFailure {
  let code: Int
  let reason: String
  let hint: String?

  init(_ error: any Error) {
    let ns = error as NSError
    code = (error as? CKError)?.errorCode ?? ns.code
    let details = ns.localizedDescription
    if ns.domain == CKErrorDomain, code == CKError.Code.invalidArguments.rawValue,
       details.contains("recordName"), details.localizedCaseInsensitiveContains("not marked queryable") {
      reason = "missing_query_index"
      hint = "CloudKit Console: select the configured container and environment, Schema > Indexes > BugKitReport > Add Basic Index > recordName > Queryable > Save."
    } else {
      reason = "sync_failed"
      hint = nil
    }
  }
}

/// Explicit local diagnostics may contain private server/account identifiers; do not publish this output.
func cloudKitErrorDetails(_ error: any Error) -> String {
  let ns = error as NSError
  return "CloudKit error: \(String(reflecting: error))\nNSError domain=\(ns.domain) code=\(ns.code)\nServer message: \(ns.localizedDescription)\nUser info: \(ns.userInfo)"
}
