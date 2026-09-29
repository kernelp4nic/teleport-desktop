import Foundation

actor TeleportRefreshWorker {
  private let teleportService: TeleportService
  private let nodeCache: TeleportNodeCache

  init(
    teleportService: TeleportService = TeleportService(),
    nodeCache: TeleportNodeCache = TeleportNodeCache()
  ) {
    self.teleportService = teleportService
    self.nodeCache = nodeCache
  }

  func loadSession(proxyOverride: String?) -> TeleportSession {
    teleportService.loadSession(proxyOverride: proxyOverride)
  }

  func refresh(
    proxyOverride: String?,
    forceRefresh: Bool
  ) -> TeleportRefreshResult {
    let session = teleportService.loadSession(proxyOverride: proxyOverride)

    guard session.isActive else {
      let errorMessage: String? = switch session.state {
      case .expired:
        "Your Teleport session expired. Run tsh login to refresh it."
      case .unavailable:
        "No active Teleport session. Run tsh login first."
      case .active:
        nil
      }

      return TeleportRefreshResult(
        session: session,
        nodes: [],
        lastRefreshedAt: nil,
        errorMessage: errorMessage
      )
    }

    let cacheKey = nodeCache.cacheKey(
      session: session,
      proxyOverride: proxyOverride
    )
    let cachedNodes = nodeCache.loadNodes(for: cacheKey)

    if !forceRefresh, let cachedNodes {
      return TeleportRefreshResult(
        session: session,
        nodes: cachedNodes.nodes,
        lastRefreshedAt: cachedNodes.fetchedAt,
        errorMessage: nil
      )
    }

    do {
      let nodes = try teleportService.loadNodes(proxyOverride: session.proxy ?? proxyOverride)
      let fetchedAt = Date()
      try? nodeCache.save(
        nodes: nodes,
        for: cacheKey,
        fetchedAt: fetchedAt
      )

      return TeleportRefreshResult(
        session: session,
        nodes: nodes,
        lastRefreshedAt: fetchedAt,
        errorMessage: nil
      )
    } catch {
      if let cachedNodes {
        return TeleportRefreshResult(
          session: session,
          nodes: cachedNodes.nodes,
          lastRefreshedAt: cachedNodes.fetchedAt,
          errorMessage: "Could not refresh servers. Showing cached data."
        )
      }

      return TeleportRefreshResult(
        session: session,
        nodes: [],
        lastRefreshedAt: nil,
        errorMessage: error.localizedDescription
      )
    }
  }
}

struct TeleportRefreshResult: Sendable {
  let session: TeleportSession
  let nodes: [TeleportNode]
  let lastRefreshedAt: Date?
  let errorMessage: String?
}
