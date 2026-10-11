import Foundation

/// An optional delivery queue. Called after the local report has been saved; enqueue must not await a network.
public protocol BugReportDelivery: Sendable {
  func enqueue(_ report: BugReport, documents: URL) async throws
}

/// The immutable wire payload carried by a CloudKit asset. Paths remain relative to Documents.
struct CloudReportPayload: Codable, Sendable {
  var version = 1
  let report: BugReport
  let files: [String: Data]
  static let maxFileBytes = 20_000_000
  static let maxEncodedBytes = 30_000_000

  static func fileURL(_ path: String, under root: URL) throws -> URL {
    let parts = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !parts.isEmpty, !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
          !path.contains("\\"), !path.contains("\0") else { throw CloudDeliveryError.invalidPath }
    let base = root.resolvingSymlinksInPath().standardizedFileURL
    let url = base.appendingPathComponent(path).resolvingSymlinksInPath().standardizedFileURL
    guard url.path.hasPrefix(base.path + "/") else { throw CloudDeliveryError.invalidPath }
    return url
  }

  static func capture(_ report: BugReport, documents: URL) throws -> Self {
    var files: [String: Data] = [:]
    var remaining = maxFileBytes
    let paths = Set(report.files + [report.screenshot, report.log].compactMap { $0 })
    guard paths.count <= 100 else { throw CloudDeliveryError.tooLarge }
    for path in paths.sorted() {
      let url = try fileURL(path, under: documents)
      let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
      guard values.isRegularFile == true else { throw CloudDeliveryError.invalidPath }
      guard let size = values.fileSize, size <= remaining else { throw CloudDeliveryError.tooLarge }
      // Bound the read even if an app log grows while it is being copied.
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      let data = try handle.read(upToCount: remaining + 1) ?? Data()
      guard data.count <= remaining else { throw CloudDeliveryError.tooLarge }
      remaining -= data.count
      files[path] = data
    }
    return Self(report: report, files: files)
  }

  func encoded() throws -> Data {
    let data = try JSONEncoder().encode(self)
    guard data.count <= Self.maxEncodedBytes else { throw CloudDeliveryError.tooLarge }
    return data
  }

  static func read(_ url: URL) throws -> Self {
    let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= maxEncodedBytes else { throw CloudDeliveryError.tooLarge }
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    let data = try handle.read(upToCount: maxEncodedBytes + 1) ?? Data()
    guard data.count <= maxEncodedBytes else { throw CloudDeliveryError.tooLarge }
    let value = try JSONDecoder().decode(Self.self, from: data)
    guard value.version == 1, value.files.count <= 100,
          value.files.values.reduce(0, { $0 + $1.count }) <= maxFileBytes else {
      throw CloudDeliveryError.invalidPayload
    }
    let expected = Set(value.report.files + [value.report.screenshot, value.report.log].compactMap { $0 })
    guard expected == Set(value.files.keys) else { throw CloudDeliveryError.invalidPayload }
    return value
  }

