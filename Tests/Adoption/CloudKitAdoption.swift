// The adoption snippets in docs/integration.md#private-cloudkit-delivery, compiled as an app would against BugKit.
import BugKit
import Foundation

#if os(iOS)
@MainActor func adoptCloudKitDelivery(
  store: BugStore, info: BugAppInfo, log: SessionLog, options: BugReporterOptions
) -> BugReporter {
  let delivery = CloudKitReportDelivery(
    containerIdentifier: "iCloud.com.example.BugKitReports", store: store, logger: log.logger)
  let reporter = BugReporter(
    hooks: BugReporterHooks(sessionLog: { log.position }, logger: log.logger, flushLog: { log.flush() }),
    options: options, store: store, info: info, delivery: delivery)
  Task { await delivery.start() } // launch; repeat on foreground
  return reporter
}
#endif

func saveWithoutReporterUI(store: BugStore, info: BugAppInfo, log: SessionLog, note: String) async -> BugReport {
  let delivery = CloudKitReportDelivery(
    containerIdentifier: "iCloud.com.example.BugKitReports", store: store, logger: log.logger)
  let writer = BugReportWriter(store: store, info: info, logger: log.logger, delivery: delivery)
  let report = await writer.save(note: note, screen: "watch", context: [:], screenshotPNG: nil,
                                 log: log.position, extraFiles: nil)
  return report
}
