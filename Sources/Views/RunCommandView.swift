import SwiftUI

/// Pick servers, type a command or script, and read each server's output as it finishes.
struct RunCommandView: View {
  @Environment(\.dismiss) private var dismiss
  @Bindable var store: NodeCommandStore
  let targets: [CommandTarget]
  @Binding var selection: Set<String>
  @State private var searchText = ""

  var body: some View {
    HSplitView {
      picker
        .frame(minWidth: 220, idealWidth: 260, maxWidth: 340)

      VStack(spacing: 12) {
        HStack {
          Text("Run Command").font(.headline)

          Spacer()

          Button { dismiss() } label: {
            Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(.secondary)
          }
          .buttonStyle(.plain)
          .keyboardShortcut(.cancelAction)
          .disabled(store.isRunning)
          .help("Close")
        }

        TextEditor(text: $store.command)
          .font(.body.monospaced())
          .frame(height: 110)
          .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
          .disabled(store.isRunning)

        HStack {
          Spacer()

          if store.isRunning {
            Button("Stop", role: .destructive) { store.cancel() }
          } else {
            Button("Run on \(selectedTargets.count) Server\(selectedTargets.count == 1 ? "" : "s")") {
              store.run(on: selectedTargets)
            }
            .buttonStyle(.borderedProminent)
            .disabled(selectedTargets.isEmpty || store.command.allSatisfy(\.isWhitespace))
          }
        }

        results
      }
      .padding(16)
      .frame(minWidth: 420)
    }
    .frame(width: 860, height: 560)
    .interactiveDismissDisabled(store.isRunning)
  }

  private var selectedTargets: [CommandTarget] {
    targets.filter { selection.contains($0.id) }
  }

  private var shownTargets: [CommandTarget] {
    targets.filter { $0.node.matches(searchText: searchText, additionalText: $0.name) }
  }

  private var picker: some View {
    VStack(alignment: .leading, spacing: 8) {
      TextField("Filter servers", text: $searchText)
        .textFieldStyle(.roundedBorder)

      HStack {
        Button("Select Shown") { selection.formUnion(shownTargets.map(\.id)) }
        Button("Clear") { selection.removeAll() }
      }
      .buttonStyle(.link)
      .disabled(store.isRunning)

      List(shownTargets) { target in
        Toggle(isOn: Binding(
          get: { selection.contains(target.id) },
          set: { if $0 { selection.insert(target.id) } else { selection.remove(target.id) } }
        )) {
          label(for: target)
        }
        .disabled(store.isRunning)
      }
    }
    .padding(16)
  }

  private func label(for target: CommandTarget) -> some View {
    HStack(spacing: 6) {
      if let icon = target.icon {
        GroupIconView(icon: icon)
      } else {
        Image(systemName: "server.rack").foregroundStyle(.secondary)
      }

      Text(target.name)
    }
  }

  private var results: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 10) {
        ForEach(store.rows) { row in
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
              status(for: row.state)
              label(for: row.target).font(.headline)
            }

            if case .finished(let result) = row.state, !result.output.isEmpty {
              ScrollView {
                Text(result.output)
                  .font(.caption.monospaced())
                  .textSelection(.enabled)
                  .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: 220)
              .padding(8)
              .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
            }
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private func status(for state: NodeCommandStore.State) -> some View {
    switch state {
    case .pending:
      Image(systemName: "clock").foregroundStyle(.secondary)
    case .running:
      ProgressView().controlSize(.small)
    case .cancelled:
      Label("Cancelled", systemImage: "slash.circle").foregroundStyle(.secondary).labelStyle(.titleAndIcon)
    case .finished(let result) where result.exitStatus == 0:
      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
    case .finished(let result):
      Label("Exit \(result.exitStatus)", systemImage: "xmark.circle.fill")
        .foregroundStyle(.red)
        .labelStyle(.titleAndIcon)
    }
  }
}
