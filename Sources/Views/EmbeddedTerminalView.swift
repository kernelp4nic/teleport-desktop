import AppKit
import SwiftTerm
import SwiftUI

struct EmbeddedTerminalView: NSViewRepresentable {
  let sessionStore: TerminalSessionStore
  let focusToken: Int
  let scrollbackLines: Int
  let localEchoEnabled: Bool

  func makeNSView(context: Context) -> TerminalContainerView {
    let containerView = TerminalContainerView()
    sessionStore.terminalController.setLocalEchoEnabled(localEchoEnabled)
    sessionStore.terminalController.setScrollbackLines(scrollbackLines)
    containerView.attach(hostView: sessionStore.terminalController.hostView)
    containerView.focusTerminalIfNeeded(using: focusToken)
    return containerView
  }

  func updateNSView(_ nsView: TerminalContainerView, context: Context) {
    sessionStore.terminalController.setLocalEchoEnabled(localEchoEnabled)
    sessionStore.terminalController.setScrollbackLines(scrollbackLines)
    nsView.attach(hostView: sessionStore.terminalController.hostView)
    nsView.focusTerminalIfNeeded(using: focusToken)
  }
}

@MainActor
final class TerminalProcessController: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
  let hostView = TerminalHostView()
  var onProcessTerminated: (@MainActor (Int32?) -> Void)?
  var onProcessOutput: (@MainActor () -> Void)?
  /// Receives every chunk of process output, decoded as UTF-8.
  var onOutputText: (@MainActor (String) -> Void)?
  private var lastRequestID: UUID?
  private var didReportInitialOutput = false
  private var localEchoPreference = false
  private var supportsLocalEcho = false

  func install(_ request: EmbeddedTerminalRequest, localEchoEnabled: Bool) {
    guard lastRequestID != request.id || hostView.terminalView == nil else {
      return
    }

    supportsLocalEcho = localEchoEnabled
    lastRequestID = request.id
    didReportInitialOutput = false
    hostView.launch(
      request: request,
      delegate: self,
      localEchoEnabled: localEchoEnabled && localEchoPreference
    ) { [weak self] in
      self?.handleInitialOutput()
    }
    hostView.terminalView?.onOutput = { [weak self] slice in
      self?.handleOutput(slice)
    }
  }

  /// Writes text to the running process as if the user had typed it.
  func sendInput(_ text: String) {
    hostView.terminalView?.send(txt: text)
  }

  func terminate() {
    hostView.terminate()
  }

  func showSearch() {
    hostView.showSearch()
  }

  func findNext() {
    hostView.findNext()
  }

  func findPrevious() {
    hostView.findPrevious()
  }

  func setLocalEchoEnabled(_ enabled: Bool) {
    localEchoPreference = enabled
    hostView.terminalView?.configureLocalEcho(enabled: enabled && supportsLocalEcho)
  }

  func setScrollbackLines(_ lines: Int) {
    hostView.setScrollbackLines(lines)
  }

  func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

  func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

  func processTerminated(source: TerminalView, exitCode: Int32?) {
    let onProcessTerminated = onProcessTerminated
    let exitCode = exitCode.map(Self.exitStatus(fromWaitStatus:))

    Task { @MainActor in
      onProcessTerminated?(exitCode)
    }
  }

  /// SwiftTerm reports the raw `waitpid` status; decode it like the shell's `$?`.
  nonisolated static func exitStatus(fromWaitStatus status: Int32) -> Int32 {
    let signal = status & 0x7f
    return signal == 0 ? (status >> 8) & 0xff : 128 + signal
  }

  private func handleOutput(_ slice: ArraySlice<UInt8>) {
    guard let onOutputText else {
      return
    }

    let text = String(decoding: slice, as: UTF8.self)

    Task { @MainActor in
      onOutputText(text)
    }
  }

  private func handleInitialOutput() {
    guard !didReportInitialOutput else {
      return
    }

    didReportInitialOutput = true
    let onProcessOutput = onProcessOutput

    Task { @MainActor in
      onProcessOutput?()
    }
  }
}

final class TerminalContainerView: NSView {
  private weak var attachedHostView: TerminalHostView?
  private var lastFocusToken: Int?

  func attach(hostView: TerminalHostView) {
    guard attachedHostView !== hostView else {
      return
    }

    attachedHostView?.removeFromSuperview()
    attachedHostView = hostView

    hostView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(hostView)

    NSLayoutConstraint.activate([
      hostView.leadingAnchor.constraint(equalTo: leadingAnchor),
      hostView.trailingAnchor.constraint(equalTo: trailingAnchor),
      hostView.topAnchor.constraint(equalTo: topAnchor),
      hostView.bottomAnchor.constraint(equalTo: bottomAnchor)
    ])
  }

