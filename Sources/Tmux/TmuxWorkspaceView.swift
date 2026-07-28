import AppKit
import SwiftTerm
import SwiftUI

struct TmuxWorkspaceView: View {
  let controller: TmuxSessionController
  let focusToken: Int
  @State private var renameWindowIsPresented = false
  @State private var windowNameDraft = ""

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 8) {
        Picker(
          "Window",
          selection: Binding(
            get: { controller.selectedWindowID ?? "" },
            set: { controller.selectWindow($0) }
          )
        ) {
          ForEach(controller.windows) { window in
            Text(window.name).tag(window.id)
          }
        }
        .labelsHidden()
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: 240, alignment: .leading)

        if let activityMessage = controller.activityMessage {
          HStack(spacing: 5) {
            ProgressView()
              .controlSize(.mini)
            Text(activityMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }

        Spacer()

        Button {
          controller.newWindow()
        } label: {
          Label("New Window", systemImage: "plus")
        }
        .disabled(!controller.isConnected)

        Button {
          windowNameDraft = controller.windows.first {
            $0.id == controller.selectedWindowID
          }?.name ?? ""
          renameWindowIsPresented = true
        } label: {
          Label("Rename Window", systemImage: "pencil")
        }
        .disabled(!controller.isConnected || controller.selectedWindowID == nil)

        Button {
          controller.splitPane()
        } label: {
          Label("Split Horizontal", systemImage: "rectangle.split.2x1")
        }
        .disabled(!controller.isConnected || controller.selectedWindowID == nil)

        Button {
          controller.splitPaneVertically()
        } label: {
          Label("Split Vertical", systemImage: "rectangle.split.1x2")
        }
        .disabled(!controller.isConnected || controller.selectedWindowID == nil)

        Button {
          controller.closeActivePane()
        } label: {
          Label("Close Pane", systemImage: "xmark")
        }
        .disabled(!controller.isConnected || controller.selectedWindowID == nil)
      }
      .buttonStyle(TmuxToolbarButtonStyle())
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .animation(.easeInOut(duration: 0.18), value: controller.activityMessage)

      Divider()

      TmuxPaneGridView(
        controller: controller,
        focusToken: focusToken &+ controller.focusRequestToken
      )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .alert("Rename tmux Window", isPresented: $renameWindowIsPresented) {
      TextField("Window name", text: $windowNameDraft)

      Button("Cancel", role: .cancel) {}
      Button("Rename") {
        controller.renameSelectedWindow(to: windowNameDraft)
      }
      .disabled(windowNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    } message: {
      Text("The name is stored in the remote tmux session.")
    }
  }
}

private struct TmuxToolbarButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    TmuxToolbarButtonBody(configuration: configuration)
  }
}

private struct TmuxToolbarButtonBody: View {
  let configuration: ButtonStyle.Configuration
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    configuration.label
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(
            configuration.isPressed
              ? Color.accentColor.opacity(0.22)
              : isHovering && isEnabled ? Color.primary.opacity(0.1) : Color.clear
          )
      }
      .overlay {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .strokeBorder(
            isHovering && isEnabled ? Color.accentColor.opacity(0.5) : Color.clear,
            lineWidth: 1
          )
      }
      .scaleEffect(
        configuration.isPressed && isEnabled ? 0.96 : isHovering && isEnabled ? 1.02 : 1
      )
      .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.45)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
      .animation(.easeOut(duration: 0.16), value: isHovering)
      .onHover { isHovering = $0 }
  }
}

struct TmuxPaneGridView: NSViewRepresentable {
  let controller: TmuxSessionController
  let focusToken: Int

  func makeNSView(context: Context) -> TmuxPaneGridHostView {
    let view = TmuxPaneGridHostView()
    view.update(controller: controller, focusToken: focusToken)
    return view
  }

  func updateNSView(_ nsView: TmuxPaneGridHostView, context: Context) {
    nsView.update(controller: controller, focusToken: focusToken)
  }
}

@MainActor
final class TmuxPaneGridHostView: NSView {
  private enum ResizeAxis {
    case horizontal
    case vertical
  }

  private weak var controller: TmuxSessionController?
  private var terminalViews: [String: TerminalView] = [:]
  private var paneContainers: [String: NSView] = [:]
  private var resizeHandles: [TmuxPaneResizeHandleView] = []
  private var resizeHandleSignature = ""
  private var resizeHandleRebuildScheduled = false
  private var visiblePanes: [TmuxPaneState] = []
  private var windowState: TmuxWindowState?
  private var lastFocusToken: Int?
  private var lastFocusedPaneID: String?

  override func layout() {
    super.layout()
    layoutPanes()
  }

