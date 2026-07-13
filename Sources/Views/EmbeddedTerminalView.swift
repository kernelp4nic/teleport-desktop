import AppKit
import SwiftTerm
import SwiftUI

struct EmbeddedTerminalView: NSViewRepresentable {
  let sessionStore: TerminalSessionStore
  let focusToken: Int

  func makeNSView(context: Context) -> TerminalContainerView {
    let containerView = TerminalContainerView()
    containerView.attach(hostView: sessionStore.terminalController.hostView)
    containerView.focusTerminalIfNeeded(using: focusToken)
    return containerView
  }

  func updateNSView(_ nsView: TerminalContainerView, context: Context) {
    nsView.attach(hostView: sessionStore.terminalController.hostView)
    nsView.focusTerminalIfNeeded(using: focusToken)
  }
}

@MainActor
final class TerminalProcessController: NSObject, @preconcurrency LocalProcessTerminalViewDelegate {
  let hostView = TerminalHostView()
  var onProcessTerminated: (@MainActor (Int32?) -> Void)?
  private var lastRequestID: UUID?

  func install(_ request: EmbeddedTerminalRequest) {
    guard lastRequestID != request.id || hostView.terminalView == nil else {
      return
    }

    lastRequestID = request.id
    hostView.launch(request: request, delegate: self)
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

  func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

  func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

  func processTerminated(source: TerminalView, exitCode: Int32?) {
    let onProcessTerminated = onProcessTerminated

    Task { @MainActor in
      onProcessTerminated?(exitCode)
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

final class TerminalHostView: NSView {
  private let contentInset: CGFloat = 12
  private(set) var terminalView: LocalProcessTerminalView?

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
    delegate: LocalProcessTerminalViewDelegate
  ) {
    if let terminalView {
      terminalView.terminate()
      terminalView.removeFromSuperview()
    }

    let terminalView = LocalProcessTerminalView(
      frame: bounds.insetBy(dx: contentInset, dy: contentInset)
    )
    terminalView.translatesAutoresizingMaskIntoConstraints = false
    terminalView.configureNativeColors()
    terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
    terminalView.caretColor = .controlAccentColor
    terminalView.processDelegate = delegate

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
