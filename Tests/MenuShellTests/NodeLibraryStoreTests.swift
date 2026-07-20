import Foundation
import Testing
@testable import MenuShell

struct NodeLibraryStoreTests {
  @Test func favoritesTogglePersists() {
    let (suiteName, defaults) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = NodeLibraryStore(defaults: defaults)
    store.toggleFavorite(nodeID: "node-1", scopeKey: "proxy-a")

    let reloadedStore = NodeLibraryStore(defaults: defaults)

    #expect(reloadedStore.isFavorite(nodeID: "node-1", scopeKey: "proxy-a"))
  }

  @Test func recentsAreDeduped() {
    let (suiteName, defaults) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = NodeLibraryStore(defaults: defaults)
    store.recordRecent(nodeID: "node-1", scopeKey: "proxy-a")
    store.recordRecent(nodeID: "node-2", scopeKey: "proxy-a")
    store.recordRecent(nodeID: "node-1", scopeKey: "proxy-a")

    #expect(store.recentNodeIDs(scopeKey: "proxy-a") == ["node-1", "node-2"])
  }

  @Test func recentsAreCappedAtTen() {
    let (suiteName, defaults) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = NodeLibraryStore(defaults: defaults)

    for index in 1...12 {
      store.recordRecent(nodeID: "node-\(index)", scopeKey: "proxy-a")
    }

    #expect(
      store.recentNodeIDs(scopeKey: "proxy-a")
        == (3...12).reversed().map { "node-\($0)" }
    )
  }

  @Test func scopeIsolationKeepsFavoritesAndRecentsSeparate() {
    let (suiteName, defaults) = makeDefaults()
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let store = NodeLibraryStore(defaults: defaults)
    store.toggleFavorite(nodeID: "node-a", scopeKey: "proxy-a")
    store.recordRecent(nodeID: "node-a", scopeKey: "proxy-a")
    store.recordRecent(nodeID: "node-b", scopeKey: "proxy-b")

    #expect(store.isFavorite(nodeID: "node-a", scopeKey: "proxy-a"))
    #expect(!store.isFavorite(nodeID: "node-a", scopeKey: "proxy-b"))
    #expect(store.recentNodeIDs(scopeKey: "proxy-a") == ["node-a"])
    #expect(store.recentNodeIDs(scopeKey: "proxy-b") == ["node-b"])
  }

  private func makeDefaults() -> (String, UserDefaults) {
    let suiteName = "NodeLibraryStoreTests.\(UUID().uuidString)"
    return (suiteName, UserDefaults(suiteName: suiteName)!)
  }
}
