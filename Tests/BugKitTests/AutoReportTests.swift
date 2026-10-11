import Foundation
import Testing

@testable import BugKit

private final class Log: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [(String, [String: JSONValue])] = []
  var logger: BugLogger { { [self] e, f in lock.lock(); items.append((e, f)); lock.unlock() } }
  var all: [(String, [String: JSONValue])] { lock.lock(); defer { lock.unlock() }; return items }
  func fields(_ name: String) -> [[String: JSONValue]] { all.filter { $0.0 == name }.map(\.1) }
}

private final class Clock: @unchecked Sendable {
  private let lock = NSLock()
  private var value = Date(timeIntervalSince1970: 1_791_000_000)
  var now: Date { lock.lock(); defer { lock.unlock() }; return value }
  func advance(_ s: TimeInterval) { lock.lock(); value += s; lock.unlock() }
}

private struct Setup {
  let docs: URL
  let log = Log()
  let clock = Clock()
  var writer: BugReportWriter {
    BugReportWriter(
      store: BugStore(documents: docs),
      info: BugAppInfo(app: "Demo", bundle: "com.example.demo", build: "1.0 (1)", commit: "abc1234", device: "Mac16,12"),
      logger: log.logger)
  }
  func reporter(_ options: BugAutoReportOptions = BugAutoReportOptions()) -> BugAutoReporter {
    let clock = clock
    return BugAutoReporter(writer: writer, options: options, now: { clock.now })
  }
  init() throws {
    docs = FileManager.default.temporaryDirectory.appendingPathComponent("bugkit-auto-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
  }
  func file(_ name: String, _ text: String) throws -> URL {
    let url = docs.appendingPathComponent("src-\(name)")
    try text.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}

@Suite struct AutoReportTests {
  @Test func anAutoReportIsANormalReportMarkedAuto() async throws {
    let s = try Setup()
    let big = try s.file("call.jsonl", "{\"type\":\"call_start\"}\n{\"type\":\"error\"}\n")
    let report = try #require(
      await s.reporter().report(
        reason: "call_failed", screen: "call", context: ["calls": 3], files: [big], log: ("logs/a.jsonl", 1200)))
    #expect(report.source == "auto")
    #expect(report.reason == "call_failed")
    #expect(report.note == "Automatic report: call_failed")
    #expect(report.screenshot == nil)
    #expect(report.files == ["\(report.folder)/src-call.jsonl"])
    #expect(report.sessionTMs == 1200)
    let copied = s.docs.appendingPathComponent(report.files[0])
    #expect(try String(contentsOf: copied, encoding: .utf8).hasSuffix("{\"type\":\"error\"}\n"))

    let lines = try BugStore(documents: s.docs).readAll()
    #expect(lines.reports == [report])
    let line = try String(decoding: report.jsonLine(), as: UTF8.self)
    #expect(line.contains("\"reason\":\"call_failed\"") && line.contains("\"source\":\"auto\""))

    let event = try #require(s.log.fields("bug_report_auto").first)
    #expect(event["reason"] == "call_failed")
    #expect(event["source"] == "auto")
    #expect(s.log.fields("bug_report").isEmpty)
  }

  @Test func aPersonsReportHasNoSourceOrReasonKeys() throws {
    let report = BugReport(app: "A", bundle: "b", build: "1", commit: "c", device: "d", screen: "s", note: "n", folder: "f")
    let line = try String(decoding: report.jsonLine(), as: UTF8.self)
    #expect(!line.contains("source") && !line.contains("reason"))
  }

  @Test func oneReportPerReasonPerWindow() async throws {
    let s = try Setup()
    let auto = s.reporter(BugAutoReportOptions(window: 600))
    #expect(await auto.report(reason: "call_failed") != nil)
    s.clock.advance(60)
    #expect(await auto.report(reason: "call_failed") == nil)
    #expect(await auto.report(reason: "sync_stalled") != nil)  // another reason has its own window
    s.clock.advance(600)
    #expect(await auto.report(reason: "call_failed") != nil)

    let skipped = s.log.fields("bug_report_auto_skipped")
    #expect(skipped.count == 1)
    #expect(skipped.first?["reason"] == "call_failed")
    #expect(skipped.first?["window_s"] == 600)
    #expect(try BugStore(documents: s.docs).readAll().reports.count == 3)
  }

  @Test func theWindowHoldsAcrossARelaunch() async throws {
    let s = try Setup()
    #expect(await s.reporter().report(reason: "call_failed") != nil)
    s.clock.advance(30)
    #expect(await s.reporter().report(reason: "call_failed") == nil)  // a new reporter, as after a relaunch
  }

  @Test func overTheCapALogKeepsItsTailFromALineStart() async throws {
    let s = try Setup()
    let lines = (1...100).map { "{\"n\":\($0)}" }.joined(separator: "\n") + "\n"  // 10 bytes or so a line
    let small = try s.file("a.txt", "12345")
    let big = try s.file("call.jsonl", lines)
    let after = try s.file("z.txt", "never")
    let report = try #require(
      await s.reporter(BugAutoReportOptions(maxBytes: 105)).report(reason: "r", files: [small, big, after]))

    #expect(report.files.map { ($0 as NSString).lastPathComponent } == ["src-a.txt", "src-call.jsonl"])
    let kept = try String(contentsOf: s.docs.appendingPathComponent(report.files[1]), encoding: .utf8)
    #expect(kept.utf8.count <= 100)
    #expect(kept.hasSuffix("{\"n\":100}\n"))
    for line in kept.split(separator: "\n") { #expect(line.hasPrefix("{\"n\":") && line.hasSuffix("}")) }

    let cuts = s.log.fields("bug_report_auto_cut")
    #expect(cuts.count == 2)
    #expect(cuts[0]["file"] == "src-call.jsonl")
    #expect(cuts[0]["kept_bytes"] == .int(kept.utf8.count))
    #expect(cuts[0]["dropped_bytes"] == .int(lines.utf8.count - kept.utf8.count))
    #expect(cuts[1]["file"] == "src-z.txt")
    #expect(cuts[1]["kept_bytes"] == 0)
  }
}
