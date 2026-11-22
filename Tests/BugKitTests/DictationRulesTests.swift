import Foundation
import Testing
@testable import BugKit

// The audio session's category and options, as AVDictationCapture.keepsDiscoveryActivation reads them.
@Test func discoveryKeepsActivationOnlyForPlainMixingHosts() {
  // .playback with .mixWithOthers; .ambient with no options
  #expect(
    DictationRules.keepsDiscoveryActivation(
      ambient: false, mixesWithOthers: true, ducksOthers: false, interruptsSpokenAudio: false))
  #expect(
    DictationRules.keepsDiscoveryActivation(
      ambient: true, mixesWithOthers: false, ducksOthers: false, interruptsSpokenAudio: false))
  // .playback with [.mixWithOthers, .duckOthers]
  #expect(
    !DictationRules.keepsDiscoveryActivation(
      ambient: false, mixesWithOthers: true, ducksOthers: true, interruptsSpokenAudio: false))
  // .playback with .interruptSpokenAudioAndMixWithOthers, which also holds .mixWithOthers' bit
  #expect(
    !DictationRules.keepsDiscoveryActivation(
      ambient: false, mixesWithOthers: true, ducksOthers: false, interruptsSpokenAudio: true))
  // .ambient with .duckOthers
  #expect(
    !DictationRules.keepsDiscoveryActivation(
      ambient: true, mixesWithOthers: false, ducksOthers: true, interruptsSpokenAudio: false))
  // .soloAmbient or .playback with no options
  #expect(
    !DictationRules.keepsDiscoveryActivation(
      ambient: false, mixesWithOthers: false, ducksOthers: false, interruptsSpokenAudio: false))
}

@Test func appleNoSpeechEndsQuietlyOnlyAfterFinish() {
  let noSpeech = NSError(domain: "kAFAssistantErrorDomain", code: 1110)
  let ended = NSError(domain: "kAFAssistantErrorDomain", code: 301)
  let network = NSError(domain: "kAFAssistantErrorDomain", code: 1101)
  #expect(DictationRules.endsQuietly(noSpeech, finishing: true))
  #expect(DictationRules.endsQuietly(ended, finishing: true))
  #expect(!DictationRules.endsQuietly(noSpeech, finishing: false))
  #expect(!DictationRules.endsQuietly(network, finishing: true))
  #expect(!DictationRules.endsQuietly(NSError(domain: NSURLErrorDomain, code: 1110), finishing: true))
  #expect(!DictationRules.endsQuietly(nil, finishing: true))
}

// #128: AirPods' HFP link takes the input as dictation starts and the engine stops about 150 ms in.
@Test func anEarlyEngineChangeRebuildsTheMicrophoneOnce() {
  let builtIn = DictationAudioShape(
    sampleRate: 48_000, channels: 1, inputPorts: ["MicrophoneBuiltIn"], outputPorts: ["Speaker"], ioBufferDuration: 0.02
  )
  let airPods = DictationAudioShape(
    sampleRate: 24_000, channels: 1, inputPorts: ["BluetoothHFP"], outputPorts: ["BluetoothHFP"],
    ioBufferDuration: 0.016)
  // Still running: only logged.
  #expect(DictationRules.engineChange(sinceStart: 0.1, running: true, rebuilt: false, after: airPods) == .ignore)
  // Stopped in the first second: rebuild, once.
  #expect(DictationRules.engineChange(sinceStart: 0.144, running: false, rebuilt: false, after: builtIn) == .rebuild)
  #expect(DictationRules.engineChange(sinceStart: 0.3, running: false, rebuilt: true, after: airPods) == .fail)
  // A headset still settling gets two seconds; any other input one.
  #expect(DictationRules.engineChange(sinceStart: 1.5, running: false, rebuilt: false, after: airPods) == .rebuild)
  #expect(DictationRules.engineChange(sinceStart: 1.5, running: false, rebuilt: false, after: builtIn) == .fail)
  #expect(DictationRules.engineChange(sinceStart: 2.5, running: false, rebuilt: false, after: airPods) == .fail)
}

// #128: the input moving onto AirPods as dictation starts is left to the engine rebuild, not stopped as a route change.
@Test func anInputMovingOntoTheHeadsetAtStartIsLeftToTheEngineRebuild() {
  let airPods = DictationAudioShape(
    sampleRate: 24_000, channels: 1, inputPorts: ["BluetoothHFP"], outputPorts: ["BluetoothHFP"],
    ioBufferDuration: 0.016)
  let usb = DictationAudioShape(
    sampleRate: 48_000, channels: 1, inputPorts: ["USBAudio"], outputPorts: ["Speaker"], ioBufferDuration: 0.01)
  #expect(!DictationRules.routeChangeStops(sinceStart: 0.8, inputChanged: true, after: airPods))
  #expect(!DictationRules.routeChangeStops(sinceStart: 1.5, inputChanged: true, after: airPods))
  #expect(DictationRules.routeChangeStops(sinceStart: 2.5, inputChanged: true, after: airPods))
  #expect(DictationRules.routeChangeStops(sinceStart: 1.2, inputChanged: true, after: usb))
  #expect(!DictationRules.routeChangeStops(sinceStart: 0.4, inputChanged: true, after: usb))
  #expect(!DictationRules.routeChangeStops(sinceStart: 5, inputChanged: false, after: usb))
  #expect(!DictationRules.routeChangeStops(sinceStart: 0.1, inputChanged: false, after: airPods))
}

@Test func anEngineChangeCarriesWhatChanged() {
  let before = DictationAudioShape(
    sampleRate: 48_000, channels: 1, inputPorts: ["MicrophoneBuiltIn"], outputPorts: ["Speaker"], ioBufferDuration: 0.02
  )
  let after = DictationAudioShape(
    sampleRate: 24_000, channels: 1, inputPorts: ["BluetoothHFP"], outputPorts: ["BluetoothHFP"],
    ioBufferDuration: 0.016)
  let fields = DictationRules.engineChangeFields(
    sinceStart: 0.1444, thisEngine: true, running: false, before: before, after: after, action: .rebuild)
  #expect(fields["where"] == .string("engine_config"))
  #expect(fields["ms_since_start"] == .int(144))
  #expect(fields["this_engine"] == .bool(true))
  #expect(fields["engine_running"] == .bool(false))
  #expect(fields["sample_rate_before"] == .double(48_000))
  #expect(fields["sample_rate_after"] == .double(24_000))
  #expect(fields["channels_before"] == .int(1))
  #expect(fields["channels_after"] == .int(1))
  #expect(fields["input_before"] == .string("MicrophoneBuiltIn"))
  #expect(fields["input_after"] == .string("BluetoothHFP"))
  #expect(fields["output_after"] == .string("BluetoothHFP"))
  #expect(fields["io_buffer_ms_before"] == .double(20))
  #expect(fields["io_buffer_ms_after"] == .double(16))
  #expect(fields["action"] == .string("rebuild"))
  // No shape at start (the change came before one was read): the after fields alone.
  let early = DictationRules.engineChangeFields(
    sinceStart: 0, thisEngine: false, running: false, before: nil, after: after, action: .fail)
  #expect(early["sample_rate_before"] == nil)
  #expect(early["sample_rate_after"] == .double(24_000))
}
