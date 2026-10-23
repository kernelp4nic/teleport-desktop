import SwiftUI

struct CommandPaletteItem: Identifiable {
  let id: String
  let title: String
  let subtitle: String?
  let icon: String
  let action: () -> Void
}

struct CommandPaletteView: View {
  let items: [CommandPaletteItem]
  let onDismiss: () -> Void

  @State private var query = ""
  @State private var highlightedIndex = 0
  @FocusState private var isFieldFocused: Bool

  private var filteredItems: [CommandPaletteItem] {
    let terms = query.lowercased().split(separator: " ")

    guard !terms.isEmpty else {
      return items
    }

    return items.filter { item in
      let text = "\(item.title) \(item.subtitle ?? "")".lowercased()
      return terms.allSatisfy { text.contains($0) }
    }
  }

  var body: some View {
    ZStack(alignment: .top) {
      Color.black.opacity(0.15)
        .ignoresSafeArea()
        .onTapGesture(perform: onDismiss)

      VStack(spacing: 0) {
        TextField("Type a command or server name", text: $query)
          .textFieldStyle(.plain)
          .font(.title3)
          .padding(14)
          .focused($isFieldFocused)
          .onSubmit(runHighlighted)
          .onKeyPress(.downArrow) {
            highlightedIndex = min(highlightedIndex + 1, filteredItems.count - 1)
            return .handled
          }
          .onKeyPress(.upArrow) {
            highlightedIndex = max(highlightedIndex - 1, 0)
            return .handled
          }
          .onKeyPress(.escape) {
            onDismiss()
            return .handled
          }

        Divider()

        if filteredItems.isEmpty {
          Text("No matches")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 60)
        } else {
          ScrollViewReader { proxy in
            ScrollView {
              LazyVStack(spacing: 0) {
                ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                  CommandPaletteRow(item: item, isHighlighted: index == highlightedIndex)
                    .id(item.id)
                    .contentShape(Rectangle())
                    .onTapGesture {
                      highlightedIndex = index
                      runHighlighted()
                    }
                }
              }
              .padding(6)
            }
            .frame(maxHeight: 380)
            .onChange(of: highlightedIndex) {
              guard filteredItems.indices.contains(highlightedIndex) else {
                return
              }

              proxy.scrollTo(filteredItems[highlightedIndex].id)
            }
          }
        }
      }
      .frame(width: 560)
      .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
      .shadow(color: .black.opacity(0.25), radius: 20, y: 8)
      .padding(.top, 80)
    }
    .onAppear {
      isFieldFocused = true
    }
    .onChange(of: query) {
      highlightedIndex = 0
    }
  }

  private func runHighlighted() {
    guard filteredItems.indices.contains(highlightedIndex) else {
      return
    }

    let item = filteredItems[highlightedIndex]
    onDismiss()
    item.action()
  }
}

private struct CommandPaletteRow: View {
  let item: CommandPaletteItem
  let isHighlighted: Bool

  var body: some View {
    HStack(spacing: 10) {
      GroupIconView(icon: item.icon)
        .frame(width: 20)
        .foregroundStyle(.secondary)

      Text(item.title)
        .lineLimit(1)

      Spacer()

      if let subtitle = item.subtitle {
        Text(subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(isHighlighted ? AnyShapeStyle(.selection) : AnyShapeStyle(Color.clear))
    )
  }
}
