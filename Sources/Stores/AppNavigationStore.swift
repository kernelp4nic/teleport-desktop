import Foundation
import Observation

struct NodeConnectionRequest: Equatable {
  let id = UUID()
  let nodeID: String
}

@MainActor
@Observable
final class AppNavigationStore {
  private(set) var nodeConnectionRequest: NodeConnectionRequest?

  func requestConnection(to nodeID: String) {
    nodeConnectionRequest = NodeConnectionRequest(nodeID: nodeID)
  }

  func consumeConnectionRequest(id: UUID) {
    guard nodeConnectionRequest?.id == id else {
      return
    }

    nodeConnectionRequest = nil
  }
}
