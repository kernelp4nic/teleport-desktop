import Foundation

struct TeleportNodeCache {
  private let fileManager: FileManager
  private let cacheDirectory: URL

  init(
    fileManager: FileManager = .default,
    cacheDirectory: URL? = nil
  ) {
    self.fileManager = fileManager

    if let cacheDirectory {
      self.cacheDirectory = cacheDirectory
    } else {
      let applicationSupportDirectory = fileManager.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

      self.cacheDirectory = applicationSupportDirectory
        .appendingPathComponent("teleport-desktop", isDirectory: true)
        .appendingPathComponent("Cache", isDirectory: true)
    }
  }

  func loadNodes(for key: String) -> CachedNodes? {
    let fileURL = cacheFileURL(for: key)

    guard let data = try? Data(contentsOf: fileURL) else {
      return nil
    }

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    return try? decoder.decode(CachedNodes.self, from: data)
  }

  func save(nodes: [TeleportNode], for key: String, fetchedAt: Date) throws {
    try fileManager.createDirectory(
      at: cacheDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let fileURL = cacheFileURL(for: key)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    let payload = CachedNodes(
      fetchedAt: fetchedAt,
      nodes: nodes
    )

    try encoder.encode(payload).write(to: fileURL, options: .atomic)
  }

  func cacheKey(session: TeleportSession, proxyOverride: String?) -> String {
    session.cluster
      ?? session.proxy
      ?? TeleportService.normalizeProxyAddress(proxyOverride)
      ?? "default"
  }

  func loadMostRecentNodes() -> CachedNodes? {
    guard let fileURLs = try? fileManager.contentsOfDirectory(
      at: cacheDirectory,
      includingPropertiesForKeys: nil
    ) else {
      return nil
    }

    return fileURLs
      .filter { $0.pathExtension == "json" }
      .compactMap { try? Data(contentsOf: $0) }
      .compactMap { data in
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedNodes.self, from: data)
      }
      .max { lhs, rhs in
        lhs.fetchedAt < rhs.fetchedAt
      }
  }

  private func cacheFileURL(for key: String) -> URL {
    cacheDirectory
      .appendingPathComponent("servers-\(safeFilename(from: key))")
      .appendingPathExtension("json")
  }

  private func safeFilename(from key: String) -> String {
    Data(key.utf8)
      .base64EncodedString()
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "=", with: "")
  }
}

struct CachedNodes: Codable, Equatable, Sendable {
  let fetchedAt: Date
  let nodes: [TeleportNode]
}
