import Foundation
import Observation
import SwiftUI

/// A tab's panes as a binary tree; `.horizontal` puts the two sides next to each other.
indirect enum PaneLayout {
  case pane(TerminalSessionStore)
  case split(Axis, PaneLayout, PaneLayout)

  /// Left-to-right, top-to-bottom.
  var panes: [TerminalSessionStore] {
    switch self {
    case .pane(let store): return [store]
    case .split(_, let first, let second): return first.panes + second.panes
    }
  }

  func splitting(_ target: TerminalSessionStore, axis: Axis, adding new: TerminalSessionStore) -> PaneLayout {
    switch self {
    case .pane(let store):
      return store === target ? .split(axis, self, .pane(new)) : self
    case .split(let current, let first, let second):
      return .split(
        current,
        first.splitting(target, axis: axis, adding: new),
        second.splitting(target, axis: axis, adding: new)
      )
    }
  }

  /// nil when the target is the only pane left.
  func removing(_ target: TerminalSessionStore) -> PaneLayout? {
    switch self {
    case .pane(let store):
      return store === target ? nil : self
    case .split(let axis, let first, let second):
      guard let newFirst = first.removing(target) else { return second }
      guard let newSecond = second.removing(target) else { return newFirst }
      return .split(axis, newFirst, newSecond)
    }
  }
}

@MainActor
@Observable
final class DesktopTab: Identifiable {
  let id: UUID
  private(set) var layout: PaneLayout
  private(set) var focusedPane: TerminalSessionStore
  var selectedNodeID: String?
  /// User-chosen name; nil falls back to the terminal's title.
  var customTitle: String?

  /// The focused pane: title, connection state, find and file transfer all follow it.
  var terminalStore: TerminalSessionStore { focusedPane }
  var panes: [TerminalSessionStore] { layout.panes }

  var displayTitle: String { customTitle ?? terminalStore.currentTitle }

  init(windowState: DesktopWindowState) {
    let store = TerminalSessionStore(windowState: windowState)
    id = windowState.id
    layout = .pane(store)
    focusedPane = store
    selectedNodeID = windowState.selectedNodeID
    track(store)
  }

  /// Splits the focused pane and focuses the new one.
  @discardableResult
  func split(_ axis: Axis, windowState: DesktopWindowState) -> TerminalSessionStore {
    let store = TerminalSessionStore(windowState: windowState)
    track(store)
    layout = layout.splitting(focusedPane, axis: axis, adding: store)
    focusedPane = store
    return store
  }

  /// Closes the focused pane; false when it is the only one, so the caller closes the tab.
  @discardableResult
  func closeFocusedPane() -> Bool {
    guard let remaining = layout.removing(focusedPane) else {
      return false
    }

    let closed = focusedPane
    let index = panes.firstIndex { $0 === closed } ?? 0
    layout = remaining
    focusedPane = remaining.panes[min(index, remaining.panes.count - 1)]
    closed.terminalController.terminate()
    return true
  }

  func focusPane(offset: Int) {
    let panes = panes

    guard panes.count > 1, let index = panes.firstIndex(where: { $0 === focusedPane }) else {
      return
    }

    focusedPane = panes[(index + offset + panes.count) % panes.count]
  }

  /// A click inside a pane moves focus to it.
  private func track(_ store: TerminalSessionStore) {
    store.terminalController.onFocus = { [weak self, weak store] in
      if let store {
        self?.focusedPane = store
      }
    }
  }
}
