import AppKit
import SwiftUI

struct WindowTabConfigurationView: NSViewRepresentable {
  let title: String

  func makeNSView(context: Context) -> NSView {
    NSView(frame: .zero)
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    DispatchQueue.main.async {
      guard let window = nsView.window else {
        return
      }

      window.title = title
      window.titleVisibility = .hidden
      window.tabbingMode = .disallowed
    }
  }
}
