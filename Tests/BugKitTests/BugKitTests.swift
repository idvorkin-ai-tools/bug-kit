import Foundation
import Testing

@testable import BugKit

private func tempDocuments() throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bugkit-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private func sample(note: String = "counted 1 rep, there were 13", date: Date = Date(timeIntervalSince1970: 1_791_642_600))
  -> BugReport
{
  BugReport(
    reportedAt: date, app: "Exercise Analyzer", bundle: "com.example.app", build: "1.0 (42)", commit: "ab4f1a5",
    device: "iPhone18,1 iOS 27.0", screen: "playback", note: note, log: "logs/swing-20261010-150000.jsonl",
    sessionTMs: 84_442, screenshot: "bugs/20261010-153000/screen.png", folder: "bugs/20261010-153000",
    files: ["bugs/20261010-153000/clip.mov"],
    context: [
      "exercise": "kettlebell-swing", "playhead": 12.5, "reps": 13, "live": true, "head": ["pan": -15, "tilt": 2.5],
      "segments": ["segment-40.mov"], "camera": nil,
    ])
}

// The format: a report survives the trip through one bugs.jsonl line, context included.
@Test func reportRoundTripsThroughItsLine() throws {
  let r = sample()
  let back = try JSONDecoder().decode(BugReport.self, from: r.jsonLine())
  #expect(back == r)
}

// The keys on disk are the ones the listener and the older apps' file-bugs read.
@Test func lineUsesTheFixedSnakeCaseKeys() throws {
  let obj = try JSONSerialization.jsonObject(with: sample().jsonLine()) as! [String: Any]
  for key in ["id", "reported_at", "app", "bundle", "build", "commit", "device", "screen", "note", "log",
    "screenshot", "context", "session_t_ms", "folder"]
  {
    #expect(obj[key] != nil, "missing \(key)")
  }
  #expect(obj["reported_at"] as? String == "2026-10-10T14:30:00.000Z")
  #expect((obj["context"] as? [String: Any])?["reps"] as? Int == 13)
  // One line: no newline inside, so bugs.jsonl stays one report per line.
  #expect(!(String(data: try sample(note: "two\nlines").jsonLine(), encoding: .utf8)!.contains("\n")))
}

// EA and MM log through their own `[String: Any]` loggers: the Foundation form serializes to the same JSON.
@Test func foundationFormSerializesLikeTheValue() throws {
  let v: JSONValue = ["n": 13, "x": 1.5, "ok": true, "s": "a", "none": nil, "list": [1, "b"], "o": ["k": 2]]
  let viaFoundation = try JSONSerialization.data(withJSONObject: v.foundation, options: [.sortedKeys])
  let enc = JSONEncoder()
  enc.outputFormatting = [.sortedKeys]
  #expect(try JSONDecoder().decode(JSONValue.self, from: viaFoundation) == v)
  #expect(String(data: viaFoundation, encoding: .utf8) == String(data: try enc.encode(v), encoding: .utf8))
}

@Test func reportedAtKeepsMillisecondsAndReadsTheOlderWholeSecondForm() throws {
  let d = Date(timeIntervalSince1970: 1_791_642_600.25)
  #expect(BugReport.formatDate(d) == "2026-10-10T14:30:00.250Z")
  #expect(BugReport.parseDate("2026-10-08T04:00:18Z") == Date(timeIntervalSince1970: 1_791_432_018))
}

