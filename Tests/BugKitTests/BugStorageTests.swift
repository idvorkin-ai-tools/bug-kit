import Foundation
import Testing
@testable import BugKit

@Test func macStorageUsesBundleIdentityAndExecutableFallback() {
  let support = URL(fileURLWithPath: "/synthetic/Library/Application Support", isDirectory: true)
  #expect(BugStorage.macDirectory(applicationSupport: support, bundleIdentifier: "com.example.timer",
                                 processName: "timer").path == support.appendingPathComponent("com.example.timer").path)
  #expect(BugStorage.macDirectory(applicationSupport: support, bundleIdentifier: nil,
                                 processName: "lcd-timer").path == support.appendingPathComponent("lcd-timer").path)
  #expect(BugStorage.macDirectory(applicationSupport: support, bundleIdentifier: "",
                                 processName: "lcd-timer").lastPathComponent == "lcd-timer")
}

@Test func macStorageCannotEscapeItsApplicationSupportRoot() {
  let support = URL(fileURLWithPath: "/synthetic/Library/Application Support", isDirectory: true)
  for identity in ["..", ".", "", "../../other", "path/with/slashes", "name\0suffix"] {
    let root = BugStorage.macDirectory(applicationSupport: support, bundleIdentifier: nil, processName: identity)
    #expect(root.deletingLastPathComponent().standardizedFileURL == support.standardizedFileURL)
  }
}

@Test func defaultStoreAndCrashCaptureShareThePlatformRoot() {
  #expect(BugStore().documents == BugStorage.defaultDirectory)
  #expect(CrashReports().folder == BugStorage.defaultDirectory.appendingPathComponent("crashes"))
  #if os(macOS)
    let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    #expect(BugStorage.defaultDirectory.deletingLastPathComponent().standardizedFileURL == support.standardizedFileURL)
  #else
    #expect(BugStorage.defaultDirectory == FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0])
  #endif
}

@Test func explicitStoreAndLogDirectoriesRemainAuthoritative() throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = BugStore(documents: root)
  let log = SessionLog(prefix: "fixture", documents: root)
  log.event("fixture_event"); log.flush()
  #expect(store.documents == root)
  #expect(log.url.deletingLastPathComponent() == root.appendingPathComponent("logs", isDirectory: true))
  #expect(FileManager.default.fileExists(atPath: log.url.path))
  #expect(try String(contentsOf: log.url, encoding: .utf8).contains("fixture_event"))
}
