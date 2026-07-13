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
  @ObservationIgnored let terminalController: TerminalProcessController

  init(windowState: DesktopWindowState) {
    request = windowState.request
    statusMessage = windowState.request.summary
    currentTitle = windowState.request.title
    connectedNodeID = windowState.connectedNodeID
    connectionState = Self.initialConnectionState(for: windowState.connectedNodeID)
    terminalController = TerminalProcessController()
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
    terminalController.install(request)
  }

  func showSearch() {
    terminalController.showSearch()
  }

  func findNext() {
    terminalController.findNext()
  }

  func findPrevious() {
    terminalController.findPrevious()
  }

  func markConnectedIfNeeded() {
    guard connectionState == .connecting else {
      return
    }

    connectionState = .connected
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
}
