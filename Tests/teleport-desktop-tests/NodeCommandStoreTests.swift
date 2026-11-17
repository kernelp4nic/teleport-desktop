import Foundation
import Testing
@testable import teleport_desktop

@MainActor
struct NodeCommandStoreTests {
  private func target(_ name: String) -> CommandTarget {
    CommandTarget(
      node: TeleportNode(id: name, hostname: name, address: "Tunnel", labels: [], labelMap: [:]),
      name: name,
      login: "ubuntu",
      icon: nil
    )
  }

  @Test func runsOnEveryTargetAndKeepsEachResult() async {
    let store = NodeCommandStore { target, command in
      NodeCommandResult(output: "\(target.name): \(command)", exitStatus: target.name == "b" ? 1 : 0)
    }
    store.command = " uptime \n"

    store.run(on: ["a", "b", "c"].map(target))
    while store.isRunning { await Task.yield() }

    #expect(store.rows.map(\.id) == ["a", "b", "c"])
    #expect(store.rows[0].state == .finished(.init(output: "a: uptime", exitStatus: 0)))
    #expect(store.rows[1].state == .finished(.init(output: "b: uptime", exitStatus: 1)))
  }

  @Test func ignoresEmptyCommandAndNoTargets() {
    let store = NodeCommandStore { _, _ in NodeCommandResult(output: "", exitStatus: 0) }

    store.run(on: [target("a")])
    #expect(store.rows.isEmpty)

    store.command = "ls"
    store.run(on: [])
    #expect(store.rows.isEmpty)
  }

  @Test func cancelMarksUnfinishedRowsCancelled() async {
    let store = NodeCommandStore { _, _ in
      try? await Task.sleep(for: .seconds(30))
      return NodeCommandResult(output: "late", exitStatus: 0)
    }
    store.command = "sleep 30"

    store.run(on: (0..<12).map { target("n\($0)") })
    await Task.yield()
    store.cancel()
    while store.isRunning { await Task.yield() }

    #expect(store.rows.allSatisfy { $0.state == .cancelled })
  }

  @Test func buildsTshSshArguments() {
    #expect(
      TeleportCommandService.arguments(command: "df -h\nfree", login: "ubuntu", hostname: "usa.web03")
        == ["ssh", "ubuntu@usa.web03", "df -h\nfree"]
    )
  }

  @Test func stripsAnsiColors() {
    #expect(TeleportCommandService.stripColors("\u{1B}[31mERROR: \u{1B}[0mboom") == "ERROR: boom")
  }
}
