import Foundation
import Testing
@testable import teleport_desktop

struct DesktopTabSplitTests {
  @MainActor
  private func makeTab() -> DesktopTab {
    DesktopTab(windowState: .command("true", title: "a", summary: "a"))
  }

  @MainActor
  @Test func splitFocusesTheNewPane() {
    let tab = makeTab()
    let first = tab.focusedPane
    let second = tab.split(.horizontal, windowState: .command("true", title: "b", summary: "b"))

    #expect(tab.panes.count == 2)
    #expect(tab.panes[0] === first && tab.panes[1] === second)
    #expect(tab.focusedPane === second)
  }

  @MainActor
  @Test func closingAPaneCollapsesTheSplitAndRefocuses() {
    let tab = makeTab()
    let first = tab.focusedPane
    tab.split(.horizontal, windowState: .command("true", title: "b", summary: "b"))
    tab.split(.vertical, windowState: .command("true", title: "c", summary: "c"))
    #expect(tab.panes.count == 3)

    #expect(tab.closeFocusedPane())
    #expect(tab.panes.count == 2)

    tab.focusPane(offset: -1)
    #expect(tab.focusedPane === first)
    #expect(tab.closeFocusedPane())
    #expect(!tab.closeFocusedPane())
    #expect(tab.panes.count == 1)
  }

  @MainActor
  @Test func focusPaneWraps() {
    let tab = makeTab()
    let first = tab.focusedPane
    tab.split(.horizontal, windowState: .command("true", title: "b", summary: "b"))

    tab.focusPane(offset: 1)
    #expect(tab.focusedPane === first)
    tab.focusPane(offset: -1)
    #expect(tab.focusedPane !== first)
  }
}
