import AppKit
import SwiftUI

struct WindowTabConfigurationView: NSViewRepresentable {
  let title: String
  let onCloseTab: () -> Bool
  let onSelectPreviousTab: () -> Bool
  let onSelectNextTab: () -> Bool
  let onShowSearch: () -> Bool
  let onFindNext: () -> Bool
  let onFindPrevious: () -> Bool

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onCloseTab: onCloseTab,
      onSelectPreviousTab: onSelectPreviousTab,
      onSelectNextTab: onSelectNextTab,
      onShowSearch: onShowSearch,
      onFindNext: onFindNext,
      onFindPrevious: onFindPrevious
    )
  }

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.onCloseTab = onCloseTab
    context.coordinator.onSelectPreviousTab = onSelectPreviousTab
    context.coordinator.onSelectNextTab = onSelectNextTab
    context.coordinator.onShowSearch = onShowSearch
    context.coordinator.onFindNext = onFindNext
    context.coordinator.onFindPrevious = onFindPrevious

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
    var onSelectPreviousTab: () -> Bool
    var onSelectNextTab: () -> Bool
    var onShowSearch: () -> Bool
    var onFindNext: () -> Bool
    var onFindPrevious: () -> Bool

    private weak var window: NSWindow?
    private var monitor: Any?

    init(
      onCloseTab: @escaping () -> Bool,
      onSelectPreviousTab: @escaping () -> Bool,
      onSelectNextTab: @escaping () -> Bool,
      onShowSearch: @escaping () -> Bool,
      onFindNext: @escaping () -> Bool,
      onFindPrevious: @escaping () -> Bool
    ) {
      self.onCloseTab = onCloseTab
      self.onSelectPreviousTab = onSelectPreviousTab
      self.onSelectNextTab = onSelectNextTab
      self.onShowSearch = onShowSearch
      self.onFindNext = onFindNext
      self.onFindPrevious = onFindPrevious
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

        if flags == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "f" {
          return self.onShowSearch() ? nil : event
        }

        if flags == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "g" {
          return self.onFindNext() ? nil : event
        }

        if flags == [.command, .shift],
           event.charactersIgnoringModifiers?.lowercased() == "g" {
          return self.onFindPrevious() ? nil : event
        }

        if flags.contains(.command),
           flags.contains(.option) {
          switch event.keyCode {
          case 123:
            return self.onSelectPreviousTab() ? nil : event
          case 124:
            return self.onSelectNextTab() ? nil : event
          default:
            break
          }
        }

        return event
      }
    }
  }
}
