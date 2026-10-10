import Foundation

/// One bug report: one line of `Documents/bugs.jsonl`. The fixed fields are the same in every app, so one listener
/// and one filer read them all; what differs per app goes in `context`.
///
/// On disk the keys are snake_case (`reported_at`, `session_t_ms`) and `reported_at` is ISO 8601 UTC with
/// milliseconds. The paths (`log`, `screenshot`, `folder`, `files`) are relative to the app's Documents folder.
public struct BugReport: Codable, Equatable, Identifiable, Sendable {
  /// The report's key everywhere: the seen-store, the issue marker, the inbox. Older reports (EA, CG before BugKit)
  /// have no id and are keyed by `reported_at`.
  public var id: UUID
  public var reportedAt: Date
  /// The app's display name and bundle id.
  public var app: String
  public var bundle: String
  /// Version and build number, and the git commit the build came from ("unknown" when not baked in).
  public var build: String
  public var commit: String
  /// Hardware model and OS ("iPhone18,1 iOS 27.0"). Never the device's user-given name.
  public var device: String
  /// The screen the report was made from, as the app names it.
  public var screen: String
  public var note: String
  /// The session log's path under Documents (`logs/swing-20261008-052700.jsonl`), so a reader jumps from the report
  /// to the log; nil when the app has none.
  public var log: String?
  /// Milliseconds since the session log began: the moment, so `jq 'select(.t > N-3000 and .t < N+3000)'` lands on it.
  public var sessionTMs: Int?
  /// The screenshot taken before the dialog appeared, under `folder`; nil when the capture failed.
  public var screenshot: String?
  /// The report's own folder, `bugs/<stamp>` (unique, see `BugStore.makeFolder`).
  public var folder: String
  /// Any other files the app put in the folder (a video clip, recent segments).
  public var files: [String]
  /// Whatever the app attaches: exercise, playhead, mode, replay time.
  public var context: [String: JSONValue]

  public init(
    id: UUID = UUID(), reportedAt: Date = Date(), app: String, bundle: String, build: String, commit: String,
    device: String, screen: String, note: String, log: String? = nil, sessionTMs: Int? = nil,
    screenshot: String? = nil, folder: String, files: [String] = [], context: [String: JSONValue] = [:]
  ) {
    // Kept at the millisecond the line stores, so a report equals itself read back.
    self.id = id; self.reportedAt = Self.parseDate(Self.formatDate(reportedAt)) ?? reportedAt; self.app = app; self.bundle = bundle; self.build = build
    self.commit = commit; self.device = device; self.screen = screen; self.note = note; self.log = log
    self.sessionTMs = sessionTMs; self.screenshot = screenshot; self.folder = folder; self.files = files
    self.context = context
  }

  enum CodingKeys: String, CodingKey {
    case id, app, bundle, build, commit, device, screen, note, log, screenshot, folder, files, context
    case reportedAt = "reported_at"
    case sessionTMs = "session_t_ms"
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    let stamp = try c.decode(String.self, forKey: .reportedAt)
    guard let date = Self.parseDate(stamp) else {
      throw DecodingError.dataCorruptedError(forKey: .reportedAt, in: c, debugDescription: "not ISO 8601: \(stamp)")
    }
    reportedAt = date
    app = try c.decode(String.self, forKey: .app)
    bundle = try c.decode(String.self, forKey: .bundle)
    build = try c.decode(String.self, forKey: .build)
    commit = try c.decode(String.self, forKey: .commit)
    device = try c.decode(String.self, forKey: .device)
    screen = try c.decode(String.self, forKey: .screen)
    note = try c.decode(String.self, forKey: .note)
    log = try c.decodeIfPresent(String.self, forKey: .log)
    sessionTMs = try c.decodeIfPresent(Int.self, forKey: .sessionTMs)
    screenshot = try c.decodeIfPresent(String.self, forKey: .screenshot)
    folder = try c.decode(String.self, forKey: .folder)
    files = try c.decodeIfPresent([String].self, forKey: .files) ?? []
    context = try c.decodeIfPresent([String: JSONValue].self, forKey: .context) ?? [:]
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(Self.formatDate(reportedAt), forKey: .reportedAt)
    try c.encode(app, forKey: .app)
    try c.encode(bundle, forKey: .bundle)
    try c.encode(build, forKey: .build)
    try c.encode(commit, forKey: .commit)
    try c.encode(device, forKey: .device)
    try c.encode(screen, forKey: .screen)
    try c.encode(note, forKey: .note)
    try c.encodeIfPresent(log, forKey: .log)
    try c.encodeIfPresent(sessionTMs, forKey: .sessionTMs)
    try c.encodeIfPresent(screenshot, forKey: .screenshot)
    try c.encode(folder, forKey: .folder)
    try c.encode(files, forKey: .files)
    try c.encode(context, forKey: .context)
  }

  /// One line of bugs.jsonl, without the newline. Keys sorted, so two writes of one report are byte-identical.
  public func jsonLine() throws -> Data {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return try enc.encode(self)
  }

  // ISO8601DateFormatter is thread-safe for formatting and parsing.
  nonisolated(unsafe) private static let withMs: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()
  nonisolated(unsafe) private static let withoutMs = ISO8601DateFormatter()

  public static func formatDate(_ date: Date) -> String { withMs.string(from: date) }
  /// Accepts milliseconds or whole seconds (the older apps wrote `2026-10-08T04:00:18Z`).
  public static func parseDate(_ text: String) -> Date? { withMs.date(from: text) ?? withoutMs.date(from: text) }
}
