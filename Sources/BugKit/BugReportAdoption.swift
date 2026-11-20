import Foundation

extension BugReportWriter {
  /// Takes the reports an extension saved in `source` (a store in the app group the app shares with it) into this
  /// writer's store, then hands each to `delivery`, so they leave the device like the app's own (story 019, #119).
  /// An extension is its own process with no reporter and often no network; this is how its reports reach the Mac.
  ///
  /// Each report keeps its id, its time and the extension's build and device; it takes this app's `app` and `bundle`
  /// (the listener files by bundle) and keeps the extension's bundle as `context["extension"]`. Its files and session
  /// log are copied into a new folder in this store. A report this store already holds is not added again.
  ///
  /// The source folder is first renamed aside with one atomic move, so an extension saving meanwhile starts a fresh
  /// store and never writes into one half taken; a move left from a take that was killed is finished first. The
  /// taken folder is then deleted; the extension's `bugs-auto.json` (its rate-limit state) is put back first, so its
  /// window holds across takes. Logs `bug_report_adopted` for each report and returns them.
  @discardableResult
  public func adopt(from source: BugStore) async -> [BugReport] {
    let fm = FileManager.default
    let parent = source.documents.deletingLastPathComponent()
    let prefix = source.documents.lastPathComponent + ".taking-"
    let left = ((try? fm.contentsOfDirectory(atPath: parent.path)) ?? []).filter { $0.hasPrefix(prefix) }.sorted()
    var staged = left.map { parent.appendingPathComponent($0, isDirectory: true) }
    if fm.fileExists(atPath: source.documents.path) {
      let aside = parent.appendingPathComponent(prefix + UUID().uuidString, isDirectory: true)
      do {
        try fm.moveItem(at: source.documents, to: aside)
        staged.append(aside)
        // The extension's rate-limit state stays with it, so its window holds across takes.
        let state = aside.appendingPathComponent("bugs-auto.json")
        if fm.fileExists(atPath: state.path) {
          try? fm.createDirectory(at: source.documents, withIntermediateDirectories: true)
          try? fm.copyItem(at: state, to: source.documents.appendingPathComponent("bugs-auto.json"))
        }
      } catch {
        logger("error", ["where": "bug_adopt_move", "message": .string("\(error)")])
      }
    }
    guard !staged.isEmpty else { return [] }
    if let delivery {
      do { try await delivery.prepare(documents: store.documents) }
      catch {
        logger("error", ["where": "bug_delivery_prepare",
                         "message": "Cloud delivery activation failed; saving the report locally."])
      }
    }
    var held = Set(((try? store.readAll().reports) ?? []).map(\.id))
    var taken: [BugReport] = []
    for folder in staged {
      let from = BugStore(documents: folder)
      let reports: [BugReport]
      do { reports = try from.readAll().reports } catch {
        logger("error", ["where": "bug_adopt_read", "message": .string("\(error)")])
        reports = []
      }
      for original in reports where !held.contains(original.id) {
        guard let report = take(original, from: folder) else { continue }
        held.insert(report.id)
        taken.append(report)
        logger(
          "bug_report_adopted",
          ["id": .string(report.id.uuidString), "from": .string(original.bundle), "folder": .string(report.folder),
           "files": .array(report.files.map(JSONValue.string))])
        if let delivery {
          do { try await delivery.enqueue(report, documents: store.documents) }
          catch {
            logger("error", ["where": "bug_delivery_enqueue", "id": .string(report.id.uuidString),
                             "message": "Cloud delivery is pending; the report remains local."])
          }
        }
      }
      do { try fm.removeItem(at: folder) } catch {
        logger("error", ["where": "bug_adopt_remove", "message": .string("\(error)")])
      }
    }
    return taken
  }

  /// Copies one report's files and log into a new folder here and appends its line; nil when the line is not written.
  private func take(_ original: BugReport, from root: URL) -> BugReport? {
    var report = original
    report.app = info.app
    report.bundle = info.bundle
    if original.bundle != info.bundle { report.context["extension"] = .string(original.bundle) }
    report.files = []
    report.screenshot = nil
    report.log = nil
    do {
      let made = try store.makeFolder(for: original.reportedAt)
      report.folder = made.relative
      var names: Set<String> = []
      func copy(_ path: String, as wanted: String) -> String? {
        var name = wanted, n = 2
        let base = (wanted as NSString).deletingPathExtension, ext = (wanted as NSString).pathExtension
        while names.contains(name) { name = ext.isEmpty ? "\(base)-\(n)" : "\(base)-\(n).\(ext)"; n += 1 }
        do {
          try FileManager.default.copyItem(
            at: root.appendingPathComponent(path), to: made.url.appendingPathComponent(name))
          names.insert(name)
          return "\(made.relative)/\(name)"
        } catch {
          logger("error", ["where": "bug_adopt_file", "id": .string(original.id.uuidString),
                           "file": .string(path), "message": .string("\(error)")])
          return nil
        }
      }
      if let shot = original.screenshot { report.screenshot = copy(shot, as: (shot as NSString).lastPathComponent) }
      report.files = original.files.compactMap { copy($0, as: ($0 as NSString).lastPathComponent) }
      if let log = original.log { report.log = copy(log, as: "session-log.jsonl") }
    } catch {
      report.folder = ""
      logger("error", ["where": "bug_folder", "id": .string(original.id.uuidString), "message": .string("\(error)")])
    }
    do {
      try store.append(report)
      return report
    } catch {
      logger("error", ["where": "bug_index", "id": .string(original.id.uuidString), "message": .string("\(error)")])
      return nil
    }
  }
}