  func update(controller: TmuxSessionController, focusToken: Int) {
    self.controller = controller
    windowState = controller.windows.first { $0.id == controller.selectedWindowID }
    visiblePanes = controller.panes.filter { $0.windowID == controller.selectedWindowID }
    let visibleIDs = Set(visiblePanes.map(\.id))
    if visiblePanes.isEmpty, !resizeHandleSignature.isEmpty {
      resizeHandleSignature = ""
      scheduleResizeHandleRebuild()
    }

    for (id, terminalView) in terminalViews where !visibleIDs.contains(id) {
      controller.detach(terminalView, from: id)
      paneContainers[id]?.removeFromSuperview()
      terminalViews[id] = nil
      paneContainers[id] = nil
    }

    for pane in visiblePanes where terminalViews[pane.id] == nil {
      let container = NSView(frame: .zero)
      container.wantsLayer = true

      let terminalView = TerminalView(frame: .zero)
      terminalView.configureNativeColors()
      terminalView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
      terminalView.caretColor = .controlAccentColor
      let clickRecognizer = NSClickGestureRecognizer(
        target: self,
        action: #selector(paneClicked(_:))
      )
      clickRecognizer.delaysPrimaryMouseButtonEvents = false
      terminalView.addGestureRecognizer(clickRecognizer)
      container.addSubview(terminalView)
      addSubview(container)
      paneContainers[pane.id] = container
      terminalViews[pane.id] = terminalView
      // SwiftTerm wraps incoming text using its current column count. Give a
      // newly created pane its real frame before attach() drains the buffered
      // prompt; a zero-sized view otherwise starts at the 2-column minimum.
      layoutPanes()
      controller.attach(terminalView, to: pane.id)
    }

    for pane in visiblePanes {
      guard let container = paneContainers[pane.id] else { continue }
      container.layer?.borderColor = (
        pane.isActive ? NSColor.controlAccentColor : NSColor.separatorColor
      ).cgColor
      container.layer?.borderWidth = pane.isActive ? 1.5 : 0.5
      container.layer?.cornerRadius = 4
    }

    needsLayout = true
    let preferredPaneID = visiblePanes.first(where: \.isActive)?.id ?? visiblePanes.first?.id
    if lastFocusToken != focusToken || lastFocusedPaneID != preferredPaneID {
      lastFocusToken = focusToken
      lastFocusedPaneID = preferredPaneID
      DispatchQueue.main.async { [weak self] in
        guard let self,
              let preferredPaneID,
              let terminalView = self.terminalViews[preferredPaneID] else { return }
        self.window?.makeFirstResponder(terminalView)
      }
    }
  }

  private func layoutPanes() {
    guard windowState != nil, !visiblePanes.isEmpty else { return }

    publishClientSize()

    // During new-window tmux may briefly report a window size inherited from
    // another client while its pane geometry already reflects the new layout.
    // Deriving the canvas from the panes keeps the native views normalized to
    // the available area throughout that transition.
    let canvasWidth = visiblePanes.map { $0.left + $0.width }.max() ?? 1
    let canvasHeight = visiblePanes.map { $0.top + $0.height }.max() ?? 1
    guard canvasWidth > 0, canvasHeight > 0 else { return }

    let cellWidth = bounds.width / CGFloat(canvasWidth)
    let cellHeight = bounds.height / CGFloat(canvasHeight)

    for pane in visiblePanes {
      let frame = CGRect(
        x: CGFloat(pane.left) * cellWidth,
        y: bounds.height - CGFloat(pane.top + pane.height) * cellHeight,
        width: CGFloat(pane.width) * cellWidth,
        height: CGFloat(pane.height) * cellHeight
      ).insetBy(dx: 2, dy: 2)
      paneContainers[pane.id]?.frame = frame
      terminalViews[pane.id]?.frame = CGRect(origin: .zero, size: frame.size)
        .insetBy(dx: 9, dy: 7)
    }

    layoutResizeHandles(
      canvasWidth: canvasWidth,
      canvasHeight: canvasHeight,
      cellWidth: cellWidth,
      cellHeight: cellHeight
    )
  }

  private func layoutResizeHandles(
    canvasWidth: Int,
    canvasHeight: Int,
    cellWidth: CGFloat,
    cellHeight: CGFloat
  ) {
    let signature = visiblePanes
      .map { "\($0.id):\($0.left):\($0.top):\($0.width):\($0.height)" }
      .sorted()
      .joined(separator: "|")

    guard signature == resizeHandleSignature else {
      resizeHandleSignature = signature
      scheduleResizeHandleRebuild()
      return
    }

    var handleIndex = 0
    for pane in visiblePanes {
      if pane.left + pane.width < canvasWidth {
        guard handleIndex < resizeHandles.count else { return }
        resizeHandles[handleIndex].frame = CGRect(
          x: CGFloat(pane.left + pane.width) * cellWidth - 4,
          y: bounds.height - CGFloat(pane.top + pane.height) * cellHeight,
          width: 8,
          height: CGFloat(pane.height) * cellHeight
        )
        handleIndex += 1
      }

      if pane.top + pane.height < canvasHeight {
        guard handleIndex < resizeHandles.count else { return }
        resizeHandles[handleIndex].frame = CGRect(
          x: CGFloat(pane.left) * cellWidth,
          y: bounds.height - CGFloat(pane.top + pane.height) * cellHeight - 4,
          width: CGFloat(pane.width) * cellWidth,
          height: 8
        )
        handleIndex += 1
      }
    }
  }

