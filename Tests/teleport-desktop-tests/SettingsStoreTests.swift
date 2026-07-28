import Foundation
import Testing
@testable import teleport_desktop

struct SettingsStoreTests {
  @Test
  func tmuxDefaultIsDisabledAndPersists() {
    let suiteName = UUID().uuidString
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let initial = SettingsStore(defaults: defaults)
    #expect(!initial.useTmuxByDefault)

    initial.useTmuxByDefault = true

    let restored = SettingsStore(defaults: defaults)
    #expect(restored.useTmuxByDefault)
  }
}
