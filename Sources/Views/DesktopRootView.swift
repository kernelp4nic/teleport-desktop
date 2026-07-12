import AppKit
import Observation
import SwiftUI

struct DesktopRootView: View {
  @Environment(\.openSettings) private var openSettings
  @Bindable var store: TeleportNodeStore
  @Bindable var settings: SettingsStore
  @SceneStorage("desktop.searchText") private var searchText = ""
  @SceneStorage("desktop.selectedGroup") private var selectedGroup = Self.allGroups
  @State private var browserSelectedNodeID: String?
  @State private var terminalFocusToken = 0
  @State private var tabStore = DesktopTabStore()

  private static let allGroups = "__all_groups__"

  var body: some View {
    NavigationSplitView {
      sidebar
        .navigationSplitViewColumnWidth(min: 320, ideal: 360)
    } detail: {
      detail
    }
    .background(
      WindowTabConfigurationView(
        title: "Teleport Desktop",
        onCloseTab: closeSelectedTabFromShortcut,
        onSelectPreviousTab: selectPreviousTabFromShortcut,
        onSelectNextTab: selectNextTabFromShortcut
      )
    )
    .toolbar {
      ToolbarItem(placement: .principal) {
        toolbarTabStrip
      }

      ToolbarItemGroup {
        Button {
          Task {
            await store.refresh(using: settings, forceRefresh: true)
            reconcileSelection()
          }
        } label: {
          Label("Refresh", systemImage: "arrow.clockwise")
        }
        .disabled(store.isLoading)

        Button {
          store.login(using: settings)
        } label: {
          Label("Login", systemImage: "person.badge.key")
        }

        Button {
          NSApp.activate(ignoringOtherApps: true)
          openSettings()
        } label: {
          Label("Settings", systemImage: "gearshape")
        }
      }

      ToolbarItem(placement: .automatic) {
        if store.isLoading {
          ProgressView()
            .controlSize(.small)
        }
      }
    }
    .task {
      guard !store.isLoading else {
        return
      }

      await store.refreshIfNeeded(using: settings)
      reconcileSelection()
    }
    .onChange(of: settings.groupingLabelKey) {
      selectedGroup = Self.allGroups
      reconcileSelection()
    }
    .onChange(of: store.nodes) {
      reconcileSelection()
    }
    .onChange(of: searchText) {
      reconcileSelection()
    }
    .onChange(of: selectedGroup) {
      reconcileSelection()
    }
    .onChange(of: tabStore.selectedTabID) {
      syncSidebarSelectionToActiveTab()
      reconcileSelection()
      requestTerminalFocus()
    }
  }