  func focusTerminalIfNeeded(using token: Int) {
    guard lastFocusToken != token else {
      return
    }

    lastFocusToken = token

    DispatchQueue.main.async { [weak self] in
      self?.attachedHostView?.focusTerminal()
    }
  }
}

final class ObservedLocalProcessTerminalView: LocalProcessTerminalView {
  var onFirstOutput: (() -> Void)?
  var onOutput: ((ArraySlice<UInt8>) -> Void)?
  private var didReceiveOutput = false
  private var localEchoEnabled = false
  private var localEchoPredictor = LocalEchoPredictor()

  func configureLocalEcho(enabled: Bool) {
    guard localEchoEnabled != enabled else { return }
    let update = localEchoPredictor.cancelPendingInput()
    if !update.bytesToDisplay.isEmpty {
      feed(byteArray: update.bytesToDisplay[...])
    }
    localEchoEnabled = enabled
    localEchoPredictor.reset()
  }

  override func send(source: TerminalView, data: ArraySlice<UInt8>) {
    if localEchoEnabled {
      let update = localEchoPredictor.userInput(data)
      if !update.bytesToDisplay.isEmpty {
        feed(byteArray: update.bytesToDisplay[...])
      }
    }

    super.send(source: source, data: data)
  }

  override func dataReceived(slice: ArraySlice<UInt8>) {
    if localEchoEnabled {
      let update = localEchoPredictor.processOutput(slice)
      if !update.bytesToDisplay.isEmpty {
        super.dataReceived(slice: update.bytesToDisplay[...])
      }
    } else {
      super.dataReceived(slice: slice)
    }

    onOutput?(slice)

    guard !didReceiveOutput, !slice.isEmpty else {
      return
    }

    didReceiveOutput = true
    onFirstOutput?()
  }
}

final class TerminalHostView: NSView {
  private let contentInset: CGFloat = 12
  private var scrollbackLines = SettingsStore.defaultTerminalScrollbackLines
  private(set) var terminalView: ObservedLocalProcessTerminalView?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    updateBackgroundColor()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    updateBackgroundColor()
  }

  func launch(
    request: EmbeddedTerminalRequest,
    delegate: LocalProcessTerminalViewDelegate,
    localEchoEnabled: Bool,
    onFirstOutput: @escaping () -> Void
  ) {
    if let terminalView {
      terminalView.terminate()
      terminalView.removeFromSuperview()
    }

    let terminalView = ObservedLocalProcessTerminalView(
      frame: bounds.insetBy(dx: contentInset, dy: contentInset)
    )
    terminalView.translatesAutoresizingMaskIntoConstraints = false
    terminalView.configureNativeColors()
    terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    terminalView.caretColor = .controlAccentColor
    terminalView.processDelegate = delegate
    terminalView.onFirstOutput = onFirstOutput
    terminalView.configureLocalEcho(enabled: localEchoEnabled)
    terminalView.changeScrollback(scrollbackLines == 0 ? nil : scrollbackLines)

    addSubview(terminalView)

    NSLayoutConstraint.activate([
      terminalView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: contentInset),
      terminalView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -contentInset),
      terminalView.topAnchor.constraint(equalTo: topAnchor, constant: contentInset),
      terminalView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -contentInset)
    ])

    terminalView.startProcess(
      executable: request.executable,
      args: request.args,
      environment: request.environment,
      execName: request.execName,
      currentDirectory: request.currentDirectory
    )

    self.terminalView = terminalView
  }

  func terminate() {
    terminalView?.processDelegate = nil
    terminalView?.terminate()
  }

  func setScrollbackLines(_ lines: Int) {
    let normalizedLines = max(0, lines)
    guard scrollbackLines != normalizedLines else {
      return
    }

    scrollbackLines = normalizedLines
    terminalView?.changeScrollback(normalizedLines == 0 ? nil : normalizedLines)
  }

  func focusTerminal() {
    guard let terminalView else {
      return
    }

    window?.makeFirstResponder(terminalView)
  }

  func showSearch() {
    guard let terminalView else {
      return
    }

    let menuItem = NSMenuItem()
    menuItem.tag = NSTextFinder.Action.showFindInterface.rawValue
    terminalView.performTextFinderAction(menuItem)
  }

  func findNext() {
    performTextFinderAction(.nextMatch)
  }

  func findPrevious() {
    performTextFinderAction(.previousMatch)
  }

  private func performTextFinderAction(_ action: NSTextFinder.Action) {
    guard let terminalView else {
      return
    }

    let menuItem = NSMenuItem()
    menuItem.tag = action.rawValue
    terminalView.performTextFinderAction(menuItem)
  }

  private func updateBackgroundColor() {
    layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
  }
}
