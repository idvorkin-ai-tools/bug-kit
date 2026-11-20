#if canImport(UIKit) && os(iOS)
  import SwiftUI
  import UIKit

  /// An error on screen with a Copy error button (CG's ProblemView, bug-kit#7). Copy puts `problem.copyText` on the
  /// pasteboard and logs `ui` with action `copy_error`, so the log shows the person took it.
  ///
  /// It also files itself (story 019, #119): when it first appears, and when its context or message changes, it
  /// hands the problem to `BugProblemFiler.current` (the app's `BugReporter`), which saves an automatic report
  /// unless the problem has `autoFile: false` or its context filed one within the window. What the person sees does
  /// not change.
  public struct BugProblemView: View {
    let problem: BugProblem
    let logger: BugLogger?
    @State private var copied = false

    public init(problem: BugProblem, logger: BugLogger? = nil) {
      self.problem = problem
      self.logger = logger
    }

    public var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        Label(problem.message, systemImage: "exclamationmark.triangle")
          .font(.footnote).foregroundStyle(.red).textSelection(.enabled)
        Button(copied ? "Copied" : "Copy error") {
          UIPasteboard.general.string = problem.copyText
          copied = true
          logger?("ui", ["action": "copy_error", "from": "tap", "where": .string(problem.context)])
        }
        .font(.footnote)
        .buttonStyle(.borderless)
        .accessibilityIdentifier("copy-error")
      }
      .onChange(of: problem) { copied = false }
      // Keyed on what the problem is, not its state: a count in `extra` ticking does not file it again.
      .task(id: Filing(context: problem.context, message: problem.message)) {
        await BugProblemFiler.current?.file(problem)
      }
    }

    private struct Filing: Equatable { let context: String, message: String }
  }
#endif
