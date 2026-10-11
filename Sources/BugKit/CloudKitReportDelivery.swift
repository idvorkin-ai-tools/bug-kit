#if canImport(CloudKit)
import CloudKit
import CryptoKit
import Foundation

/// Opt-in delivery to the owner's private CloudKit database. The app must carry the container entitlement.
/// Uses the locally saved report index as its outbox; reports/evidence are never deleted from BugStore.
public actor CloudKitReportDelivery: BugReportDelivery {
  private let outbox: CloudReportOutbox

  public init(containerIdentifier: String, store: BugStore = BugStore(), logger: @escaping BugLogger) {
    let name = SHA256.hash(data: Data(containerIdentifier.utf8)).map { String(format: "%02x", $0) }.joined()
    outbox = CloudReportOutbox(
      store: store, root: store.documents.appendingPathComponent("bug-delivery/cloudkit-" + name),
      transport: NativeCloudReportTransport(containerIdentifier: containerIdentifier), logger: logger)
  }

  public func enqueue(_ report: BugReport, documents: URL) async throws {
    try await outbox.enqueue(report, documents: documents)
  }

  /// Start automatic backoff retries and recover saved reports. Call at launch and foreground.
  public func start() async { await outbox.start() }
  /// Stop app-level retry timers; an already submitted long-lived CloudKit operation can still finish.
  public func stop() async { await outbox.stop() }

  /// One upload pass; start() also handles retries after transient failures. Returns uploads this pass.
  @discardableResult public func flush() async throws -> Int { try await outbox.flush() }
}

private struct NativeCloudReportTransport: CloudReportTransport {
  let containerIdentifier: String
  var container: CKContainer { CKContainer(identifier: containerIdentifier) }

  func accountID() async throws -> String {
    guard try await container.accountStatus() == .available else { throw CloudDeliveryError.accountUnavailable }
    return try await container.userRecordID().recordName
  }

  func upload(_ report: BugReport, payload: URL) async throws {
    let record = CKRecord(recordType: "BugKitReport", recordID: CKRecord.ID(recordName: report.id.uuidString))
    record["bundle"] = report.bundle as CKRecordValue
    record["reportedAt"] = report.reportedAt as CKRecordValue
    record["payload"] = CKAsset(fileURL: payload)
    // Persist the daemon operation ID beside immutable evidence; reattach callbacks after app restart.
    let operationFile = payload.deletingPathExtension().appendingPathExtension("operation")
    var restored: CKModifyRecordsOperation?
    if FileManager.default.fileExists(atPath: operationFile.path) {
      let id = try String(contentsOf: operationFile, encoding: .utf8)
      restored = try await container.longLivedOperation(for: id) as? CKModifyRecordsOperation
    }
    let operation = restored ?? CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
    if restored == nil {
      operation.savePolicy = .allKeys
      operation.isAtomic = false
      operation.configuration.allowsCellularAccess = true
      operation.configuration.isLongLived = true
      operation.configuration.qualityOfService = .userInitiated
      operation.configuration.timeoutIntervalForRequest = 60
      operation.configuration.timeoutIntervalForResource = 120
      try Data(operation.operationID.utf8).write(to: operationFile, options: .atomic)
    }
    do {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        operation.modifyRecordsResultBlock = { result in continuation.resume(with: result) }
        container.privateCloudDatabase.add(operation)
      }
      try? FileManager.default.removeItem(at: operationFile)
    } catch {
      try? FileManager.default.removeItem(at: operationFile)
      throw error
    }
  }

  func retryDelay(for error: any Error, attempt: Int) -> TimeInterval? {
    if error as? CloudDeliveryError == .accountUnavailable { return 30 }
    guard let error = error as? CKError else { return nil }
    if let delay = error.retryAfterSeconds { return max(1, delay) }
    if error.code == .partialFailure, let errors = error.partialErrorsByItemID {
      let delays = errors.values.compactMap { retryDelay(for: $0, attempt: attempt) }
      return delays.count == errors.count ? delays.max() : nil
    }
    switch error.code {
    case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
         .zoneBusy, .serverResponseLost, .accountTemporarilyUnavailable, .notAuthenticated:
      return min(300, 5 * pow(2, Double(min(attempt, 6))))
    default: return nil
    }
  }
}

/// Downloads private reports to an atomic local inbox for the Mac listener. Requires the same iCloud account
/// and shared container entitlement as the sending apps. Does not file issues or delete cloud records.
public actor CloudKitReportReceiver {
  private let inbox: CloudReportInbox
  public init(containerIdentifier: String, logger: @escaping BugLogger = { _, _ in }) {
    inbox = CloudReportInbox(source: NativeCloudReportSource(containerIdentifier: containerIdentifier), logger: logger)
  }
  @discardableResult public func download(to directory: URL) async throws -> Int {
    try await inbox.download(to: directory)
  }
}

private struct NativeCloudReportSource: CloudReportSource {
  let containerIdentifier: String
  var container: CKContainer { CKContainer(identifier: containerIdentifier) }

  func accountID() async throws -> String {
    guard try await container.accountStatus() == .available else { throw CloudDeliveryError.accountUnavailable }
    return try await container.userRecordID().recordName
  }

  func reports() async throws -> [CloudReportReference] {
    let database = container.privateCloudDatabase
    let query = CKQuery(recordType: "BugKitReport", predicate: NSPredicate(value: true))
    var page = try await database.records(matching: query, desiredKeys: ["bundle"], resultsLimit: 100)
    var reports: [CloudReportReference] = []
    while true {
      for (id, result) in page.matchResults {
        let record = try result.get()
        guard let uuid = UUID(uuidString: id.recordName), let bundle = record["bundle"] as? String else {
          throw CloudDeliveryError.invalidPayload
        }
        reports.append(CloudReportReference(id: uuid, bundle: bundle))
      }
      guard let cursor = page.queryCursor else { break }
      page = try await database.records(continuingMatchFrom: cursor, desiredKeys: ["bundle"], resultsLimit: 100)
    }
    return reports
  }

  func asset(for id: UUID) async throws -> CloudReportAsset {
    let record = try await container.privateCloudDatabase.record(for: CKRecord.ID(recordName: id.uuidString))
    guard let asset = record["payload"] as? CKAsset, let file = asset.fileURL,
          let bundle = record["bundle"] as? String else { throw CloudDeliveryError.invalidPayload }
    return CloudReportAsset(bundle: bundle, file: file)
  }
}
#endif
