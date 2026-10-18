// The watch adoption snippet in docs/integration.md#watchos-reporting, compiled as a watch app would against BugKit.
#if os(watchOS)
import BugKit
import SwiftUI

@MainActor func adoptWatchReporting(store: BugStore, info: BugAppInfo, log: SessionLog) async throws -> BugReportWriter {
  let delivery = CloudKitReportDelivery(
    containerIdentifier: "iCloud.com.example.BugKitReports", store: store, logger: log.logger)
  try await delivery.prepare(documents: store.documents) // before exposing the form
  Task { await delivery.start() } // launch; repeat when the watch app becomes active
  return BugReportWriter(store: store, info: info, logger: log.logger, copySessionLog: true, delivery: delivery)
}

@MainActor func watchReportForm(writer: BugReportWriter, log: SessionLog) -> some View {
  WatchBugReportView(session: WatchBugReportSession(writer: writer, screen: "card", context: ["card": .int(7)], log: log))
}
#endif
