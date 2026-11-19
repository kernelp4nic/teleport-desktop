import SwiftUI

/// Renders a tab's pane tree with native, draggable split dividers.
struct PaneLayoutView<Leaf: View>: View {
  let layout: PaneLayout
  @ViewBuilder let leaf: (TerminalSessionStore) -> Leaf

  var body: some View {
    switch layout {
    case .pane(let store):
      leaf(store)
    case .split(let axis, let first, let second):
      if axis == .horizontal {
        HSplitView {
          PaneLayoutView(layout: first, leaf: leaf)
          PaneLayoutView(layout: second, leaf: leaf)
        }
      } else {
        VSplitView {
          PaneLayoutView(layout: first, leaf: leaf)
          PaneLayoutView(layout: second, leaf: leaf)
        }
      }
    }
  }
}
