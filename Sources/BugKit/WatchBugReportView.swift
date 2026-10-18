#if os(watchOS) && canImport(SwiftUI)
import SwiftUI

/// The watch report form (#25): present it from the watch app's own sheet or navigation. `TextFieldLink` takes the
/// note through the watch's system text input (dictation, Scribble or the keyboard). The form refuses a blank note,
/// closes only once the report is in bugs.jsonl, and keeps the note when the save fails so the person can retry.
public struct WatchBugReportView: View {
  private let session: WatchBugReportSession
  @Environment(\.dismiss) private var dismiss
  @State private var note = ""
  @State private var saving = false
  @State private var problem: String?

  public init(session: WatchBugReportSession) { self.session = session }

  public var body: some View {
    Form {
      TextFieldLink(prompt: Text("What went wrong?")) {
        Label(note.isEmpty ? "Add a note" : note, systemImage: "text.bubble")
      } onSubmit: { note = $0 }
      .disabled(saving)
      .accessibilityIdentifier("watch-report-note")
      if let problem { Text(problem).foregroundStyle(.red) }
      Button(saving ? "Saving…" : "Log it") {
        saving = true
        problem = nil
        Task { @MainActor in
          do {
            _ = try await session.save(note: note)
            dismiss()
          } catch {
            problem = "Could not save the report. Your note is kept; try again."
          }
          saving = false
        }
      }
      .disabled(saving || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      .accessibilityIdentifier("watch-report-log-it")
    }
    .navigationTitle("Report a problem")
  }
}
#endif
