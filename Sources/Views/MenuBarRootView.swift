import AppKit
import Observation
import SwiftUI

struct MenuBarRootView: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openSettings) private var openSettings
  @Bindable var store: TeleportNodeStore
  @Bindable var settings: SettingsStore
  @State private var searchText = ""
  @State private var selectedGroup = Self.allGroups

  private static let allGroups = "__all_groups__"

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      header
      searchControls
      content
      footer
    }
    .padding(14)
    .task {
      guard !store.isLoading else {
        return
      }

      await store.refreshIfNeeded(using: settings)
    }
    .onChange(of: settings.groupingLabelKey) {
      selectedGroup = Self.allGroups
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
          Text(store.session.cluster ?? "Teleport")
            .font(.headline)

          Text(statusLine)
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        if store.isLoading {
          ProgressView()
            .controlSize(.small)
        }

        Button {
          Task {
            await store.refresh(using: settings, forceRefresh: true)
          }
        } label: {
          Image(systemName: "arrow.clockwise")
        }
        .help("Refresh servers")

        Button("Login") {
          store.login(using: settings)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
      }

      if let errorMessage = store.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private var searchControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      TextField("Search host, address or label", text: $searchText)
        .textFieldStyle(.roundedBorder)

      HStack {
        if let groupingKey = settings.normalizedGroupingLabelKey {
          Picker("Group", selection: $selectedGroup) {
            Text("All \(groupingKey)").tag(Self.allGroups)

            ForEach(groupValues, id: \.self) { value in
              Text(value).tag(value)
            }
          }
          .pickerStyle(.menu)
        } else {
          Text("Grouping disabled")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Text("\(filteredNodes.count) servers")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  @ViewBuilder
  private var content: some View {
    if store.isLoading && store.nodes.isEmpty {
      Spacer()
      HStack {
        Spacer()
        ProgressView("Loading Teleport nodes...")
        Spacer()
      }
      Spacer()
    } else if filteredNodes.isEmpty {
      Spacer()
      ContentUnavailableView(
        "No servers found",
        systemImage: "terminal",
        description: Text(emptyStateText)
      )
      Spacer()
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 14) {
          ForEach(sections, id: \.title) { section in
            VStack(alignment: .leading, spacing: 8) {
              if shouldShowSectionHeaders {
                HStack {
                  Text(section.title)
                    .font(.subheadline.weight(.semibold))
                  Spacer()
                  Text("\(section.nodes.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }

              ForEach(section.nodes) { node in
                ServerRowView(
                  node: node,
                  groupKey: settings.normalizedGroupingLabelKey,
                  loginKey: settings.normalizedLoginLabelKey,
                  resolvedLogin: node.preferredLogin(
                    labelKey: settings.normalizedLoginLabelKey,
                    fallback: settings.normalizedFallbackLogin,
                    allowedLogins: store.session.logins
                  ),
                  onConnect: {
                    Task {
                      dismiss()
                      try? await Task.sleep(for: .milliseconds(120))
                      store.connect(to: node, settings: settings)
                    }
                  }
                )
              }
            }
          }
        }
        .padding(.vertical, 2)
      }
      .scrollIndicators(.visible)
    }
  }

  private var footer: some View {
    HStack {
      Button {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
      } label: {
        Label("Settings", systemImage: "gear")
      }
      .buttonStyle(.plain)

      Spacer()

      if let lastRefreshedAt = store.lastRefreshedAt {
        Text(lastRefreshedAt, style: .time)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }

      Button("Quit") {
        NSApplication.shared.terminate(nil)
      }
      .buttonStyle(.plain)
    }
  }

  private var statusLine: String {
    var components = [store.session.statusText]

    if let username = store.session.username {
      components.append("as \(username)")
    }

    if let validUntil = store.session.validUntil {
      components.append("until \(validUntil.formatted(date: .abbreviated, time: .shortened))")
    }

    if let proxy = store.session.proxy {
      components.append(proxy)
    }

    return components.joined(separator: " • ")
  }

  private var emptyStateText: String {
    if store.session.state == .expired {
      return "The current tsh session is expired. Run login and refresh."
    }

    if store.session.state == .unavailable {
      return "Open Settings if you want to force a proxy, then run login."
    }

    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return "Try a different hostname, group or label value."
    }

    return "Teleport did not return any nodes for the current profile."
  }

  private var filteredNodes: [TeleportNode] {
    store.nodes.filter { node in
      guard node.matches(searchText: searchText) else {
        return false
      }

      if selectedGroup == Self.allGroups {
        return true
      }

      return node.groupValue(for: settings.normalizedGroupingLabelKey) == selectedGroup
    }
  }

  private var groupValues: [String] {
    guard let groupingKey = settings.normalizedGroupingLabelKey else {
      return []
    }

    return Array(
      Set(
        store.nodes.map { $0.groupValue(for: groupingKey) }
      )
    )
    .sorted { lhs, rhs in
      lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
    }
  }

  private var sections: [ServerSection] {
    guard let groupingKey = settings.normalizedGroupingLabelKey else {
      return [ServerSection(title: "Servers", nodes: filteredNodes)]
    }

    let grouped = Dictionary(grouping: filteredNodes) { node in
      node.groupValue(for: groupingKey)
    }

    return grouped.keys
      .sorted { lhs, rhs in
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
      }
      .map { key in
        ServerSection(
          title: key,
          nodes: grouped[key, default: []]
        )
      }
  }

  private var shouldShowSectionHeaders: Bool {
    settings.normalizedGroupingLabelKey != nil && sections.count > 1
  }
}

private struct ServerSection {
  let title: String
  let nodes: [TeleportNode]
}
