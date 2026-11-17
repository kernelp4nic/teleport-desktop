import Foundation
import Observation

@MainActor
@Observable
final class DesktopTab: Identifiable {
  let id: UUID
  let terminalStore: TerminalSessionStore
  var selectedNodeID: String?
  /// User-chosen name; nil falls back to the terminal's title.
  var customTitle: String?

  var displayTitle: String { customTitle ?? terminalStore.currentTitle }

  init(windowState: DesktopWindowState) {
    id = windowState.id
    terminalStore = TerminalSessionStore(windowState: windowState)
    selectedNodeID = windowState.selectedNodeID
  }
}
