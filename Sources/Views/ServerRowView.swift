import SwiftUI

struct ServerRowView: View {
  let node: TeleportNode
  let groupKey: String?
  let loginKey: String?
  let isFavorite: Bool
  let resolvedLogin: String?
  let onToggleFavorite: () -> Void
  let onConnect: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 8) {
          Text(node.hostname)
            .font(.headline)
            .lineLimit(1)

          if let resolvedLogin {
            Label(resolvedLogin, systemImage: "person.crop.circle")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Text(node.address)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)

        HStack(spacing: 6) {
          ForEach(node.displayLabels(groupKey: groupKey, loginKey: loginKey)) { label in
            LabelChip(label: label)
          }
        }
      }

      Spacer(minLength: 12)

      VStack(alignment: .trailing, spacing: 8) {
        Button(action: onToggleFavorite) {
          Image(systemName: isFavorite ? "star.fill" : "star")
            .foregroundStyle(isFavorite ? .yellow : .secondary)
        }
        .buttonStyle(.plain)
        .help(isFavorite ? "Remove from favorites" : "Add to favorites")

        Button("Connect", action: onConnect)
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
          .disabled(resolvedLogin == nil)
      }
    }
    .padding(10)
    .background(
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(.quaternary.opacity(0.35))
    )
  }
}

private struct LabelChip: View {
  let label: TeleportLabel

  var body: some View {
    Text("\(label.key): \(label.value)")
      .font(.caption2)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Capsule(style: .continuous)
          .fill(.tertiary.opacity(0.35))
      )
  }
}
