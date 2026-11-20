import Foundation

/// An error a person sees, with what an agent needs to debug it from one paste: the message, where it happened,
/// which build, and the state at that moment (CG's `MirrorProblem`, bug-kit#7). Every on-screen error should be one.
public struct BugProblem: Equatable, Sendable {
  public var message: String
  /// Where: "screen.operation", e.g. "BugReportSheet.dictation".
  public var context: String
  /// Which build: "1.2 (34) abc1234", from `BugAppInfo.buildLine`.
  public var build: String
  /// The state at that moment: permission status, the mode, a count.
  public var extra: [String: JSONValue]
  /// Whether showing it files an automatic report (#119, story 019): on by default, so every error that reaches the
  /// screen reaches the agents too, once per context per `BugAutoReportOptions.window`. Set false for a context
  /// the app expects to fail (being offline, say).
  public var autoFile: Bool

  public init(
    message: String, context: String, build: String = "unknown", extra: [String: JSONValue] = [:],
    autoFile: Bool = true
  ) {
    self.message = message; self.context = context; self.build = build; self.extra = extra
    self.autoFile = autoFile
  }

  /// What Copy puts on the pasteboard: the message, then `context:`, `build:` and each extra field sorted by key,
  /// one per line.
  public var copyText: String {
    ([message, "context: \(context)", "build: \(build)"]
      + extra.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.display)" }).joined(separator: "\n")
  }

  /// The same problem as a log event's fields, so the log and the paste say the same thing.
  public var fields: [String: JSONValue] {
    extra.merging(["message": .string(message), "where": .string(context)]) { _, fixed in fixed }
  }
}

extension BugAppInfo {
  /// "1.2 (34) abc1234": the version, build number and commit, for a `BugProblem`.
  public var buildLine: String { "\(build) \(commit)" }
}

/// How an error on screen files itself (story 019, #119): `BugProblemView` hands each problem it shows to
/// `BugProblemFiler.current` when it first appears and whenever its context or message changes.
@MainActor
public struct BugProblemFiler {
  public let file: @MainActor (BugProblem) async -> Void

  public init(file: @escaping @MainActor (BugProblem) async -> Void) { self.file = file }

  /// The process's filer. A `BugReporter` sets itself here when it is created, so every `BugProblemView` in the app
  /// files through its automatic reports. An extension, which has no reporter, sets `.auto(_:)` with a reporter on a
  /// store in its app group (`BugReportWriter.adopt(from:)` in the app takes the reports from there). Nil files
  /// nothing.
  public static var current: BugProblemFiler?

  /// Files through `reporter`, with the screen and session log read when the problem appears.
  public static func auto(
    _ reporter: BugAutoReporter, screen: @escaping @MainActor () -> String = { "" },
    sessionLog: @escaping @MainActor () -> (path: String, tMs: Int)? = { nil },
    flushLog: @escaping @MainActor () -> Void = {}
  ) -> BugProblemFiler {
    BugProblemFiler { problem in
      flushLog()
      await reporter.report(problem: problem, screen: screen(), log: sessionLog())
    }
  }
}
