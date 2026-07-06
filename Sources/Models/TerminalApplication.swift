import AppKit
import Foundation

enum TerminalApplication: String, CaseIterable, Identifiable {
  case systemDefault = "system-default"
  case terminal = "com.apple.Terminal"
  case iTerm = "com.googlecode.iterm2"
  case warp = "dev.warp.Warp-Stable"
  case ghostty = "com.mitchellh.ghostty"
  case kitty = "net.kovidgoyal.kitty"
  case wezTerm = "com.github.wez.wezterm"
  case alacritty = "org.alacritty"
  case hyper = "co.zeit.hyper"

  var id: String {
    rawValue
  }

  var displayName: String {
    switch self {
    case .systemDefault:
      return "System default"
    case .terminal:
      return "Terminal"
    case .iTerm:
      return "iTerm"
    case .warp:
      return "Warp"
    case .ghostty:
      return "Ghostty"
    case .kitty:
      return "kitty"
    case .wezTerm:
      return "WezTerm"
    case .alacritty:
      return "Alacritty"
    case .hyper:
      return "Hyper"
    }
  }

  var bundleIdentifier: String? {
    switch self {
    case .systemDefault:
      return nil
    default:
      return rawValue
    }
  }

  var applicationURL: URL? {
    guard let bundleIdentifier else {
      return nil
    }

    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
  }

  var isInstalled: Bool {
    applicationURL != nil || self == .systemDefault
  }

  static var selectableApplications: [TerminalApplication] {
    [.systemDefault] + allCases.dropFirst().filter(\.isInstalled)
  }
}
