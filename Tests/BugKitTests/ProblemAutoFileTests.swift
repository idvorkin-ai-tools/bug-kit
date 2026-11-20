import Foundation
import Testing

@testable import BugKit

// Story 019 (#119): an error shown to the person files a report by itself, once per context per window, unless the
// app opts the context out; an extension's report is handed to its app through an app-group store.

private final class Log: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [(String, [String: JSONValue])] = []
  var logger: BugLogger { { [self] e, f in lock.lock(); items.append((e, f)); lock.unlock() } }
  func fields(_ name: String) -> [[String: JSONValue]] {
    lock.lock(); defer { lock.unlock() }
    return items.filter { $0.0 == name }.map(\.1)
  }
}

private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_791_000_000)
  var now: Date { lock.lock(); defer { lock.unlock() }; return value }
  func advance(_ s: TimeInterval) { lock.lock(); value += s; lock.unlock() }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var n = 0
  func bump() { lock.lock(); n += 1; lock.unlock() }
  var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private actor RecordingDelivery: BugReportDelivery {
  private(set) var prepared: [URL] = []
  private(set) var enqueued: [UUID] = []
  func prepare(documents: URL) async throws { prepared.append(documents) }
  func enqueue(_ report: BugReport, documents: URL) async throws { enqueued.append(report.id) }
}

private let appInfo = BugAppInfo(
  app: "Demo", bundle: "com.example.demo", build: "1.0 (1)", commit: "abc1234", device: "iPhone18,1")
private let extensionInfo = BugAppInfo(
  app: "Demo Share", bundle: "com.example.demo.share", build: "1.0 (1)", commit: "abc1234", device: "iPhone18,1")

