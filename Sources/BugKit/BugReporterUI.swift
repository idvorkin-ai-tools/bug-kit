#if canImport(UIKit) && os(iOS)
  import SwiftUI
  import UIKit

  /// The app's side of a report: everything BugKit cannot know by itself.
  public struct BugReporterHooks {
    /// The current screen's name ("home", "playback").
    public var screen: @MainActor () -> String
    /// What the app attaches, read at the moment the dialog opens (EA: exercise, playhead; MM: mode, replay time).
    public var context: @MainActor () -> [String: JSONValue]
    /// The session log's path under Documents and the milliseconds since it began; nil when the app has none.
    public var sessionLog: @MainActor () -> (path: String, tMs: Int)?
    /// The app's logger. It receives `bug_report_open`, `bug_report`, `bug_report_cancel` and `error` events.
    public var logger: BugLogger
    /// Extra files for the report's folder (a clip, video segments); nil for none.
    public var extraFiles: BugExtraFiles?

    public init(
      screen: @escaping @MainActor () -> String = { "" },
      context: @escaping @MainActor () -> [String: JSONValue] = { [:] },
      sessionLog: @escaping @MainActor () -> (path: String, tMs: Int)? = { nil },
      logger: @escaping BugLogger,
      extraFiles: BugExtraFiles? = nil
    ) {
      self.screen = screen; self.context = context; self.sessionLog = sessionLog; self.logger = logger
      self.extraFiles = extraFiles
    }
  }

  /// Opens the report dialog and saves what it says. One per app, created at launch:
  ///
  ///     let reporter = BugReporter(hooks: BugReporterHooks(logger: { log.event($0, $1) }))
  ///     ContentView().bugReporting(reporter)
  @MainActor
  public final class BugReporter: ObservableObject {
    @Published public var flow = BugReportFlow()
    /// The moment the dialog opened: the screen as it was, and the context then.
    @Published public private(set) var screenshot: UIImage?
    @Published public private(set) var context: [String: JSONValue] = [:]
    /// What the last save says, for a status line or a toast.
    @Published public private(set) var lastStatus: String?

    public let hooks: BugReporterHooks
    public let writer: BugReportWriter
    /// Set false to ignore shakes (EA's instrumented run, story 037: a phone in a pocket shakes).
    public var shakeEnabled = true
    private var screen = ""
    private weak var presented: UIViewController?
    private let dismissWatcher = DismissWatcher()

    public init(hooks: BugReporterHooks, store: BugStore = BugStore(), info: BugAppInfo? = nil) {
      self.hooks = hooks
      let device = "\(BugAppInfo.hardwareModel()) \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
      self.writer = BugReportWriter(
        store: store, info: info ?? .fromMainBundle(device: device), logger: hooks.logger)
      dismissWatcher.onDismiss = { [weak self] in self?.dismissedBySwipe() }
    }

    /// Captures the screen first, then presents the dialog from the topmost view controller, so it opens over any
    /// sheet already up instead of replacing it (EA #41: a shake from the Workouts sheet closed that sheet).
    public func open(from source: BugReportFlow.Source) {
      if source == .shake, !shakeEnabled {
        hooks.logger("bug_report_open", ["source": "shake", "ignored": true])
        return
      }
      guard flow.open(from: source) else {
        hooks.logger("bug_report_open", ["source": .string(source.rawValue), "already_open": true])
        return
      }
      let window = Self.keyWindow()
      screenshot = window.map(Self.snapshot)
      context = hooks.context()
      screen = hooks.screen()
      guard let top = window?.rootViewController.map(Self.topmost) else {
        hooks.logger("error", ["where": "bug_report_open", "message": "no window to present from"])
        flow.cancel()
        return
      }
      let host = UIHostingController(rootView: BugReportSheet(reporter: self))
      host.modalPresentationStyle = .formSheet
      host.presentationController?.delegate = dismissWatcher
      presented = host
      top.present(host, animated: true)
      hooks.logger(
        "bug_report_open",
        [
          "source": .string(source.rawValue), "screen": .string(screen), "screenshot": .bool(screenshot != nil),
          "over": .string(String(describing: type(of: top))),
        ])
    }

    /// "Log it" or "Log it and another". The save runs in a Task; the dialog closes (or empties) at once.
    public func log(another: Bool) {
      guard let note = flow.log(another: another) else { return }
      let png = screenshot?.pngData()
      let screen = screen, context = context, sessionLog = hooks.sessionLog()
      let writer = writer, extra = hooks.extraFiles
      if !another { close() }
      Task { @MainActor in
        let report = await writer.save(
          note: note, screen: screen, context: context, screenshotPNG: png, log: sessionLog, extraFiles: extra)
        self.lastStatus = report.folder.isEmpty ? "Problem noted in the log only" : "Problem logged. Thanks."
      }
    }

    public func cancel() {
      hooks.logger("bug_report_cancel", ["saved": .int(flow.savedThisTime)])
      flow.cancel()
      close()
    }

    private func close() {
      presented?.dismiss(animated: true)
      presented = nil
      if !flow.isPresented { screenshot = nil }
    }

    private func dismissedBySwipe() {
      guard flow.isPresented else { return }
      hooks.logger("bug_report_cancel", ["saved": .int(flow.savedThisTime), "swipe": true])
      flow.cancel()
      presented = nil
      screenshot = nil
    }

    static func keyWindow() -> UIWindow? {
      let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
      return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    static func snapshot(_ window: UIWindow) -> UIImage {
      UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
        window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
      }
    }

    /// The view controller on top of every presented one: present from here, or UIKit refuses (or, with SwiftUI's
    /// `.sheet` on the root, swaps out the sheet that is up).
    public static func topmost(_ root: UIViewController) -> UIViewController {
      var top = root
      while let next = top.presentedViewController, !next.isBeingDismissed { top = next }
      return top
    }
  }

  /// Swipe-to-dismiss on the sheet counts as Cancel.
  @MainActor
  private final class DismissWatcher: NSObject, UIAdaptivePresentationControllerDelegate {
    var onDismiss: (() -> Void)?
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { onDismiss?() }
  }

  /// The dialog: a note, the screenshot, what is attached, and "Log it" / "Log it and another".
  public struct BugReportSheet: View {
    @ObservedObject var reporter: BugReporter
    @FocusState private var noteFocused: Bool

    public init(reporter: BugReporter) { self.reporter = reporter }

    public var body: some View {
      NavigationStack {
        Form {
          Section("What went wrong?") {
            TextField("One line is enough", text: $reporter.flow.note, axis: .vertical)
              .lineLimit(3...8)
              .focused($noteFocused)
              .id(reporter.flow.draft)
            if reporter.flow.savedThisTime > 0 {
              Text("\(reporter.flow.savedThisTime) logged from this moment").font(.footnote).foregroundStyle(.secondary)
            }
          }
          Section("Attached automatically") {
            if let shot = reporter.screenshot {
              Image(uiImage: shot).resizable().scaledToFit().frame(maxHeight: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            ForEach(reporter.context.sorted(by: { $0.key < $1.key }), id: \.key) { item in
              LabeledContent(item.key, value: item.value.display)
            }
          }
        }
        .navigationTitle("Report a problem")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
          ToolbarItem(placement: .cancellationAction) { Button("Cancel") { reporter.cancel() } }
          ToolbarItemGroup(placement: .confirmationAction) {
            Button("Log it and another") {
              reporter.log(another: true)
              noteFocused = true
            }
            .disabled(!reporter.flow.canLog)
            Button("Log it") { reporter.log(another: false) }
              .disabled(!reporter.flow.canLog)
              .keyboardShortcut(.defaultAction)
          }
        }
        .onAppear { noteFocused = true }
      }
    }
  }

  /// For when shaking is awkward (an iPad on a stand, a phone on a tripod).
  public struct BugReportButton: View {
    @ObservedObject var reporter: BugReporter
    let title: String

    public init(_ title: String = "Report a problem", reporter: BugReporter) {
      self.title = title; self.reporter = reporter
    }

    public var body: some View {
      Button { reporter.open(from: .button) } label: { Label(title, systemImage: "ladybug") }
    }
  }

  /// Calls `onShake` when the device is shaken. Sits invisibly in the view tree and holds first responder.
  public struct ShakeDetector: UIViewControllerRepresentable {
    let onShake: () -> Void

    public init(onShake: @escaping () -> Void) { self.onShake = onShake }

    public final class Controller: UIViewController {
      var onShake: (() -> Void)?
      override public var canBecomeFirstResponder: Bool { true }
      override public func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
      }
      override public func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake { onShake?() }
        super.motionEnded(motion, with: event)
      }
    }

    public func makeUIViewController(context: Context) -> Controller {
      let controller = Controller()
      controller.onShake = onShake
      controller.view.isUserInteractionEnabled = false
      return controller
    }

    public func updateUIViewController(_ controller: Controller, context: Context) {
      controller.onShake = onShake
    }
  }

  extension View {
    /// Shake anywhere, or ⌘I on a hardware keyboard (the iPad), opens the report dialog.
    public func bugReporting(_ reporter: BugReporter) -> some View {
      background {
        ZStack {
          ShakeDetector { reporter.open(from: .shake) }
          Button("Report a problem") { reporter.open(from: .key) }
            .keyboardShortcut("i", modifiers: .command)
            .opacity(0)
            .accessibilityHidden(true)
        }
        .frame(width: 0, height: 0)
      }
    }
  }
#endif
