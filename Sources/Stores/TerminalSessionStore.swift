import Foundation
import Observation

@MainActor
@Observable
final class TerminalSessionStore {
  var request: EmbeddedTerminalRequest
  var statusMessage: String
  var currentTitle: String
  var connectedNodeID: String?
  var lastExitStatus: Int32?
  @ObservationIgnored let terminalController: TerminalProcessController

  init(windowState: DesktopWindowState) {
    request = windowState.request
    statusMessage = windowState.request.summary
    currentTitle = windowState.request.title
    connectedNodeID = windowState.connectedNodeID
    terminalController = TerminalProcessController()
    terminalController.install(request)
    terminalController.onProcessTerminated = { [weak self] exitCode in
      self?.processTerminated(exitCode: exitCode)
    }
  }

  func run(request: EmbeddedTerminalRequest, connectedNodeID: String?) {
    self.request = request
    statusMessage = request.summary
    currentTitle = request.title
    self.connectedNodeID = connectedNodeID
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

  func processTerminated(exitCode: Int32?) {
    lastExitStatus = exitCode
    connectedNodeID = nil

    if let exitCode {
      statusMessage = "Terminal session ended with status \(exitCode)"
    } else {
      statusMessage = "Terminal session closed"
    }
  }
}