  @ViewBuilder
  private var toolbarTabStrip: some View {
    if !tabStore.tabs.isEmpty {
      ScrollView(.horizontal) {
        HStack(spacing: 6) {
          ForEach(tabStore.tabs) { tab in
            DesktopTabPillView(
              title: tab.terminalStore.currentTitle,
              isSelected: tab.id == tabStore.selectedTabID,
              onSelect: {
                tabStore.selectTab(id: tab.id)
              },
              onClose: {
                closeTab(tab)
              }
            )
          }
        }
        .padding(.horizontal, 2)
        .padding(.vertical, 1)
      }
      .scrollIndicators(.hidden)
    }
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: 12) {
        Text(store.session.cluster ?? "Teleport")
          .font(.title3.weight(.semibold))

        Text(statusLine)
          .font(.caption)
          .foregroundStyle(.secondary)

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
      .padding(16)

      if let errorMessage = store.errorMessage {
        Text(errorMessage)
          .font(.caption)
          .foregroundStyle(.red)
          .padding(.horizontal, 16)
          .padding(.bottom, 12)
      }

      Divider()
        .padding(.top, 6)
        .padding(.bottom, 8)

      Group {
        if store.isLoading && store.nodes.isEmpty {
          VStack(spacing: 12) {
            Spacer()
            ProgressView("Loading Teleport nodes...")
            Spacer()
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filteredNodes.isEmpty {
          ContentUnavailableView(
            "No servers found",
            systemImage: "server.rack",
            description: Text(emptyStateText)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
          List(selection: selectedNodeBinding) {
            ForEach(sections, id: \.title) { section in
              Section {
                ForEach(section.nodes) { node in
                  DesktopServerRowView(
                    node: node,
                    groupingKey: settings.normalizedGroupingLabelKey,
                    resolvedLogin: resolvedLogin(for: node)
                  )
                  .tag(node.id)
                  .contentShape(Rectangle())
                  .listRowInsets(
                    EdgeInsets(top: 4, leading: 26, bottom: 4, trailing: 10)
                  )
                }
              } header: {
                Text(section.title)
                  .textCase(nil)
                  .font(.caption.weight(.medium))
                  .foregroundStyle(.secondary)
                  .padding(.leading, 6)
              }
            }
          }
          .listStyle(.sidebar)
          .contextMenu(forSelectionType: String.self) { selectedIDs in
            Button("Connect in App") {
              connectSelectionToNewTab(selectedIDs)
            }
            .disabled(!canConnectSelection(selectedIDs))

            Button("Open Externally") {
              openSelectionExternally(selectedIDs)
            }
            .disabled(!canConnectSelection(selectedIDs))
          } primaryAction: { selectedIDs in
            connectSelectionToNewTab(selectedIDs)
          }
        }
      }

      Divider()

      HStack {
        if let lastRefreshedAt = store.lastRefreshedAt {
          Text("Updated \(lastRefreshedAt.formatted(date: .omitted, time: .shortened))")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }

        Spacer()

        Button("Quit") {
          NSApplication.shared.terminate(nil)
        }
        .buttonStyle(.plain)
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: 16) {
      VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 16) {
          VStack(alignment: .leading, spacing: 4) {
            Text(detailTitle)
              .font(.title2.weight(.semibold))

            Text(detailSubtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Spacer()

          if isActiveTabConnected {
            Label("Connected in This Tab", systemImage: "checkmark.circle.fill")
              .font(.caption.weight(.medium))
              .foregroundStyle(.secondary)
          } else {
            HStack(spacing: 10) {
              Button("Connect") {
                if let actionNode {
                  openNodeInApp(node: actionNode)
                }
              }
              .buttonStyle(.borderedProminent)
              .disabled(actionNode == nil || actionLogin == nil)

              Button(openExternallyTitle) {
                if let actionNode {
                  openNodeExternally(actionNode)
                }
              }
              .disabled(actionNode == nil || actionLogin == nil)
            }
          }
        }

        if let detailNode {
          HStack(spacing: 8) {
            Text(detailNode.address)
              .font(.caption)
              .foregroundStyle(.secondary)

            if let detailLogin {
              Label(detailLogin, systemImage: "person.crop.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
            }
          }

          ScrollView(.horizontal) {
            HStack(spacing: 6) {
              ForEach(detailNode.displayLabels(
                groupKey: settings.normalizedGroupingLabelKey,
                loginKey: settings.normalizedLoginLabelKey,
                limit: 8
              )) { label in
                DesktopLabelChip(label: label)
              }
            }
          }
          .scrollIndicators(.hidden)
        } else {
          Text("Select a server to start a Teleport session.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        Text(activeTab?.terminalStore.statusMessage ?? "Ready to connect")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      if let activeTab {
        EmbeddedTerminalView(
          sessionStore: activeTab.terminalStore,
          focusToken: terminalFocusToken
        )
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(.quaternary, lineWidth: 1)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ContentUnavailableView(
          "No Active Connection",
          systemImage: "terminal",
          description: Text("Connect to a server from the sidebar to open a Teleport tab.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
    .padding(20)
  }

  private var selectedNodeBinding: Binding<String?> {
    Binding(
      get: {
        browserSelectedNodeID
      },
      set: { newValue in
        browserSelectedNodeID = newValue
      }
    )
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
      return "The current tsh session is expired. Run tsh login and wait for the desktop tab to refresh."
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

    return Array(Set(store.nodes.map { $0.groupValue(for: groupingKey) }))
      .sorted { lhs, rhs in
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
      }
  }

  private var sections: [DesktopServerSection] {
    guard let groupingKey = settings.normalizedGroupingLabelKey else {
      return [DesktopServerSection(title: "Servers", nodes: filteredNodes)]
    }

    let grouped = Dictionary(grouping: filteredNodes) { node in
      node.groupValue(for: groupingKey)
    }

    return grouped.keys
      .sorted { lhs, rhs in
        lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
      }
      .map { key in
        DesktopServerSection(title: key, nodes: grouped[key, default: []])
      }
  }

  private var activeTab: DesktopTab? {
    tabStore.selectedTab
  }

  private var sidebarSelectedNode: TeleportNode? {
    guard let browserSelectedNodeID else {
      return nil
    }

    return store.nodes.first { $0.id == browserSelectedNodeID }
  }

  private var activeTabNode: TeleportNode? {
    guard let activeTab else {
      return nil
    }

    let nodeID = activeTab.terminalStore.connectedNodeID ?? activeTab.selectedNodeID

    guard let nodeID else {
      return nil
    }

    return store.nodes.first { $0.id == nodeID }
  }

  private var detailNode: TeleportNode? {
    activeTabNode ?? sidebarSelectedNode
  }

  private var detailLogin: String? {
    guard let detailNode else {
      return nil
    }

    return resolvedLogin(for: detailNode)
  }

  private var actionNode: TeleportNode? {
    activeTabNode ?? sidebarSelectedNode
  }

  private var actionLogin: String? {
    guard let actionNode else {
      return nil
    }

    return resolvedLogin(for: actionNode)
  }

  private var isActiveTabConnected: Bool {
    activeTab?.terminalStore.connectedNodeID != nil
  }

  private var detailTitle: String {
    if let detailNode {
      return detailNode.hostname
    }

    return activeTab?.terminalStore.currentTitle ?? "Select a Server"
  }

  private var detailSubtitle: String {
    if let detailNode, let groupingKey = settings.normalizedGroupingLabelKey {
      let groupValue = detailNode.groupValue(for: groupingKey)

      if groupValue != "Ungrouped" {
        return groupValue
      }
    }

    return statusLine
  }

  private var openExternallyTitle: String {
    let terminalApplication = settings.selectedTerminalApplication

    if terminalApplication == .systemDefault {
      return "Open Externally"
    }

    return "Open in \(terminalApplication.displayName)"
  }

  private func resolvedLogin(for node: TeleportNode) -> String? {
    node.preferredLogin(
      labelKey: settings.normalizedLoginLabelKey,
      fallback: settings.normalizedFallbackLogin,
      allowedLogins: store.session.logins
    )
  }

  private func openNodeInApp(node: TeleportNode) {
    guard let command = store.connectCommand(for: node, settings: settings) else {
      store.errorMessage = "Could not resolve an SSH login for \(node.hostname)."
      return
    }

    browserSelectedNodeID = node.id

    let login = resolvedLogin(for: node) ?? "unknown"
    _ = tabStore.openTab(
      windowState: DesktopWindowState.command(
        command,
        title: "\(login)@\(node.hostname)",
        summary: "Running tsh ssh as \(login)",
        selectedNodeID: node.id,
        connectedNodeID: node.id
      )
    )
    requestTerminalFocus()
  }

  private func connectSelectionToNewTab(_ selectedIDs: Set<String>) {
    guard let node = node(forSelection: selectedIDs) else {
      return
    }

    openNodeInApp(node: node)
  }

  private func openSelectionExternally(_ selectedIDs: Set<String>) {
    guard let node = node(forSelection: selectedIDs) else {
      return
    }

    openNodeExternally(node)
  }

  private func canConnectSelection(_ selectedIDs: Set<String>) -> Bool {
    guard let node = node(forSelection: selectedIDs) else {
      return false
    }

    return resolvedLogin(for: node) != nil
  }

  private func node(forSelection selectedIDs: Set<String>) -> TeleportNode? {
    guard let nodeID = selectedIDs.first else {
      return nil
    }

    return filteredNodes.first { $0.id == nodeID }
  }

  private func openNodeExternally(_ node: TeleportNode) {
    store.connect(to: node, settings: settings)
  }

  private func reconcileSelection() {
    if let activeTab {
      if let selectedNodeID = activeTab.selectedNodeID,
         store.nodes.contains(where: { $0.id == selectedNodeID }) {
        return
      }

      guard !filteredNodes.isEmpty else {
        activeTab.selectedNodeID = nil
        return
      }

      activeTab.selectedNodeID = filteredNodes[0].id
      return
    }

    if let browserSelectedNodeID,
       store.nodes.contains(where: { $0.id == browserSelectedNodeID }) {
      return
    }

    guard !filteredNodes.isEmpty else {
      browserSelectedNodeID = nil
      return
    }

    browserSelectedNodeID = filteredNodes[0].id
  }

  private func syncSidebarSelectionToActiveTab() {
    guard let selectedNodeID = activeTab?.selectedNodeID else {
      return
    }

    browserSelectedNodeID = selectedNodeID
  }

  private func closeTab(_ tab: DesktopTab) {
    browserSelectedNodeID = tab.selectedNodeID
    _ = tabStore.closeTab(id: tab.id)
  }

  private func closeSelectedTabFromShortcut() -> Bool {
    guard let activeTab else {
      return false
    }

    closeTab(activeTab)
    return true
  }

  private func selectPreviousTabFromShortcut() -> Bool {
    tabStore.selectPreviousTab()
  }

  private func selectNextTabFromShortcut() -> Bool {
    tabStore.selectNextTab()
  }

  private func requestTerminalFocus() {
    terminalFocusToken += 1
  }
}

private struct DesktopServerSection {
  let title: String
  let nodes: [TeleportNode]
}

private struct DesktopTabPillView: View {
  let title: String
  let isSelected: Bool
  let onSelect: () -> Void
  let onClose: () -> Void

  var body: some View {
    HStack(spacing: 6) {
      Button(action: onSelect) {
        HStack(spacing: 8) {
          Image(systemName: "terminal")
            .font(.caption)
            .foregroundStyle(isSelected ? .primary : .secondary)

          Text(title)
            .font(.subheadline.weight(.medium))
            .lineLimit(1)
            .foregroundStyle(isSelected ? .primary : .secondary)
        }
        .padding(.leading, 10)
        .padding(.vertical, 8)
      }
      .buttonStyle(.plain)

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.caption2.weight(.bold))
          .foregroundStyle(.secondary)
          .padding(6)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .padding(.trailing, 6)
    }
    .background(
      Capsule()
        .fill(isSelected ? AnyShapeStyle(.quinary) : AnyShapeStyle(Color.clear))
    )
    .overlay(
      Capsule()
        .strokeBorder(
          isSelected ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Color.clear),
          lineWidth: 1
        )
    )
  }
}

private struct DesktopLabelChip: View {
  let label: TeleportLabel

  var body: some View {
    Text("\(label.key): \(label.value)")
      .font(.caption2)
      .lineLimit(1)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(
        Capsule(style: .continuous)
          .fill(.quaternary.opacity(0.5))
      )
  }
}
