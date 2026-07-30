import Foundation
import Testing
@testable import teleport_desktop

struct SettingsStoreTests {
  @Test func terminalScrollbackUsesSaneDefault() {
    let defaults = makeDefaults()

    let settings = SettingsStore(defaults: defaults)

    #expect(settings.terminalScrollbackLines == 10_000)
  }

  @Test func terminalScrollbackIsPersisted() {
    let defaults = makeDefaults()
    let settings = SettingsStore(defaults: defaults)

    settings.terminalScrollbackLines = 25_000

    #expect(SettingsStore(defaults: defaults).terminalScrollbackLines == 25_000)
  }

  @Test func negativeStoredScrollbackIsClampedToZero() {
    let defaults = makeDefaults()
    defaults.set(-1, forKey: "terminalScrollbackLines")

    #expect(SettingsStore(defaults: defaults).terminalScrollbackLines == 0)
  }

  @Test func negativeScrollbackChangesAreClampedToZero() {
    let settings = SettingsStore(defaults: makeDefaults())

    settings.terminalScrollbackLines = -1

    #expect(settings.terminalScrollbackLines == 0)
  }

  @Test func soundFeedbackUsesSaneDefaults() {
    let settings = SettingsStore(defaults: makeDefaults())

    #expect(settings.soundFeedbackEnabled)
    #expect(settings.soundFeedbackVolume == 0.65)
  }

  @Test func soundFeedbackPreferencesArePersisted() {
    let defaults = makeDefaults()
    let settings = SettingsStore(defaults: defaults)

    settings.soundFeedbackEnabled = false
    settings.soundFeedbackVolume = 0.25

    let restoredSettings = SettingsStore(defaults: defaults)
    #expect(!restoredSettings.soundFeedbackEnabled)
    #expect(restoredSettings.soundFeedbackVolume == 0.25)
  }

  @Test func soundFeedbackVolumeIsClamped() {
    let settings = SettingsStore(defaults: makeDefaults())

    settings.soundFeedbackVolume = 2
    #expect(settings.soundFeedbackVolume == 1)

    settings.soundFeedbackVolume = -1
    #expect(settings.soundFeedbackVolume == 0)
  }

  private func makeDefaults() -> UserDefaults {
    let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
  }
}
