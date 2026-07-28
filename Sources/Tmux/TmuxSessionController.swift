import AppKit
import Observation
import SwiftTerm

@MainActor
@Observable
final class TmuxWindowState: Identifiable {
  let id: String
  var name: String
  var width: Int
  var height: Int

  init(id: String, name: String, width: Int, height: Int) {
    self.id = id
    self.name = name
    self.width = width
    self.height = height
  }
}

@MainActor
@Observable
final class TmuxPaneState: Identifiable {
  let id: String
  var windowID: String
  var left: Int
  var top: Int
  var width: Int
  var height: Int
  var isActive: Bool
  var currentCommand: String
  var cursorY: Int
  @ObservationIgnored weak var terminalView: TerminalView?
  @ObservationIgnored var pendingOutput: [UInt8] = []

  init(
    id: String,
    windowID: String,
    left: Int,
    top: Int,
    width: Int,
    height: Int,
    isActive: Bool = false,
    currentCommand: String = "",
    cursorY: Int = 0
  ) {
    self.id = id
    self.windowID = windowID
    self.left = left
    self.top = top
    self.width = width
    self.height = height
    self.isActive = isActive
    self.currentCommand = currentCommand
    self.cursorY = cursorY
  }
}

final class TmuxGatewayTerminalView: LocalProcessTerminalView {
  var onData: ((ArraySlice<UInt8>) -> Void)?

  override func getWindowSize() -> winsize {
    // This view is a hidden control channel, so SwiftTerm cannot infer useful
    // dimensions from an on-screen layout. Start the remote PTY at a sane size
    // to prevent tmux from printing its first prompt at the 2-column minimum.
    // The visible workspace publishes its exact size with refresh-client -C
    // as soon as it is attached.
    winsize(
      ws_row: 40,
      ws_col: 120,
      ws_xpixel: 960,
      ws_ypixel: 640
    )
  }

  override func dataReceived(slice: ArraySlice<UInt8>) {
    onData?(slice)
  }
}

