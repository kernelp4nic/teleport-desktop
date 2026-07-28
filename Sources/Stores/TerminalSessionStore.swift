import Foundation
import Observation

enum TerminalConnectionState: Equatable {
  case idle
  case connecting
  case connected
  case disconnected
}

@MainActor
@Observable
final class TerminalSessionStore {
  var request: EmbeddedTerminalRequest
  var statusMessage: String
  var currentTitle: String
  var connectedNodeID: String?
  var connectionState: TerminalConnectionState
  var lastExitStatus: Int32?
  @ObservationIgnored var onConnectionEstablished: (@MainActor () -> Void)? {
    didSet {
      notifyConnectionEstablishedIfNeeded()
    }
  }
  @ObservationIgnored var onTmuxSessionEnded: (@MainActor () -> Void)? {
    didSet {
      notifyTmuxSessionEndedIfNeeded()
    }
  }
  @ObservationIgnored let terminalController: TerminalProcessController
  @ObservationIgnored let tmuxController: TmuxSessionController?
  @ObservationIgnored private var didNotifyConnectionEstablished = false
  @ObservationIgnored private var tmuxSessionDidEnd = false
  @ObservationIgnored private var didNotifyTmuxSessionEnded = false

  init(windowState: DesktopWindowState) {
    request = windowState.request
    statusMessage = windowState.request.summary
    currentTitle = windowState.request.title
    connectedNodeID = windowState.connectedNodeID
    connectionState = Self.initialConnectionState(for: windowState.connectedNodeID)
    onConnectionEstablished = nil
    terminalController = TerminalProcessController()
    tmuxController = windowState.request.mode == .tmuxControl ? TmuxSessionController() : nil
    if let tmuxController {
      tmuxController.onConnectionEstablished = { [weak self] in
        self?.statusMessage = "Connected to remote tmux"
        self?.markConnectedIfNeeded()
      }
      tmuxController.onProcessTerminated = { [weak self] exitCode in
        self?.processTerminated(exitCode: exitCode)
      }
      tmuxController.onSessionEnded = { [weak self] in
        self?.tmuxSessionEnded()
      }
      tmuxController.start(request)
      return
    }
    terminalController.onProcessOutput = { [weak self] in
      self?.markConnectedIfNeeded()
    }
    terminalController.onProcessTerminated = { [weak self] exitCode in
      self?.processTerminated(exitCode: exitCode)
    }
    terminalController.install(request)
  }

  func run(request: EmbeddedTerminalRequest, connectedNodeID: String?) {
    self.request = request
    statusMessage = request.summary
    currentTitle = request.title
    self.connectedNodeID = connectedNodeID
    connectionState = Self.initialConnectionState(for: connectedNodeID)
    lastExitStatus = nil
    didNotifyConnectionEstablished = false
    terminalController.install(request)
  }

  func showSearch() {
    guard tmuxController == nil else { return }
    terminalController.showSearch()
  }

  func findNext() {
    guard tmuxController == nil else { return }
    terminalController.findNext()
  }

  func findPrevious() {
    guard tmuxController == nil else { return }
    terminalController.findPrevious()
  }

  func markConnectedIfNeeded() {
    guard connectionState == .connecting else {
      return
    }

    connectionState = .connected
    notifyConnectionEstablishedIfNeeded()
  }

  func processTerminated(exitCode: Int32?) {
    lastExitStatus = exitCode
    connectedNodeID = nil
    connectionState = .disconnected

    if let exitCode {
      statusMessage = "Terminal session ended with status \(exitCode)"
    } else {
      statusMessage = "Terminal session closed"
    }
  }

  private static func initialConnectionState(for connectedNodeID: String?) -> TerminalConnectionState {
    connectedNodeID == nil ? .idle : .connecting
  }

  private func notifyConnectionEstablishedIfNeeded() {
    guard connectionState == .connected,
          !didNotifyConnectionEstablished,
          let onConnectionEstablished else {
      return
    }

    didNotifyConnectionEstablished = true
    onConnectionEstablished()
  }

  private func tmuxSessionEnded() {
    tmuxSessionDidEnd = true
    notifyTmuxSessionEndedIfNeeded()
  }

  private func notifyTmuxSessionEndedIfNeeded() {
    guard tmuxSessionDidEnd,
          !didNotifyTmuxSessionEnded,
          let onTmuxSessionEnded else { return }
    didNotifyTmuxSessionEnded = true
    onTmuxSessionEnded()
  }
}
