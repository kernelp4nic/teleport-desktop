import SwiftUI

struct DesktopServerRowView: View {
  let node: TeleportNode
  let name: String
  let groupingKey: String?
  let resolvedLogin: String?
  let isFavorite: Bool
  let onToggleFavorite: () -> Void

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "server.rack")
        .foregroundStyle(.secondary)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .lineLimit(1)

        Text(rowSubtitle)
          .font(.caption)
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
