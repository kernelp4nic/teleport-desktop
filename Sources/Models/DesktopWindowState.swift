import Foundation

struct DesktopWindowState: Codable, Hashable, Identifiable {
  let id: UUID
  var request: EmbeddedTerminalRequest
  var selectedNodeID: String?
  var connectedNodeID: String?

  init(
    id: UUID = UUID(),
    request: EmbeddedTerminalRequest,
    selectedNodeID: String?,
    connectedNodeID: String?
  ) {
    self.id = id
    self.request = request
    self.selectedNodeID = selectedNodeID
    self.connectedNodeID = connectedNodeID
  }

  static func shell() -> DesktopWindowState {
    DesktopWindowState(
      request: .shell(),
      selectedNodeID: nil,
      connectedNodeID: nil
    )
  }

  static func command(
    _ command: String,
    title: String,
    summary: String,
    selectedNodeID: String? = nil,
    connectedNodeID: String? = nil
  ) -> DesktopWindowState {
    DesktopWindowState(
      request: .command(
        command,
        title: title,
        summary: summary
      ),
      selectedNodeID: selectedNodeID,
      connectedNodeID: connectedNodeID
    )
  }
}
