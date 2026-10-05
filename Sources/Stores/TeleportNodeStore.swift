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
  @ObservationIgnored private let sessionPollInterval: Duration
  @ObservationIgnored private var sessionPollTask: Task<Void, Never>?
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
    sessionPollInterval: Duration = .seconds(5),
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) {
    self.teleportService = teleportService
    self.nodeCache = nodeCache
    refreshWorker = TeleportRefreshWorker()
    self.terminalLauncher = terminalLauncher
    self.autoRefreshCooldown = autoRefreshCooldown
    self.sessionPollInterval = sessionPollInterval
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

    if session.isActive {
      stopSessionPolling()
    } else {
      startSessionPollingIfNeeded(using: settings)
    }

    if forceRefresh {
      SoundFeedbackService.play(
        result.errorMessage == nil ? .completed : .error,
        settings: settings
      )
    }
  }

  func connect(to node: TeleportNode, settings: SettingsStore) {
    guard let command = connectCommand(for: node, settings: settings) else {
      errorMessage = "Could not resolve an SSH login for \(node.hostname)."
      SoundFeedbackService.play(.error, settings: settings)
      return
    }

    do {
      try terminalLauncher.open(
        command: command,
        label: node.hostname,
        terminalApplication: settings.selectedTerminalApplication
      )
      SoundFeedbackService.play(.action, settings: settings)
    } catch {
      errorMessage = error.localizedDescription
      SoundFeedbackService.play(.error, settings: settings)
    }
  }

  func login(using settings: SettingsStore) {
    do {
      try terminalLauncher.open(
        command: loginCommand(using: settings),
        label: "teleport-login",
        terminalApplication: settings.selectedTerminalApplication
      )
      SoundFeedbackService.play(.action, settings: settings)
    } catch {
      errorMessage = error.localizedDescription
      SoundFeedbackService.play(.error, settings: settings)
    }
  }

  func connectCommand(for node: TeleportNode, settings: SettingsStore) -> String? {
    teleportService.connectCommand(
      for: node,
      settings: settings,
      session: session
    )
  }

  /// `fallbackUser` is used when no Teleport user is configured, e.g. the
  /// username stored in 1Password.
  func loginCommand(using settings: SettingsStore, fallbackUser: String? = nil) -> String {
    teleportService.loginCommand(
      proxy: session.proxy ?? settings.normalizedProxyAddress,
      user: settings.normalizedTeleportUser ?? fallbackUser
    )
  }

  /// Polls `tsh status` until a session becomes active (e.g. after `tsh login`
  /// finishes in a terminal), then performs a full refresh and stops polling.
  private func startSessionPollingIfNeeded(using settings: SettingsStore) {
    guard sessionPollTask == nil else {
      return
    }

    let interval = sessionPollInterval
    sessionPollTask = Task { [weak self, refreshWorker] in
      while !Task.isCancelled {
        try? await Task.sleep(for: interval)

        guard !Task.isCancelled else {
          return
        }

        let proxyOverride = settings.normalizedProxyAddress
        let probed = await refreshWorker.loadSession(proxyOverride: proxyOverride)

        guard probed.isActive else {
          continue
        }

        guard let self else {
          return
        }

        sessionPollTask = nil
        await refresh(using: settings)
        return
      }
    }
  }

  private func stopSessionPolling() {
    sessionPollTask?.cancel()
    sessionPollTask = nil
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
