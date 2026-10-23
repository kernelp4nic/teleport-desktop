import AppKit
import Foundation
import Testing
@testable import teleport_desktop

struct ShortcutStoreTests {
  @MainActor
  @Test func defaultsAreAssignedUntilChanged() {
    let store = ShortcutStore(defaults: makeDefaults())

    #expect(store.shortcut(for: .commandPalette)?.label == "⇧⌘P")
    #expect(store.shortcut(for: .refreshServers) == nil)
  }

  @MainActor
  @Test func assignRejectsShortcutOwnedByAnotherAction() {
    let store = ShortcutStore(defaults: makeDefaults())
    let closeTab = DesktopShortcut(key: "w", flags: .command)

    let message = store.assign(closeTab, to: .refreshServers)

    #expect(message == "That shortcut already belongs to “Close Tab”.")
    #expect(store.shortcut(for: .refreshServers) == nil)
  }

  @MainActor
  @Test func assignRejectsReservedAppMenuShortcut() {
    let store = ShortcutStore(defaults: makeDefaults())

    #expect(store.assign(DesktopShortcut(key: "q", flags: .command), to: .login) != nil)
    #expect(store.shortcut(for: .login) == nil)
  }

  @MainActor
  @Test func clearedShortcutStaysClearedAfterRelaunch() {
    let defaults = makeDefaults()
    ShortcutStore(defaults: defaults).assign(nil, to: .closeTab)

    let relaunched = ShortcutStore(defaults: defaults)

    #expect(relaunched.shortcut(for: .closeTab) == nil)
  }

  @MainActor
  @Test func resetRestoresDefaults() {
    let defaults = makeDefaults()
    let store = ShortcutStore(defaults: defaults)
    store.assign(DesktopShortcut(key: "k", flags: [.control, .option]), to: .refreshServers)
    store.assign(nil, to: .closeTab)

    store.reset()

    #expect(store.shortcut(for: .closeTab)?.label == "⌘W")
    #expect(store.shortcut(for: .refreshServers) == nil)
  }

  @MainActor
  @Test func keyEventResolvesToActionAndIgnoresUnassignedKeys() throws {
    let store = ShortcutStore(defaults: makeDefaults())
    let commandShiftP = try #require(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [.command, .shift], timestamp: 0,
      windowNumber: 0, context: nil, characters: "P", charactersIgnoringModifiers: "P",
      isARepeat: false, keyCode: 35
    ))
    let commandK = try #require(NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
      windowNumber: 0, context: nil, characters: "k", charactersIgnoringModifiers: "k",
      isARepeat: false, keyCode: 40
    ))

    #expect(store.action(for: commandShiftP) == .commandPalette)
    #expect(store.action(for: commandK) == nil)
  }

  @Test func labelUsesStandardModifierOrderAndArrowSymbols() {
    let left = String(UnicodeScalar(NSLeftArrowFunctionKey)!)

    #expect(DesktopShortcut(key: "g", flags: [.command, .shift]).label == "⇧⌘G")
    #expect(DesktopShortcut(key: left, flags: [.control, .shift]).label == "⌃⇧←")
  }

  @Test func shortcutNeedsCommandOptionOrControlUnlessItIsAFunctionKey() {
    #expect(!DesktopShortcut(key: "p", flags: .shift).isValid)
    #expect(DesktopShortcut(key: "p", flags: [.control]).isValid)
    #expect(DesktopShortcut(key: String(UnicodeScalar(NSF5FunctionKey)!), flags: []).isValid)
  }

  private func makeDefaults() -> UserDefaults {
    let suite = "ShortcutStoreTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }
}
