import Foundation

/// The app's logger: BugKit sends it `bug_report` (and `error`) events so they land in the app's own session log,
/// next to everything else the app did at that moment.
public typealias BugLogger = @Sendable (_ event: String, _ fields: [String: JSONValue]) -> Void

/// Extra files for a report (EA's clip at the playhead, MM's recent video segments): write them into `folder` and
/// return their names. Thrown errors are logged and the report is saved without them.
public typealias BugExtraFiles = @Sendable (_ folder: URL) async throws -> [String]

/// Who made the report: the fixed fields that do not change within a launch.
public struct BugAppInfo: Equatable, Sendable {
  public var app: String
  public var bundle: String
  public var build: String
  public var commit: String
  public var device: String

  public init(app: String, bundle: String, build: String, commit: String, device: String) {
    self.app = app; self.bundle = bundle; self.build = build; self.commit = commit; self.device = device
  }

  /// From the main bundle: the display name, the bundle id, "version (build)", and the commit from the Info.plist
  /// key `BugKitCommit` (set it from `git rev-parse --short HEAD` at build time), else "unknown".
  public static func fromMainBundle(device: String) -> BugAppInfo {
    let b = Bundle.main
    let info = b.infoDictionary ?? [:]
    let name = (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? "app"
    let version = info["CFBundleShortVersionString"] as? String ?? "?"
    let number = info["CFBundleVersion"] as? String ?? "?"
    let commit = (info["BugKitCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "unknown"
    return BugAppInfo(
      app: name, bundle: b.bundleIdentifier ?? "unknown", build: "\(version) (\(number))", commit: commit,
      device: device)
  }

  /// "iPhone18,1 iOS 27.0": the hardware model and the system, never the device's own name.
  public static func hardwareModel() -> String {
    var info = utsname()
    uname(&info)
    return withUnsafeBytes(of: &info.machine) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
  }
}

/// Saves one report: its folder, the screenshot, the app's extra files, the line in bugs.jsonl, and a `bug_report`
/// event in the app's log. Every step that fails is logged as an `error` and the rest still runs, so a report is
/// never lost to one failing part.
public struct BugReportWriter: Sendable {
  public let store: BugStore
  public let info: BugAppInfo
  public let logger: BugLogger

  public init(store: BugStore, info: BugAppInfo, logger: @escaping BugLogger) {
    self.store = store; self.info = info; self.logger = logger
  }

  /// `log`: the session log's path under Documents and the milliseconds since it began, from the app.
  public func save(
    note: String, screen: String, context: [String: JSONValue], screenshotPNG: Data?,
    log: (path: String, tMs: Int)?, extraFiles: BugExtraFiles?, date: Date = Date()
  ) async -> BugReport {
    var report = BugReport(
      reportedAt: date, app: info.app, bundle: info.bundle, build: info.build, commit: info.commit,
      device: info.device, screen: screen, note: note, log: log?.path, sessionTMs: log?.tMs, folder: "",
      context: context)
    var folderURL: URL?
    do {
      let made = try store.makeFolder(for: date)
      report.folder = made.relative
      folderURL = made.url
    } catch {
      logger("error", ["where": "bug_folder", "id": .string(report.id.uuidString), "message": .string("\(error)")])
    }
    if let folderURL, let png = screenshotPNG {
      do {
        try png.write(to: folderURL.appendingPathComponent("screen.png"))
        report.screenshot = "\(report.folder)/screen.png"
      } catch {
        logger("error", ["where": "bug_screenshot", "id": .string(report.id.uuidString), "message": .string("\(error)")])
      }
    }
    if let folderURL, let extraFiles {
      do {
        report.files = try await extraFiles(folderURL).map { "\(report.folder)/\($0)" }
      } catch {
        logger("error", ["where": "bug_extra_files", "id": .string(report.id.uuidString), "message": .string("\(error)")])
      }
    }
    var indexWritten = true
    do {
      try store.append(report)
    } catch {
      // The report is still in the session log below; bugs.jsonl is what the listener reads, so say it is missing.
      indexWritten = false
      logger("error", ["where": "bug_index", "id": .string(report.id.uuidString), "message": .string("\(error)")])
    }
    var fields: [String: JSONValue] = [
      "id": .string(report.id.uuidString), "note": .string(note), "screen": .string(screen),
      "folder": .string(report.folder), "screenshot": report.screenshot.map(JSONValue.string) ?? .null,
      "files": .array(report.files.map(JSONValue.string)), "index_written": .bool(indexWritten),
    ]
    fields["context"] = .object(context)
    logger("bug_report", fields)
    return report
  }
}
