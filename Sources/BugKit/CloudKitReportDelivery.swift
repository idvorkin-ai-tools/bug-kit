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

  /// Retry pending work after launch, foregrounding, or restored connectivity. Returns uploads this pass.
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
    // A stable UUID and overwrite policy make a retry safe after an uncertain network acknowledgement.
    let result = try await container.privateCloudDatabase.modifyRecords(
      saving: [record], deleting: [], savePolicy: .allKeys, atomically: true)
    guard let saved = result.saveResults[record.recordID] else { throw CloudDeliveryError.invalidPayload }
    _ = try saved.get()
  }
}

/// Downloads private reports to an atomic local inbox for the Mac listener. Requires the same iCloud account
/// and shared container entitlement as the sending apps. Does not file issues or delete cloud records.
public actor CloudKitReportReceiver {
  private let container: CKContainer
  public init(containerIdentifier: String) { container = CKContainer(identifier: containerIdentifier) }

  @discardableResult public func download(to inbox: URL) async throws -> Int {
    guard try await container.accountStatus() == .available else { throw CloudDeliveryError.accountUnavailable }
    let account = try await container.userRecordID().recordName
    try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let binding = inbox.appendingPathComponent("account.txt")
    if FileManager.default.fileExists(atPath: binding.path) {
      guard try String(contentsOf: binding, encoding: .utf8) == account else { throw CloudDeliveryError.accountChanged }
    } else { try Data(account.utf8).write(to: binding, options: .atomic) }
    let database = container.privateCloudDatabase
    let query = CKQuery(recordType: "BugKitReport", predicate: NSPredicate(value: true))
    var page = try await database.records(matching: query, desiredKeys: ["bundle"], resultsLimit: 100)
    var count = 0
    while true {
      for (id, result) in page.matchResults {
        guard let uuid = UUID(uuidString: id.recordName) else { throw CloudDeliveryError.invalidPayload }
        let destination = inbox.appendingPathComponent(uuid.uuidString)
        _ = try result.get()
        if CloudReportPayload.isComplete(destination) { continue }
        guard try await container.userRecordID().recordName == account else { throw CloudDeliveryError.accountChanged }
        let record = try await database.record(for: id)
        guard let asset = record["payload"] as? CKAsset, let url = asset.fileURL else {
          throw CloudDeliveryError.invalidPayload
        }
        let payload = try CloudReportPayload.read(url)
        guard payload.report.id == uuid, payload.report.bundle == record["bundle"] as? String else {
          throw CloudDeliveryError.invalidPayload
        }
        _ = try payload.install(in: inbox)
        count += 1
      }
      guard let cursor = page.queryCursor else { break }
      page = try await database.records(continuingMatchFrom: cursor, desiredKeys: ["bundle"], resultsLimit: 100)
    }
    return count
  }
}
#endif
