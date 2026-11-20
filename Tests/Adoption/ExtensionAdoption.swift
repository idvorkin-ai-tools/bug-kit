// This consumer is compiled with -application-extension in CI. Host UI stays unavailable.
import BugKit
import Foundation

func extensionEvidence(root: URL, info: BugAppInfo) async throws -> BugReport {
  let store = BugStore(documents: root)
  let log = SessionLog(prefix: "extension", documents: root)
  log.event("extension_started", [:])
  log.flush()
  let writer = BugReportWriter(store: store, info: info, logger: log.logger)
  return await writer.save(note: "Extension evidence", screen: "keyboard", context: [:],
                           screenshotPNG: nil, log: log.position, extraFiles: nil)
}

/// Story 019: an extension's errors on screen file into a store in its app group, which the app adopts and uploads.
@MainActor
func extensionProblemFiling(group: URL, info: BugAppInfo) {
  let shared = BugStore(documents: group.appendingPathComponent("bugkit-share", isDirectory: true))
  let log = SessionLog(prefix: "share", documents: shared.documents)
  let auto = BugAutoReporter(writer: BugReportWriter(store: shared, info: info, logger: log.logger))
  BugProblemFiler.current = .auto(auto, screen: { "share" }, sessionLog: { log.position }, flushLog: { log.flush() })
}
