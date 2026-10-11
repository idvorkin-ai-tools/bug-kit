import Foundation
import Testing
@testable import BugKit

@Test func whatsNewResetHookIsExplicitAndPrefixScoped() {
  #expect(BugLaunchHooks.parse(["APP_WHATS_NEW_RESET": "1"], prefix: "APP").whatsNewReset)
  #expect(!BugLaunchHooks.parse(["APP_WHATS_NEW_RESET": "1"], prefix: "APP").isEmpty)
  for value in ["0", "true", "", "yes"] {
    #expect(!BugLaunchHooks.parse(["APP_WHATS_NEW_RESET": value], prefix: "APP").whatsNewReset)
  }
  #expect(BugLaunchHooks.parse(["OTHER_WHATS_NEW_RESET": "1"], prefix: "APP").isEmpty)
}

@Test func whatsNewResetRunsBeforeFirstReadAndPreservesOtherDefaults() throws {
  let name = "BugKit-reset-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: name))
  defer { defaults.removePersistentDomain(forName: name) }
  defaults.set("old", forKey: WhatsNewSeen.defaultKey)
  defaults.set("keep", forKey: "unrelated")
  let unchanged = WhatsNewSeen(defaults: defaults, launchHookPrefix: "APP", environment: [:])
  #expect(unchanged.newestSeen == "old")
  let reset = WhatsNewSeen(defaults: defaults, launchHookPrefix: "APP", environment: ["APP_WHATS_NEW_RESET": "1"])
  #expect(reset.newestSeen == nil)
  #expect(defaults.string(forKey: "unrelated") == "keep")
  defaults.set("custom", forKey: "custom")
  WhatsNewSeen(defaults: defaults, key: "custom").reset()
  #expect(defaults.object(forKey: "custom") == nil)
}
