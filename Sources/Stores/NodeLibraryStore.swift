import Foundation
import Observation

@Observable
final class NodeLibraryStore {
  private enum Keys {
    static let favoritesByScope = "favoritesByScope"
    static let recentsByScope = "recentsByScope"
    static let nodeNamesByScope = "nodeNamesByScope"
  }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let encoder = JSONEncoder()
  @ObservationIgnored private let decoder = JSONDecoder()

  var favoritesByScope: [String: Set<String>] {
    didSet {
      persistFavorites()
    }
  }

  var recentsByScope: [String: [String]] {
    didSet {
      persistRecents()
    }
  }

  var nodeNamesByScope: [String: [String: String]] {
    didSet {
      persistNodeNames()
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    favoritesByScope = Self.loadValue(
      forKey: Keys.favoritesByScope,
      defaults: defaults,
      decoder: decoder,
      fallback: [:]
    )
    recentsByScope = Self.loadValue(
      forKey: Keys.recentsByScope,
      defaults: defaults,
      decoder: decoder,
      fallback: [:]
    )
    nodeNamesByScope = Self.loadValue(
      forKey: Keys.nodeNamesByScope,
      defaults: defaults,
      decoder: decoder,
      fallback: [:]
    )
  }

  func scopeKey(session: TeleportSession, settings: SettingsStore) -> String {
    if let proxy = normalizedScopeValue(session.proxy) {
      return proxy
    }

    if let proxyOverride = normalizedScopeValue(settings.normalizedProxyAddress) {
      return proxyOverride
    }

    if let cluster = normalizedScopeValue(session.cluster) {
      return cluster
    }

    return "default"
  }

  func favoriteNodeIDs(scopeKey: String) -> Set<String> {
    favoritesByScope[scopeKey, default: []]
  }

  func recentNodeIDs(scopeKey: String) -> [String] {
    recentsByScope[scopeKey, default: []]
  }

  func isFavorite(nodeID: String, scopeKey: String) -> Bool {
    favoriteNodeIDs(scopeKey: scopeKey).contains(nodeID)
  }

  func toggleFavorite(nodeID: String, scopeKey: String) {
    var favorites = favoriteNodeIDs(scopeKey: scopeKey)

    if favorites.contains(nodeID) {
      favorites.remove(nodeID)
    } else {
      favorites.insert(nodeID)
    }

    if favorites.isEmpty {
      favoritesByScope.removeValue(forKey: scopeKey)
    } else {
      favoritesByScope[scopeKey] = favorites
    }
  }

  func recordRecent(nodeID: String, scopeKey: String) {
    var recents = recentNodeIDs(scopeKey: scopeKey)
    recents.removeAll { $0 == nodeID }
    recents.insert(nodeID, at: 0)
    recents = Array(recents.prefix(10))

    if recents.isEmpty {
      recentsByScope.removeValue(forKey: scopeKey)
    } else {
      recentsByScope[scopeKey] = recents
    }
  }

  func name(for node: TeleportNode, scopeKey: String) -> String {
    nodeNamesByScope[scopeKey]?[node.id] ?? node.hostname
  }

  func rename(nodeID: String, to name: String, scopeKey: String) {
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

    if trimmedName.isEmpty {
      nodeNamesByScope[scopeKey]?.removeValue(forKey: nodeID)

      if nodeNamesByScope[scopeKey]?.isEmpty == true {
        nodeNamesByScope.removeValue(forKey: scopeKey)
      }
    } else {
      nodeNamesByScope[scopeKey, default: [:]][nodeID] = trimmedName
    }
  }

  private static func loadValue<T: Decodable>(
    forKey key: String,
    defaults: UserDefaults,
    decoder: JSONDecoder,
    fallback: T
  ) -> T {
    guard let data = defaults.data(forKey: key),
          let value = try? decoder.decode(T.self, from: data) else {
      return fallback
    }

    return value
  }

  private func persistFavorites() {
    persist(favoritesByScope, forKey: Keys.favoritesByScope)
  }

  private func persistRecents() {
    persist(recentsByScope, forKey: Keys.recentsByScope)
  }

  private func persistNodeNames() {
    persist(nodeNamesByScope, forKey: Keys.nodeNamesByScope)
  }

  private func persist<T: Encodable>(_ value: T, forKey key: String) {
    guard let data = try? encoder.encode(value) else {
      return
    }

    defaults.set(data, forKey: key)
  }

  private func normalizedScopeValue(_ value: String?) -> String? {
    guard let value else {
      return nil
    }

    let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmedValue.isEmpty ? nil : trimmedValue
  }
}
