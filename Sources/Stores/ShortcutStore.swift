import AppKit
import Observation

@MainActor
@Observable
final class ShortcutStore {
  private static let defaultsKey = "keyboardShortcuts.v1"
  // Menu commands the app owns; a custom shortcut must not shadow them.
  private static let reserved = [
    DesktopShortcut(key: ",", flags: .command),
    DesktopShortcut(key: "q", flags: .command),
    DesktopShortcut(key: "h", flags: .command),
    DesktopShortcut(key: "m", flags: .command),
    DesktopShortcut(key: "n", flags: .command)
  ]

  @ObservationIgnored private let defaults: UserDefaults
  /// Missing entries are unassigned, so an explicit clear survives relaunch.
  private(set) var bindings: [String: DesktopShortcut]

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults

    if let data = defaults.data(forKey: Self.defaultsKey),
       let saved = try? JSONDecoder().decode([String: DesktopShortcut].self, from: data) {
      bindings = saved
    } else {
      bindings = Self.defaultBindings
    }
  }

  func shortcut(for action: DesktopAction) -> DesktopShortcut? {
    bindings[action.rawValue]
  }

  func action(for event: NSEvent) -> DesktopAction? {
    guard let key = event.charactersIgnoringModifiers?.lowercased() else {
      return nil
    }

    let shortcut = DesktopShortcut(key: key, flags: event.modifierFlags)
    return DesktopAction.allCases.first { bindings[$0.rawValue] == shortcut }
  }

  /// Returns a message when the shortcut cannot be used; nil when it was saved.
  @discardableResult
  func assign(_ shortcut: DesktopShortcut?, to action: DesktopAction) -> String? {
    if let shortcut {
      if Self.reserved.contains(shortcut) {
        return "That shortcut is reserved by the app menu."
      }

      if let other = DesktopAction.allCases.first(where: { $0 != action && bindings[$0.rawValue] == shortcut }) {
        return "That shortcut already belongs to “\(other.title)”."
      }
    }

    bindings[action.rawValue] = shortcut
    save()
    return nil
  }

  func reset() {
    bindings = Self.defaultBindings
    save()
  }

  private static var defaultBindings: [String: DesktopShortcut] {
    Dictionary(uniqueKeysWithValues: DesktopAction.allCases.compactMap { action in
      action.defaultShortcut.map { (action.rawValue, $0) }
    })
  }

  private func save() {
    defaults.set(try? JSONEncoder().encode(bindings), forKey: Self.defaultsKey)
  }
}