  /// Publish the complete folder with one rename, so the listener never sees partially downloaded evidence.
  func install(in root: URL) throws -> URL {
    let destination = root.appendingPathComponent(report.id.uuidString)
    if Self.isComplete(destination) { return destination }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let stage = root.appendingPathComponent(".\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: stage) }
    let documents = stage.appendingPathComponent("Documents")
    try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
    for (path, data) in files {
      let url = try Self.fileURL(path, under: documents)
      try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    }
    try report.jsonLine().write(to: stage.appendingPathComponent("report.json"), options: .atomic)
    let lengths = files.mapValues { $0.count }
    try JSONEncoder().encode(lengths).write(to: stage.appendingPathComponent("files.json"), options: .atomic)
    let backup = root.appendingPathComponent(".old-\(UUID().uuidString)")
    let existed = FileManager.default.fileExists(atPath: destination.path)
    if existed { try FileManager.default.moveItem(at: destination, to: backup) }
    do { try FileManager.default.moveItem(at: stage, to: destination) }
    catch {
      if existed { try? FileManager.default.moveItem(at: backup, to: destination) }
      throw error
    }
    if existed { try? FileManager.default.removeItem(at: backup) }
    return destination
  }

  static func isComplete(_ destination: URL) -> Bool {
    do {
      guard try destination.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
            try destination.appendingPathComponent("Documents").resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { return false }
      let report = try JSONDecoder().decode(BugReport.self, from: Data(contentsOf: destination.appendingPathComponent("report.json")))
      guard destination.lastPathComponent == report.id.uuidString else { return false }
      let sizes = try JSONDecoder().decode([String: Int].self, from: Data(contentsOf: destination.appendingPathComponent("files.json")))
      let expected = Set(report.files + [report.screenshot, report.log].compactMap { $0 })
      guard expected == Set(sizes.keys) else { return false }
      for (path, size) in sizes {
        let url = try fileURL(path, under: destination.appendingPathComponent("Documents"))
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true, values.fileSize == size else { return false }
      }
      return true
    } catch { return false }
  }
}

public enum CloudDeliveryError: Error, Equatable, Sendable {
  case invalidPath, invalidPayload, tooLarge, wrongStore, accountUnavailable, accountChanged
}

protocol CloudReportTransport: Sendable {
  func accountID() async throws -> String
  func upload(_ report: BugReport, payload: URL) async throws
}

/// Durable outbox shared by the native adapter and fake-backed host tests.
actor CloudReportOutbox: BugReportDelivery {
  let store: BugStore
  let root: URL
  let transport: any CloudReportTransport
  let logger: BugLogger
  private var flushing: Task<Int, Error>?

  init(store: BugStore, root: URL, transport: any CloudReportTransport, logger: @escaping BugLogger) {
    self.store = store; self.root = root; self.transport = transport; self.logger = logger
  }

  func enqueue(_ report: BugReport, documents: URL) async throws {
    guard documents.standardizedFileURL == store.documents.standardizedFileURL else {
      throw CloudDeliveryError.wrongStore
    }
    try stage(report)
    Task { _ = try? await self.flush() }
  }

  private var pending: URL { root.appendingPathComponent("pending") }
  private var sent: URL { root.appendingPathComponent("sent") }
  private func stage(_ report: BugReport) throws {
    let name = report.id.uuidString + ".json"
    guard !FileManager.default.fileExists(atPath: sent.appendingPathComponent(name).path),
          !FileManager.default.fileExists(atPath: pending.appendingPathComponent(name).path) else { return }
    let data = try CloudReportPayload.capture(report, documents: store.documents).encoded()
    try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
    try data.write(to: pending.appendingPathComponent(name), options: .atomic)
  }

  /// Resume persisted work and enqueue locally saved reports that could not be staged earlier.
  /// Call at app launch/foreground or when connectivity returns. One upload pass is shared by concurrent calls.
  func flush() async throws -> Int {
    if let flushing { return try await flushing.value }
    let task = Task { try await self.drain() }
    flushing = task
    defer { flushing = nil }
    return try await task.value
  }

  private func drain() async throws -> Int {
    // Account switches must not silently deliver an old account's reports to the new account.
    let account = try await transport.accountID()
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let binding = root.appendingPathComponent("account.txt")
    if FileManager.default.fileExists(atPath: binding.path) {
      guard try String(contentsOf: binding, encoding: .utf8) == account else {
        throw CloudDeliveryError.accountChanged
      }
    } else { try Data(account.utf8).write(to: binding, options: .atomic) }
    for report in try store.readAll().reports {
      do { try stage(report) }
      catch {
        logger("bug_delivery_pending", ["id": .string(report.id.uuidString), "transport": "cloudkit",
                                        "reason": "evidence could not be staged"])
      }
    }
    var count = 0
    while count < 100 {
      let urls = (try? FileManager.default.contentsOfDirectory(at: pending, includingPropertiesForKeys: nil)) ?? []
      guard let url = urls.filter({ $0.pathExtension == "json" }).sorted(by: { $0.path < $1.path }).first else { break }
      let payload = try CloudReportPayload.read(url)
      guard try await transport.accountID() == account else { throw CloudDeliveryError.accountChanged }
      do { try await transport.upload(payload.report, payload: url) }
      catch {
        logger("bug_delivery_pending", ["id": .string(payload.report.id.uuidString), "transport": "cloudkit"])
        throw error
      }
      try FileManager.default.createDirectory(at: sent, withIntermediateDirectories: true)
      // Receipt first: a crash before removing the payload cannot lose a pending report.
      try Data().write(to: sent.appendingPathComponent(url.lastPathComponent), options: .atomic)
      try FileManager.default.removeItem(at: url)
      logger("bug_delivery_uploaded", ["id": .string(payload.report.id.uuidString), "transport": "cloudkit"])
      count += 1
    }
    return count
  }
}
