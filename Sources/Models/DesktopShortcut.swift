import AppKit

/// A key plus its modifiers. Letters are stored lowercased, arrows and F-keys by their AppKit function-key scalar.
struct DesktopShortcut: Codable, Equatable {
  private static let modifierMask: NSEvent.ModifierFlags = [.command, .option, .control, .shift]

  let key: String
  let modifiers: UInt

  init(key: String, flags: NSEvent.ModifierFlags) {
    self.key = key
    modifiers = flags.intersection(Self.modifierMask).rawValue
  }

  var flags: NSEvent.ModifierFlags {
    NSEvent.ModifierFlags(rawValue: modifiers)
  }

  /// Function keys work alone; any other key needs ⌘, ⌥ or ⌃ so typing never triggers an action.
  var isValid: Bool {
    if let scalar = key.unicodeScalars.first, Self.isFunctionKey(scalar) {
      return true
    }

    return !flags.intersection([.command, .option, .control]).isEmpty
  }

  var label: String {
    let symbols: [(NSEvent.ModifierFlags, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
    let prefix = symbols.filter { flags.contains($0.0) }.map(\.1).joined()
    return prefix + Self.keyName(key)
  }

  private static func isFunctionKey(_ scalar: Unicode.Scalar) -> Bool {
    (0xF700...0xF8FF).contains(scalar.value)
  }

  private static func keyName(_ key: String) -> String {
    switch key {
    case String(UnicodeScalar(NSUpArrowFunctionKey)!): return "↑"
    case String(UnicodeScalar(NSDownArrowFunctionKey)!): return "↓"
    case String(UnicodeScalar(NSLeftArrowFunctionKey)!): return "←"
    case String(UnicodeScalar(NSRightArrowFunctionKey)!): return "→"
    case "\r": return "↩"
    case "\t": return "⇥"
    case " ": return "Space"
    default:
      if let scalar = key.unicodeScalars.first, isFunctionKey(scalar) {
        return "F\(scalar.value - UInt32(NSF1FunctionKey) + 1)"
      }

      return key.uppercased()
    }
  }
}

enum DesktopAction: String, CaseIterable, Identifiable {
  case commandPalette
  case refreshServers, login, collapseGroups
  case find, findNext, findPrevious
  case closeTab, previousTab, nextTab, moveTabLeft, moveTabRight
  case uploadFiles, downloadFile

  var id: String { rawValue }

  var title: String {
    switch self {
    case .commandPalette: return "Command Palette"
    case .refreshServers: return "Refresh Servers"
    case .login: return "Log in to Teleport"
    case .collapseGroups: return "Collapse or Expand Groups"
    case .find: return "Find in Terminal"
    case .findNext: return "Find Next"
    case .findPrevious: return "Find Previous"
    case .closeTab: return "Close Tab"
    case .previousTab: return "Previous Tab"
    case .nextTab: return "Next Tab"
    case .moveTabLeft: return "Move Tab Left"
    case .moveTabRight: return "Move Tab Right"
    case .uploadFiles: return "Upload Files"
    case .downloadFile: return "Download File"
    }
  }

  var systemImage: String {
    switch self {
    case .commandPalette: return "command"
    case .refreshServers: return "arrow.clockwise"
    case .login: return "person.badge.key"
    case .collapseGroups: return "rectangle.compress.vertical"
    case .find: return "magnifyingglass"
    case .findNext: return "chevron.down"
    case .findPrevious: return "chevron.up"
    case .closeTab: return "xmark"
    case .previousTab: return "arrow.left"
    case .nextTab: return "arrow.right"
    case .moveTabLeft: return "arrow.left.to.line"
    case .moveTabRight: return "arrow.right.to.line"
    case .uploadFiles: return "arrow.up.to.line"
    case .downloadFile: return "arrow.down.to.line"
    }
  }

  var defaultShortcut: DesktopShortcut? {
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)
    let right = String(UnicodeScalar(NSRightArrowFunctionKey)!)

    switch self {
    case .commandPalette: return DesktopShortcut(key: "p", flags: [.command, .shift])
    case .find: return DesktopShortcut(key: "f", flags: .command)
    case .findNext: return DesktopShortcut(key: "g", flags: .command)
    case .findPrevious: return DesktopShortcut(key: "g", flags: [.command, .shift])
    case .closeTab: return DesktopShortcut(key: "w", flags: .command)
    case .previousTab: return DesktopShortcut(key: left, flags: [.command, .option])
    case .nextTab: return DesktopShortcut(key: right, flags: [.command, .option])
    case .moveTabLeft: return DesktopShortcut(key: left, flags: [.control, .shift])
    case .moveTabRight: return DesktopShortcut(key: right, flags: [.control, .shift])
    case .refreshServers, .login, .collapseGroups, .uploadFiles, .downloadFile: return nil
    }
  }
}
