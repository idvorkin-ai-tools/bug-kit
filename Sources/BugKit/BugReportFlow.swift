import Foundation

/// The dialog's logic, apart from SwiftUI so the host tests can drive it.
///
/// - "Log it" saves the note and closes the dialog.
/// - "Log it and another" saves the note, then opens a fresh report. Two styles, both from the apps:
///   - `.keepMoment` (EA #212, MM story 061): the dialog stays up with an empty note and a new `draft`, and the next
///     report keeps the moment that opened the dialog (its screenshot), since the dialog now covers the screen.
///   - `.recapture` (CG story 142, a85e228): the dialog closes, the screen underneath is captured again, and a fresh
///     dialog opens (`reopenPending`, then `reopenIfPending()`), so each report has its own picture.
/// - "Log it and another" while the note is being dictated carries the dictation into the fresh report
///   (`dictateNext`, then `takeDictateNext()`), in either style (#121, CG #341).
/// - An empty or blank note saves nothing.
public struct BugReportFlow: Equatable, Sendable {
  public enum Source: String, Sendable { case shake, button, key, hook, another }
  public enum AnotherStyle: String, Sendable { case keepMoment, recapture }

  public private(set) var isPresented = false
  public private(set) var source: Source?
  public var note = ""
  public private(set) var screenshotDropped = false
  /// A new id for each fresh report: the sheet keys its text field on it, so focus returns to an empty field.
  public private(set) var draft = UUID()
  /// Reports saved since the dialog opened.
  public private(set) var savedThisTime = 0
  /// `.recapture`: the dialog closed after "Log it and another" and a fresh one should open once it is gone.
  public private(set) var reopenPending = false
  /// "Log it and another" was tapped while dictating: the fresh report should start listening by itself.
  public private(set) var dictateNext = false

  public init() {}

  public var canLog: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  /// Opens a fresh report. Returns false when one is already open (a second shake while typing must not wipe
  /// the note). `dialogOnScreen: false` says the open report's dialog is gone without a cancel or save (the phone
  /// locked with it up, BugKit #96): that report no longer blocks this one.
  @discardableResult
  public mutating func open(from source: Source, dialogOnScreen: Bool = true) -> Bool {
    if isPresented && !dialogOnScreen { cancel() }
    guard !isPresented else { return false }
    isPresented = true
    if source != .another { dictateNext = false }  // only a "Log it and another" reopen carries the mic
    self.source = source
    note = ""
    draft = UUID()
    savedThisTime = 0
    screenshotDropped = false
    return true
  }

  /// "Log it" (`another: false`) or "Log it and another" (`another: true`). Returns the trimmed note to save, or
  /// nil when there is nothing to save; the caller saves it. `dictating`: the note was being spoken, so the fresh
  /// report of "Log it and another" should listen again (`dictateNext`).
  public mutating func log(another: Bool, style: AnotherStyle = .keepMoment, dictating: Bool = false) -> String? {
    guard isPresented, canLog else { return nil }
    let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
    savedThisTime += 1
    note = ""
    dictateNext = another && dictating
    if another && style == .keepMoment {
      draft = UUID()
    } else {
      isPresented = false
      reopenPending = another
    }
    return text
  }

  /// `.recapture`: once the closed dialog is off screen (and the screen captured again), opens the fresh one.
  /// Returns false when nothing was pending.
  public mutating func reopenIfPending() -> Bool {
    guard reopenPending else { return false }
    reopenPending = false
    return open(from: .another)
  }

  /// The fresh report is on screen: returns whether it should start dictating, once.
  public mutating func takeDictateNext() -> Bool {
    guard isPresented, dictateNext else { return false }
    dictateNext = false
    return true
  }

  /// Exclude the captured screenshot from every report about this moment.
  public mutating func dropScreenshot() {
    guard isPresented else { return }
    screenshotDropped = true
  }

  public mutating func cancel() {
    isPresented = false
    reopenPending = false
    dictateNext = false
    note = ""
  }
}
