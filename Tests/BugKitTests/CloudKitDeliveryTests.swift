import Foundation
import Testing
@testable import BugKit

private actor FakeCloudTransport: CloudReportTransport {
  var account = "owner"
  var failing = false
  var uploads: [UUID: Data] = [:]
  func accountID() -> String { account }
  func upload(_ report: BugReport, payload: URL) throws {
    if failing { throw CloudDeliveryError.accountUnavailable }
    uploads[report.id] = try Data(contentsOf: payload)
  }
  func setFailing(_ value: Bool) { failing = value }
  func setAccount(_ value: String) { account = value }
  func count() -> Int { uploads.count }
  func data(_ id: UUID) -> Data? { uploads[id] }
}

private struct CloudFixture {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  var documents: URL { root.appendingPathComponent("source") }
  var store: BugStore { BugStore(documents: documents) }
  var outboxRoot: URL { documents.appendingPathComponent("delivery") }
  func outbox(_ transport: FakeCloudTransport) -> CloudReportOutbox {
    CloudReportOutbox(store: store, root: outboxRoot, transport: transport, logger: { _, _ in })
  }
  func report() throws -> BugReport {
    let folder = documents.appendingPathComponent("bugs/sample")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("synthetic screen".utf8).write(to: folder.appendingPathComponent("screen.png"))
    try Data("synthetic interactions".utf8).write(to: folder.appendingPathComponent("interactions.jsonl"))
    return BugReport(app: "fixture", bundle: "local.fixture", build: "1", commit: "fixture", device: "synthetic",
                     screen: "home", note: "fixture note", screenshot: "bugs/sample/screen.png",
                     folder: "bugs/sample", files: ["bugs/sample/interactions.jsonl"])
  }
  func clean() { try? FileManager.default.removeItem(at: root) }
}

@Test func cloudDeliveryRestartsAndRetriesWithoutChangingEvidence() async throws {
  let f = CloudFixture(); defer { f.clean() }
  let transport = FakeCloudTransport(); await transport.setFailing(true)
  let report = try f.report(); try f.store.append(report)
  let queue = f.outbox(transport)
  try await queue.enqueue(report, documents: f.documents)
  do { _ = try await queue.flush(); Issue.record("Upload should fail") } catch {}
  #expect(await transport.count() == 0)
  try Data("later screen".utf8).write(to: f.documents.appendingPathComponent(report.screenshot!))
  await transport.setFailing(false)
  let restarted = f.outbox(transport)
  _ = try await restarted.flush()
  #expect(await transport.count() == 1)
  let data = try #require(await transport.data(report.id))
  let payload = try JSONDecoder().decode(CloudReportPayload.self, from: data)
  #expect(payload.files[report.screenshot!] == Data("synthetic screen".utf8))
  #expect(try await restarted.flush() == 0)
  #expect(try f.store.readAll().reports == [report])
}

@Test func cloudDeliveryStopsWhenAccountChanges() async throws {
  let f = CloudFixture(); defer { f.clean() }
  let transport = FakeCloudTransport()
  let report = try f.report(); try f.store.append(report)
  _ = try await f.outbox(transport).flush()
  await transport.setAccount("different-owner")
  await #expect(throws: CloudDeliveryError.accountChanged) { try await f.outbox(transport).flush() }
  #expect(await transport.count() == 1)
}

@Test func cloudPayloadInstallsCompleteEvidenceAndRepairsMissingFiles() throws {
  let f = CloudFixture(); defer { f.clean() }
  let report = try f.report()
  let payload = try CloudReportPayload.capture(report, documents: f.documents)
  let inbox = f.root.appendingPathComponent("inbox")
  let installed = try payload.install(in: inbox)
  #expect(CloudReportPayload.isComplete(installed))
  let evidence = installed.appendingPathComponent("Documents").appendingPathComponent(report.screenshot!)
  try FileManager.default.removeItem(at: evidence)
  #expect(!CloudReportPayload.isComplete(installed))
  _ = try payload.install(in: inbox)
  #expect(CloudReportPayload.isComplete(installed))
  #expect(try Data(contentsOf: evidence) == payload.files[report.screenshot!])
}

@Test func cloudPayloadRejectsEscapesAndMissingEvidence() throws {
  let f = CloudFixture(); defer { f.clean() }
  var report = try f.report()
  report.files.append("../outside")
  #expect(throws: CloudDeliveryError.invalidPath) { try CloudReportPayload.capture(report, documents: f.documents) }
  report.files = ["bugs/sample/missing.txt"]
  #expect(throws: (any Error).self) { try CloudReportPayload.capture(report, documents: f.documents) }
  let outside = f.root.appendingPathComponent("outside")
  try Data("outside".utf8).write(to: outside)
  let link = f.documents.appendingPathComponent("escape")
  try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
  report.files = ["escape"]
  #expect(throws: CloudDeliveryError.invalidPath) { try CloudReportPayload.capture(report, documents: f.documents) }
}

@Test func cloudDeliveryRecoversSavedReportWhenOneAttachmentIsMissing() async throws {
  let f = CloudFixture(); defer { f.clean() }
  let transport = FakeCloudTransport()
  var bad = try f.report(); bad.files = ["bugs/sample/not-yet.txt"]
  try f.store.append(bad)
  let good = try f.report(); try f.store.append(good)
  let queue = f.outbox(transport)
  #expect(try await queue.flush() == 1)
  #expect(await transport.data(bad.id) == nil)
  try Data("arrived".utf8).write(to: f.documents.appendingPathComponent("bugs/sample/not-yet.txt"))
  #expect(try await queue.flush() == 1)
  #expect(await transport.count() == 2)
}

