import Testing
@testable import MenuShell

struct TeleportNodeStoreTests {
  @MainActor
  @Test func demoModeUsesFictionalNodesWithoutRefreshing() async {
    let store = TeleportNodeStore(environment: ["TELEPORT_DESKTOP_DEMO": "1"])
    let settings = SettingsStore()

    await store.refresh(using: settings, forceRefresh: true)

    #expect(store.session.cluster == "demo-cluster")
    #expect(store.nodes.count == 16)
    #expect(store.nodes.allSatisfy { $0.labelMap["customer"] != nil })
  }
}
