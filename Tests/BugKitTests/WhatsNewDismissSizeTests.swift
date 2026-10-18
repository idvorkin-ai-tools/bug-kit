#if canImport(UIKit) && os(iOS)
import SwiftUI
import Testing
import UIKit
@testable import BugKit

// #35: the row's ✕ is a touch target of at least 44×44 pt, so the row is at least that tall.
@MainActor @Test func whatsNewDismissIsATouchSizedTarget() throws {
  let suite = "bugkit-dismiss-size-\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let feed = WhatsNewFeed(
    generated: "2026-10-10",
    days: [WhatsNewDay(day: "2026-10-10", items: [WhatsNewItem(story: 1, text: "A change", sha: "abc1234")])])
  let host = UIHostingController(
    rootView: WhatsNewRow(feed: feed, seen: WhatsNewSeen(defaults: defaults), logger: { _, _ in }, open: {}))
  let size = host.sizeThatFits(in: CGSize(width: 390, height: CGFloat.greatestFiniteMagnitude))
  #expect(size.height >= 44)
}
#endif
