import Foundation
import Testing
@testable import BugKit

@Test func breadcrumbsKeepOnlyRecentEventsAndValidJSON() throws {
  var crumbs = InteractionBreadcrumbs(capacity: 2)
  crumbs.record("first", tMs: 1)
  crumbs.record("ui_tap", tMs: 2, fields: ["identifier": "a\nb", "x": .double(.nan)])
  let frozen = crumbs.jsonLines
  crumbs.record("ui_drag", tMs: 3)
  let rows = try String(decoding: crumbs.jsonLines, as: UTF8.self).split(separator: "\n").map {
    try JSONSerialization.jsonObject(with: Data($0.utf8)) as! [String: Any]
  }
  #expect(crumbs.count == 2)
  #expect(rows.map { $0["type"] as! String } == ["ui_tap", "ui_drag"])
  #expect(rows[0]["identifier"] as? String == "a\nb")
  #expect(rows[0]["x"] is NSNull)
  #expect(String(decoding: frozen, as: UTF8.self).contains("first"))
  #expect(InteractionBreadcrumbs(capacity: 0).capacity == 1)
  #expect(InteractionBreadcrumbs(capacity: 10_000).capacity == 1_000)
}

@Test func diagnosticsAreWrittenAndIndexedAlongsideExtraFiles() async throws {
  let docs = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: docs) }
  let writer = BugReportWriter(store: BugStore(documents: docs),
    info: BugAppInfo(app: "test", bundle: "test", build: "1", commit: "c", device: "host"),
    logger: { _, _ in }, writeReportJSON: true)
  let diagnostics = BugDiagnosticsSnapshot(interactions: Data("{\"type\":\"ui_tap\"}\n".utf8),
                                           accessibility: Data("{\"nodes\":[]}".utf8))
  let report = await writer.save(note: "test", screen: "home", context: [:], screenshotPNG: nil, log: nil,
    extraFiles: { folder in
      try Data("clip".utf8).write(to: folder.appendingPathComponent("clip.txt"))
      return ["clip.txt"]
    }, diagnostics: diagnostics)
  #expect(report.files.map { URL(fileURLWithPath: $0).lastPathComponent } == ["clip.txt", "interactions.jsonl", "accessibility.json"])
  let folder = docs.appendingPathComponent(report.folder)
  #expect(try Data(contentsOf: folder.appendingPathComponent("accessibility.json")) == diagnostics.accessibility)
  let index = try writer.store.readAll()
  #expect(index.reports.first?.files == report.files)
  let json = try JSONDecoder().decode(BugReport.self, from: Data(contentsOf: folder.appendingPathComponent("report.json")))
  #expect(json.files == report.files)
}

@Test func oneDiagnosticWriteFailureDoesNotLoseTheReportOrOtherEvidence() async throws {
  let docs = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: docs) }
  let writer = BugReportWriter(store: BugStore(documents: docs),
    info: BugAppInfo(app: "test", bundle: "test", build: "1", commit: "c", device: "host"), logger: { _, _ in })
  let report = await writer.save(note: "test", screen: "home", context: [:], screenshotPNG: nil, log: nil,
    extraFiles: { folder in
      try FileManager.default.createDirectory(at: folder.appendingPathComponent("accessibility.json"), withIntermediateDirectories: false)
      return []
    }, diagnostics: BugDiagnosticsSnapshot(interactions: Data("{}\n".utf8), accessibility: Data("{}".utf8)))
  #expect(report.files == ["\(report.folder)/interactions.jsonl"])
  #expect(try writer.store.readAll().reports.count == 1)
}

#if canImport(UIKit) && os(iOS)
  import UIKit

  @Test @MainActor func accessibilitySnapshotRedactsTextAndTraversesContainersWithoutCycles() throws {
    let root = UIView(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
    let button = UIButton(type: .system)
    button.accessibilityIdentifier = "save-button"
    button.accessibilityLabel = "Save"
    root.addSubview(button)
    let field = UITextField()
    field.text = "private-typed-text"
    field.accessibilityLabel = "private-typed-text"
    field.accessibilityValue = "private-typed-text"
    let child = UILabel()
    child.accessibilityLabel = "private-typed-text"
    field.addSubview(child)
    root.addSubview(field)
    let element = UIAccessibilityElement(accessibilityContainer: root)
    element.accessibilityLabel = "Custom element"
    element.accessibilityValue = "private-ax-value"
    root.accessibilityElements = [element, root]
    let data = AccessibilitySnapshot.capture(root)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains("save-button") && text.contains("Custom element"))
    #expect(!text.contains("private-typed-text") && !text.contains("private-ax-value"))
    let record = try JSONSerialization.jsonObject(with: data) as! [String: Any]
    #expect(record["truncated"] as? Bool == false)
    let nodes = record["nodes"] as! [[String: Any]]
    #expect(nodes.contains { $0["redacted"] as? Bool == true })
    let bounded = try JSONSerialization.jsonObject(with: AccessibilitySnapshot.capture(root, maxNodes: 1)) as! [String: Any]
    #expect(bounded["truncated"] as? Bool == true)
    #expect((bounded["nodes"] as! [Any]).count == 1)
  }

  @Test @MainActor func controlCaptureIsOptionalAndDetachesWithoutReplacingAppActions() {
    let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 400))
    let button = UIButton(type: .system)
    button.accessibilityIdentifier = "save-button"
    window.addSubview(button)
    var applicationActions = 0
    button.addAction(UIAction { _ in applicationActions += 1 }, for: .primaryActionTriggered)
    var events: [String] = []
    let capture = InteractionCapture { event, _ in events.append(event) }
    capture.start(in: window)
    let observer = window.gestureRecognizers!.last!
    #expect(!observer.cancelsTouchesInView && !observer.delaysTouchesBegan && !observer.delaysTouchesEnded)
    #expect(!observer.canPrevent(UITapGestureRecognizer()))
    #expect(!observer.canBePrevented(by: UITapGestureRecognizer()))
    button.sendActions(for: .primaryActionTriggered)
    #expect(applicationActions == 1 && events == ["ui_control"])
    capture.stop()
    button.sendActions(for: .primaryActionTriggered)
    #expect(applicationActions == 2 && events == ["ui_control"])
    #expect(!(window.gestureRecognizers ?? []).contains { $0 === observer })
  }
#endif