// mmn-cfr: reports saved together (Log it and another) finish together; none may overwrite another's line.
@Test func sixtyFourConcurrentAppendsGiveSixtyFourValidLines() throws {
  let docs = try tempDocuments()
  defer { try? FileManager.default.removeItem(at: docs) }
  let store = BugStore(documents: docs)
  DispatchQueue.concurrentPerform(iterations: 64) { i in
    // Notes of different lengths, so a lost or torn write cannot hide behind equal sizes.
    try! store.append(sample(note: "report \(i) " + String(repeating: "x", count: i * 37)))
  }
  let text = try String(contentsOf: store.index, encoding: .utf8)
  let lines = text.split(separator: "\n")
  #expect(lines.count == 64)
  let reports = try lines.map { try JSONDecoder().decode(BugReport.self, from: Data($0.utf8)) }
  #expect(Set(reports.map(\.id)).count == 64)
  #expect(Set(reports.map { $0.note.split(separator: " ")[1] }) == Set((0..<64).map { Substring(String($0)) }))
  let (read, skipped) = try store.readAll()
  #expect(read.count == 64 && skipped == 0)
}

// Two stores on one file (two parts of an app) share the lock.
@Test func twoStoresOnOneIndexDoNotInterleave() throws {
  let docs = try tempDocuments()
  defer { try? FileManager.default.removeItem(at: docs) }
  let a = BugStore(documents: docs), b = BugStore(documents: docs)
  DispatchQueue.concurrentPerform(iterations: 32) { i in try! (i.isMultiple(of: 2) ? a : b).append(sample()) }
  #expect(try a.readAll().reports.count == 32)
}

@Test func readAllCountsLinesItCannotRead() throws {
  let docs = try tempDocuments()
  defer { try? FileManager.default.removeItem(at: docs) }
  let store = BugStore(documents: docs)
  try store.append(sample())
  // An EA-format line from before BugKit: no id, no folder.
  let old = #"{"note":"old","reported_at":"2026-10-08T04:00:18Z","log":"swing-1.jsonl"}"#
  let handle = try FileHandle(forWritingTo: store.index)
  try handle.seekToEnd()
  try handle.write(contentsOf: Data((old + "\n").utf8))
  try handle.close()
  try store.append(sample())
  let (reports, skipped) = try store.readAll()
  #expect(reports.count == 2 && skipped == 1)
}

// MM story 061: two reports in one second each get their own folder.
@Test func folderNamesAreUniqueWithinOneSecond() throws {
  let docs = try tempDocuments()
  defer { try? FileManager.default.removeItem(at: docs) }
  let store = BugStore(documents: docs)
  let d = Date(timeIntervalSince1970: 1_791_642_600)
  let first = try store.makeFolder(for: d).relative
  let second = try store.makeFolder(for: d).relative
  let third = try store.makeFolder(for: d).relative
  #expect(first == "bugs/20261010-143000")
  #expect(second == first + "-2" && third == first + "-3")
}

@Test func concurrentFoldersInOneSecondAreAllDistinct() throws {
  let docs = try tempDocuments()
  defer { try? FileManager.default.removeItem(at: docs) }
  let store = BugStore(documents: docs)
  let d = Date(timeIntervalSince1970: 1_791_642_600)
  let lock = NSLock()
  var names: [String] = []
  DispatchQueue.concurrentPerform(iterations: 32) { _ in
    let name = try! store.makeFolder(for: d).relative
    lock.lock(); names.append(name); lock.unlock()
  }
  #expect(Set(names).count == 32)
}

// The dialog: "Log it and another" saves, then opens a fresh report; "Log it" saves and closes.
@Test func logItAndAnotherSavesThenOpensAFreshReport() {
  var flow = BugReportFlow()
  let opened = flow.open(from: .shake)
  #expect(opened)
  let firstDraft = flow.draft
  flow.note = "  rep 3 isn't a rep \n"
  #expect(flow.log(another: true) == "rep 3 isn't a rep")
  #expect(flow.isPresented)
  #expect(flow.note.isEmpty)
  #expect(flow.draft != firstDraft)
  #expect(flow.savedThisTime == 1)
  flow.note = "and the timer skipped the rest"
  #expect(flow.log(another: false) == "and the timer skipped the rest")
  #expect(!flow.isPresented)
  #expect(flow.savedThisTime == 2)
}

