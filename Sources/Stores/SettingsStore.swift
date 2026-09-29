import Foundation
import Observation

@Observable
final class SettingsStore {
  static let defaultTerminalScrollbackLines = 10_000
  static let defaultSoundFeedbackVolume = 0.65

  private enum Keys {
    static let proxyAddress = "proxyAddress"
    static let teleportUser = "teleportUser"
    static let groupingLabelKey = "groupingLabelKey"
    static let loginLabelKey = "loginLabelKey"
    static let fallbackLogin = "fallbackLogin"
    static let terminalApplicationID = "terminalApplicationID"
    static let terminalScrollbackLines = "terminalScrollbackLines"
    static let localEchoEnabled = "localEchoEnabled"
    static let soundFeedbackEnabled = "soundFeedbackEnabled"
    static let soundFeedbackVolume = "soundFeedbackVolume"
  }

  @ObservationIgnored private let defaults: UserDefaults

  var proxyAddress: String {
    didSet {
      defaults.set(proxyAddress, forKey: Keys.proxyAddress)
    }
  }

  var teleportUser: String {
    didSet {
      defaults.set(teleportUser, forKey: Keys.teleportUser)
    }
  }

  var groupingLabelKey: String {
    didSet {
      defaults.set(groupingLabelKey, forKey: Keys.groupingLabelKey)
    }
  }

  var loginLabelKey: String {
    didSet {
      defaults.set(loginLabelKey, forKey: Keys.loginLabelKey)
    }
  }

  var fallbackLogin: String {
    didSet {
      defaults.set(fallbackLogin, forKey: Keys.fallbackLogin)
    }
  }

  var terminalApplicationID: String {
    didSet {
      defaults.set(terminalApplicationID, forKey: Keys.terminalApplicationID)
    }
  }

  var terminalScrollbackLines: Int {
    didSet {
      if terminalScrollbackLines < 0 {
        terminalScrollbackLines = 0
      }
      defaults.set(terminalScrollbackLines, forKey: Keys.terminalScrollbackLines)
    }
  }

  var localEchoEnabled: Bool {
    didSet {
      defaults.set(localEchoEnabled, forKey: Keys.localEchoEnabled)
    }
  }

  var soundFeedbackEnabled: Bool {
    didSet {
      defaults.set(soundFeedbackEnabled, forKey: Keys.soundFeedbackEnabled)
    }
  }

  var soundFeedbackVolume: Double {
    didSet {
      let clampedVolume = min(max(soundFeedbackVolume, 0), 1)
      if soundFeedbackVolume != clampedVolume {
        soundFeedbackVolume = clampedVolume
        return
      }
      defaults.set(soundFeedbackVolume, forKey: Keys.soundFeedbackVolume)
    }
  }

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    proxyAddress = defaults.string(forKey: Keys.proxyAddress) ?? ""
    teleportUser = defaults.string(forKey: Keys.teleportUser) ?? ""
    groupingLabelKey = defaults.string(forKey: Keys.groupingLabelKey) ?? "customer"
    loginLabelKey = defaults.string(forKey: Keys.loginLabelKey) ?? "user"
    fallbackLogin = defaults.string(forKey: Keys.fallbackLogin) ?? ""
    terminalApplicationID = defaults.string(forKey: Keys.terminalApplicationID)
      ?? TerminalApplication.systemDefault.rawValue
    terminalScrollbackLines = defaults.object(forKey: Keys.terminalScrollbackLines) == nil
      ? Self.defaultTerminalScrollbackLines
      : max(0, defaults.integer(forKey: Keys.terminalScrollbackLines))
    localEchoEnabled = defaults.bool(forKey: Keys.localEchoEnabled)
    soundFeedbackEnabled = defaults.object(forKey: Keys.soundFeedbackEnabled) == nil
      ? true
      : defaults.bool(forKey: Keys.soundFeedbackEnabled)
    soundFeedbackVolume = defaults.object(forKey: Keys.soundFeedbackVolume) == nil
      ? Self.defaultSoundFeedbackVolume
      : min(max(defaults.double(forKey: Keys.soundFeedbackVolume), 0), 1)
  }

  var normalizedProxyAddress: String? {
    TeleportService.normalizeProxyAddress(proxyAddress)
  }

  var normalizedTeleportUser: String? {
    Self.normalizedValue(teleportUser)
  }

  var normalizedGroupingLabelKey: String? {
    Self.normalizedValue(groupingLabelKey)
  }

  var normalizedLoginLabelKey: String? {
    Self.normalizedValue(loginLabelKey)
  }

  var normalizedFallbackLogin: String? {
    Self.normalizedValue(fallbackLogin)
  }

  var selectedTerminalApplication: TerminalApplication {
    TerminalApplication(rawValue: terminalApplicationID) ?? .systemDefault
  }

  private static func normalizedValue(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}
