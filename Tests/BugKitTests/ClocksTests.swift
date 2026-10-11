import Foundation
import Testing

@testable import BugKit

// MM special sauce: lines carry wall and host-clock time, so "it happened at 15:10" and a camera frame's time both
// land on the right line.

@Test func linesCarryWallAndMonoWhenAsked() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bugkit-clocks-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: dir) }
  let log = SessionLog(prefix: "app", documents: dir, clocks: [.wall, .mono])
  log.event("frame", ["wall": "spoofed", "n": 1])
  log.flush()
  let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n")
  let line = try #require(JSONSerialization.jsonObject(with: Data(lines[1].utf8)) as? [String: Any])
  let wall = try #require(line["wall"] as? String)
  #expect(wall != "spoofed")  // a field cannot replace the clock
  #expect(ISO8601DateFormatter.withMs.date(from: wall) != nil)
  #expect(line["mono"] is Double)
}

@Test func noClocksByDefault() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bugkit-clocks-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: dir) }
  let log = SessionLog(prefix: "app", documents: dir)
  log.flush()
  let first = try String(contentsOf: log.url, encoding: .utf8)
  #expect(!first.contains("\"wall\"") && !first.contains("\"mono\""))
}

@Test func wallStampsKeepTheLocalOffsetAndMilliseconds() {
  let date = Date(timeIntervalSince1970: 1_791_642_600.25)  // 2026-10-10T14:30:00.250Z
  let la = TimeZone(identifier: "America/Los_Angeles")!
  let stamps = SessionLog.stamps([.wall, .mono], wall: date, mono: 12.3456789, timeZone: la)
  #expect(stamps["wall"] == "2026-10-10T07:30:00.250-07:00")
  #expect(stamps["mono"] == .double(12.346))
}

@Test func aFramesHostTimeConvertsToWallTime() {
  let now = Date(timeIntervalSince1970: 1_791_642_600)
  // A frame stamped 2.5 s before "now" on the host clock happened 2.5 s before now on the wall.
  #expect(SessionLog.wall(ofMono: 997.5, now: now, nowMono: 1000) == now.addingTimeInterval(-2.5))
}

extension ISO8601DateFormatter {
  fileprivate static var withMs: ISO8601DateFormatter {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }
}
