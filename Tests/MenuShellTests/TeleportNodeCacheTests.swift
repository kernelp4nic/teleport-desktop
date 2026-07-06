import Foundation
import Testing
@testable import MenuShell

struct TeleportNodeCacheTests {
  @Test func saveAndLoadNodesRoundTrip() throws {
    let cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let cache = TeleportNodeCache(cacheDirectory: cacheDirectory)
    let fetchedAt = Date(timeIntervalSince1970: 1_713_800_000)
    let nodes = [
      TeleportNode(
        id: "node-1",
        hostname: "acme.web01",
        address: "Tunnel",
        labels: [
          TeleportLabel(key: "customer", value: "acme"),
          TeleportLabel(key: "user", value: "ubuntu")
        ],
        labelMap: [
          "customer": "acme",
          "user": "ubuntu"
        ]
      )
    ]

    try cache.save(
      nodes: nodes,
      for: "teleport.example.com",
      fetchedAt: fetchedAt
    )

    let cachedNodes = cache.loadNodes(for: "teleport.example.com")

    #expect(cachedNodes?.fetchedAt == fetchedAt)
    #expect(cachedNodes?.nodes == nodes)
  }

  @Test func cacheKeyPrefersClusterThenProxy() {
    let cache = TeleportNodeCache(
      cacheDirectory: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    )

    let session = TeleportSession(
      state: .active,
      proxy: "teleport.example.com:443",
      cluster: "teleport.example.com",
      username: "sebastianm",
      logins: ["ubuntu"],
      validUntil: nil
    )

    #expect(cache.cacheKey(session: session, proxyOverride: nil) == "teleport.example.com")
  }

  @Test func loadMostRecentNodesReturnsNewestPayload() throws {
    let cacheDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    let cache = TeleportNodeCache(cacheDirectory: cacheDirectory)

    try cache.save(
      nodes: [],
      for: "older",
      fetchedAt: Date(timeIntervalSince1970: 10)
    )

    let latestNode = TeleportNode(
      id: "node-1",
      hostname: "newer.web01",
      address: "Tunnel",
      labels: [],
      labelMap: [:]
    )

    try cache.save(
      nodes: [latestNode],
      for: "newer",
      fetchedAt: Date(timeIntervalSince1970: 20)
    )

    let cachedNodes = cache.loadMostRecentNodes()

    #expect(cachedNodes?.nodes == [latestNode])
    #expect(cachedNodes?.fetchedAt == Date(timeIntervalSince1970: 20))
  }
}
