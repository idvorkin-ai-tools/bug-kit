#if canImport(UIKit) && os(iOS)
import Foundation
import Testing
@testable import BugKit

@MainActor
@Test func dictationCustomProviderSkipsSpeechPermissionAndUsesSelectedMicrophone() async throws {
  let fixture = try DictationFixture()
  defer { fixture.cleanup() }
  await fixture.dictation.refreshMicrophones()
  fixture.dictation.selectMicrophone("usb")
  fixture.dictation.toggle(note: "typed") { fixture.note.value = $0 }
  try await fixture.until { fixture.dictation.listening }
  #expect(fixture.permissions.speech == 0)
  #expect(fixture.capture.preferred == "usb")
  await fixture.provider.emit("spoken")
  try await fixture.until { fixture.note.value == "typed spoken" }
  let saved = await fixture.dictation.finish(why: "log_it")
  #expect(saved)
  #expect(fixture.note.value == "typed spoken final")
  #expect(!fixture.dictation.busy)
  #expect(fixture.capture.restores > 0)
}

@MainActor
@Test func dictationCancelWhilePermissionPendingCannotStartLater() async throws {
  let gate = MicrophonePermissionGate()
  let fixture = try DictationFixture(microphone: { await gate.wait() })
  defer { fixture.cleanup() }
  fixture.dictation.toggle(note: "typed") { fixture.note.value = $0 }
  try await fixture.until { gate.waiting }
  fixture.dictation.stop(why: "closed")
  gate.release()
  try await Task.sleep(for: .milliseconds(30))
  #expect(await fixture.provider.starts == 0)
  #expect(fixture.capture.starts == 0)
  #expect(!fixture.dictation.busy)
  #expect(fixture.note.value == "")
}

@MainActor
@Test func dictationFailureRestoresCaptureAndKeepsNote() async throws {
  let fixture = try DictationFixture()
  defer { fixture.cleanup() }
  fixture.dictation.toggle(note: "typed") { fixture.note.value = $0 }
  try await fixture.until { fixture.dictation.listening }
  await fixture.provider.emit("spoken")
  try await fixture.until { fixture.note.value == "typed spoken" }
  await fixture.provider.fail()
  try await fixture.until { !fixture.dictation.busy }
  #expect(fixture.note.value == "typed spoken")
  #expect(fixture.dictation.problem != nil)
  #expect(fixture.capture.restores > 0)
}

@MainActor
@Test func dictationDoesNotPromptForMicrophoneWhenOpeningTheSheet() async throws {
  let fixture = try DictationFixture(hasMicrophone: false)
  defer { fixture.cleanup() }
  await fixture.dictation.refreshMicrophones(requestPermission: false)
  #expect(fixture.permissions.microphone == 0)
  #expect(fixture.capture.lists == 0)
  #expect(fixture.dictation.microphones.isEmpty)
}

@MainActor
@Test func dictationRemovedMicrophoneReturnsPickerToAutomatic() async throws {
  let fixture = try DictationFixture()
  defer { fixture.cleanup() }
  await fixture.dictation.refreshMicrophones()
  fixture.dictation.selectMicrophone("usb")
  fixture.capture.inputs.removeAll { $0.id == "usb" }
  await fixture.dictation.refreshMicrophones()
  #expect(fixture.dictation.selectedMicrophoneID == nil)
  #expect(fixture.dictation.selectedMicrophoneName == "Automatic")
  #expect(fixture.defaults.string(forKey: "bugkit.dictation_microphone") == nil)
}

@MainActor
@Test func dictationHostRecordingSkipsMicrophoneDiscovery() async throws {
  let fixture = try DictationFixture()
  defer { fixture.cleanup() }
  await fixture.dictation.refreshMicrophones(requestPermission: false, hostMicrophoneBusy: { true })
  await fixture.dictation.refreshMicrophones(hostMicrophoneBusy: { true })
  #expect(fixture.capture.lists == 0)
  #expect(fixture.permissions.microphone == 0)
  #expect(fixture.dictation.microphones.isEmpty)
  await fixture.dictation.refreshMicrophones(requestPermission: false)
  #expect(fixture.capture.lists == 1)
}

@MainActor
@Test func dictationHostRecordingStartedDuringPermissionPromptSkipsDiscovery() async throws {
  let gate = MicrophonePermissionGate()
  let fixture = try DictationFixture(microphone: { await gate.wait() })
  defer { fixture.cleanup() }
  let host = HostRecording()
  let refresh = Task { await fixture.dictation.refreshMicrophones(hostMicrophoneBusy: { host.busy }) }
  try await fixture.until { gate.waiting }
  host.busy = true
  gate.release()
  await refresh.value
  #expect(fixture.permissions.microphone == 1)
  #expect(fixture.capture.lists == 0)
  #expect(fixture.dictation.microphones.isEmpty)
  #expect(!fixture.dictation.refreshingMicrophones)
}

@Test func appleNoSpeechEndsQuietlyOnlyAfterFinish() {
  let noSpeech = NSError(domain: "kAFAssistantErrorDomain", code: 1110)
  let ended = NSError(domain: "kAFAssistantErrorDomain", code: 301)
  let network = NSError(domain: "kAFAssistantErrorDomain", code: 1101)
  #expect(AppleDictationProvider.endsQuietly(noSpeech, finishing: true))
  #expect(AppleDictationProvider.endsQuietly(ended, finishing: true))
  #expect(!AppleDictationProvider.endsQuietly(noSpeech, finishing: false))
  #expect(!AppleDictationProvider.endsQuietly(network, finishing: true))
  #expect(!AppleDictationProvider.endsQuietly(NSError(domain: NSURLErrorDomain, code: 1110), finishing: true))
  #expect(!AppleDictationProvider.endsQuietly(nil, finishing: true))
}