  private func scheduleResizeHandleRebuild() {
    guard !resizeHandleRebuildScheduled else { return }
    resizeHandleRebuildScheduled = true
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      self.resizeHandleRebuildScheduled = false
      self.rebuildResizeHandles()
      self.needsLayout = true
    }
  }

  private func rebuildResizeHandles() {
    resizeHandles.forEach { $0.removeFromSuperview() }
    resizeHandles.removeAll(keepingCapacity: true)

    let canvasWidth = visiblePanes.map { $0.left + $0.width }.max() ?? 1
    let canvasHeight = visiblePanes.map { $0.top + $0.height }.max() ?? 1
    for pane in visiblePanes {
      if pane.left + pane.width < canvasWidth {
        let handle = makeResizeHandle(
          paneID: pane.id,
          axis: .horizontal
        )
        addSubview(handle)
        resizeHandles.append(handle)
      }

      if pane.top + pane.height < canvasHeight {
        let handle = makeResizeHandle(
          paneID: pane.id,
          axis: .vertical
        )
        addSubview(handle)
        resizeHandles.append(handle)
      }
    }
  }

  private func makeResizeHandle(
    paneID: String,
    axis: ResizeAxis
  ) -> TmuxPaneResizeHandleView {
    let handle = TmuxPaneResizeHandleView(axis: axis == .horizontal ? .horizontal : .vertical)
    handle.onDragEnded = { [weak self] translation in
      guard let self else { return }
      let canvasWidth = self.visiblePanes.map { $0.left + $0.width }.max() ?? 1
      let canvasHeight = self.visiblePanes.map { $0.top + $0.height }.max() ?? 1
      switch axis {
      case .horizontal:
        let cellSize = self.bounds.width / CGFloat(max(canvasWidth, 1))
        let cells = Int((translation.width / max(cellSize, 1)).rounded())
        self.controller?.resizePane(paneID, horizontalDelta: cells)
      case .vertical:
        let cellSize = self.bounds.height / CGFloat(max(canvasHeight, 1))
        let cells = Int((-translation.height / max(cellSize, 1)).rounded())
        self.controller?.resizePane(paneID, verticalDelta: cells)
      }
    }
    return handle
  }

  private func publishClientSize() {
    let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
    let cellWidth = max(font.maximumAdvancement.width, 1)
    let cellHeight = max(font.ascender - font.descender + font.leading, 1)
    let columns = Int(bounds.width / cellWidth)
    let rows = Int(bounds.height / cellHeight)
    controller?.updateClientSize(columns: columns, rows: rows)
  }

  @objc private func paneClicked(_ recognizer: NSClickGestureRecognizer) {
    guard let terminalView = recognizer.view as? TerminalView,
          let paneID = terminalViews.first(where: { $0.value === terminalView })?.key else {
      return
    }
    controller?.activatePane(paneID)
  }
}

@MainActor
private final class TmuxPaneResizeHandleView: NSView {
  enum Axis {
    case horizontal
    case vertical
  }

  var onDragEnded: ((CGSize) -> Void)?
  private let axis: Axis
  private var dragOrigin: CGPoint?
  private var trackingAreaReference: NSTrackingArea?

  init(axis: Axis) {
    self.axis = axis
    super.init(frame: .zero)
    wantsLayer = true
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let trackingAreaReference {
      removeTrackingArea(trackingAreaReference)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.activeInKeyWindow, .mouseEnteredAndExited],
      owner: self
    )
    addTrackingArea(area)
    trackingAreaReference = area
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    addCursorRect(
      bounds,
      cursor: axis == .horizontal ? .resizeLeftRight : .resizeUpDown
    )
  }

  override func mouseEntered(with event: NSEvent) {
    layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
  }

  override func mouseExited(with event: NSEvent) {
    guard dragOrigin == nil else { return }
    layer?.backgroundColor = NSColor.clear.cgColor
  }

  override func mouseDown(with event: NSEvent) {
    dragOrigin = event.locationInWindow
    layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.35).cgColor
  }

  override func mouseUp(with event: NSEvent) {
    guard let dragOrigin else { return }
    self.dragOrigin = nil
    let end = event.locationInWindow
    onDragEnded?(
      CGSize(width: end.x - dragOrigin.x, height: end.y - dragOrigin.y)
    )
    layer?.backgroundColor = NSColor.clear.cgColor
  }
}
