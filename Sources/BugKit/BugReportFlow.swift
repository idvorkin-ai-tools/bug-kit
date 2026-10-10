import Foundation

/// The dialog's logic, apart from SwiftUI so the host tests can drive it.
///
/// - "Log it" saves the note and closes the dialog.
/// - "Log it and another" saves the note, then opens a fresh report: the note is empty, `draft` is new, and the
///   dialog stays up. The fresh report keeps the moment that opened the dialog (its screenshot), since the dialog
///   now covers the screen (EA #212, MM story 061).
/// - An empty or blank note saves nothing.
public struct BugReportFlow: Equatable, Sendable {
  public enum Source: String, Sendable { case shake, button, key, hook }

  public private(set) var isPresented = false
  public private(set) var source: Source?
  public var note = ""
  /// A new id for each fresh report: the sheet keys its text field on it, so focus returns to an empty field.
  public private(set) var draft = UUID()
  /// Reports saved since the dialog opened.
  public private(set) var savedThisTime = 0

  public init() {}

  public var canLog: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

  /// Opens a fresh report. Returns false when one is already open (a second shake while typing must not wipe
  /// the note).
  @discardableResult
  public mutating func open(from source: Source) -> Bool {
    guard !isPresented else { return false }
    isPresented = true
    self.source = source
    note = ""
    draft = UUID()
    savedThisTime = 0
    return true
  }

  /// "Log it" (`another: false`) or "Log it and another" (`another: true`). Returns the trimmed note to save, or
  /// nil when there is nothing to save; the caller saves it.
  public mutating func log(another: Bool) -> String? {
    guard isPresented, canLog else { return nil }
    let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
    savedThisTime += 1
    note = ""
    if another {
      draft = UUID()
    } else {
      isPresented = false
    }
    return text
  }

  public mutating func cancel() {
    isPresented = false
    note = ""
  }
}
