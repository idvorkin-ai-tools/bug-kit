#if canImport(UIKit) && os(iOS)
  import SwiftUI
  import UIKit

  /// An error on screen with a Copy error button (CG's ProblemView, bug-kit#7). Copy puts `problem.copyText` on the
  /// pasteboard and logs `ui` with action `copy_error`, so the log shows the person took it.
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
    }
  }
#endif
