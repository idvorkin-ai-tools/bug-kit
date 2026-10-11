import Foundation

/// Simulator hooks instead of tapping (ios-test-ladder): environment variables that drive the report without a
/// shake, so a simulator check asserts on the log. With `simctl launch`, set them as `SIMCTL_CHILD_<PREFIX>_BUG=…`;
/// simctl strips `SIMCTL_CHILD_`.
///
/// - `<PREFIX>_BUG=note` saves a report with that note a couple of seconds after launch (after the first frame,
///   so the screenshot has something on it); `a|b` saves two, as "Log it and another" would (EA `SWING_BUG`,
///   CG `GRABBER_BUG`).
/// - `<PREFIX>_BUG_AFTER=<seconds>` delays automatic reports (default 2); use a longer delay for cold launches.
/// - `<PREFIX>_SHAKE_AFTER=<seconds>` opens the dialog as a shake would, that long after launch (CG
///   `GRABBER_SHAKE_AFTER`).
public struct BugLaunchHooks: Equatable, Sendable {
  public var notes: [String] = []
  public var shakeAfter: Double?
  public var whatsNewReset: Bool = false
  public var bugAfter: Double = 2

  public init(notes: [String] = [], shakeAfter: Double? = nil, whatsNewReset: Bool = false, bugAfter: Double = 2) {
    self.notes = notes; self.shakeAfter = shakeAfter; self.whatsNewReset = whatsNewReset
    self.bugAfter = bugAfter
  }

  public var isEmpty: Bool { notes.isEmpty && shakeAfter == nil }

  public static func parse(_ env: [String: String] = ProcessInfo.processInfo.environment, prefix: String) -> Self {
    var hooks = Self()
    if let bug = env["\(prefix)_BUG"] {
      hooks.notes = bug.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    if let after = env["\(prefix)_SHAKE_AFTER"].flatMap(Double.init), after >= 0 { hooks.shakeAfter = after }
    hooks.whatsNewReset = env["\(prefix)_WHATS_NEW_RESET"] == "1"
    if let after = env["\(prefix)_BUG_AFTER"].flatMap(Double.init), after.isFinite, after >= 0 {
      hooks.bugAfter = after
    }
    return hooks
  }
}

/// MM story 040: a report carries the recorded segments that cover the last `seconds` before the moment, any that
/// overlaps. For apps that record in rolling segments; feed the result to the extra-files hook.
public enum RecentSegments {
  public static func covering<S>(
    _ segments: [S], now: Double, seconds: Double, start: (S) -> Double, end: (S) -> Double
  ) -> [S] {
    segments.filter { end($0) > now - seconds && start($0) <= now }
  }
}
