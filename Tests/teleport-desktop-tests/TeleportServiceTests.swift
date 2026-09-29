import Foundation
import Testing
@testable import teleport_desktop

struct TeleportServiceTests {
  @Test func parseNodesMergesStaticAndDynamicLabels() throws {
    let json = """
    [
      {
        "metadata": {
          "name": "uuid-1",
          "labels": {
            "customer": "acme",
            "roles": "web"
          }
        },
        "spec": {
          "hostname": "acme.web01",
          "addr": "",
          "use_tunnel": true,
          "cmd_labels": {
            "user": {
              "result": "ubuntu"
            }
          }
        }
      }
    ]
    """

    let nodes = try TeleportService.parseNodes(from: json)

    #expect(nodes.count == 1)
    #expect(nodes[0].hostname == "acme.web01")
    #expect(nodes[0].address == "Tunnel")
    #expect(nodes[0].labelMap["customer"] == "acme")
    #expect(nodes[0].labelMap["user"] == "ubuntu")
    #expect(nodes[0].labelMap["hostname"] == "acme.web01")
  }

  @Test func parseSessionMarksExpiredProfilesAndNormalizesProxy() throws {
    let json = """
    {
      "active": {
        "profile_url": "https://teleport.example.com:443",
        "cluster": "teleport.example.com",
        "username": "sebastianm",
        "logins": ["ubuntu", "-teleport-internal-join"],
        "valid_until": "2026-04-22T03:32:30-03:00"
      }
    }
    """

    let session = try TeleportService.parseSession(
      from: json,
      now: .distantFuture
    )

    #expect(session.state == .expired)
    #expect(session.proxy == "teleport.example.com:443")
    #expect(session.logins == ["ubuntu"])
  }

  @Test func connectCommandUsesResolvedLogin() {
    let defaults = UserDefaults(suiteName: "TeleportServiceTests.connectCommand.\(UUID().uuidString)")!
    let settings = SettingsStore(defaults: defaults)
    settings.loginLabelKey = "user"
    settings.fallbackLogin = "ec2-user"

    let node = TeleportNode(
      id: "node-1",
      hostname: "acme.web01",
      address: "Tunnel",
      labels: [
        TeleportLabel(key: "user", value: "ubuntu")
      ],
      labelMap: [
        "user": "ubuntu"
      ]
    )

    let session = TeleportSession(
      state: .active,
      proxy: nil,
      cluster: "teleport.example.com",
      username: "sebastianm",
      logins: ["ubuntu", "ec2-user"],
      validUntil: nil
    )

    let command = TeleportService().connectCommand(
      for: node,
      settings: settings,
      session: session
    )

    #expect(command == "tsh ssh ubuntu@acme.web01")
  }

  @Test func loginCommandIncludesProxyAndUser() {
    let service = TeleportService()

    #expect(
      service.loginCommand(proxy: "https://teleport.example.com/", user: " sebastianm ")
        == "tsh login --proxy=teleport.example.com --user=sebastianm"
    )
    #expect(service.loginCommand(proxy: "teleport.example.com", user: "  ") == "tsh login --proxy=teleport.example.com")
    #expect(service.loginCommand(proxy: nil) == "tsh login")
  }
}
