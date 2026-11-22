import Foundation

/// The rules dictation's iOS-only parts follow, kept out of AVFoundation and Speech so the host tests see them.
enum DictationRules {
  /// After Stop/Log it, "no speech detected" or a request ended with the audio is a normal end; the note is kept.
  static func endsQuietly(_ error: Error?, finishing: Bool) -> Bool {
    guard finishing, let error = error as NSError?, error.domain == "kAFAssistantErrorDomain" else { return false }
    return [1110, 301].contains(error.code)
  }

  /// Listing the microphones keeps its activation only for a host that mixes (or is ambient) without ducking or
  /// interrupting other audio. `AVDictationCapture.keepsDiscoveryActivation` reads these from the audio session.
  static func keepsDiscoveryActivation(
    ambient: Bool, mixesWithOthers: Bool, ducksOthers: Bool, interruptsSpokenAudio: Bool
  ) -> Bool {
    let changesOtherAudio = ducksOthers || interruptsSpokenAudio
    return !changesOtherAudio && (ambient || mixesWithOthers)
  }

  /// What to do when the audio engine is reconfigured while dictating (#128). A running engine needs nothing. A stopped
  /// one is rebuilt once if the change came in the first second, or the first two while the input is a Bluetooth HFP
  /// headset (its link can still be coming up as dictation starts); otherwise dictation stops.
  static func engineChange(
    sinceStart: Double, running: Bool, rebuilt: Bool, after: DictationAudioShape
  ) -> DictationEngineChange {
    if running { return .ignore }
    return !rebuilt && sinceStart < settling(after) ? .rebuild : .fail
  }

  /// Whether the input moving to another microphone stops dictation: only once the engine change's settling time has
  /// passed, so an input moving onto the headset as dictation starts is left to the engine rebuild.
  static func routeChangeStops(sinceStart: Double, inputChanged: Bool, after: DictationAudioShape) -> Bool {
    inputChanged && sinceStart >= settling(after)
  }

  private static func settling(_ shape: DictationAudioShape) -> Double {
    shape.inputPorts.contains("BluetoothHFP") ? 2.0 : 1.0
  }

  /// The `dictation_engine_config` log line, and the state a failure copies: what the microphone was when the tap was
  /// installed, what it is now, and what was done.
  static func engineChangeFields(
    sinceStart: Double, thisEngine: Bool, running: Bool, before: DictationAudioShape?, after: DictationAudioShape,
    action: DictationEngineChange
  ) -> [String: JSONValue] {
    var fields: [String: JSONValue] = [
      "where": "engine_config", "ms_since_start": .int(Int((sinceStart * 1000).rounded(.down))),
      "this_engine": .bool(thisEngine), "engine_running": .bool(running), "action": .string(action.rawValue),
    ]
    fields.merge(after.fields("after")) { first, _ in first }
    if let before { fields.merge(before.fields("before")) { first, _ in first } }
    return fields
  }
}

enum DictationEngineChange: String, Sendable {
  case ignore, rebuild, fail
}

/// The microphone as the audio session reports it at one moment (`AVAudioSession`'s sample rate, input channels,
/// route port types and I/O buffer duration), so an engine change can say what changed.
struct DictationAudioShape: Equatable, Sendable {
  var sampleRate: Double
  var channels: Int
  var inputPorts: [String]
  var outputPorts: [String]
  var ioBufferDuration: Double

  func fields(_ suffix: String) -> [String: JSONValue] {
    [
      "sample_rate_\(suffix)": .double(sampleRate), "channels_\(suffix)": .int(channels),
      "input_\(suffix)": .string(inputPorts.joined(separator: ",")),
      "output_\(suffix)": .string(outputPorts.joined(separator: ",")),
      "io_buffer_ms_\(suffix)": .double((ioBufferDuration * 1000).rounded()),
    ]
  }
}
