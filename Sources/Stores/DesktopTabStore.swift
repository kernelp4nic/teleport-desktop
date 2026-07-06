import Foundation
import Observation

@MainActor
@Observable
final class DesktopTabStore {
  var tabs: [DesktopTab]
  var selectedTabID: UUID?

  init() {
    tabs = []
    selectedTabID = nil
  }

  var selectedTab: DesktopTab? {
    guard let selectedTabID else {
      return nil
    }

    return tabs.first { $0.id == selectedTabID }
  }

  @discardableResult
  func openTab(windowState: DesktopWindowState) -> DesktopTab {
    let tab = DesktopTab(windowState: windowState)
    tabs.append(tab)
    selectedTabID = tab.id
    return tab
  }

  @discardableResult
  func closeSelectedTab() -> Bool {
    guard let selectedTabID else {
      return false
    }

    return closeTab(id: selectedTabID)
  }

  @discardableResult
  func closeTab(id: UUID) -> Bool {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else {
      return false
    }

    tabs.remove(at: index)

    if selectedTabID == id {
      selectedTabID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
    }

    return true
  }

  func selectTab(id: UUID) {
    guard tabs.contains(where: { $0.id == id }) else {
      return
    }

    selectedTabID = id
  }

  @discardableResult
  func selectNextTab() -> Bool {
    guard tabs.count > 1,
          let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
      return false
    }

    let nextIndex = (index + 1) % tabs.count
    selectedTabID = tabs[nextIndex].id
    return true
  }

  @discardableResult
  func selectPreviousTab() -> Bool {
    guard tabs.count > 1,
          let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else {
      return false
    }

    let previousIndex = index == 0 ? tabs.count - 1 : index - 1
    selectedTabID = tabs[previousIndex].id
    return true
  }
}
