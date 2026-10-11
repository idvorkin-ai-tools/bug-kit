import Foundation
import Testing

@testable import BugKit

// MM special sauce: resident memory on the status line, so a leak shows in the log.

@Test func residentMemoryIsReadable() throws {
  let mb = try #require(SessionLog.residentMegabytes())
  #expect(mb > 0 && mb < 100_000)
}

@Test func theStatusLineCarriesRSSWhenAsked() async throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("bugkit-rss-\(UUID().uuidString)")
  defer { try? FileManager.default.removeItem(at: dir) }
  let log = SessionLog(prefix: "app", documents: dir)
  log.status("with_memory", every: 0.05, memory: true) { ["n": 1] }
  log.status("without_memory", every: 0.05) { ["n": 1] }
  try await Task.sleep(for: .milliseconds(300))
  log.flush()
  let lines = try String(contentsOf: log.url, encoding: .utf8).split(separator: "\n")
    .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
  let with = lines.filter { $0["type"] as? String == "with_memory" }
  let without = lines.filter { $0["type"] as? String == "without_memory" }
  #expect(!with.isEmpty && with.allSatisfy { ($0["rss_mb"] as? Int ?? 0) > 0 })
  #expect(!without.isEmpty && without.allSatisfy { $0["rss_mb"] == nil })
}
