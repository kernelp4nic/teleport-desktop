import SwiftUI

struct DesktopServerRowView: View {
  let node: TeleportNode
  let name: String
  let groupingKey: String?
  let groupIcon: String?
  let resolvedLogin: String?
  let isFavorite: Bool
  let onToggleFavorite: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Group {
        if let groupIcon {
          GroupIconView(icon: groupIcon)
        } else {
          Image(systemName: "server.rack")
            .foregroundStyle(.secondary)
        }
      }
      .font(.system(size: 15))
      .fixedSize()
      .frame(minWidth: 20)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.system(size: 14, weight: .medium))
          .lineLimit(1)

        Text(rowSubtitle)
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 8)

      Button(action: onToggleFavorite) {
        Image(systemName: isFavorite ? "star.fill" : "star")
          .foregroundStyle(isFavorite ? .yellow : .secondary)
      }
      .buttonStyle(.plain)
      .help(isFavorite ? "Remove from favorites" : "Add to favorites")
    }
  }

  private var rowSubtitle: String {
    var components: [String] = []

    let groupValue = node.groupValue(for: groupingKey)
    if groupValue != "Ungrouped" {
      components.append(groupValue)
    }

    if let resolvedLogin {
      components.append(resolvedLogin)
    }

    if components.isEmpty {
      components.append(node.address)
    }

    return components.joined(separator: " • ")
  }
}
