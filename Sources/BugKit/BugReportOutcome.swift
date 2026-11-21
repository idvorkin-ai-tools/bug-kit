import Foundation

/// What became of a report the person opened (#120), so an app can confirm exactly that ("Sent ✓") instead of
/// assuming a closed dialog means a saved report. `BugReporter` publishes each one as `lastOutcome` and passes it
/// to `onOutcome`.
public enum BugReportOutcome: Equatable, Sendable {
  /// bugs.jsonl holds the report, so the listener files it. `queued`: the writer's delivery (CloudKit) took it to
  /// upload; false when the app has no delivery or the hand-off failed (the report stays local and is pulled from
  /// the device). The upload itself happens later and is not reported here.
  case saved(id: UUID, queued: Bool)
  /// bugs.jsonl did not take the report: only the session log has it, and nothing will file it.
  case failed(id: UUID)
  /// The dialog closed (Cancel, a swipe down, or a dialog the system removed) without saving its current note.
  /// Reports already saved from the same moment by "Log it and another" each had their own `saved`.
  case cancelled

  /// True for `saved`.
  public var isSaved: Bool {
    if case .saved = self { return true }
    return false
  }
}
