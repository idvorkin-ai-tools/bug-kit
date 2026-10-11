#if os(macOS)
  import AppKit
  import SwiftUI
  import XCTest

  @testable import BugKit

  /// The Mac row's ✕, clicked in a hosted window: the row disappears and stays hidden.
  @MainActor
  final class WhatsNewMacDismissTests: XCTestCase {
    private func settle(_ host: NSView) {
      host.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.2))
      host.layoutSubtreeIfNeeded()
    }

    private func click(_ window: NSWindow, at point: NSPoint) throws {
      for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        window.sendEvent(
          try XCTUnwrap(
            NSEvent.mouseEvent(
              with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
              windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
      }
    }

    func testTheDismissButtonHidesTheRowAndKeepsItHidden() throws {
      let suite = "bugkit-mac-dismiss-\(UUID().uuidString)"
      let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
      defer { defaults.removePersistentDomain(forName: suite) }
      let seen = WhatsNewSeen(defaults: defaults)
      let feed = WhatsNewFeed(
        generated: "2026-10-10",
        days: [WhatsNewDay(day: "2026-10-10", items: [WhatsNewItem(story: 1, text: "A change", sha: "abc1234")])])
      var events: [String] = []
      let host = NSHostingView(
        rootView: WhatsNewRow(feed: feed, seen: seen, logger: { name, _ in events.append(name) }, open: {}))
      let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 400, height: 40), styleMask: [.borderless], backing: .buffered,
        defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = host
      defer { window.close() }
      NSApplication.shared.setActivationPolicy(.accessory)
      window.makeKeyAndOrderFront(nil)
      settle(host)
      XCTAssertGreaterThan(host.fittingSize.height, 0)

      try click(window, at: NSPoint(x: host.frame.maxX - 1, y: host.frame.midY))
      settle(host)

      XCTAssertEqual(host.fittingSize, .zero)
      XCTAssertEqual(seen.newestSeen, "abc1234")
      XCTAssertEqual(events, ["ui"])

      host.rootView = WhatsNewRow(feed: feed, seen: seen, logger: { _, _ in }, open: {})
      settle(host)
      XCTAssertEqual(host.fittingSize, .zero)
    }
  }
#endif
