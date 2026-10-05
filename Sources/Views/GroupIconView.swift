import AppKit
import SwiftUI

/// Renders a group icon that is either an SF Symbol name (e.g. "globe") or free text such as an emoji.
struct GroupIconView: View {
  let icon: String

  var body: some View {
    if Self.isSystemSymbol(icon) {
      Image(systemName: icon)
    } else {
      Text(icon)
    }
  }

  static func isSystemSymbol(_ icon: String) -> Bool {
    icon.allSatisfy { $0.isASCII } && NSImage(systemSymbolName: icon, accessibilityDescription: nil) != nil
  }
}

struct GroupTitleView: View {
  let title: String
  let icon: String?

  var body: some View {
    HStack(spacing: 6) {
      if let icon {
        GroupIconView(icon: icon)
      }

      Text(title)
    }
  }
}
