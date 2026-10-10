import Foundation

/// A gentle shake, read from the motion itself (CG story 146, #164): iOS's own shake gesture wants a hard shake,
/// and reporting should stay a reflex, not a workout.
///
/// A shake is a quick back-and-forth: flicks of at least `threshold` g along the strongest axis, alternating in
/// direction, more than `reversals` changes of direction within `window` seconds. Walking and setting the phone down
/// are one push, not alternating flicks. Platform-free: feed it user-acceleration samples (gravity removed), in g.
/// `ShakeMotion` (iOS) feeds it from Core Motion at 50 Hz.
public struct ShakeGesture: Sendable {
  public var threshold = 1.5
  public var reversals = 3
  public var window = 1.0
  /// After a shake, nothing for this long: one shake, one sheet.
  public var cooldown = 2.0

  private var flicks: [(t: Double, sign: Int)] = []
  private var peak = 0.0
  private var quietUntil = -Double.infinity

  public init() {}

  /// Returns the shake's peak force in g when this sample completes one, else nil.
  public mutating func feed(x: Double, y: Double, z: Double, t: Double) -> Double? {
    guard t >= quietUntil else { return nil }
    let axis = [x, y, z].max { abs($0) < abs($1) } ?? 0
    guard abs(axis) >= threshold else { return nil }
    let sign = axis > 0 ? 1 : -1
    flicks.removeAll { t - $0.t > window }
    if flicks.isEmpty { peak = 0 }
    peak = max(peak, abs(axis))
    // Samples of the same push repeat its sign; only a change of direction is a new flick.
    if flicks.last?.sign != sign { flicks.append((t, sign)) }
    guard flicks.count > reversals else { return nil }
    let found = peak
    flicks.removeAll()
    peak = 0
    quietUntil = t + cooldown
    return found
  }
}
