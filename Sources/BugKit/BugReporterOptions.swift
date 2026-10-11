import Foundation

/// What a `BugReporter` does beyond the core (a shake, the dialog, the report on disk). Each option comes from one
/// of the apps; the defaults are what every app wants, the rest is opt-in.
public struct BugReporterOptions: Equatable, Sendable {
  /// iOS's own shake gesture (a hard shake). EA, CG.
  public var systemShake = true
  /// A gentle shake read from Core Motion, three quick flicks (CG story 146, #164). Runs only while the scene is
  /// active; logs `shake` with the peak force.
  public var gentleShake = true
  /// ⌘I on a hardware keyboard (MM story 040, the iPad).
  public var commandI = true
  /// Keys in the dialog: ⌘Return logs, ⇧⌘Return logs and opens another, Escape cancels (MM stories 040, 061).
  public var dialogKeys = true
  /// What "Log it and another" does next; see `BugReportFlow.AnotherStyle`.
  public var another: BugReportFlow.AnotherStyle = .keepMoment
  /// A microphone button that speaks the note (CG #239). Needs `NSSpeechRecognitionUsageDescription` and
  /// `NSMicrophoneUsageDescription` in Info.plist, so it is off by default.
  public var dictation = false
  /// A line under the note saying where the report goes, e.g. "Nothing leaves this iPad." (MM story 062).
  public var privacyNote: String?
  /// The note field's placeholder.
  public var placeholder = "What went wrong? One line is enough"
  /// Copy the session log into the report's folder as `session.jsonl` (MM story 040).
  public var copySessionLog = false
  /// Write `report.json` in the report's folder too (MM story 040).
  public var writeReportJSON = false
  /// Log touch/gesture, UIKit control and scene breadcrumbs, and attach the most recent ones to reports.
  public var recordInteractions = false
  /// Attach the app's public UIKit view/accessibility metadata before the report dialog opens.
  /// Text-entry subtrees and accessibility values are excluded. SwiftUI's virtual AX tree may be incomplete.
  public var captureAccessibility = false
  /// Maximum recent interaction events per report (clamped to 1...1,000).
  public var interactionLimit = 200
  /// Environment variable prefix for the simulator hooks (`<PREFIX>_BUG`, `<PREFIX>_SHAKE_AFTER`); nil for none.
  public var launchHookPrefix: String?

  public init() {}
}
