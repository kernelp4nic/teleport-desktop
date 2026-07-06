import Foundation
import Observation

@MainActor
@Observable
final class DesktopTab: Identifiable {
  let id: UUID
  let terminalStore: TerminalSessionStore
  var selectedNodeID: String?

  init(windowState: DesktopWindowState) {
    id = windowState.id
    terminalStore = TerminalSessionStore(windowState: windowState)
    selectedNodeID = windowState.selectedNodeID
  }
}
