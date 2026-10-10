import Foundation
import Testing

@testable import BugKit

private func tempDir() throws -> URL {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bugkit2-\(UUID().uuidString)")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  return dir
}

private final class Events: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [(String, [String: JSONValue])] = []
  var logger: BugLogger { { [self] e, f in lock.lock(); items.append((e, f)); lock.unlock() } }
  var all: [(String, [String: JSONValue])] { lock.lock(); defer { lock.unlock() }; return items }
  var names: [String] { all.map(\.0) }
}

// MARK: - The gentle shake (CG story 146, #164)

/// A sine on one axis at `hz`, `g` strong, sampled at 50 Hz for `seconds`; returns the first shake's peak.
private func run(_ g: Double, hz: Double, seconds: Double, start: Double = 0, on gesture: inout ShakeGesture) -> Double? {
  var t = start
  while t < start + seconds {
    if let p = gesture.feed(x: 0.05, y: g * sin(2 * .pi * hz * t), z: 0.1, t: t) { return p }
    t += 0.02
  }
  return nil
}

@Test func aQuickLightShakeIsAShake() throws {
  var g = ShakeGesture()
  let peak = try #require(run(1.8, hz: 4, seconds: 1.5, on: &g))  // lighter than iOS's hard shake
  #expect(peak >= 1.5)
}

@Test func onePushIsNotAShake() {
  var g = ShakeGesture()
  var hit = false
  // Setting the phone down: one hard push the same way, then nothing.
  for i in 0..<50 where g.feed(x: 0, y: i < 5 ? -2.5 : 0, z: 0, t: Double(i) * 0.02) != nil { hit = true }
  #expect(!hit)
}

@Test func aSlowSwayAndAWeakJiggleAreNotShakes() {
  var sway = ShakeGesture()
  #expect(run(1.7, hz: 0.5, seconds: 4, on: &sway) == nil)  // walking's swing
  var jiggle = ShakeGesture()
  #expect(run(1.0, hz: 5, seconds: 3, on: &jiggle) == nil)
}

@Test func oneShakeOpensOneSheet() {
  var g = ShakeGesture()
  #expect(run(2, hz: 4, seconds: 1.2, on: &g) != nil)
  #expect(run(2, hz: 4, seconds: 1.0, start: 1.2, on: &g) == nil)  // still shaking inside the cooldown
}

// MARK: - "Log it and another", the recapture style (CG a85e228)

@Test func recaptureClosesThenReopensAFreshReport() {
  var flow = BugReportFlow()
  flow.open(from: .shake)
  flow.note = "first"
  #expect(flow.log(another: true, style: .recapture) == "first")
  #expect(!flow.isPresented && flow.reopenPending)
  let reopened = flow.reopenIfPending()
  #expect(reopened && flow.isPresented && flow.source == .another && flow.note.isEmpty)
  #expect(!flow.reopenPending)
  flow.note = "second"
  #expect(flow.log(another: false, style: .recapture) == "second")
  let again = flow.reopenIfPending()
  #expect(!again && !flow.isPresented)
}

@Test func cancelClearsAPendingReopen() {
  var flow = BugReportFlow()
  flow.open(from: .key)
  flow.note = "x"
  _ = flow.log(another: true, style: .recapture)
  flow.cancel()
  let reopened = flow.reopenIfPending()
  #expect(!reopened)
}

// MARK: - Dictation joins what was typed (CG #239)

@Test func dictatedWordsGoAfterTheTypedNote() {
  #expect(DictationText.merge(before: "", spoken: "timer skipped") == "timer skipped")
  #expect(DictationText.merge(before: " rest  \n", spoken: "timer skipped") == "rest timer skipped")
}

// MARK: - Simulator hooks (EA SWING_BUG, CG GRABBER_BUG / GRABBER_SHAKE_AFTER)

@Test func launchHooksParseNotesAndShakeAfter() {
  let h = BugLaunchHooks.parse(["APP_BUG": "first | second||", "APP_SHAKE_AFTER": "3.5", "OTHER_BUG": "x"], prefix: "APP")
  #expect(h == BugLaunchHooks(notes: ["first", "second"], shakeAfter: 3.5))
  #expect(BugLaunchHooks.parse(["APP_SHAKE_AFTER": "soon"], prefix: "APP").isEmpty)
  #expect(BugLaunchHooks.parse([:], prefix: "APP").isEmpty)
}

// MARK: - The last N seconds of segments (MM story 040)

@Test func recentSegmentsCoverTheLastNinetySeconds() {
  let segs = (0..<30).map { (id: $0, start: Double($0) * 5, end: Double($0 + 1) * 5) }  // 0…150 s
  let picked = RecentSegments.covering(segs, now: 148, seconds: 90, start: \.start, end: \.end)
  #expect(picked.first?.id == 11)  // 55–60 overlaps 58
  #expect(picked.last?.id == 29)
  #expect(picked.count == 19)
  #expect(RecentSegments.covering(segs, now: 10, seconds: 90, start: \.start, end: \.end).map(\.id) == [0, 1, 2])
}

// MARK: - The writer's folder extras (MM story 040)

@Test func writerCopiesTheSessionLogAndWritesReportJSONWhenAsked() async throws {
  let docs = try tempDir()
  defer { try? FileManager.default.removeItem(at: docs) }
  try FileManager.default.createDirectory(at: docs.appendingPathComponent("logs"), withIntermediateDirectories: true)
  try Data("{\"type\":\"session_start\",\"t\":0}\n".utf8).write(to: docs.appendingPathComponent("logs/app-1.jsonl"))
  let events = Events()
  let writer = BugReportWriter(
    store: BugStore(documents: docs), info: BugAppInfo(app: "T", bundle: "b", build: "1", commit: "c", device: "d"),
    logger: events.logger, copySessionLog: true, writeReportJSON: true)
  let report = await writer.save(
    note: "n", screen: "s", context: [:], screenshotPNG: nil, log: ("logs/app-1.jsonl", 5), extraFiles: nil)
  let folder = docs.appendingPathComponent(report.folder)
  #expect(report.files == ["\(report.folder)/session.jsonl"])
  #expect(try String(contentsOf: folder.appendingPathComponent("session.jsonl"), encoding: .utf8).contains("session_start"))
  let back = try JSONDecoder().decode(BugReport.self, from: Data(contentsOf: folder.appendingPathComponent("report.json")))
  #expect(back == report)
  #expect(events.names == ["bug_report"])
}

@Test func aMissingSessionLogIsAnErrorAndTheReportStillSaves() async throws {
  let docs = try tempDir()
  defer { try? FileManager.default.removeItem(at: docs) }
  let events = Events()
  let writer = BugReportWriter(
    store: BugStore(documents: docs), info: BugAppInfo(app: "T", bundle: "b", build: "1", commit: "c", device: "d"),
    logger: events.logger, copySessionLog: true)
  let report = await writer.save(
    note: "n", screen: "s", context: [:], screenshotPNG: nil, log: ("logs/gone.jsonl", 5), extraFiles: nil)
  #expect(report.files.isEmpty)
  #expect(events.names == ["error", "bug_report"])
  #expect(events.all.first?.1["where"] == "bug_session_log")
  #expect(try BugStore(documents: docs).readAll().reports.count == 1)
}

