import Foundation

/// Session logs older than 30 days are deleted at launch, except a log that a report in bugs.jsonl names: the
/// evidence for an open report survives (EA #72, CG story 145).
public enum LogRetention {
  public static let retentionSeconds: Double = 30 * 24 * 3600

  /// Names to delete: older than `retention` seconds and not named by a report. The boundary stays (strictly older).
  public static func prune(
    files: [(name: String, age: Double)], referenced: Set<String>, retention: Double = retentionSeconds
  ) -> [String] {
    files.filter { $0.age > retention && !referenced.contains($0.name) }.map(\.name)
  }

  /// The log file names the reports in a bugs.jsonl name. Accepts BugKit's `logs/<name>` paths and the older apps'
  /// bare names. Malformed lines are skipped.
  public static func referencedLogs(bugsJsonl text: String) -> Set<String> {
    var names = Set<String>()
    for line in text.split(separator: "\n") {
      guard let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        let name = record["log"] as? String, !name.isEmpty
      else { continue }
      names.insert((name as NSString).lastPathComponent)
    }
    return names
  }
}

extension BugStore {
  /// Deletes `*.jsonl` in `logs` (default `Documents/logs`) older than `retention`, except logs a report names.
  /// Logs one `logs_pruned` event even when nothing went (count, bytes, kept_for_reports). A bugs.jsonl that exists
  /// but cannot be read means the reported logs are unknown, so nothing is pruned (an `error` says so). A file
  /// whose age cannot be read is never deleted. Run it at launch, after the new session's log is open.
  @discardableResult
  public func pruneLogs(
    in logs: URL? = nil, retention: Double = LogRetention.retentionSeconds, now: Date = Date(),
    logger: BugLogger
  ) -> [String] {
    let dir = logs ?? documents.appendingPathComponent("logs", isDirectory: true)
    var referenced = Set<String>()
    if FileManager.default.fileExists(atPath: index.path) {
      guard let text = try? String(contentsOf: index, encoding: .utf8) else {
        logger("error", ["where": "logs_prune", "message": "bugs.jsonl unreadable; nothing pruned"])
        return []
      }
      referenced = LogRetention.referencedLogs(bugsJsonl: text)
    }
    let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
    let files = ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? [])
      .filter { $0.pathExtension == "jsonl" }
      .compactMap { url -> (name: String, age: Double, size: Int)? in
        guard let values = try? url.resourceValues(forKeys: Set(keys)), let modified = values.contentModificationDate
        else { return nil }
        return (url.lastPathComponent, now.timeIntervalSince(modified), values.fileSize ?? 0)
      }
    let victims = Set(LogRetention.prune(
      files: files.map { (name: $0.name, age: $0.age) }, referenced: referenced, retention: retention))
    var deleted: [String] = []
    var freed = 0
    for file in files where victims.contains(file.name) {
      do {
        try FileManager.default.removeItem(at: dir.appendingPathComponent(file.name))
        deleted.append(file.name)
        freed += file.size
      } catch {
        logger("error", ["where": "logs_prune", "file": .string(file.name), "message": .string("\(error)")])
      }
    }
    let kept = files.filter { $0.age > retention && referenced.contains($0.name) }.count
    logger("logs_pruned", ["count": .int(deleted.count), "bytes": .int(freed), "kept_for_reports": .int(kept)])
    return deleted.sorted()
  }
}
