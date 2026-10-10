import Foundation

/// One JSON Lines file per launch: `Documents/logs/<prefix>-<yyyyMMdd-HHmmss>.jsonl`, one event per line,
/// `{"type": "<event>", "t": <ms since launch>, …fields}`. Written as each event comes (no buffer to lose in a
/// crash), in Documents so the Files app shows it and `devicectl` copies it. Optional: an app with its own log
/// passes its logger to `BugReporterHooks` instead.
///
///     let log = SessionLog(prefix: "swing", fields: ["build": "1.0 (42)"])
///     log.event("set_saved", ["reps": 13])
public final class SessionLog: @unchecked Sendable {
  public let url: URL
  public let startedAt: Date
  private let documents: URL
  private let queue = DispatchQueue(label: "bugkit.session-log")
  private var handle: FileHandle?
  private var timers: [DispatchSourceTimer] = []

  /// Opens a new log and writes `session_start` with `fields` (put the device, system and build there).
  public init(
    prefix: String, documents: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0],
    fields: [String: JSONValue] = [:], now: Date = Date()
  ) {
    self.documents = documents
    startedAt = now
    let dir = documents.appendingPathComponent("logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    var candidate = dir.appendingPathComponent("\(prefix)-\(f.string(from: now)).jsonl")
    var n = 2
    while FileManager.default.fileExists(atPath: candidate.path) {  // two launches in one second
      candidate = dir.appendingPathComponent("\(prefix)-\(f.string(from: now))-\(n).jsonl")
      n += 1
    }
    url = candidate
    FileManager.default.createFile(atPath: url.path, contents: nil)
    do {
      handle = try FileHandle(forWritingTo: url)
    } catch {
      // No file, no evidence: say so once where a tethered run can see it.
      print("SessionLog: cannot open \(url.path): \(error)")
    }
    var start = fields
    start["started"] = .string(BugReport.formatDate(now))
    event("session_start", start)
  }

  /// The log's path under Documents (`logs/swing-20261010-150000.jsonl`), as a report names it.
  public var relativePath: String { "logs/\(url.lastPathComponent)" }

  public var msSinceStart: Int { Int(Date().timeIntervalSince(startedAt) * 1000) }

  /// For `BugReporterHooks.sessionLog`.
  public var position: (path: String, tMs: Int) { (relativePath, msSinceStart) }

  /// For `BugReporterHooks.logger`.
  public var logger: BugLogger { { [self] type, fields in event(type, fields) } }

  public func event(_ type: String, _ fields: [String: JSONValue] = [:]) {
    let t = msSinceStart
    queue.async { [self] in
      guard let handle else { return }
      handle.write(Self.line(type: type, t: t, fields: fields))
      handle.write(Data([0x0A]))
    }
  }

  /// Waits for every queued event to reach the file (before copying the log into a report).
  public func flush() { queue.sync {} }

  /// A periodic status line (`type`, every `seconds`): for anything that can go quiet or get stuck, so the minutes
  /// before every report are in the log. Runs until the log is released.
  public func status(_ type: String = "status", every seconds: Double, _ fields: @escaping @Sendable () -> [String: JSONValue]) {
    let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
    timer.schedule(deadline: .now() + seconds, repeating: seconds)
    timer.setEventHandler { [weak self] in self?.event(type, fields()) }
    timer.resume()
    queue.sync { timers.append(timer) }
  }

  deinit { timers.forEach { $0.cancel() } }

  /// One line, no newline. `type` and `t` come after the fields, so a field cannot replace them; a non-finite number
  /// becomes null rather than losing the whole line.
  public static func line(type: String, t: Int, fields: [String: JSONValue]) -> Data {
    var record = fields.mapValues(sanitize)
    record["type"] = .string(type)
    record["t"] = .int(t)
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    if let data = try? enc.encode(record) { return data }
    let fallback: [String: JSONValue] = [
      "type": "error", "t": .int(t), "where": "log", "event": .string(type), "message": "a field JSON cannot carry",
    ]
    return (try? enc.encode(fallback)) ?? Data()
  }

  static func sanitize(_ value: JSONValue) -> JSONValue {
    switch value {
    case .double(let d): return d.isFinite ? value : .null
    case .array(let a): return .array(a.map(sanitize))
    case .object(let o): return .object(o.mapValues(sanitize))
    default: return value
    }
  }
}
