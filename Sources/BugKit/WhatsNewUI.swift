import Foundation

/// Which change the person has dismissed, kept in UserDefaults (CG story 148): the home row shows until its newest
/// change is dismissed with its ✕, and comes back for a build with something newer. Opening the list does not
/// dismiss it; the list stays reachable from the app's settings.
public struct WhatsNewSeen: @unchecked Sendable {
  public static let defaultKey = "bugkit.whats_new_seen"
  let defaults: UserDefaults
  let key: String

  public init(defaults: UserDefaults = .standard, key: String = defaultKey) {
    self.defaults = defaults; self.key = key
  }

  public var newestSeen: String? { defaults.string(forKey: key) }

  public func showsRow(_ feed: WhatsNewFeed?) -> Bool { WhatsNewFeed.showsOnHome(feed, seen: newestSeen) }

  /// The ✕: remembers the feed's newest change. Logs `ui` dismiss_whats_new.
  public func dismiss(_ feed: WhatsNewFeed?, logger: BugLogger? = nil) {
    guard let newest = feed?.newest else { return }
    defaults.set(newest, forKey: key)
    logger?("ui", ["action": "dismiss_whats_new", "newest": .string(newest)])
  }

  /// The feed the build bundled as `whats-new.json` (scripts/whats-new.sh); nil when it is missing or unreadable.
  public static func bundledFeed(_ bundle: Bundle = .main, name: String = "whats-new") -> WhatsNewFeed? {
    WhatsNewFeed.decode(bundle.url(forResource: name, withExtension: "json").flatMap { try? Data(contentsOf: $0) })
  }
}

// Plain SwiftUI, so the same views serve iOS and a Mac app (MM, 2026-10-10: What's new on the Mac too). On the Mac,
// give the list a size (`.frame(minWidth:minHeight:)`) when it is shown in a sheet or window.
#if canImport(SwiftUI)
  import SwiftUI

  /// The list: the last month's changes by day, newest first, each opening its story (CG #232). Logs `ui`
  /// open_whats_new on appear and open_story on a tap.
  public struct WhatsNewView: View {
    let feed: WhatsNewFeed?
    let logger: BugLogger
    let from: String
    @Environment(\.openURL) private var openURL

    public init(feed: WhatsNewFeed?, logger: @escaping BugLogger, from: String = "row") {
      self.feed = feed; self.logger = logger; self.from = from
    }

    public var body: some View {
      List {
        if let days = feed?.days, !days.isEmpty {
          ForEach(days, id: \.day) { day in
            Section(WhatsNew.label(day: day.day, style: .long)) {
              ForEach(day.items, id: \.sha) { item in
                if let link = item.link.flatMap(URL.init(string:)) {
                  Button {
                    logger("ui", ["action": "open_story", "story": .int(item.story), "url": .string(link.absoluteString)])
                    openURL(link)
                  } label: {
                    HStack {
                      ChangeLine(item: item)
                      Spacer()
                      Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                  }
                  .tint(.primary)
                  .accessibilityIdentifier("whats-new-story-\(item.story)")
                } else {
                  ChangeLine(item: item)
                }
              }
            }
          }
        } else {
          Text("Nothing new in the last thirty days.").foregroundStyle(.secondary)
        }
      }
      .navigationTitle("What's new")
      .accessibilityIdentifier("whats-new")
      .onAppear {
        let days = feed?.days ?? []
        logger(
          "ui",
          [
            "action": "open_whats_new", "from": .string(from), "days": .int(days.count),
            "changes": .int(days.reduce(0) { $0 + $1.items.count }),
          ])
      }
    }
  }

  private struct ChangeLine: View {
    let item: WhatsNewItem

    var body: some View {
      VStack(alignment: .leading, spacing: 3) {
        Text(item.text)
        Text(item.caption).font(.caption).foregroundStyle(.secondary)
      }
      .padding(.vertical, 2)
    }
  }

  /// The home screen's one-line pointer: "What's new · Oct 5 — <newest change>", with a ✕ that hides it until a
  /// newer build. Shows nothing when there is nothing to show or the newest was dismissed.
  public struct WhatsNewRow: View {
    let feed: WhatsNewFeed?
    let seen: WhatsNewSeen
    let logger: BugLogger
    let open: () -> Void
    @State private var dismissed = false

    public init(feed: WhatsNewFeed?, seen: WhatsNewSeen = WhatsNewSeen(), logger: @escaping BugLogger, open: @escaping () -> Void) {
      self.feed = feed; self.seen = seen; self.logger = logger; self.open = open
    }

    public var body: some View {
      if !dismissed, seen.showsRow(feed) {
        HStack(alignment: .firstTextBaseline) {
          Button(action: open) {
            (Text(Image(systemName: "sparkles")) + Text("  What's new").fontWeight(.semibold)
              + Text(" · \(WhatsNew.homeLine(feed))").foregroundStyle(.secondary))
              .font(.subheadline)
              .lineLimit(2)
              .multilineTextAlignment(.leading)
          }
          .tint(.primary)
          .accessibilityIdentifier("whats-new-row")
          Spacer()
          Button {
            seen.dismiss(feed, logger: logger)
            dismissed = true
          } label: {
            Image(systemName: "xmark").font(.footnote.weight(.semibold))
          }
          .buttonStyle(.borderless)
          .accessibilityLabel("Hide What's new until the next change")
          .accessibilityIdentifier("whats-new-dismiss")
        }
      }
    }
  }
#endif
