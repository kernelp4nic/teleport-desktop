import SwiftUI

struct DesktopServerRowView: View {
  let node: TeleportNode
  let groupingKey: String?
  let resolvedLogin: String?

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: "server.rack")
        .foregroundStyle(.secondary)
        .frame(width: 16)

      VStack(alignment: .leading, spacing: 2) {
        Text(node.hostname)
          .lineLimit(1)

        Text(rowSubtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
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
