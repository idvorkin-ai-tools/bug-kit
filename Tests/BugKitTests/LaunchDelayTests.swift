import Testing
@testable import BugKit

@Test func automaticReportDelayDefaultsToTwoSeconds() {
  #expect(BugLaunchHooks.parse([:], prefix: "APP").bugAfter == 2)
  #expect(BugLaunchHooks.parse(["OTHER_BUG_AFTER": "9"], prefix: "APP").bugAfter == 2)
}

@Test func automaticReportDelayAcceptsOnlyFiniteNonnegativeValues() {
  for value in ["-1", "soon", "nan", "inf", "-inf", "1e999", "1e21", "86400.5"] {
    #expect(BugLaunchHooks.parse(["APP_BUG_AFTER": value], prefix: "APP").bugAfter == 2)
  }
  #expect(BugLaunchHooks.parse(["APP_BUG_AFTER": "0"], prefix: "APP").bugAfter == 0)
  #expect(BugLaunchHooks.parse(["APP_BUG": "note", "APP_BUG_AFTER": "12.5"], prefix: "APP").bugAfter == 12.5)
  #expect(BugLaunchHooks.parse(["APP_BUG_AFTER": "12.5"], prefix: "APP").isEmpty)
  #expect(BugLaunchHooks.parse(["APP_BUG_AFTER": "86400"], prefix: "APP").bugAfter == 86_400)
}

@Test func shakeDelayAcceptsOnlyBoundedNonnegativeValues() {
  for value in ["-1", "soon", "nan", "inf", "1e21"] {
    #expect(BugLaunchHooks.parse(["APP_SHAKE_AFTER": value], prefix: "APP").shakeAfter == nil)
  }
  #expect(BugLaunchHooks.parse(["APP_SHAKE_AFTER": "3"], prefix: "APP").shakeAfter == 3)
}
