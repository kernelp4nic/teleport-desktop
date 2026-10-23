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

  /// Drops the tab on the target's slot, landing after it when moving right.
  func moveTab(id: UUID, onto targetID: UUID) {
    guard id != targetID,
          let from = tabs.firstIndex(where: { $0.id == id }),
          let to = tabs.firstIndex(where: { $0.id == targetID }) else {
      return
    }

    let tab = tabs.remove(at: from)
    let targetIndex = tabs.firstIndex { $0.id == targetID } ?? tabs.count
    tabs.insert(tab, at: from < to ? targetIndex + 1 : targetIndex)
  }

  @discardableResult
  func moveSelectedTab(by offset: Int) -> Bool {
    guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
          tabs.indices.contains(index + offset) else {
      return false
    }

    tabs.swapAt(index, index + offset)
    return true
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
