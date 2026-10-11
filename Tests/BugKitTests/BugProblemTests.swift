import Foundation
import Testing

@testable import BugKit

@Suite struct BugProblemTests {
  @Test func copyTextIsMessageContextBuildThenSortedExtras() {
    let problem = BugProblem(
      message: "Speech recognition is off for this app (Settings)", context: "BugReportSheet.dictation",
      build: "1.2 (34) abc1234-dirty", extra: ["mic_busy": false, "auth": 1, "on_device": true])
    #expect(
      problem.copyText == """
        Speech recognition is off for this app (Settings)
        context: BugReportSheet.dictation
        build: 1.2 (34) abc1234-dirty
        auth: 1
        mic_busy: false
        on_device: true
        """)
  }

  @Test func noExtrasIsThreeLines() {
    let problem = BugProblem(message: "Saving failed", context: "Home.save")
    #expect(problem.copyText == "Saving failed\ncontext: Home.save\nbuild: unknown")
  }

  @Test func fieldsKeepMessageAndWhereOverExtras() {
    let problem = BugProblem(message: "m", context: "c", extra: ["message": "shadowed", "n": 2])
    #expect(problem.fields == ["message": "m", "where": "c", "n": 2])
  }

  @Test func buildLineNamesVersionAndCommit() {
    let info = BugAppInfo(app: "A", bundle: "b", build: "1.2 (34)", commit: "abc1234", device: "Mac16,12")
    #expect(info.buildLine == "1.2 (34) abc1234")
  }
}
