import Foundation
import Testing
@testable import MenuShell

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
}
