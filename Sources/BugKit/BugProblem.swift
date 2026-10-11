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

  public init(message: String, context: String, build: String = "unknown", extra: [String: JSONValue] = [:]) {
    self.message = message; self.context = context; self.build = build; self.extra = extra
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
