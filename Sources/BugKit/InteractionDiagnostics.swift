import Foundation

/// Bounded JSON Lines breadcrumbs. UI capture owns this on the main actor; apps can also use it with their own logger.
public struct InteractionBreadcrumbs: Sendable {
  public let capacity: Int
  private var lines: [Data] = []

  public init(capacity: Int = 200) { self.capacity = min(max(capacity, 1), 1_000) }
  public var count: Int { lines.count }

  public mutating func record(_ event: String, tMs: Int, fields: [String: JSONValue] = [:]) {
    lines.append(SessionLog.line(type: event, t: tMs, fields: fields))
    if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
  }

  public var jsonLines: Data {
    var result = Data()
    for line in lines { result.append(line); result.append(0x0A) }
    return result
  }
}

/// Frozen before presenting the report UI, so the evidence describes the app underneath the dialog.
public struct BugDiagnosticsSnapshot: Sendable {
  public var interactions: Data?
  public var accessibility: Data?

  public init(interactions: Data? = nil, accessibility: Data? = nil) {
    self.interactions = interactions; self.accessibility = accessibility
  }

  var files: [(String, Data)] {
    var result: [(String, Data)] = []
    if let interactions { result.append(("interactions.jsonl", interactions)) }
    if let accessibility { result.append(("accessibility.json", accessibility)) }
    return result
  }
}
