import Testing
@testable import MenuShell

struct TerminalSessionStoreTests {
  @MainActor
  @Test func initializesFromWindowState() {
    let windowState = DesktopWindowState.command(
      "tsh ssh ubuntu@example",
      title: "ubuntu@example",
      summary: "Running tsh ssh as ubuntu",
      selectedNodeID: "node-1",
      connectedNodeID: "node-1"
    )

    let store = TerminalSessionStore(windowState: windowState)

    #expect(store.currentTitle == "ubuntu@example")
    #expect(store.statusMessage == "Running tsh ssh as ubuntu")
    #expect(store.connectedNodeID == "node-1")
  }

  @MainActor
  @Test func processTerminatedClearsConnectedNodeAndSetsStatus() {
    let windowState = DesktopWindowState.command(
      "tsh ssh ubuntu@example",
      title: "ubuntu@example",
      summary: "Running tsh ssh as ubuntu",
      selectedNodeID: "node-1",
      connectedNodeID: "node-1"
    )

    let store = TerminalSessionStore(windowState: windowState)
    store.processTerminated(exitCode: 1)

    #expect(store.connectedNodeID == nil)
    #expect(store.statusMessage == "Terminal session ended with status 1")
  }

  @MainActor
  @Test func runReplacesRequestAndClearsExitStatus() {
    let initialState = DesktopWindowState.shell()
    let store = TerminalSessionStore(windowState: initialState)
    store.processTerminated(exitCode: 1)

    let request = EmbeddedTerminalRequest.command(
      "tsh login",
      title: "Local Shell",
      summary: "Running tsh login in local shell"
    )

    store.run(request: request, connectedNodeID: nil)

    #expect(store.request == request)
    #expect(store.currentTitle == "Local Shell")
    #expect(store.statusMessage == "Running tsh login in local shell")
    #expect(store.connectedNodeID == nil)
    #expect(store.lastExitStatus == nil)
  }
}
