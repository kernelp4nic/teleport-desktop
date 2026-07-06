import AppKit
import SwiftUI

struct WindowTabConfigurationView: NSViewRepresentable {
  let title: String
  let onCloseTab: () -> Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(onCloseTab: onCloseTab)
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.onCloseTab = onCloseTab

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
    var onCloseTab: () -> Bool

    private weak var window: NSWindow?
    private var monitor: Any?

    init(onCloseTab: @escaping () -> Bool) {
      self.onCloseTab = onCloseTab
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

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "w" {
          return self.onCloseTab() ? nil : event
        }

        return event
      }
    }
  }
}
