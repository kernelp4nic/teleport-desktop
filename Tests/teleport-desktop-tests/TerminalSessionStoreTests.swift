import Testing
@testable import teleport_desktop

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
    #expect(store.connectionState == .connecting)
  }

  @MainActor
  @Test func markConnectedIfNeededTransitionsFromConnectingToConnected() {
    let windowState = DesktopWindowState.command(
      "tsh ssh ubuntu@example",
      title: "ubuntu@example",
      summary: "Running tsh ssh as ubuntu",
      selectedNodeID: "node-1",
      connectedNodeID: "node-1"
    )

    let store = TerminalSessionStore(windowState: windowState)
    store.markConnectedIfNeeded()

    #expect(store.connectionState == .connected)
  }

  @MainActor
  @Test func connectionEstablishedCallbackFiresOnceOnFirstTransitionToConnected() {
    let windowState = DesktopWindowState.command(
      "tsh ssh ubuntu@example",
      title: "ubuntu@example",
      summary: "Running tsh ssh as ubuntu",
      selectedNodeID: "node-1",
      connectedNodeID: "node-1"
    )

    let store = TerminalSessionStore(windowState: windowState)
    var callbackCount = 0
    store.onConnectionEstablished = {
      callbackCount += 1
    }

    store.markConnectedIfNeeded()
    store.markConnectedIfNeeded()

    #expect(store.connectionState == .connected)
    #expect(callbackCount == 1)
  }

  @MainActor
  @Test func disconnectedOrIdleSessionsDoNotFireConnectionEstablishedCallback() {
    let store = TerminalSessionStore(windowState: .shell())
    var callbackCount = 0
    store.onConnectionEstablished = {
      callbackCount += 1
    }

    store.markConnectedIfNeeded()
    store.processTerminated(exitCode: 1)
    store.onConnectionEstablished = {
      callbackCount += 1
    }

    #expect(store.connectionState == .disconnected)
    #expect(callbackCount == 0)
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
    #expect(store.connectionState == .disconnected)
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
    #expect(store.connectionState == .idle)
    #expect(store.lastExitStatus == nil)
  }

  @MainActor
  @Test func callbackAssignedAfterConnectionStillFiresOnce() {
    let windowState = DesktopWindowState.command(
      "tsh ssh ubuntu@example",
      title: "ubuntu@example",
      summary: "Running tsh ssh as ubuntu",
      selectedNodeID: "node-1",
      connectedNodeID: "node-1"
    )

    let store = TerminalSessionStore(windowState: windowState)
    store.markConnectedIfNeeded()

    var callbackCount = 0
    store.onConnectionEstablished = {
      callbackCount += 1
    }
    store.onConnectionEstablished = {
      callbackCount += 1
    }

    #expect(callbackCount == 1)
  }

  @Test func decodesWaitStatusLikeTheShell() {
    #expect(TerminalProcessController.exitStatus(fromWaitStatus: 0) == 0)
    #expect(TerminalProcessController.exitStatus(fromWaitStatus: 256) == 1)
    #expect(TerminalProcessController.exitStatus(fromWaitStatus: 9) == 137)
  }
}
