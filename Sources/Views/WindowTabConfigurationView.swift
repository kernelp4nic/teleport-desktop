import AppKit
import SwiftUI

struct WindowTabConfigurationView: NSViewRepresentable {
  let title: String
  let actionForEvent: (NSEvent) -> DesktopAction?
  let onAction: (DesktopAction) -> Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(actionForEvent: actionForEvent, onAction: onAction)
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.actionForEvent = actionForEvent
    context.coordinator.onAction = onAction

    DispatchQueue.main.async {
      guard let window = nsView.window else {
        return
      }

      context.coordinator.attach(to: window)
      window.title = title
      window.titleVisibility = .hidden
      window.tabbingMode = .disallowed
    }
  }
}

extension WindowTabConfigurationView {
  final class Coordinator {
    var actionForEvent: (NSEvent) -> DesktopAction?
    var onAction: (DesktopAction) -> Bool

    private weak var window: NSWindow?
    private var monitor: Any?

    init(
      actionForEvent: @escaping (NSEvent) -> DesktopAction?,
      onAction: @escaping (DesktopAction) -> Bool
    ) {
      self.actionForEvent = actionForEvent
      self.onAction = onAction
    }

    deinit {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }
    }

    func attach(to window: NSWindow) {
      guard self.window !== window else {
        return
      }

      self.window = window
      installMonitorIfNeeded()
    }

    private func installMonitorIfNeeded() {
      guard monitor == nil else {
        return
      }

      monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        guard let self,
              let window = self.window,
              event.window === window else {
          return event
        }

        guard let action = self.actionForEvent(event) else {
          return event
        }

        return self.onAction(action) ? nil : event
      }
    }
  }
}
