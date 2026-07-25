import Foundation

enum DemoContent {
  static let session = TeleportSession(
    state: .active,
    proxy: "teleport.demo.example:443",
    cluster: "demo-cluster",
    username: "demo-user",
    logins: ["ubuntu", "ec2-user", "admin"],
    validUntil: Date(timeIntervalSince1970: 2_051_222_400)
  )

  static let nodes = [
    node("aurora-api-01", customer: "Aurora Labs", role: "api", login: "ubuntu"),
    node("aurora-api-02", customer: "Aurora Labs", role: "api", login: "ubuntu"),
    node("aurora-worker-01", customer: "Aurora Labs", role: "worker", login: "ec2-user"),
    node("aurora-staging-01", customer: "Aurora Labs", role: "api", login: "ubuntu"),
    node("bluebird-web-01", customer: "Bluebird", role: "web", login: "ubuntu"),
    node("bluebird-web-02", customer: "Bluebird", role: "web", login: "ubuntu"),
    node("bluebird-db-01", customer: "Bluebird", role: "database", login: "admin"),
    node("bluebird-cache-01", customer: "Bluebird", role: "cache", login: "ec2-user"),
    node("cinder-gateway-01", customer: "Cinder Cloud", role: "gateway", login: "ubuntu"),
    node("cinder-app-01", customer: "Cinder Cloud", role: "app", login: "ubuntu"),
    node("cinder-app-02", customer: "Cinder Cloud", role: "app", login: "ubuntu"),
    node("cinder-observer-01", customer: "Cinder Cloud", role: "observability", login: "admin"),
    node("northstar-edge-01", customer: "Northstar", role: "edge", login: "ec2-user"),
    node("northstar-service-01", customer: "Northstar", role: "service", login: "ubuntu"),
    node("northstar-service-02", customer: "Northstar", role: "service", login: "ubuntu"),
    node("sandbox-runner-01", customer: "Internal", role: "runner", login: "admin")
  ]

  private static func node(
    _ hostname: String,
    customer: String,
    role: String,
    login: String
  ) -> TeleportNode {
    let labels = [
      TeleportLabel(key: "customer", value: customer),
      TeleportLabel(key: "environment", value: customer == "Internal" ? "development" : "production"),
      TeleportLabel(key: "role", value: role),
      TeleportLabel(key: "user", value: login)
    ]

    return TeleportNode(
      id: hostname,
      hostname: hostname,
      address: "Tunnel",
      labels: labels,
      labelMap: Dictionary(uniqueKeysWithValues: labels.map { ($0.key, $0.value) })
    )
  }
}
