import Foundation

/// How dictated words join what was typed (CG #239): after it, with one space; nothing typed, just the words.
public enum DictationText {
  public static func merge(before: String, spoken: String) -> String {
    let typed = before.trimmingCharacters(in: .whitespacesAndNewlines)
    return typed.isEmpty ? spoken : "\(typed) \(spoken)"
  }
}

/// Speaking after a pause adds to the note, never replaces it (CG #249: "when I stop talking the input gets
/// replaced"). The recogniser can start a fresh transcription after a pause (on-device recognition does), each
/// result then holding only the new stretch of speech. The note is what was typed, then every finished stretch, then
/// the one being heard. Whether a restart after a pause is the cause is what `dictation_pause` is there to show.
public struct DictationJoin: Equatable, Sendable {
  /// What was typed when listening began, then every finished stretch of speech.
  public private(set) var kept: String
  /// The stretch being heard now, as the recogniser last gave it.
  public private(set) var current = ""
  private var currentStart: Double?
  /// When the stretch being heard last ended, in seconds from the start of listening.
  public private(set) var currentEnd: Double = 0

  public init(typed: String) { kept = typed.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// The whole note so far.
  public var note: String { Self.join(kept, current) }

  /// One result from the recogniser: its text and when its first and last words were spoken, in seconds from the
  /// start of listening. Returns true when it began a new stretch (the one before it was kept).
  @discardableResult
  public mutating func update(text: String, firstStart: Double, lastEnd: Double) -> Bool {
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    var fresh = false
    if let start = currentStart, !current.isEmpty, !text.isEmpty {
      // A result that starts after the last one ended is new speech; so is a shorter one that no longer begins
      // with the same word (the recogniser revises a stretch's words, it does not drop its start).
      let after = firstStart >= currentEnd - 0.05 && firstStart > start
      let restarted = text.count < current.count && Self.firstWord(text) != Self.firstWord(current)
      fresh = after || restarted
    }
    if fresh { kept = Self.join(kept, current) }
    current = text
    currentStart = firstStart
    currentEnd = lastEnd
    return fresh
  }

  private static func join(_ a: String, _ b: String) -> String {
    a.isEmpty ? b : b.isEmpty ? a : "\(a) \(b)"
  }

  private static func firstWord(_ s: String) -> Substring {
    s.split(separator: " ").first.map { $0.lowercased()[...] } ?? ""
  }
}

#if canImport(UIKit) && os(iOS)
  import AVFoundation
  import Speech

  /// Speak the note (CG #239, story 142): the dialog's microphone. Words land in the note as they are said, after
  /// whatever was typed, recognised on the device when it can be. The audio session is mixed while listening, so
  /// music keeps playing, and put back exactly as it was afterwards.
  ///
  /// Needs `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` in Info.plist. Logs
  /// `dictation_start` (on_device), `dictation_stop` (why: tap / log_it / cancel / closed / final / error) and
  /// `dictation_error` (auth, mic, recognizer, error, message), and `dictation_pause` (kept_chars, new_chars,
  /// prev_end_s, new_start_s) each time a pause starts a new stretch of speech.
  @MainActor
  public final class NoteDictation: ObservableObject {
    @Published public private(set) var listening = false
    /// Why it cannot listen, in words for the dialog; nil when it can.
    @Published public private(set) var problem: String?

    private let logger: BugLogger
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var saved: (category: AVAudioSession.Category, mode: AVAudioSession.Mode, options: AVAudioSession.CategoryOptions)?
    private var join = DictationJoin(typed: "")
    private var onText: (@MainActor @Sendable (String) -> Void)?

    public init(logger: @escaping BugLogger) { self.logger = logger }

    public func toggle(note: String, onText: @escaping @MainActor @Sendable (String) -> Void) {
      if listening { stop(why: "tap") } else { start(note: note, onText: onText) }
    }

    private func start(note: String, onText: @escaping @MainActor @Sendable (String) -> Void) {
      problem = nil
      SFSpeechRecognizer.requestAuthorization { status in
        Task { @MainActor in
          guard status == .authorized else {
            self.fail("Speech recognition is off for this app (Settings)", ["auth": .int(status.rawValue)])
            return
          }
          AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
              guard granted else {
                self.fail("The microphone is off for this app (Settings)", ["mic": "denied"])
                return
              }
              self.begin(note: note, onText: onText)
            }
          }
        }
      }
    }

    private func begin(note: String, onText: @escaping @MainActor @Sendable (String) -> Void) {
      guard let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else {
        fail("This device cannot recognise speech right now", ["recognizer": "unavailable"])
        return
      }
      let session = AVAudioSession.sharedInstance()
      saved = (session.category, session.mode, session.categoryOptions)
      let request = SFSpeechAudioBufferRecognitionRequest()
      request.shouldReportPartialResults = true
      request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
      do {
        try session.setCategory(
          .playAndRecord, mode: .default, options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true)
        let input = engine.inputNode
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
          request.append(buffer)
        }
        engine.prepare()
        try engine.start()
      } catch {
        engine.inputNode.removeTap(onBus: 0)
        restoreSession()
        fail("The microphone would not start", ["error": .string("\(error)")])
        return
      }
      self.request = request
      self.onText = onText
      join = DictationJoin(typed: note)
      listening = true
      logger("dictation_start", ["on_device": .bool(request.requiresOnDeviceRecognition)])
      task = recognizer.recognitionTask(with: request) { result, error in
        let text = result?.bestTranscription.formattedString
        let segments = result?.bestTranscription.segments ?? []
        let firstStart = segments.first?.timestamp ?? 0
        let lastEnd = segments.last.map { $0.timestamp + $0.duration } ?? 0
        let final = result?.isFinal ?? false
        let message = error.map { "\($0)" }
        Task { @MainActor in
          guard self.listening else { return }
          if let text {
            let was = self.join.current
            let wasEnd = self.join.currentEnd
            if self.join.update(text: text, firstStart: firstStart, lastEnd: lastEnd) {
              self.logger(
                "dictation_pause",
                ["kept_chars": .int(was.count), "new_chars": .int(text.count), "prev_end_s": .double(wasEnd),
                 "new_start_s": .double(firstStart)])
            }
            self.onText?(self.join.note)
          }
          if let message, !final {
            self.logger("dictation_error", ["error": .string(message)])
            self.stop(why: "error")
          } else if final {
            self.stop(why: "final")
          }
        }
      }
    }

    /// Stops listening: a second tap, Log it, the dialog closing, the end of speech or an error.
    public func stop(why: String) {
      guard listening else { return }
      listening = false
      engine.stop()
      engine.inputNode.removeTap(onBus: 0)
      request?.endAudio()
      task?.finish()
      request = nil
      task = nil
      onText = nil
      restoreSession()
      logger("dictation_stop", ["why": .string(why)])
    }

    private func restoreSession() {
      guard let saved else { return }
      self.saved = nil
      let session = AVAudioSession.sharedInstance()
      do {
        try session.setCategory(saved.category, mode: saved.mode, options: saved.options)
        // Nothing of the app's was sounding before: let go, so other apps resume.
        if saved.category == .ambient || saved.category == .soloAmbient {
          try session.setActive(false, options: .notifyOthersOnDeactivation)
        }
      } catch {
        logger("error", ["where": "dictation_restore", "message": .string("\(error)")])
      }
    }

    private func fail(_ message: String, _ extra: [String: JSONValue]) {
      problem = message
      logger("dictation_error", extra.merging(["message": .string(message)]) { a, _ in a })
    }
  }
#endif
