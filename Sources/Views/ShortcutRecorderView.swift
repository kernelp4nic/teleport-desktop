import AppKit
import SwiftUI

/// Captures the next key combination. Command shortcuts arrive through performKeyEquivalent,
/// which SwiftUI key handlers never see, so the capture lives in an NSButton.
struct ShortcutRecorderView: NSViewRepresentable {
  let label: String
  let isRecording: Bool
  let onStart: () -> Void
  /// Receives nil when recording is cancelled with Escape.
  let onFinish: (DesktopShortcut?) -> Void

  func makeNSView(context: Context) -> RecorderNSButton {
    let button = RecorderNSButton()
    button.bezelStyle = .rounded
    button.target = button
    button.action = #selector(RecorderNSButton.begin)
    return button
  }

  func updateNSView(_ button: RecorderNSButton, context: Context) {
    button.title = isRecording ? "Press a shortcut…" : label
    button.isRecording = isRecording
    button.onStart = onStart
    button.onFinish = onFinish

    if isRecording {
      button.window?.makeFirstResponder(button)
    }
  }
}

final class RecorderNSButton: NSButton {
  var isRecording = false
  var onStart: (() -> Void)?
  var onFinish: ((DesktopShortcut?) -> Void)?

  override var acceptsFirstResponder: Bool { true }

  @objc func begin() {
    window?.makeFirstResponder(self)
    onStart?()
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    guard isRecording else {
      return super.performKeyEquivalent(with: event)
    }

    keyDown(with: event)
    return true
  }

  override func keyDown(with event: NSEvent) {
    guard isRecording else {
      super.keyDown(with: event)
      return
    }

    if event.keyCode == 53 {
      onFinish?(nil)
      return
    }

    guard let key = event.charactersIgnoringModifiers?.lowercased(), key.count == 1 else {
      NSSound.beep()
      return
    }

    let shortcut = DesktopShortcut(key: key, flags: event.modifierFlags)
    guard shortcut.isValid else {
      NSSound.beep()
      return
    }

    onFinish?(shortcut)
  }
}
