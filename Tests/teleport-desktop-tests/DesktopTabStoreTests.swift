import Foundation
import Testing
@testable import teleport_desktop

struct DesktopTabStoreTests {
  @MainActor
  @Test func openTabSelectsTheNewTab() {
    let store = DesktopTabStore()
    #expect(store.selectedTabID == nil)

    let newTab = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ubuntu@example",
        title: "ubuntu@example",
        summary: "Running tsh ssh as ubuntu",
        selectedNodeID: "node-1",
        connectedNodeID: "node-1"
      )
    )

    #expect(store.tabs.count == 1)
    #expect(store.selectedTabID == newTab.id)
  }

  @MainActor
  @Test func closeSelectedTabKeepsNeighborSelected() {
    let store = DesktopTabStore()
    let firstTab = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ubuntu@example",
        title: "ubuntu@example",
        summary: "Running tsh ssh as ubuntu"
      )
    )

    _ = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ec2-user@example",
        title: "ec2-user@example",
        summary: "Running tsh ssh as ec2-user"
      )
    )
    let handled = store.closeSelectedTab()

    #expect(handled)
    #expect(store.tabs.count == 1)
    #expect(store.selectedTabID == firstTab.id)
  }

  @MainActor
  @Test func closeSelectedTabReturnsFalseWhenThereIsNoTab() {
    let store = DesktopTabStore()

    #expect(!store.closeSelectedTab())
    #expect(store.tabs.isEmpty)
    #expect(store.selectedTabID == nil)
  }

  @MainActor
  @Test func closeSelectedTabClearsSelectionWhenItIsTheOnlyTab() {
    let store = DesktopTabStore()

    _ = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ubuntu@example",
        title: "ubuntu@example",
        summary: "Running tsh ssh as ubuntu"
      )
    )

    #expect(store.closeSelectedTab())
    #expect(store.tabs.isEmpty)
    #expect(store.selectedTabID == nil)
  }

  @MainActor
  @Test func closeTabReturnsFalseWhenTabDoesNotExist() {
    let store = DesktopTabStore()

    #expect(!store.closeTab(id: UUID()))
    #expect(store.tabs.isEmpty)
    #expect(store.selectedTabID == nil)
  }

  @MainActor
  @Test func selectNextTabReturnsFalseWhenThereAreFewerThanTwoTabs() {
    let store = DesktopTabStore()

    #expect(!store.selectNextTab())
    #expect(store.tabs.isEmpty)
    #expect(store.selectedTabID == nil)
  }

  @MainActor
  @Test func selectPreviousTabReturnsFalseWhenThereAreFewerThanTwoTabs() {
    let store = DesktopTabStore()

    #expect(!store.selectPreviousTab())
    #expect(store.tabs.isEmpty)
    #expect(store.selectedTabID == nil)
  }

  @MainActor
  @Test func selectTabIgnoresUnknownIdentifiers() {
    let store = DesktopTabStore()

    store.selectTab(id: UUID())

    #expect(store.tabs.isEmpty)
    #expect(store.selectedTabID == nil)
  }

  @MainActor
  @Test func selectNextTabWrapsAround() {
    let store = DesktopTabStore()
    let firstTab = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ubuntu@example",
        title: "ubuntu@example",
        summary: "Running tsh ssh as ubuntu"
      )
    )

    _ = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ec2-user@example",
        title: "ec2-user@example",
        summary: "Running tsh ssh as ec2-user"
      )
    )

    #expect(store.selectNextTab())
    #expect(store.selectedTabID == firstTab.id)
  }

  @MainActor
  @Test func selectPreviousTabWrapsAround() {
    let store = DesktopTabStore()
    let firstTab = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ubuntu@example",
        title: "ubuntu@example",
        summary: "Running tsh ssh as ubuntu"
      )
    )

    let secondTab = store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ec2-user@example",
        title: "ec2-user@example",
        summary: "Running tsh ssh as ec2-user"
      )
    )
    store.selectTab(id: firstTab.id)

    #expect(store.selectPreviousTab())
    #expect(store.selectedTabID == secondTab.id)
  }

  @MainActor
  @Test func moveTabOntoTargetLandsOnTargetSlot() {
    let store = DesktopTabStore()
    let tabs = (1...3).map { openTab(in: store, name: "host-\($0)") }

    store.moveTab(id: tabs[0].id, onto: tabs[2].id)
    #expect(store.tabs.map(\.id) == [tabs[1].id, tabs[2].id, tabs[0].id])

    store.moveTab(id: tabs[0].id, onto: tabs[1].id)
    #expect(store.tabs.map(\.id) == [tabs[0].id, tabs[1].id, tabs[2].id])
  }

  @MainActor
  @Test func moveSelectedTabKeepsSelectionAndStopsAtEdges() {
    let store = DesktopTabStore()
    let first = openTab(in: store, name: "host-1")
    let second = openTab(in: store, name: "host-2")

    // The last tab is selected, so moving right is past the edge.
    #expect(!store.moveSelectedTab(by: 1))
    #expect(store.tabs.map(\.id) == [first.id, second.id])

    #expect(store.moveSelectedTab(by: -1))
    #expect(store.tabs.map(\.id) == [second.id, first.id])
    #expect(store.selectedTabID == second.id)
  }

  @MainActor
  private func openTab(in store: DesktopTabStore, name: String) -> DesktopTab {
    store.openTab(
      windowState: DesktopWindowState.command(
        "tsh ssh ubuntu@\(name)",
        title: "ubuntu@\(name)",
        summary: "Running tsh ssh as ubuntu"
      )
    )
  }
}