private actor RejectingDelivery: BugReportDelivery {
  var called = false
  func enqueue(_ report: BugReport, documents: URL) throws { called = true; throw CloudDeliveryError.accountUnavailable }
  func wasCalled() -> Bool { called }
}

@Test func cloudDeliveryFailureDoesNotLoseLocalWriterReport() async throws {
  let f = CloudFixture(); defer { f.clean() }
  let delivery = RejectingDelivery()
  let writer = BugReportWriter(store: f.store,
    info: BugAppInfo(app: "fixture", bundle: "local.fixture", build: "1", commit: "fixture", device: "synthetic"),
    logger: { _, _ in }, delivery: delivery)
  let report = await writer.save(note: "kept locally", screen: "home", context: [:], screenshotPNG: nil,
                                 log: nil, extraFiles: nil)
  #expect(await delivery.wasCalled())
  #expect(try f.store.readAll().reports == [report])
}

private actor LoopbackCloud: CloudReportTransport, CloudReportSource {
  let root: URL
  var available = false
  var saved: [UUID: CloudReportReference] = [:]
  var uploadAttempts = 0
  init(root: URL) { self.root = root }
  func accountID() -> String { "synthetic-owner" }
  nonisolated func retryDelay(for error: any Error, attempt: Int) -> TimeInterval? { 0.01 }
  func upload(_ report: BugReport, payload: URL) throws {
    uploadAttempts += 1
    guard available else { throw CloudDeliveryError.accountUnavailable }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try Data(contentsOf: payload).write(to: root.appendingPathComponent(report.id.uuidString), options: .atomic)
    saved[report.id] = CloudReportReference(id: report.id, bundle: report.bundle)
  }
  func reports() -> [CloudReportReference] { Array(saved.values) }
  func asset(for id: UUID) throws -> CloudReportAsset {
    guard let report = saved[id] else { throw CloudDeliveryError.invalidPayload }
    return CloudReportAsset(bundle: report.bundle, file: root.appendingPathComponent(id.uuidString))
  }
  func connect() { available = true }
  func attempts() -> Int { uploadAttempts }
  func count() -> Int { saved.count }
}

@Test func cloudReportEventuallyReachesMacAfterOfflineSaveWithoutAnotherEnqueue() async throws {
  let f = CloudFixture(); defer { f.clean() }
  let cloud = LoopbackCloud(root: f.root.appendingPathComponent("server"))
  let queue = CloudReportOutbox(store: f.store, root: f.outboxRoot, transport: cloud, logger: { _, _ in })
  let writer = BugReportWriter(store: f.store,
    info: BugAppInfo(app: "fixture", bundle: "local.fixture", build: "1", commit: "fixture", device: "synthetic"),
    logger: { _, _ in }, delivery: queue)
  let report = await writer.save(note: "cellular fixture", screen: "home", context: [:],
                                 screenshotPNG: Data("evidence".utf8), log: nil, extraFiles: nil)
  for _ in 0..<100 where await cloud.attempts() == 0 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(await cloud.attempts() > 0)
  #expect(await cloud.count() == 0)
  await cloud.connect()
  for _ in 0..<100 where await cloud.count() == 0 { try await Task.sleep(for: .milliseconds(10)) }
  #expect(await cloud.count() == 1)
  let mac = f.root.appendingPathComponent("mac")
  let receiver = CloudReportInbox(source: cloud, logger: { _, _ in })
  #expect(try await receiver.download(to: mac) == 1)
  let destination = mac.appendingPathComponent(report.id.uuidString)
  #expect(CloudReportPayload.isComplete(destination))
  #expect(try Data(contentsOf: destination.appendingPathComponent("Documents/" + report.screenshot!)) == Data("evidence".utf8))
  #expect(try await receiver.download(to: mac) == 0)
  #expect(try f.store.readAll().reports == [report])
  await queue.stop()
}

@Test func cloudReceiverFailureIsNotMistakenForMacDeliveryAndRetries() async throws {
  let f = CloudFixture(); defer { f.clean() }
  let cloud = LoopbackCloud(root: f.root.appendingPathComponent("server"))
  await cloud.connect()
  let report = try f.report(); try f.store.append(report)
  _ = try await f.outboxRootQueue(cloud).flush()
  let serverFile = f.root.appendingPathComponent("server/" + report.id.uuidString)
  let bytes = try Data(contentsOf: serverFile)
  try Data("truncated".utf8).write(to: serverFile)
  let mac = f.root.appendingPathComponent("mac")
  let receiver = CloudReportInbox(source: cloud, logger: { _, _ in })
  await #expect(throws: (any Error).self) { try await receiver.download(to: mac) }
  #expect(!CloudReportPayload.isComplete(mac.appendingPathComponent(report.id.uuidString)))
  try bytes.write(to: serverFile)
  #expect(try await receiver.download(to: mac) == 1)
  #expect(CloudReportPayload.isComplete(mac.appendingPathComponent(report.id.uuidString)))
}

private extension CloudFixture {
  func outboxRootQueue(_ transport: any CloudReportTransport) -> CloudReportOutbox {
    CloudReportOutbox(store: store, root: outboxRoot, transport: transport, logger: { _, _ in })
  }
}
