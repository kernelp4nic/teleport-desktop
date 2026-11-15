import AppKit
import SwiftUI

struct WindowTabConfigurationView: NSViewRepresentable {
  let title: String
  let actionForEvent: (NSEvent) -> DesktopAction?
  let onAction: (DesktopAction) -> Bool
  /// ⌘1…⌘9 land here with the 1-based number; return true when handled.
  let onTabNumber: (Int) -> Bool
  let onCommandHeld: (Bool) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(actionForEvent: actionForEvent, onAction: onAction, onTabNumber: onTabNumber, onCommandHeld: onCommandHeld)
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.actionForEvent = actionForEvent
    context.coordinator.onAction = onAction
    context.coordinator.onTabNumber = onTabNumber
    context.coordinator.onCommandHeld = onCommandHeld

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
    var onTabNumber: (Int) -> Bool
    var onCommandHeld: (Bool) -> Void

    private weak var window: NSWindow?
    private var monitor: Any?
    private var resignObserver: Any?

    init(
      actionForEvent: @escaping (NSEvent) -> DesktopAction?,
      onAction: @escaping (DesktopAction) -> Bool,
      onTabNumber: @escaping (Int) -> Bool,
      onCommandHeld: @escaping (Bool) -> Void
    ) {
      self.actionForEvent = actionForEvent
      self.onAction = onAction
      self.onTabNumber = onTabNumber
      self.onCommandHeld = onCommandHeld
    }

    deinit {
      if let monitor {
        NSEvent.removeMonitor(monitor)
      }

      if let resignObserver {
        NotificationCenter.default.removeObserver(resignObserver)
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

      // Releasing ⌘ after switching apps never reaches us, so drop the hint when the app deactivates.
      resignObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        self?.onCommandHeld(false)
      }

      monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
        guard let self,
              let window = self.window,
              event.window === window else {
          return event
        }

        if event.type == .flagsChanged {
          self.onCommandHeld(event.modifierFlags.contains(.command))
          return event
        }

        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           let number = event.charactersIgnoringModifiers.flatMap(Int.init),
           (1...9).contains(number),
           self.onTabNumber(number) {
          return nil
        }

        guard let action = self.actionForEvent(event) else {
          return event
        }

        return self.onAction(action) ? nil : event
      }
    }
  }
}