@Test func anEmptyNoteSavesNothingAndKeepsTheDialogUp() {
  var flow = BugReportFlow()
  flow.open(from: .button)
  flow.note = "   \n "
  #expect(!flow.canLog)
  #expect(flow.log(another: false) == nil)
  #expect(flow.log(another: true) == nil)
  #expect(flow.isPresented && flow.savedThisTime == 0)
}

@Test func aSecondShakeWhileTypingKeepsTheNote() {
  var flow = BugReportFlow()
  flow.open(from: .shake)
  flow.note = "half typed"
  let reopened = flow.open(from: .shake)
  #expect(!reopened)
  #expect(flow.note == "half typed")
}

@Test func cancelClosesAndSavesNothing() {
  var flow = BugReportFlow()
  flow.open(from: .key)
  flow.note = "never mind"
  flow.cancel()
  #expect(!flow.isPresented)
  #expect(flow.log(another: false) == nil)
}

// The hooks: the app's logger gets `bug_report`, the extra files land in the report's folder, and the line names them.
@Test func writerSavesTheScreenshotTheExtraFilesTheLineAndTellsTheLogger() async throws {
  let docs = try tempDocuments()
  defer { try? FileManager.default.removeItem(at: docs) }
  let events = EventSink()
  let writer = BugReportWriter(
    store: BugStore(documents: docs),
    info: BugAppInfo(app: "Test", bundle: "com.example.test", build: "1 (1)", commit: "abc1234", device: "Mac"),
    logger: { events.add($0, $1) })
  let report = await writer.save(
    note: "it froze", screen: "home", context: ["mode": "replay"], screenshotPNG: Data([0x89, 0x50]),
    log: ("logs/test-1.jsonl", 1234),
    extraFiles: { folder in
      try Data("clip".utf8).write(to: folder.appendingPathComponent("clip.mov"))
      return ["clip.mov"]
    })
  #expect(report.screenshot == "\(report.folder)/screen.png")
  #expect(report.files == ["\(report.folder)/clip.mov"])
  #expect(FileManager.default.fileExists(atPath: docs.appendingPathComponent(report.files[0]).path))
  #expect(FileManager.default.fileExists(atPath: docs.appendingPathComponent(report.screenshot!).path))
  #expect(try BugStore(documents: docs).readAll().reports == [report])
  #expect(report.log == "logs/test-1.jsonl" && report.sessionTMs == 1234)
  let logged = events.all
  #expect(logged.map(\.0) == ["bug_report"])
  #expect(logged.first?.1["id"] == .string(report.id.uuidString))
  #expect(logged.first?.1["index_written"] == true)
}

@Test func aFailingExtraFilesHookIsLoggedAndTheReportStillSaves() async throws {
  struct Boom: Error {}
  let docs = try tempDocuments()
  defer { try? FileManager.default.removeItem(at: docs) }
  let events = EventSink()
  let writer = BugReportWriter(
    store: BugStore(documents: docs),
    info: BugAppInfo(app: "T", bundle: "b", build: "1", commit: "c", device: "d"), logger: { events.add($0, $1) })
  let report = await writer.save(
    note: "n", screen: "s", context: [:], screenshotPNG: nil, log: nil, extraFiles: { _ in throw Boom() })
  #expect(report.files.isEmpty && report.screenshot == nil)
  #expect(try BugStore(documents: docs).readAll().reports.count == 1)
  #expect(events.all.map(\.0) == ["error", "bug_report"])
  #expect(events.all.first?.1["where"] == "bug_extra_files")
}

private final class EventSink: @unchecked Sendable {
  private let lock = NSLock()
  private var events: [(String, [String: JSONValue])] = []
  func add(_ e: String, _ f: [String: JSONValue]) { lock.lock(); events.append((e, f)); lock.unlock() }
  var all: [(String, [String: JSONValue])] { lock.lock(); defer { lock.unlock() }; return events }
}