private func temporaryFolder(_ name: String) throws -> URL {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent("bugkit-\(name)-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  return url
}

private let problem = BugProblem(
  message: "Voice input could not start", context: "ShareCard.dictation", build: "1.0 (1) abc1234",
  extra: ["mic_permission": "granted", "code": 1101])

@Suite struct ProblemAutoFileTests {
  fileprivate let log = Log()
  fileprivate let clock = Clock()

  fileprivate func reporter(_ docs: URL, info: BugAppInfo = appInfo) -> BugAutoReporter {
    let clock = clock
    return BugAutoReporter(
      writer: BugReportWriter(store: BugStore(documents: docs), info: info, logger: log.logger), now: { clock.now })
  }

  @Test func anErrorOnScreenFilesAReportForItsContext() async throws {
    let docs = try temporaryFolder("problem")
    let report = try #require(
      await reporter(docs).report(problem: problem, screen: "share", log: ("logs/a.jsonl", 900)))
    #expect(report.source == "auto")
    #expect(report.reason == "ShareCard.dictation")
    #expect(report.note == problem.copyText)
    #expect(report.screen == "share")
    #expect(report.screenshot == nil)
    #expect(report.sessionTMs == 900)
    #expect(report.context["message"] == "Voice input could not start")
    #expect(report.context["where"] == "ShareCard.dictation")
    #expect(report.context["build"] == "1.0 (1) abc1234")
    #expect(report.context["mic_permission"] == "granted")
    #expect(report.context["code"] == 1101)
    #expect(try BugStore(documents: docs).readAll().reports.map(\.id) == [report.id])
    #expect(log.fields("bug_report_auto").first?["reason"] == "ShareCard.dictation")
  }

  @Test func aContextFilesOncePerWindowWhateverItsMessage() async throws {
    let docs = try temporaryFolder("problem-window")
    let auto = reporter(docs)
    #expect(await auto.report(problem: problem) != nil)
    clock.advance(120)
    var again = problem
    again.message = "Voice input stopped"
    #expect(await auto.report(problem: again) == nil)
    #expect(log.fields("bug_report_auto_skipped").first?["reason"] == "ShareCard.dictation")
    #expect(await auto.report(problem: BugProblem(message: "Saving failed", context: "Home.save")) != nil)
    clock.advance(600)
    #expect(await auto.report(problem: again) != nil)
  }

  @Test func anOptedOutContextFilesNothingAndKeepsItsWindow() async throws {
    let docs = try temporaryFolder("problem-off")
    let auto = reporter(docs)
    let offline = BugProblem(message: "The Mac is not reachable", context: "Chat.offline", autoFile: false)
    #expect(await auto.report(problem: offline) == nil)
    #expect(log.fields("bug_report_auto_skipped") == [["reason": "Chat.offline", "auto_file": false]])
    #expect(try BugStore(documents: docs).readAll().reports.isEmpty)
    var filed = offline
    filed.autoFile = true
    #expect(await auto.report(problem: filed) != nil)
  }

  @Test func theTreeIsCapturedOnlyForAReportThatIsSaved() async throws {
    let docs = try temporaryFolder("problem-tree")
    let auto = reporter(docs)
    let captures = Counter()
    let tree: @MainActor @Sendable () -> BugDiagnosticsSnapshot = {
      captures.bump()
      return BugDiagnosticsSnapshot(accessibility: Data("{\"tree\":1}".utf8))
    }
    let report = try #require(await auto.report(problem: problem, diagnostics: tree))
    #expect(report.files == ["\(report.folder)/accessibility.json"])
    #expect(await auto.report(problem: problem, diagnostics: tree) == nil)
    #expect(captures.value == 1)
  }

  @Test @MainActor func theFilerAnAppSetsFilesThroughItsReporter() async throws {
    let docs = try temporaryFolder("problem-filer")
    let filer = BugProblemFiler.auto(reporter(docs), screen: { "share" })
    await filer.file(problem)
    let reports = try BugStore(documents: docs).readAll().reports
    #expect(reports.map(\.reason) == ["ShareCard.dictation"])
    #expect(reports.map(\.screen) == ["share"])
  }

  @Test func theAppTakesAnExtensionsReportOnceUnderItsOwnName() async throws {
    let group = try temporaryFolder("group")
    let shared = BugStore(documents: group.appendingPathComponent("bugkit-share"))
    try FileManager.default.createDirectory(
      at: shared.documents.appendingPathComponent("logs"), withIntermediateDirectories: true)
    try "{\"type\":\"dictation_error\"}\n".write(
      to: shared.documents.appendingPathComponent("logs/share.jsonl"), atomically: true, encoding: .utf8)
    let extensionAuto = BugAutoReporter(
      writer: BugReportWriter(store: shared, info: extensionInfo, logger: log.logger))
    let tree: @MainActor @Sendable () -> BugDiagnosticsSnapshot = {
      BugDiagnosticsSnapshot(accessibility: Data("{}".utf8))
    }
    let saved = try #require(
      await extensionAuto.report(problem: problem, log: ("logs/share.jsonl", 40), diagnostics: tree))

    let appDocs = try temporaryFolder("app")
    let delivery = RecordingDelivery()
    let writer = BugReportWriter(
      store: BugStore(documents: appDocs), info: appInfo, logger: log.logger, delivery: delivery)
    let taken = await writer.adopt(from: shared)
    #expect(taken.map(\.id) == [saved.id])
    let report = try #require(try writer.store.readAll().reports.first)
    #expect(report.id == saved.id)
    #expect(report.app == "Demo")
    #expect(report.bundle == "com.example.demo")
    #expect(report.context["extension"] == "com.example.demo.share")
    #expect(report.reason == "ShareCard.dictation")
    #expect(report.sessionTMs == 40)
    for path in report.files + [report.log].compactMap({ $0 }) {
      #expect(FileManager.default.fileExists(atPath: appDocs.appendingPathComponent(path).path), "\(path)")
      #expect(path.hasPrefix(report.folder + "/"), "\(path)")
    }
    #expect(
      try String(contentsOf: appDocs.appendingPathComponent(try #require(report.log)), encoding: .utf8)
        .contains("dictation_error"))
    #expect(await delivery.enqueued == [saved.id])
    #expect(log.fields("bug_report_adopted").first?["id"] == .string(saved.id.uuidString))
    #expect(try shared.readAll().reports.isEmpty)
    #expect(await writer.adopt(from: shared).isEmpty)
    #expect(try writer.store.readAll().reports.count == 1)
    // The extension's window survives the take: the same context, a minute later, files nothing.
    let relaunched = BugAutoReporter(writer: BugReportWriter(store: shared, info: extensionInfo, logger: log.logger))
    #expect(await relaunched.report(problem: problem) == nil)
  }

  @Test func aReportAlreadyTakenIsNeverAddedTwice() async throws {
    let group = try temporaryFolder("group-again")
    let shared = BugStore(documents: group.appendingPathComponent("bugkit-share"))
    let saved = try #require(
      await BugAutoReporter(writer: BugReportWriter(store: shared, info: extensionInfo, logger: log.logger))
        .report(problem: problem))
    // A take that stopped after appending (the app was killed) leaves the report in both stores.
    let appDocs = try temporaryFolder("app-again")
    let appStore = BugStore(documents: appDocs)
    try appStore.append(saved)
    let writer = BugReportWriter(store: appStore, info: appInfo, logger: log.logger)
    #expect(await writer.adopt(from: shared).isEmpty)
    #expect(try appStore.readAll().reports.map(\.id) == [saved.id])
    #expect(try shared.readAll().reports.isEmpty)
  }

  @Test func aStoreFolderNotMadeYetStillKeepsTheWindow() async throws {
    // An extension's folder in the group does not exist before its first report.
    let shared = BugStore(documents: try temporaryFolder("fresh").appendingPathComponent("bugkit-share"))
    let writer = BugReportWriter(store: shared, info: extensionInfo, logger: log.logger)
    #expect(await BugAutoReporter(writer: writer).report(problem: problem) != nil)
    #expect(await BugAutoReporter(writer: writer).report(problem: problem) == nil)
    #expect(log.fields("error").isEmpty)
  }

  @Test func noExtensionStoreIsNothingToTake() async throws {
    let group = try temporaryFolder("group-none")
    let writer = BugReportWriter(
      store: BugStore(documents: try temporaryFolder("app-none")), info: appInfo, logger: log.logger)
    #expect(await writer.adopt(from: BugStore(documents: group.appendingPathComponent("bugkit-share"))).isEmpty)
    #expect(log.fields("error").isEmpty)
  }
}
