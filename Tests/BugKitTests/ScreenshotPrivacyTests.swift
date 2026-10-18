import Foundation
import Testing
@testable import BugKit
#if canImport(UIKit) && os(iOS)
import UIKit
#endif

@Test func richDiagnosticsAreOnByDefaultWithOneSwitch() {
  // VISION: breadcrumbs and the accessibility snapshot are on in every app that adopts BugKit; one option turns
  // them off (bug-1nq).
  #expect(BugReporterOptions().richDiagnostics)
}

@Test func screenshotsCaptureByDefaultAndDisabledCaptureNeverRenders() {
  var options = BugReporterOptions()
  var renders = 0
  func render() -> Data? { renders += 1; return Data("synthetic screen".utf8) }
  #expect(options.screenshot(render) == Data("synthetic screen".utf8))
  #expect(renders == 1)
  options.captureScreenshots = false
  #expect(options.screenshot(render) == nil)
  #expect(renders == 1)
}

@Test func screenshotDisabledReportStillSavesNoteAndContext() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = BugStore(documents: root)
  let writer = BugReportWriter(store: store,
    info: BugAppInfo(app: "fixture", bundle: "local.fixture", build: "1", commit: "fixture", device: "fixture"),
    logger: { _, _ in })
  var options = BugReporterOptions(); options.captureScreenshots = false
  let image = options.screenshot { Data("private screen".utf8) }
  let report = await writer.save(note: "issue note", screen: "home", context: ["mode": "fixture"],
                                 screenshotPNG: image, log: nil, extraFiles: nil)
  #expect(report.screenshot == nil)
  #expect(report.note == "issue note" && report.context["mode"] == "fixture")
  #expect(try store.readAll().reports == [report])
  #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(report.folder + "/screen.png").path))
}

#if canImport(UIKit) && os(iOS)
@MainActor @Test func screenshotPrivacyAppliesToRealSheetAndLaunchHook() async throws {
  let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
  let original = scene.windows.first { $0.isKeyWindow }
  let window = UIWindow(windowScene: scene)
  window.rootViewController = UIViewController()
  window.makeKeyAndVisible()
  defer { window.isHidden = true; original?.makeKeyAndVisible() }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = BugStore(documents: root)
  var options = BugReporterOptions()
  options.captureScreenshots = false
  options.launchHookPrefix = "PRIVACY"
  let reporter = BugReporter(hooks: BugReporterHooks(logger: { _, _ in }), options: options, store: store)
  reporter.open(from: .button)
  #expect(reporter.flow.isPresented)
  #expect(reporter.screenshot == nil)
  reporter.flow.note = "sheet issue note"
  reporter.log(another: false)
  reporter.runLaunchHooks(["PRIVACY_BUG": "launch issue note", "PRIVACY_BUG_AFTER": "0"])
  for _ in 0..<100 {
    if try store.readAll().reports.count == 2 { break }
    try await Task.sleep(for: .milliseconds(20))
  }
  let reports = try store.readAll().reports
  #expect(reports.count == 2)
  #expect(Set(reports.map(\.note)) == ["sheet issue note", "launch issue note"])
  #expect(reports.allSatisfy { $0.screenshot == nil })
}
@MainActor @Test(arguments: [true, false]) func oneSwitchAttachesOrDropsBothDiagnostics(richDiagnostics: Bool) async throws {
  let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
  let original = scene.windows.first { $0.isKeyWindow }
  let window = UIWindow(windowScene: scene)
  window.rootViewController = UIViewController()
  window.makeKeyAndVisible()
  defer { window.isHidden = true; original?.makeKeyAndVisible() }
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = BugStore(documents: root)
  var options = BugReporterOptions()
  options.captureScreenshots = false
  options.gentleShake = false
  if !richDiagnostics { options.richDiagnostics = false }  // the default is on; turning it off is the one switch
  let reporter = BugReporter(hooks: BugReporterHooks(logger: { _, _ in }), options: options, store: store)
  reporter.recordInteraction("open_settings")
  reporter.open(from: .button)
  reporter.flow.note = "diagnostics note"
  reporter.log(another: false)
  for _ in 0..<100 where try store.readAll().reports.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
  let report = try #require(try store.readAll().reports.first)
  let names = Set(report.files.map { ($0 as NSString).lastPathComponent })
  #expect(names.contains("interactions.jsonl") == richDiagnostics)
  #expect(names.contains("accessibility.json") == richDiagnostics)
  try await Task.sleep(for: .milliseconds(500))  // the report sheet's dismissal animation
}
#endif
