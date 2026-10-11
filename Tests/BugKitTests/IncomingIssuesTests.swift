import Foundation
import Testing
@testable import BugKit

@Test func whatsNewResetHookIsExplicitAndPrefixScoped() {
  #expect(BugLaunchHooks.parse(["APP_WHATS_NEW_RESET": "1"], prefix: "APP").whatsNewReset)
  #expect(BugLaunchHooks.parse(["APP_WHATS_NEW_RESET": "1"], prefix: "APP").isEmpty)
  for value in ["0", "true", "", "yes"] {
    #expect(!BugLaunchHooks.parse(["APP_WHATS_NEW_RESET": value], prefix: "APP").whatsNewReset)
  }
  #expect(!BugLaunchHooks.parse(["OTHER_WHATS_NEW_RESET": "1"], prefix: "APP").whatsNewReset)
}

@Test func whatsNewResetRunsBeforeFirstReadAndPreservesOtherDefaults() throws {
  let name = "BugKit-reset-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  defaults.set("old", forKey: WhatsNewSeen.defaultKey)
  defaults.set("keep", forKey: "unrelated")
  let events = IncomingEvents()
  let unchanged = WhatsNewSeen(defaults: defaults, launchHookPrefix: "APP",
    environment: ["OTHER_WHATS_NEW_RESET": "1"], logger: events.logger)
  #expect(unchanged.newestSeen == "old")
  #expect(events.all.isEmpty)
  let reset = WhatsNewSeen(defaults: defaults, launchHookPrefix: "APP", environment: ["APP_WHATS_NEW_RESET": "1"],
    logger: events.logger)
  #expect(reset.newestSeen == nil)
  #expect(events.all.count == 1)
  #expect(events.all.first?.0 == "bug_hook")
  #expect(events.all.first?.1["whats_new_reset"] == true)
  #expect(defaults.string(forKey: "unrelated") == "keep")
  defaults.set("custom", forKey: "custom")
  WhatsNewSeen(defaults: defaults, key: "custom").reset()
  #expect(defaults.object(forKey: "custom") == nil)
}

@Test func screenshotDropPersistsForSameMomentAndResetsOnRecapture() {
  var flow = BugReportFlow()
  flow.open(from: .button)
  flow.dropScreenshot()
  flow.note = "first"
  #expect(flow.log(another: true) == "first")
  #expect(flow.screenshotDropped)
  flow.note = "second"
  #expect(flow.log(another: true, style: .recapture) == "second")
  let reopened = flow.reopenIfPending()
  #expect(reopened)
  #expect(!flow.screenshotDropped)
  flow.dropScreenshot()
  flow.cancel()
  flow.open(from: .button)
  #expect(!flow.screenshotDropped)
}

@Test func droppedScreenshotIsAbsentFromSavedReportAndFolder() async throws {
  let docs = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: docs) }
  let events = IncomingEvents()
  let store = BugStore(documents: docs)
  let writer = BugReportWriter(store: store,
    info: BugAppInfo(app: "T", bundle: "b", build: "1", commit: "c", device: "d"), logger: events.logger)
  let report = await writer.save(note: "private screen", screen: "home", context: ["mode": "test"],
    screenshotPNG: Data([1, 2, 3]), log: nil, extraFiles: nil, screenshotDropped: true)
  #expect(report.screenshot == nil)
  #expect(report.context["mode"] == "test")
  #expect(!FileManager.default.fileExists(atPath: docs.appendingPathComponent(report.folder + "/screen.png").path))
  #expect(try store.readAll().reports.first?.screenshot == nil)
  #expect(events.all.last?.1["screenshot_dropped"] == true)
}

private final class IncomingEvents: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [(String, [String: JSONValue])] = []
  var logger: BugLogger { { [self] e, f in lock.lock(); items.append((e, f)); lock.unlock() } }
  var all: [(String, [String: JSONValue])] { lock.lock(); defer { lock.unlock() }; return items }
}
