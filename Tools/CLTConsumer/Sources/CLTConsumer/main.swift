import BugKit
import Foundation

// Link a real unbundled consumer of the Foundation API without requiring a SwiftUI macro plugin.
let store = BugStore()
precondition(store.documents == BugStorage.defaultDirectory)
let seen = WhatsNewSeen(defaults: UserDefaults(suiteName: "bugkit-clt-fixture")!)
precondition(!seen.showsRow(nil))
print("BugKit CLT consumer linked")
