import Foundation
import Testing

@testable import BugKit

/// BugKit's own stories carry Issues lines, read the way What's new reads an app's.
@Suite struct IssuesLineTests {
  static let stories = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("docs/stories")

  @Test func bugKitsIssuesMapToTheirStories() throws {
    let files = try FileManager.default.contentsOfDirectory(at: Self.stories, includingPropertiesForKeys: nil)
      .filter { $0.lastPathComponent.first?.isNumber == true }
    let markdown = try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    let map = WhatsNew.issueStories(fromMarkdown: markdown)
    #expect(map[6] == 10)
    #expect(map[7] == 7)
  }
}
