import Testing
@testable import MenuShell

struct DesktopTabStoreTests {
  @MainActor
  @Test func openTabSelectsTheNewTab() {
    let store = DesktopTabStore()
    let initialTabID = store.selectedTabID

    let newTab = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ubuntu@example",
        title: "ubuntu@example",
        summary: "Running tsh ssh as ubuntu",
        selectedNodeID: "node-1",
        connectedNodeID: "node-1"
      )
    )

    #expect(store.tabs.count == 2)
    #expect(store.selectedTabID == newTab.id)
    #expect(store.selectedTabID != initialTabID)
  }

  @MainActor
  @Test func closeSelectedTabKeepsNeighborSelected() {
    let store = DesktopTabStore()
    let firstTabID = store.selectedTabID

    _ = store.openShellTab()
    let handled = store.closeSelectedTab()

    #expect(handled)
    #expect(store.tabs.count == 1)
    #expect(store.selectedTabID == firstTabID)
  }

  @MainActor
  @Test func closeSelectedTabReturnsFalseWhenItIsTheOnlyTab() {
    let store = DesktopTabStore()

    #expect(!store.closeSelectedTab())
    #expect(store.tabs.count == 1)
  }

  @MainActor
  @Test func selectNextTabWrapsAround() {
    let store = DesktopTabStore()
    let firstTabID = store.selectedTabID

    _ = store.openShellTab()

    #expect(store.selectNextTab())
    #expect(store.selectedTabID == firstTabID)
  }

  @MainActor
  @Test func selectPreviousTabWrapsAround() {
    let store = DesktopTabStore()
    let firstTabID = store.selectedTabID

    let secondTab = store.openShellTab()
    store.selectTab(id: firstTabID)

    #expect(store.selectPreviousTab())
    #expect(store.selectedTabID == secondTab.id)
  }
}
