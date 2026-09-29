import AppKit
import Observation
import SwiftUI

struct DesktopRootView: View {
  @Environment(\.openSettings) private var openSettings
  @FocusState private var isRenameFieldFocused: Bool
  @Bindable var store: TeleportNodeStore
  @Bindable var settings: SettingsStore
  @Bindable var library: NodeLibraryStore
  @SceneStorage("desktop.searchText") private var searchText = ""
  @SceneStorage("desktop.selectedGroup") private var selectedGroup = Self.allGroups
  @State private var browserSelectedNodeID: String?
  @State private var browserSelectedRowID: String?
  @State private var collapsedSectionIDs = Set<String>()
  @State private var fileTransferDirection: FileTransferDirection?
  @State private var fileTransferMessage: String?
  @State private var fileTransferOperation: TeleportFileTransferOperation?
  @State private var fileTransferProgress: Double?
  @State private var fileTransferToastMessage: String?
  @State private var isTransferringFile = false
  @State private var isLoginSheetPresented = false
  @State private var remoteFilePath = "~/"
  @State private var renamedNodeID: String?
  @State private var renamedNodeName = ""
  @State private var uploadURLs: [URL] = []
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
        onSelectNextTab: selectNextTabFromShortcut,
        onShowSearch: showSearchFromShortcut,
        onFindNext: findNextFromShortcut,
        onFindPrevious: findPreviousFromShortcut
      )
    )
    .overlay(alignment: .bottomTrailing) {
      if let fileTransferToastMessage {
        FileTransferToast(message: fileTransferToastMessage)
          .padding(20)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
    }
    .animation(.easeInOut(duration: 0.2), value: fileTransferToastMessage)
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
          presentLoginSheet()
        } label: {
          Label("Login", systemImage: "person.badge.key")
        }

        Button {
          showTerminalSearch()
        } label: {
          Label("Find", systemImage: "magnifyingglass")
        }
        .disabled(activeTab == nil)

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
    .sheet(isPresented: $isLoginSheetPresented, onDismiss: loginSheetDismissed) {
      TeleportLoginSheet(store: store, settings: settings)
    }
    .sheet(item: $fileTransferDirection) { direction in
      FileTransferView(
        direction: direction,
        remotePath: $remoteFilePath,
        uploadURLs: uploadURLs,
        isTransferring: isTransferringFile,
        message: fileTransferMessage,
        progress: fileTransferProgress,
        onCancel: cancelFileTransfer,
        onChooseFiles: chooseUploadFiles,
        onChooseDownloadDirectory: downloadFile,
        onUpload: uploadFiles
      )
    }
    .alert("Rename Server", isPresented: renameAlertIsPresented) {
      TextField("Server name", text: $renamedNodeName)
        .focused($isRenameFieldFocused)

      Button("Cancel", role: .cancel) {
        isRenameFieldFocused = false
        renamedNodeID = nil
      }

      Button("Rename") {
        applyNodeRename()
      }
    } message: {
      Text("Leave the name empty to restore the original hostname.")
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
            ForEach(sections) { section in
              Section(isExpanded: sectionIsExpandedBinding(for: section.id)) {
                ForEach(section.nodes) { node in
                  DesktopServerRowView(
                    node: node,
                    name: library.name(for: node, scopeKey: libraryScopeKey),
                    groupingKey: settings.normalizedGroupingLabelKey,
                    resolvedLogin: resolvedLogin(for: node),
                    isFavorite: library.isFavorite(nodeID: node.id, scopeKey: libraryScopeKey),
                    onToggleFavorite: {
                      toggleFavorite(for: node)
                    }
                  )
                  .tag(rowID(sectionID: section.id, nodeID: node.id))
                  .contentShape(Rectangle())
                  .listRowInsets(
                    EdgeInsets(top: 4, leading: 26, bottom: 4, trailing: 10)
                  )
                }
              } header: {
                Text(section.title)
                  .textCase(nil)
                  .font(.subheadline.weight(.semibold))
                  .foregroundStyle(.secondary)
                  .frame(maxWidth: .infinity, alignment: .leading)
                  .contentShape(Rectangle())
                  .onTapGesture {
                    toggleSection(section.id)
                  }
                  .padding(.leading, 6)
              }
            }
          }
          .listStyle(.sidebar)
          .contextMenu(forSelectionType: String.self) { selectedIDs in
            Button("Rename") {
              prepareNodeRename(selectedIDs)
            }
            .disabled(node(forSelection: selectedIDs) == nil)

            Divider()

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

          if let connectionBadgeState = activeConnectionBadgeState {
            HStack(spacing: 10) {
              if connectionBadgeState == .connected {
                Button {
                  prepareUpload()
                } label: {
                  Label("Upload Files", systemImage: "arrow.up.to.line")
                }
                .help("Upload files")

                Button {
                  prepareDownload()
                } label: {
                  Label("Download File", systemImage: "arrow.down.to.line")
                }
                .help("Download file")
              }

              ConnectionStatusBadge(state: connectionBadgeState)
            }
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
          focusToken: terminalFocusToken,
          scrollbackLines: settings.terminalScrollbackLines,
          localEchoEnabled: settings.localEchoEnabled
        )
          .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
              .strokeBorder(.quaternary, lineWidth: 1)
          )
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if store.session.state != .active {
        ContentUnavailableView {
          Label("Teleport Login Required", systemImage: "person.badge.key")
        } description: {
          Text("Authenticate with Teleport to load your servers.")
        } actions: {
          Button("Login") {
            presentLoginSheet()
          }
          .buttonStyle(.borderedProminent)
        }
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
        browserSelectedRowID
      },
      set: { newValue in
        browserSelectedRowID = newValue
        browserSelectedNodeID = newValue.flatMap(nodeID(fromRowID:))
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
      guard node.matches(
        searchText: searchText,
        additionalText: library.name(for: node, scopeKey: libraryScopeKey)
      ) else {
        return false
      }

      if selectedGroup == Self.allGroups {
        return true
      }

      return node.groupValue(for: settings.normalizedGroupingLabelKey) == selectedGroup
    }
  }

  private var libraryScopeKey: String {
    library.scopeKey(session: store.session, settings: settings)
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

  private var favoriteNodes: [TeleportNode] {
    filteredNodes
      .filter { library.isFavorite(nodeID: $0.id, scopeKey: libraryScopeKey) }
      .sorted { lhs, rhs in
        library.name(for: lhs, scopeKey: libraryScopeKey).localizedCaseInsensitiveCompare(
          library.name(for: rhs, scopeKey: libraryScopeKey)
        ) == .orderedAscending
      }
  }

  private var recentNodes: [TeleportNode] {
    let nodesByID = Dictionary(uniqueKeysWithValues: filteredNodes.map { ($0.id, $0) })
    let favoriteNodeIDs = Set(favoriteNodes.map(\.id))

    return library.recentNodeIDs(scopeKey: libraryScopeKey).compactMap { nodeID in
      guard !favoriteNodeIDs.contains(nodeID) else {
        return nil
      }

      return nodesByID[nodeID]
    }
  }

  private var sections: [DesktopServerSection] {
    var visibleSections: [DesktopServerSection] = []

    if !favoriteNodes.isEmpty {
      visibleSections.append(
        DesktopServerSection(id: "favorites", title: "Favorites", nodes: favoriteNodes)
      )
    }

    if !recentNodes.isEmpty {
      visibleSections.append(
        DesktopServerSection(id: "recent", title: "Recent", nodes: recentNodes)
      )
    }

    guard let groupingKey = settings.normalizedGroupingLabelKey else {
      if !filteredNodes.isEmpty {
        visibleSections.append(
          DesktopServerSection(id: "servers", title: "Servers", nodes: filteredNodes)
        )
      }
      return visibleSections
    }

    let grouped = Dictionary(grouping: filteredNodes) { node in
      node.groupValue(for: groupingKey)
    }

    visibleSections.append(
      contentsOf: grouped.keys
        .sorted { lhs, rhs in
          lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        .map { key in
          DesktopServerSection(id: "group:\(key)", title: key, nodes: grouped[key, default: []])
        }
    )

    return visibleSections
  }

  private func sectionIsExpandedBinding(for sectionID: String) -> Binding<Bool> {
    Binding(
      get: { !collapsedSectionIDs.contains(sectionID) },
      set: { isExpanded in
        withAnimation(.easeInOut(duration: 0.2)) {
          if isExpanded {
            collapsedSectionIDs.remove(sectionID)
          } else {
            collapsedSectionIDs.insert(sectionID)
          }
        }
      }
    )
  }

  private func toggleSection(_ sectionID: String) {
    withAnimation(.easeInOut(duration: 0.2)) {
      if collapsedSectionIDs.contains(sectionID) {
        collapsedSectionIDs.remove(sectionID)
      } else {
        collapsedSectionIDs.insert(sectionID)
      }
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

  private var activeConnectionBadgeState: TerminalConnectionState? {
    guard let activeTab else {
      return nil
    }

    switch activeTab.terminalStore.connectionState {
    case .connecting, .connected:
      return activeTab.terminalStore.connectionState
    case .idle, .disconnected:
      return nil
    }
  }

  private var detailTitle: String {
    if let detailNode {
      return library.name(for: detailNode, scopeKey: libraryScopeKey)
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
      SoundFeedbackService.play(.error, settings: settings)
      return
    }

    browserSelectedNodeID = node.id

    let login = resolvedLogin(for: node) ?? "unknown"
    let scopeKey = libraryScopeKey
    let tab = tabStore.openTab(
      windowState: DesktopWindowState.command(
        command,
        title: "\(login)@\(library.name(for: node, scopeKey: libraryScopeKey))",
        summary: "Running tsh ssh as \(login)",
        selectedNodeID: node.id,
        connectedNodeID: node.id
      )
    )
    tab.terminalStore.onConnectionEstablished = { [library] in
      library.recordRecent(nodeID: node.id, scopeKey: scopeKey)
      SoundFeedbackService.play(.connected, settings: settings)
    }
    SoundFeedbackService.play(.action, settings: settings)
    requestTerminalFocus()
  }

  private func presentLoginSheet() {
    SoundFeedbackService.play(.action, settings: settings)
    isLoginSheetPresented = true
  }

  private func loginSheetDismissed() {
    reconcileSelection()
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
    guard let rowID = selectedIDs.first,
          let nodeID = nodeID(fromRowID: rowID) else {
      return nil
    }

    return filteredNodes.first { $0.id == nodeID }
  }

  private func openNodeExternally(_ node: TeleportNode) {
    store.connect(to: node, settings: settings)
  }

  private func toggleFavorite(for node: TeleportNode) {
    library.toggleFavorite(nodeID: node.id, scopeKey: libraryScopeKey)
    SoundFeedbackService.play(.favorite, settings: settings)
  }

  private func rowID(sectionID: String, nodeID: String) -> String {
    "\(sectionID)\u{1F}\(nodeID)"
  }

  private func nodeID(fromRowID rowID: String) -> String? {
    rowID.split(separator: "\u{1F}", maxSplits: 1).last.map(String.init)
  }

  private func preferredRowID(for nodeID: String) -> String? {
    guard let section = sections.last(where: { section in
      section.nodes.contains { $0.id == nodeID }
    }) else {
      return nil
    }

    return rowID(sectionID: section.id, nodeID: nodeID)
  }

  private var renameAlertIsPresented: Binding<Bool> {
    Binding(
      get: { renamedNodeID != nil },
      set: { isPresented in
        if !isPresented {
          renamedNodeID = nil
        }
      }
    )
  }

  private func prepareNodeRename(_ selectedIDs: Set<String>) {
    guard let node = node(forSelection: selectedIDs) else {
      return
    }

    renamedNodeID = node.id
    renamedNodeName = library.name(for: node, scopeKey: libraryScopeKey)
    isRenameFieldFocused = true
  }

  private func applyNodeRename() {
    guard let renamedNodeID else {
      return
    }

    library.rename(nodeID: renamedNodeID, to: renamedNodeName, scopeKey: libraryScopeKey)
    isRenameFieldFocused = false
    self.renamedNodeID = nil
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
      if browserSelectedRowID.flatMap(nodeID(fromRowID:)) != browserSelectedNodeID {
        browserSelectedRowID = preferredRowID(for: browserSelectedNodeID)
      }
      return
    }

    guard !filteredNodes.isEmpty else {
      browserSelectedNodeID = nil
      browserSelectedRowID = nil
      return
    }

    browserSelectedNodeID = filteredNodes[0].id
    browserSelectedRowID = preferredRowID(for: filteredNodes[0].id)
  }

  private func syncSidebarSelectionToActiveTab() {
    guard let selectedNodeID = activeTab?.selectedNodeID else {
      return
    }

    browserSelectedNodeID = selectedNodeID
    browserSelectedRowID = preferredRowID(for: selectedNodeID)
  }

  private func closeTab(_ tab: DesktopTab) {
    browserSelectedNodeID = tab.selectedNodeID
    browserSelectedRowID = tab.selectedNodeID.flatMap(preferredRowID(for:))
    _ = tabStore.closeTab(id: tab.id)
    SoundFeedbackService.play(.dismissed, settings: settings)
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

  private func showTerminalSearch() {
    activeTab?.terminalStore.showSearch()
  }

  private func findNextSearchResult() {
    activeTab?.terminalStore.findNext()
  }

  private func findPreviousSearchResult() {
    activeTab?.terminalStore.findPrevious()
  }

  private func showSearchFromShortcut() -> Bool {
    guard activeTab != nil else {
      return false
    }

    showTerminalSearch()
    return true
  }

  private func findNextFromShortcut() -> Bool {
    guard activeTab != nil else {
      return false
    }

    findNextSearchResult()
    return true
  }

  private func findPreviousFromShortcut() -> Bool {
    guard activeTab != nil else {
      return false
    }

    findPreviousSearchResult()
    return true
  }

  private func prepareUpload() {
    remoteFilePath = "~/"
    uploadURLs = []
    fileTransferMessage = nil
    fileTransferProgress = nil
    fileTransferDirection = .upload
  }

  private func prepareDownload() {
    remoteFilePath = "~/"
    fileTransferMessage = nil
    fileTransferProgress = nil
    fileTransferDirection = .download
  }

  private func chooseUploadFiles() {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = false
    panel.canChooseFiles = true

    guard panel.runModal() == .OK else {
      return
    }

    uploadURLs = panel.urls
  }

  private func uploadFiles() {
    guard !uploadURLs.isEmpty,
          let transferTarget else {
      return
    }

    let urls = uploadURLs
    let remotePath = remoteFilePath
    isTransferringFile = true
    fileTransferProgress = 0
    fileTransferMessage = "Uploading \(urls.count) file\(urls.count == 1 ? "" : "s")…"

    Task {
      do {
        let operation = try TeleportFileTransferService().uploadOperation(
          localURLs: urls,
          remotePath: remotePath,
          login: transferTarget.login,
          hostname: transferTarget.hostname
        )
        fileTransferOperation = operation
        try await operation.run { progress in
          Task { @MainActor in
            fileTransferProgress = progress
          }
        }
        fileTransferDirection = nil
        showFileTransferToast("Upload complete")
        SoundFeedbackService.play(.completed, settings: settings)
      } catch {
        fileTransferMessage = error.localizedDescription
        SoundFeedbackService.play(.error, settings: settings)
      }

      isTransferringFile = false
      fileTransferOperation = nil
    }
  }

  private func downloadFile() {
    guard let transferTarget else {
      return
    }

    let panel = NSOpenPanel()
    panel.prompt = "Download Here"
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true

    guard panel.runModal() == .OK,
          let localDirectoryURL = panel.url else {
      return
    }

    let remotePath = remoteFilePath
    isTransferringFile = true
    fileTransferProgress = 0
    fileTransferMessage = "Downloading file…"

    Task {
      do {
        let operation = try TeleportFileTransferService().downloadOperation(
          remotePath: remotePath,
          localDirectoryURL: localDirectoryURL,
          login: transferTarget.login,
          hostname: transferTarget.hostname
        )
        fileTransferOperation = operation
        try await operation.run { progress in
          Task { @MainActor in
            fileTransferProgress = progress
          }
        }
        fileTransferDirection = nil
        showFileTransferToast("Download complete")
        SoundFeedbackService.play(.completed, settings: settings)
      } catch {
        fileTransferMessage = error.localizedDescription
        SoundFeedbackService.play(.error, settings: settings)
      }

      isTransferringFile = false
      fileTransferOperation = nil
    }
  }

  private func cancelFileTransfer() {
    fileTransferMessage = "Cancelling transfer…"
    fileTransferOperation?.cancel()
  }

  private var transferTarget: (login: String, hostname: String)? {
    guard activeConnectionBadgeState == .connected,
          let node = activeTabNode,
          let login = resolvedLogin(for: node) else {
      return nil
    }

    return (login, node.hostname)
  }

  private func showFileTransferToast(_ message: String) {
    fileTransferToastMessage = message

    Task {
      try? await Task.sleep(for: .seconds(3))

      if fileTransferToastMessage == message {
        fileTransferToastMessage = nil
      }
    }
  }
}

private enum FileTransferDirection: String, Identifiable {
  case upload
  case download

  var id: String {
    rawValue
  }
}

private struct FileTransferView: View {
  let direction: FileTransferDirection
  @Binding var remotePath: String
  let uploadURLs: [URL]
  let isTransferring: Bool
  let message: String?
  let progress: Double?
  let onCancel: () -> Void
  let onChooseFiles: () -> Void
  let onChooseDownloadDirectory: () -> Void
  let onUpload: () -> Void

  var body: some View {
    VStack(spacing: 18) {
      Text(direction == .upload ? "Upload Files" : "Download File")
        .font(.headline)

      TextField(
        direction == .upload ? "Upload destination" : "Remote file path",
        text: $remotePath
      )
      .textFieldStyle(.roundedBorder)
      .disabled(isTransferring)

      if direction == .upload {
        Button(action: onChooseFiles) {
          VStack(spacing: 8) {
            Image(systemName: uploadURLs.isEmpty ? "doc.badge.plus" : "checkmark.circle.fill")
              .font(.title2)

            Text(uploadButtonTitle)
          }
          .frame(maxWidth: .infinity, minHeight: 90)
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(.quaternary.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .disabled(isTransferring)

        Button("Upload", action: onUpload)
          .buttonStyle(.borderedProminent)
          .disabled(uploadURLs.isEmpty || remotePathIsEmpty || isTransferring)
      } else {
        Button("Choose Destination and Download", action: onChooseDownloadDirectory)
          .buttonStyle(.borderedProminent)
          .disabled(remotePathIsEmpty || isTransferring)
      }

      if isTransferring {
        VStack(spacing: 10) {
          if let progress {
            ProgressView(value: progress)

            Text("\(Int(progress * 100))%")
              .font(.caption.monospacedDigit())
              .foregroundStyle(.secondary)
          } else {
            ProgressView()
          }

          if let message {
            Text(message)
              .font(.caption)
              .foregroundStyle(.secondary)
          }

          Button("Cancel", role: .destructive, action: onCancel)
        }
        .frame(maxWidth: .infinity)
      }

      if let message, !isTransferring {
        Text(message)
          .font(.caption)
          .foregroundStyle(.red)
          .multilineTextAlignment(.center)
      }
    }
    .padding(20)
    .frame(width: 420)
    .interactiveDismissDisabled(isTransferring)
  }

  private var uploadButtonTitle: String {
    if uploadURLs.isEmpty {
      return "Choose Files…"
    }

    return "\(uploadURLs.count) file\(uploadURLs.count == 1 ? "" : "s") selected"
  }

  private var remotePathIsEmpty: Bool {
    remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }
}

private struct FileTransferToast: View {
  let message: String

  var body: some View {
    Label(message, systemImage: "checkmark.circle.fill")
      .font(.callout.weight(.medium))
      .foregroundStyle(.white)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .background(.green, in: Capsule())
      .shadow(radius: 8, y: 3)
  }
}

private struct DesktopServerSection: Identifiable {
  let id: String
  let title: String
  let nodes: [TeleportNode]
}

private struct ConnectionStatusBadge: View {
  let state: TerminalConnectionState

  var body: some View {
    HStack(spacing: 6) {
      Circle()
        .fill(indicatorColor)
        .frame(width: 8, height: 8)

      Text(labelText)
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(
      Capsule()
        .fill(.quaternary.opacity(0.35))
    )
  }

  private var labelText: String {
    switch state {
    case .connecting:
      return "Connecting"
    case .connected:
      return "Connected"
    case .idle, .disconnected:
      return ""
    }
  }

  private var indicatorColor: Color {
    switch state {
    case .connecting:
      return .yellow
    case .connected:
      return .green
    case .idle, .disconnected:
      return .secondary
    }
  }
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
