#if canImport(UIKit) && os(iOS)
  import UIKit
  import UIKit.UIGestureRecognizerSubclass

  /// Public UIKit metadata, not the system's private VoiceOver/XCTest tree. Text-entry subtrees are redacted.
  @MainActor
  public enum AccessibilitySnapshot {
    public static func capture(_ root: UIView, maxNodes: Int = 500, maxDepth: Int = 30) -> Data {
      let limit = min(max(maxNodes, 1), 2_000)
      var nodes: [[String: JSONValue]] = []
      var visited = Set<ObjectIdentifier>()
      var truncated = false
      func walk(_ object: NSObject, parent: Int?, depth: Int, relation: String) {
        guard !visited.contains(ObjectIdentifier(object)) else { return }
        guard nodes.count < limit, depth <= min(max(maxDepth, 0), 50) else { truncated = true; return }
        visited.insert(ObjectIdentifier(object))
        let index = nodes.count
        var node: [String: JSONValue] = ["id": .int(index), "class": .string(String(describing: type(of: object))),
                                         "relation": .string(relation), "is_accessibility_element": .bool(object.isAccessibilityElement)]
        if let parent { node["parent"] = .int(parent) }
        if let view = object as? UIView {
          let frame = view.convert(view.bounds, to: nil)
          node["frame"] = .array([frame.minX, frame.minY, frame.width, frame.height].map { .double(Double($0)) })
          node["hidden"] = .bool(view.isHidden)
          node["alpha"] = .double(Double(view.alpha))
          node["interaction_enabled"] = .bool(view.isUserInteractionEnabled)
          if let identifier = view.accessibilityIdentifier { node["identifier"] = .string(String(identifier.prefix(256))) }
          if view is UITextField || view is UITextView {
            node["redacted"] = .bool(true)
            nodes.append(node)
            return  // Text can leak through child labels and accessibility elements too.
          }
        } else if let element = object as? UIAccessibilityElement {
          let frame = element.accessibilityFrame
          node["frame"] = .array([frame.minX, frame.minY, frame.width, frame.height].map { .double(Double($0)) })
          if let identifier = element.accessibilityIdentifier { node["identifier"] = .string(String(identifier.prefix(256))) }
        }
        if let label = object.accessibilityLabel { node["label"] = .string(String(label.prefix(512))) }
        if let hint = object.accessibilityHint { node["hint"] = .string(String(hint.prefix(512))) }
        node["traits"] = .string(String(object.accessibilityTraits.rawValue))
        // Never read accessibilityValue: it may contain entered or secure text.
        nodes.append(node)
        if let view = object as? UIView {
          for child in view.subviews {
            if nodes.count >= limit { truncated = true; break }
            walk(child, parent: index, depth: depth + 1, relation: "subview")
          }
        }
        if let elements = object.accessibilityElements {
          for element in elements.prefix(limit) {
            if nodes.count >= limit { truncated = true; break }
            if let child = element as? NSObject {
              walk(child, parent: index, depth: depth + 1, relation: "accessibility_element")
            }
          }
          if elements.count > limit { truncated = true }
          return
        }
        let count = object.accessibilityElementCount()
        if count > 0, count != NSNotFound {
          for i in 0..<min(count, limit) {
            if nodes.count >= limit { truncated = true; break }
            if let child = object.accessibilityElement(at: i) as? NSObject {
              walk(child, parent: index, depth: depth + 1, relation: "accessibility_element")
            }
          }
          if count > limit { truncated = true }
        }
      }
      walk(root, parent: nil, depth: 0, relation: "root")
      let record: [String: JSONValue] = [
        "schema_version": 1, "captured_at": .string(BugReport.formatDate(Date())),
        "scope": "app UIKit views and public accessibility containers; SwiftUI virtual elements may be absent",
        "values_redacted": true, "truncated": .bool(truncated), "nodes": .array(nodes.map(JSONValue.object)),
      ]
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      return (try? encoder.encode(record.mapValues(SessionLog.sanitize))) ?? Data("{}".utf8)
    }
  }

  /// Watches touch sequences without recognizing, cancelling or delaying the app's gestures.
  @MainActor
  final class InteractionCapture: NSObject {
    private weak var window: UIWindow?
    private var observer: TouchObserver?
    private let controls = NSHashTable<UIControl>.weakObjects()
    private let record: (String, [String: JSONValue]) -> Void

    init(record: @escaping (String, [String: JSONValue]) -> Void) { self.record = record }

    func start(in window: UIWindow) {
      guard self.window !== window else { return }
      stop()
      self.window = window
      let observer = TouchObserver()
      observer.name = "BugKitInteractionObserver"
      observer.cancelsTouchesInView = false
      observer.delaysTouchesBegan = false
      observer.delaysTouchesEnded = false
      observer.record = { [weak self] event, fields in self?.record(event, fields) }
      observer.touchView = { [weak self] view in self?.registerAncestors(of: view) }
      window.addGestureRecognizer(observer)
      self.observer = observer
      registerControls(in: window)
    }

    func stop() {
      if let observer { window?.removeGestureRecognizer(observer) }
      observer = nil; window = nil
      for control in controls.allObjects {
        control.removeTarget(self, action: #selector(controlActivated(_:)), for: [.primaryActionTriggered, .valueChanged])
      }
      controls.removeAllObjects()
    }

    private func registerControls(in view: UIView) {
      register(view)
      for child in view.subviews { registerControls(in: child) }
    }

    private func registerAncestors(of view: UIView?) {
      var current = view
      while let view = current { register(view); current = view.superview }
    }

    private func register(_ view: UIView) {
      guard let control = view as? UIControl, !(control is UITextField), !controls.contains(control) else { return }
      controls.add(control)
      control.addTarget(self, action: #selector(controlActivated(_:)), for: [.primaryActionTriggered, .valueChanged])
    }

    @objc private func controlActivated(_ control: UIControl) {
      var fields = Self.describe(control)
      if let toggle = control as? UISwitch { fields["on"] = .bool(toggle.isOn) }
      if let slider = control as? UISlider { fields["value"] = .double(Double(slider.value)) }
      if let segmented = control as? UISegmentedControl { fields["selected_index"] = .int(segmented.selectedSegmentIndex) }
      record("ui_control", fields)
    }

    static func describe(_ view: UIView?) -> [String: JSONValue] {
      guard let view else { return [:] }
      var fields: [String: JSONValue] = ["view_class": .string(String(describing: type(of: view)))]
      var current: UIView? = view
      while let candidate = current {
        if let identifier = candidate.accessibilityIdentifier, !identifier.isEmpty {
          fields["identifier"] = .string(String(identifier.prefix(256)))
          break
        }
        current = candidate.superview
      }
      return fields
    }
  }

  @MainActor
  private final class TouchObserver: UIGestureRecognizer {
    var record: ((String, [String: JSONValue]) -> Void)?
    var touchView: ((UIView?) -> Void)?
    private var starts: [ObjectIdentifier: (CGPoint, TimeInterval, [String: JSONValue])] = [:]

    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
      for touch in touches {
        touchView?(touch.view)
        let point = touch.location(in: view)
        var fields = InteractionCapture.describe(touch.view)
        fields["x"] = .double(Double(point.x)); fields["y"] = .double(Double(point.y))
        fields["touch_type"] = .int(touch.type.rawValue)
        starts[ObjectIdentifier(touch)] = (point, touch.timestamp, fields)
        record?("ui_touch_begin", fields)
      }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
      for touch in touches {
        guard let (start, began, original) = starts.removeValue(forKey: ObjectIdentifier(touch)) else { continue }
        let end = touch.location(in: view)
        let distance = hypot(end.x - start.x, end.y - start.y)
        let duration = touch.timestamp - began
        var fields = original
        fields["dx"] = .double(Double(end.x - start.x)); fields["dy"] = .double(Double(end.y - start.y))
        fields["duration_ms"] = .int(Int(duration * 1_000))
        fields["tap_count"] = .int(touch.tapCount)
        record?(distance > 10 ? "ui_drag" : duration > 0.5 ? "ui_long_press" : "ui_tap", fields)
      }
      if starts.isEmpty { state = .failed }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
      for touch in touches {
        if let (_, _, fields) = starts.removeValue(forKey: ObjectIdentifier(touch)) { record?("ui_touch_cancel", fields) }
      }
      if starts.isEmpty { state = .failed }
    }

    override func reset() { starts.removeAll(); super.reset() }
  }
#endif
