import Foundation
import Observation

@MainActor
@Observable
final class DesktopTabStore {
  var tabs: [DesktopTab]
  var selectedTabID: UUID

  init(initialWindowState: DesktopWindowState = .shell()) {
    let tab = DesktopTab(windowState: initialWindowState)
    tabs = [tab]
    selectedTabID = tab.id
  }

  var selectedTab: DesktopTab? {
    tabs.first { $0.id == selectedTabID }
  }

  @discardableResult
  func openTab(windowState: DesktopWindowState) -> DesktopTab {
    let tab = DesktopTab(windowState: windowState)
    tabs.append(tab)
    selectedTabID = tab.id
    return tab
  }

  @discardableResult
  func openShellTab() -> DesktopTab {
    openTab(windowState: .shell())
  }

  @discardableResult
  func closeSelectedTab() -> Bool {
    closeTab(id: selectedTabID)
  }

  @discardableResult
  func closeTab(id: UUID) -> Bool {
    guard let index = tabs.firstIndex(where: { $0.id == id }) else {
      return false
    }

    guard tabs.count > 1 else {
      return false
    }

    tabs.remove(at: index)

    if selectedTabID == id {
      selectedTabID = tabs[min(index, tabs.count - 1)].id
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
