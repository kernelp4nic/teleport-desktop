import Foundation
import Observation

@MainActor
@Observable
final class TeleportNodeStore {
  @ObservationIgnored private let teleportService: TeleportService
  @ObservationIgnored private let nodeCache: TeleportNodeCache
  @ObservationIgnored private let refreshWorker: TeleportRefreshWorker
  @ObservationIgnored private let terminalLauncher: TerminalLauncher
  @ObservationIgnored private let autoRefreshCooldown: TimeInterval
  @ObservationIgnored private let isDemoMode: Bool
  @ObservationIgnored private var isRefreshing = false

  var nodes: [TeleportNode] = []
  var session: TeleportSession = .unavailable(proxy: nil)
  var isLoading = false
  var errorMessage: String?
  var lastRefreshedAt: Date?
  var lastRefreshAttemptAt: Date?

  init(
    teleportService: TeleportService = TeleportService(),
    nodeCache: TeleportNodeCache = TeleportNodeCache(),
    terminalLauncher: TerminalLauncher = TerminalLauncher(),
    autoRefreshCooldown: TimeInterval = 120,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.teleportService = teleportService
    self.nodeCache = nodeCache
    refreshWorker = TeleportRefreshWorker()
    self.terminalLauncher = terminalLauncher
    self.autoRefreshCooldown = autoRefreshCooldown
    isDemoMode = environment["TELEPORT_DESKTOP_DEMO"] == "1"

    if isDemoMode {
      nodes = DemoContent.nodes
      session = DemoContent.session
      lastRefreshedAt = Date()
    } else if let cachedNodes = nodeCache.loadMostRecentNodes() {
      nodes = cachedNodes.nodes
      lastRefreshedAt = cachedNodes.fetchedAt
    }
  }

  func refreshIfNeeded(using settings: SettingsStore) async {
    guard !isDemoMode else {
      return
    }

    guard shouldAutoRefresh else {
      return
    }

    await refresh(using: settings)
  }

  func refresh(using settings: SettingsStore, forceRefresh: Bool = false) async {
    guard !isDemoMode else {
      return
    }

    guard !isRefreshing else {
      return
    }

    isRefreshing = true
    lastRefreshAttemptAt = Date()
    isLoading = true
    errorMessage = nil

    let proxyOverride = settings.normalizedProxyAddress
    let result = await refreshWorker.refresh(
      proxyOverride: proxyOverride,
      forceRefresh: forceRefresh
    )

    if session != result.session {
      session = result.session
    }

    if nodes != result.nodes {
      nodes = result.nodes
    }

    if lastRefreshedAt != result.lastRefreshedAt {
      lastRefreshedAt = result.lastRefreshedAt
    }

    if errorMessage != result.errorMessage {
      errorMessage = result.errorMessage
    }

    if isLoading {
      isLoading = false
    }

    isRefreshing = false
  }

  func connect(to node: TeleportNode, settings: SettingsStore) {
    guard let command = connectCommand(for: node, settings: settings) else {
      errorMessage = "Could not resolve an SSH login for \(node.hostname)."
      return
    }

    do {
      try terminalLauncher.open(
        command: command,
        label: node.hostname,
        terminalApplication: settings.selectedTerminalApplication
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func login(using settings: SettingsStore) {
    do {
      try terminalLauncher.open(
        command: loginCommand(using: settings),
        label: "teleport-login",
        terminalApplication: settings.selectedTerminalApplication
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func connectCommand(for node: TeleportNode, settings: SettingsStore) -> String? {
    teleportService.connectCommand(
      for: node,
      settings: settings,
      session: session
    )
  }

  func tmuxControlCommand(for node: TeleportNode, settings: SettingsStore) -> String? {
    teleportService.tmuxControlCommand(
      for: node,
      settings: settings,
      session: session
    )
  }

  func loginCommand(using settings: SettingsStore) -> String {
    teleportService.loginCommand(proxy: session.proxy ?? settings.normalizedProxyAddress)
  }

  private var shouldAutoRefresh: Bool {
    guard let lastRefreshAttemptAt else {
      return true
    }

    if nodes.isEmpty {
      return true
    }

    return Date().timeIntervalSince(lastRefreshAttemptAt) > autoRefreshCooldown
  }
}
