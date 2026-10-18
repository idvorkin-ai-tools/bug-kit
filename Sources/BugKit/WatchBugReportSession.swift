import Foundation

/// Saves a watch note through the same store, report format and optional delivery as the phone (#25). There is no
/// UIKit and no screenshot; the app supplies the screen and context when it presents its own note input.
public struct WatchBugReportSession: Sendable {
  public enum SaveError: Error, Equatable, Sendable {
    case emptyNote
    /// The report did not reach bugs.jsonl, which is what the listener reads. Keep the note so the person can retry.
    case indexNotWritten
  }

  public let writer: BugReportWriter
  public let screen: String
  public let context: [String: JSONValue]
  public let log: SessionLog?

  public init(writer: BugReportWriter, screen: String, context: [String: JSONValue] = [:], log: SessionLog? = nil) {
    self.writer = writer; self.screen = screen; self.context = context; self.log = log
  }

  /// Returns only once bugs.jsonl holds the report. CloudKit delivery, when the writer has it, stays asynchronous.
  public func save(note: String) async throws -> BugReport {
    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw SaveError.emptyNote }
    log?.flush()  // so the copied session.jsonl holds the moments before the report
    let saved = await writer.write(note: trimmed, screen: screen, context: context, screenshotPNG: nil,
                                   log: log?.position, extraFiles: nil)
    guard saved.indexWritten else { throw SaveError.indexNotWritten }
    return saved.report
  }
}