@MainActor
@Observable
final class TmuxSessionController: NSObject, @preconcurrency LocalProcessTerminalViewDelegate,
  @preconcurrency TerminalViewDelegate
{
  var windows: [TmuxWindowState] = []
  var panes: [TmuxPaneState] = []
  var selectedWindowID: String?
  var statusMessage = "Starting tmux control mode…"
  var isConnected = false
  var focusRequestToken = 0
  var activityMessage: String?
  var onConnectionEstablished: (@MainActor () -> Void)?
  var onProcessTerminated: (@MainActor (Int32?) -> Void)?
  var onSessionEnded: (@MainActor () -> Void)?

  @ObservationIgnored private let gateway = TmuxGatewayTerminalView(frame: .init(x: 0, y: 0, width: 800, height: 500))
  @ObservationIgnored private var parser = TmuxControlParser()
  @ObservationIgnored private var refreshScheduled = false
  @ObservationIgnored private var refreshedWindowIDs = Set<String>()
  @ObservationIgnored private var refreshedPaneIDs = Set<String>()
  @ObservationIgnored private var lastClientSize: (columns: Int, rows: Int)?
  @ObservationIgnored private var pendingOutputByPaneID: [String: [UInt8]] = [:]
  @ObservationIgnored private var snapshotRequestedPaneIDs = Set<String>()
  @ObservationIgnored private var snapshotAttemptsByPaneID: [String: Int] = [:]
  @ObservationIgnored private var initialSyncInProgress = false
  @ObservationIgnored private var activityToken = 0

  override init() {
    super.init()
    gateway.processDelegate = self
    gateway.onData = { [weak self] bytes in
      Task { @MainActor in
        self?.receive(bytes)
      }
    }
  }

  func start(_ request: EmbeddedTerminalRequest) {
    gateway.startProcess(
      executable: request.executable,
      args: request.args,
      environment: request.environment,
      execName: request.execName,
      currentDirectory: request.currentDirectory
    )
  }

  func selectWindow(_ id: String) {
    guard windows.contains(where: { $0.id == id }) else { return }
    selectedWindowID = id
    requestTerminalFocus()
    sendCommand("select-window -t \(id)")
  }

  func newWindow() {
    guard isConnected else { return }
    beginActivity("Creating window…")
    requestTerminalFocus()
    sendCommand("new-window")
    scheduleRefresh()
  }

  func renameSelectedWindow(to name: String) {
    guard isConnected else { return }
    guard let selectedWindowID else { return }
    let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedName.isEmpty else { return }

    beginActivity("Renaming window…")
    requestTerminalFocus()
    sendCommand(
      "rename-window -t \(selectedWindowID) \(Self.quoteTmuxArgument(trimmedName))"
    )
  }

  func splitPane() {
    guard isConnected else { return }
    guard let selectedWindowID else { return }
    beginActivity("Splitting horizontally…")
    requestTerminalFocus()
    sendCommand("split-window -t \(selectedWindowID)")
    scheduleRefresh()
  }

  func splitPaneVertically() {
    guard isConnected else { return }
    guard let selectedWindowID else { return }
    beginActivity("Splitting vertically…")
    requestTerminalFocus()
    sendCommand("split-window -h -t \(selectedWindowID)")
    scheduleRefresh()
  }

  func resizePane(_ paneID: String, horizontalDelta: Int = 0, verticalDelta: Int = 0) {
    guard isConnected, panes.contains(where: { $0.id == paneID }) else { return }

    if horizontalDelta > 0 {
      sendCommand("resize-pane -t \(paneID) -R \(horizontalDelta)")
    } else if horizontalDelta < 0 {
      sendCommand("resize-pane -t \(paneID) -L \(-horizontalDelta)")
    }

    if verticalDelta > 0 {
      sendCommand("resize-pane -t \(paneID) -D \(verticalDelta)")
    } else if verticalDelta < 0 {
      sendCommand("resize-pane -t \(paneID) -U \(-verticalDelta)")
    }

    guard horizontalDelta != 0 || verticalDelta != 0 else { return }
    beginActivity("Resizing pane…")
    requestTerminalFocus()
    scheduleRefresh()
  }

  func closeActivePane() {
    guard isConnected else { return }
    guard let selectedWindowID else { return }
    let pane = panes.first {
      $0.windowID == selectedWindowID && $0.isActive
    } ?? panes.first {
      $0.windowID == selectedWindowID
    }
    guard let pane else { return }
    beginActivity("Closing pane…")
    requestTerminalFocus()
    sendCommand("kill-pane -t \(pane.id)")
    scheduleRefresh()
  }

  func updateClientSize(columns: Int, rows: Int) {
    let size = (columns: max(columns, 20), rows: max(rows, 5))
    guard lastClientSize?.columns != size.columns ||
          lastClientSize?.rows != size.rows else { return }
    lastClientSize = size
    sendCommand("refresh-client -C \(size.columns)x\(size.rows)")
  }

  func attach(_ terminalView: TerminalView, to paneID: String) {
    guard let pane = panes.first(where: { $0.id == paneID }) else { return }
    let needsSnapshot = pane.pendingOutput.isEmpty
    pane.terminalView = terminalView
    terminalView.terminalDelegate = self
    if !pane.pendingOutput.isEmpty {
      terminalView.feed(byteArray: pane.pendingOutput[...])
    }
    if needsSnapshot {
      requestSnapshot(for: pane)
    }
  }

  func detach(_ terminalView: TerminalView, from paneID: String) {
    guard let pane = panes.first(where: { $0.id == paneID }),
          pane.terminalView === terminalView else { return }
    pane.terminalView = nil
  }

  func paneID(for terminalView: TerminalView) -> String? {
    panes.first(where: { $0.terminalView === terminalView })?.id
  }

  func activatePane(_ paneID: String) {
    guard isConnected,
          let pane = panes.first(where: { $0.id == paneID }),
          pane.windowID == selectedWindowID else { return }
    guard !pane.isActive else { return }

    for candidate in panes where candidate.windowID == pane.windowID {
      candidate.isActive = candidate.id == paneID
    }
    sendCommand("select-pane -t \(paneID)")
  }

  func send(source: TerminalView, data: ArraySlice<UInt8>) {
    guard let paneID = paneID(for: source), !data.isEmpty else { return }
    let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
    sendCommand("send-keys -H -t \(paneID) \(hex)")
  }

  func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
    // tmux owns the pane geometry. Echoing every SwiftTerm view resize back as
    // resize-pane creates a feedback loop while a split is settling.
  }

  func setTerminalTitle(source: TerminalView, title: String) {}
  func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
  func scrolled(source: TerminalView, position: Double) {}
  func clipboardCopy(source: TerminalView, content: Data) {
    guard let string = String(data: content, encoding: .utf8) else { return }
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(string, forType: .string)
  }
  func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}

  func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
  func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

  func processTerminated(source: TerminalView, exitCode: Int32?) {
    isConnected = false
    statusMessage = "tmux connection closed"
    onProcessTerminated?(exitCode)
  }

  private func receive(_ bytes: ArraySlice<UInt8>) {
    for event in parser.append(bytes) {
      handle(event)
    }
  }

  private func handle(_ event: TmuxControlEvent) {
    switch event {
    case .output(let paneID, let data):
      guard let pane = panes.first(where: { $0.id == paneID }) else {
        bufferPendingOutput(data, for: paneID)
        return
      }
      appendPendingOutput(data, to: pane)
      if let terminalView = pane.terminalView {
        terminalView.feed(byteArray: data[...])
      }
    case .paneSnapshot(let paneID, let data):
      snapshotRequestedPaneIDs.remove(paneID)
      guard !data.isEmpty else {
        retryEmptySnapshot(for: paneID)
        return
      }
      guard let pane = panes.first(where: { $0.id == paneID }) else {
        bufferPendingOutput(data, for: paneID)
        return
      }
      let snapshot = snapshotData(data, for: pane)
      pane.pendingOutput = snapshot
      snapshotAttemptsByPaneID[paneID] = nil
      if let terminalView = pane.terminalView {
        terminalView.terminal.resetToInitialState()
        terminalView.feed(byteArray: snapshot[...])
      }
    case .windowAdded, .inventoryRecord(["REFRESH"]):
      scheduleRefresh()
    case .windowClosed(let windowID):
      removeWindow(id: windowID)
      scheduleRefresh()
    case .paneClosed(let paneID):
      panes.removeAll { $0.id == paneID }
      pendingOutputByPaneID[paneID] = nil
      snapshotRequestedPaneIDs.remove(paneID)
      snapshotAttemptsByPaneID[paneID] = nil
      scheduleRefresh()
    case .activeWindowChanged(let windowID):
      selectedWindowID = windowID
      scheduleRefresh()
    case .windowRenamed(let id, let name):
      windows.first(where: { $0.id == id })?.name = name
    case .sessionChanged:
      markConnected()
      performInitialSync()
    case .inventoryRecord(let fields):
      applyInventory(fields)
    case .inventoryCompleted(let kind):
      completeInventory(kind: kind)
    case .commandError(let message):
      if !message.isEmpty {
        statusMessage = message
      }
    case .exited:
      isConnected = false
      statusMessage = "Detached from tmux"
      windows.removeAll()
      panes.removeAll()
      pendingOutputByPaneID.removeAll()
      snapshotRequestedPaneIDs.removeAll()
      snapshotAttemptsByPaneID.removeAll()
      onProcessTerminated?(0)
      onSessionEnded?()
    }
  }

  private func removeWindow(id: String) {
    let removedPaneIDs = Set(
      panes.lazy.filter { $0.windowID == id }.map(\.id)
    )
    windows.removeAll { $0.id == id }
    panes.removeAll { $0.windowID == id }
    pendingOutputByPaneID = pendingOutputByPaneID.filter {
      !removedPaneIDs.contains($0.key)
    }
    snapshotRequestedPaneIDs.subtract(removedPaneIDs)
    for paneID in removedPaneIDs {
      snapshotAttemptsByPaneID[paneID] = nil
    }
    if selectedWindowID == id {
      selectedWindowID = windows.first?.id
    }
  }

  private func applyInventory(_ fields: [String]) {
    guard fields.count >= 3 else { return }
    if fields[1] == "W", fields.count >= 7 {
      let id = fields[2]
      refreshedWindowIDs.insert(id)
      let window = windows.first(where: { $0.id == id }) ??
        TmuxWindowState(id: id, name: fields[3], width: 80, height: 24)
      window.name = fields[3]
      window.width = Int(fields[4]) ?? 80
      window.height = Int(fields[5]) ?? 24
      if !windows.contains(where: { $0.id == id }) {
        windows.append(window)
      }
      if fields[6] == "1" || selectedWindowID == nil {
        selectedWindowID = id
      }
    } else if fields[1] == "P", fields.count >= 8 {
      let id = fields[2]
      refreshedPaneIDs.insert(id)
      let bufferedOutput = pendingOutputByPaneID[id]
      let pane = panes.first(where: { $0.id == id }) ??
        TmuxPaneState(id: id, windowID: fields[3], left: 0, top: 0, width: 80, height: 24)
      pane.windowID = fields[3]
      pane.left = Int(fields[4]) ?? 0
      pane.top = Int(fields[5]) ?? 0
      pane.width = Int(fields[6]) ?? 80
      pane.height = Int(fields[7]) ?? 24
      pane.isActive = fields.count >= 9 && fields[8] == "1"
      pane.currentCommand = fields.count >= 10 ? fields[9] : ""
      pane.cursorY = fields.count >= 11 ? Int(fields[10]) ?? 0 : 0
      if !panes.contains(where: { $0.id == id }) {
        panes.append(pane)
      }
      if let pendingOutput = pendingOutputByPaneID.removeValue(forKey: id) {
        appendPendingOutput(pendingOutput, to: pane)
      } else if bufferedOutput == nil,
                pane.pendingOutput.isEmpty,
                pane.terminalView == nil {
        requestSnapshot(for: pane)
      }
    }
  }

  private func bufferPendingOutput(_ data: [UInt8], for paneID: String) {
    var output = pendingOutputByPaneID[paneID, default: []]
    output.append(contentsOf: data)
    trimPendingOutput(&output)
    pendingOutputByPaneID[paneID] = output
  }

  private func appendPendingOutput(_ data: [UInt8], to pane: TmuxPaneState) {
    pane.pendingOutput.append(contentsOf: data)
    trimPendingOutput(&pane.pendingOutput)
  }

  private func trimPendingOutput(_ output: inout [UInt8]) {
    let maximumBufferedBytes = 1_048_576
    if output.count > maximumBufferedBytes {
      output.removeFirst(output.count - maximumBufferedBytes)
    }
  }

  private func completeInventory(kind: String) {
    if kind == "W" {
      windows.removeAll { !refreshedWindowIDs.contains($0.id) }
      refreshedWindowIDs.removeAll(keepingCapacity: true)
      if !windows.contains(where: { $0.id == selectedWindowID }) {
        selectedWindowID = windows.first?.id
      }
    } else if kind == "P" {
      panes.removeAll { !refreshedPaneIDs.contains($0.id) }
      pendingOutputByPaneID = pendingOutputByPaneID.filter {
        refreshedPaneIDs.contains($0.key)
      }
      refreshedPaneIDs.removeAll(keepingCapacity: true)
      let livePaneIDs = Set(panes.map(\.id))
      snapshotRequestedPaneIDs = snapshotRequestedPaneIDs.filter {
        livePaneIDs.contains($0)
      }
      snapshotAttemptsByPaneID = snapshotAttemptsByPaneID.filter {
        livePaneIDs.contains($0.key)
      }
    }
  }

  private func requestSnapshot(for pane: TmuxPaneState) {
    let paneID = pane.id
    guard snapshotRequestedPaneIDs.insert(paneID).inserted else { return }
    snapshotAttemptsByPaneID[paneID, default: 0] += 1
    let captureRange: String
    if Self.isShellCommand(pane.currentCommand) {
      captureRange = " -S \(pane.cursorY) -E \(pane.cursorY)"
    } else {
      captureRange = ""
    }
    sendCommand(
      "display-message -p \(Self.quoteTmuxArgument("TD|C|\(paneID)")) ; " +
      "capture-pane -p -e -t \(paneID)\(captureRange)"
    )
  }

  private func retryEmptySnapshot(for paneID: String) {
    guard snapshotAttemptsByPaneID[paneID, default: 0] < 3 else {
      snapshotAttemptsByPaneID[paneID] = nil
      return
    }
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(120))
      guard let self,
            let pane = self.panes.first(where: { $0.id == paneID }),
            pane.pendingOutput.isEmpty else { return }
      self.requestSnapshot(for: pane)
    }
  }

  private func snapshotData(_ data: [UInt8], for pane: TmuxPaneState) -> [UInt8] {
    guard Self.isShellCommand(pane.currentCommand),
          let last = data.last,
          ![UInt8(ascii: " "), 0x09, 0x0a, 0x0d].contains(last) else {
      return data
    }
    return data + [UInt8(ascii: " ")]
  }

  private func requestTerminalFocus() {
    focusRequestToken &+= 1
  }

  private func beginActivity(_ message: String) {
    activityToken &+= 1
    let token = activityToken
    activityMessage = message
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(700))
      guard let self, self.activityToken == token else { return }
      self.activityMessage = nil
    }
  }

  private func markConnected() {
    guard !isConnected else { return }
    isConnected = true
    statusMessage = "Connected to remote tmux"
    onConnectionEstablished?()
  }

  private func refreshInventory() {
    refreshedWindowIDs.removeAll(keepingCapacity: true)
    refreshedPaneIDs.removeAll(keepingCapacity: true)
    sendCommand("list-windows -F 'TD|W|#{window_id}|#{window_name}|#{window_width}|#{window_height}|#{window_active}'")
    sendCommand("list-panes -a -F 'TD|P|#{pane_id}|#{window_id}|#{pane_left}|#{pane_top}|#{pane_width}|#{pane_height}|#{pane_active}|#{pane_current_command}|#{cursor_y}'")
  }

  private func scheduleRefresh() {
    guard !refreshScheduled, !initialSyncInProgress else { return }
    refreshScheduled = true
    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(100))
      guard let self else { return }
      self.refreshScheduled = false
      self.refreshInventory()
    }
  }

  private func performInitialSync() {
    guard !initialSyncInProgress else { return }
    initialSyncInProgress = true
    pendingOutputByPaneID.removeAll()
    lastClientSize = (columns: 120, rows: 40)
    sendCommand("refresh-client -C 120x40")

    Task { @MainActor [weak self] in
      try? await Task.sleep(for: .milliseconds(150))
      guard let self else { return }
      // Ignore output emitted using the stale control-client dimensions.
      // capture-pane will restore the current cursor line after the resize.
      self.pendingOutputByPaneID.removeAll()
      self.initialSyncInProgress = false
      self.refreshInventory()
    }
  }

  private func sendCommand(_ command: String) {
    let bytes = Array("\(command)\n".utf8)
    gateway.process.send(data: bytes[...])
  }

  nonisolated static func quoteTmuxArgument(_ value: String) -> String {
    let escaped = value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
    return "\"\(escaped)\""
  }

  nonisolated static func isShellCommand(_ command: String) -> Bool {
    let name = URL(fileURLWithPath: command).lastPathComponent.lowercased()
    return ["bash", "zsh", "sh", "fish", "dash", "ksh", "tcsh", "csh"].contains(name)
  }
}