@MainActor
@Test func dictationBusyHostSkipsPermissionsAndProviderStart() async throws {
  let fixture = try DictationFixture(hostMicrophoneBusy: { true })
  defer { fixture.cleanup() }
  fixture.dictation.toggle(note: "typed") { fixture.note.value = $0 }
  await fixture.dictation.refreshMicrophones()
  #expect(fixture.permissions.microphone == 0)
  #expect(await fixture.provider.starts == 0)
  #expect(fixture.capture.starts == 0)
  #expect(fixture.capture.lists == 0)
  #expect(!fixture.dictation.busy)
}

@MainActor
@Test func dictationHostRecordingStartedDuringStartupNeverCaptures() async throws {
  for waitForProvider in [false, true] {
    let gate = MicrophonePermissionGate()
    let host = HostRecording()
    let fixture = try DictationFixture(microphone: {
                                        if waitForProvider { return true }
                                        return await gate.wait()
                                      },
                                      hostMicrophoneBusy: { host.busy })
    defer { gate.release(); fixture.cleanup() }
    if waitForProvider { await fixture.provider.holdStart { _ = await gate.wait() } }
    fixture.dictation.toggle(note: "typed") { fixture.note.value = $0 }
    try await fixture.until { gate.waiting }
    host.busy = true
    gate.release()
    try await fixture.until { !fixture.dictation.busy }
    #expect(fixture.capture.starts == 0)
    #expect(await fixture.provider.starts == (waitForProvider ? 1 : 0))
    #expect(fixture.dictation.problem == "The microphone is in use by this app")
    for _ in 0..<100 {
      if await fixture.provider.cancellations > 0 { break }
      try await Task.sleep(for: .milliseconds(5))
    }
    #expect(await fixture.provider.cancellations > 0)
  }
}

@MainActor
private final class DictationFixture {
  let capture = TestDictationCapture()
  let provider = TestNoteProvider()
  let note = NoteValue()
  let permissions = PermissionCounts()
  let defaults: UserDefaults
  let suite: String
  let dictation: NoteDictation
  init(microphone: (@MainActor () async -> Bool)? = nil, hasMicrophone: Bool = true,
       hostMicrophoneBusy: @escaping @MainActor () -> Bool = { false }) throws {
    suite = "BugKit-dictation-\(UUID())"
    defaults = try #require(UserDefaults(suiteName: suite))
    let counts = permissions
    dictation = NoteDictation(logger: { _, _ in }, providerFactory: { [provider] in provider }, capture: capture,
      permissions: DictationPermissions(speech: { counts.speech += 1; return true },
        microphone: { counts.microphone += 1; return await microphone?() ?? true },
        hasMicrophonePermission: { hasMicrophone }), defaults: defaults, hostMicrophoneBusy: hostMicrophoneBusy)
  }
  func until(_ predicate: @MainActor () -> Bool) async throws {
    for _ in 0..<2_000 {
      if predicate() { return }
      try await Task.sleep(for: .milliseconds(5))
    }
    Issue.record("dictation did not reach expected state")
    throw TestNoteError.failed
  }
  func cleanup() { dictation.stop(why: "test_closed"); defaults.removePersistentDomain(forName: suite) }
}

@MainActor private final class NoteValue { var value = "" }
@MainActor private final class HostRecording { var busy = false }
@MainActor private final class PermissionCounts { var speech = 0; var microphone = 0 }
@MainActor private final class MicrophonePermissionGate {
  var waiting = false
  private var continuation: CheckedContinuation<Bool, Never>?
  func wait() async -> Bool { waiting = true; return await withCheckedContinuation { continuation = $0 } }
  func release() { continuation?.resume(returning: true); continuation = nil }
}

@MainActor private final class TestDictationCapture: DictationCapture {
  var onFailure: (@MainActor (String) -> Void)?
  var currentInputID: String? { preferred ?? "built-in" }
  var inputs = [BugMicrophone(id: "built-in", name: "iPhone Microphone", kind: "builtInMic"),
                BugMicrophone(id: "usb", name: "USB Microphone", kind: "usbAudio")]
  var preferred: String?
  var starts = 0, restores = 0, lists = 0
  private var audio: AsyncStream<Data>.Continuation?
  func availableMicrophones() throws -> [BugMicrophone] { lists += 1; return inputs }
  func start(preferredInputID: String?) throws -> AsyncStream<Data> {
    starts += 1; preferred = preferredInputID
    let (stream, continuation) = AsyncStream<Data>.makeStream()
    audio = continuation; continuation.yield(Data([0, 0]))
    return stream
  }
  func stop() { audio?.finish(); audio = nil }
  func restore() { restores += 1 }
}

private enum TestNoteError: Error { case failed }
private actor TestNoteProvider: BugDictationProvider {
  nonisolated let name = "Test server"
  nonisolated let requiresSpeechAuthorization = false
  private var results: AsyncThrowingStream<String, Error>.Continuation?
  private(set) var starts = 0
  private(set) var cancellations = 0
  private var startGate: (@Sendable () async -> Void)?
  func holdStart(_ gate: @escaping @Sendable () async -> Void) { startGate = gate }
  func start() async throws -> AsyncThrowingStream<String, Error> {
    starts += 1
    await startGate?()
    let (stream, continuation) = AsyncThrowingStream<String, Error>.makeStream()
    results = continuation; return stream
  }
  func appendAudio(_ pcm16: Data) async throws {}
  func emit(_ text: String) { results?.yield(text) }
  func fail() { results?.finish(throwing: TestNoteError.failed); results = nil }
  func finish() async throws { results?.yield("spoken final"); results?.finish(); results = nil }
  func cancel() async { cancellations += 1; results?.finish(); results = nil }
}
#endif
