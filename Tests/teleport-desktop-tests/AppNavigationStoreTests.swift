import Foundation
import Testing
@testable import teleport_desktop

@MainActor
struct AppNavigationStoreTests {
  @Test
  func connectionRequestCanBeConsumedOnlyByItsIdentifier() {
    let store = AppNavigationStore()

    store.requestConnection(to: "first-node")
    let request = store.nodeConnectionRequest!

    store.consumeConnectionRequest(id: UUID())
    #expect(store.nodeConnectionRequest == request)

    store.consumeConnectionRequest(id: request.id)
    #expect(store.nodeConnectionRequest == nil)
  }

  @Test
  func latestConnectionRequestReplacesThePreviousOne() {
    let store = AppNavigationStore()

    store.requestConnection(to: "first-node")
    store.requestConnection(to: "second-node")

    #expect(store.nodeConnectionRequest?.nodeID == "second-node")
  }
}
