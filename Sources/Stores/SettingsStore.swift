import Foundation
import Observation

@Observable
final class SettingsStore {
  static let defaultTerminalScrollbackLines = 10_000
  static let defaultSoundFeedbackVolume = 0.65
  static let defaultTerminalFontSize = 13.0
  static let terminalFontSizeRange = 8.0...36.0

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
    static let showsRecentServers = "showsRecentServers"
    static let onePasswordEnabled = "onePasswordEnabled"
    static let onePasswordItem = "onePasswordItem"
    static let onePasswordVault = "onePasswordVault"
    static let onePasswordAccount = "onePasswordAccount"
    static let interfaceTheme = "interfaceTheme"
    static let tabSize = "tabSize"
    static let terminalFontFamily = "terminalFontFamily"
    static let terminalFontSize = "terminalFontSize"
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

  var interfaceTheme: InterfaceTheme {
    didSet {
      defaults.set(interfaceTheme.rawValue, forKey: Keys.interfaceTheme)
    }
  }

  var tabSize: TabSize {
    didSet {
      defaults.set(tabSize.rawValue, forKey: Keys.tabSize)
    }
  }

  /// Empty means the system monospaced font.
  var terminalFontFamily: String {
    didSet {
      defaults.set(terminalFontFamily, forKey: Keys.terminalFontFamily)
    }
  }

  var terminalFontSize: Double {
    didSet {
      let clamped = min(max(terminalFontSize, Self.terminalFontSizeRange.lowerBound), Self.terminalFontSizeRange.upperBound)
      if clamped != terminalFontSize {
        terminalFontSize = clamped
      }
      defaults.set(terminalFontSize, forKey: Keys.terminalFontSize)
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

  var showsRecentServers: Bool {
    didSet {
      defaults.set(showsRecentServers, forKey: Keys.showsRecentServers)
    }
  }

  var onePasswordEnabled: Bool {
    didSet {
      defaults.set(onePasswordEnabled, forKey: Keys.onePasswordEnabled)
    }
  }

  var onePasswordItem: String {
    didSet {
      defaults.set(onePasswordItem, forKey: Keys.onePasswordItem)
    }
  }

  var onePasswordVault: String {
    didSet {
      defaults.set(onePasswordVault, forKey: Keys.onePasswordVault)
    }
  }

  /// 1Password account UUID; empty uses the CLI's default account.
  var onePasswordAccount: String {
    didSet {
      defaults.set(onePasswordAccount, forKey: Keys.onePasswordAccount)
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
    interfaceTheme = InterfaceTheme(rawValue: defaults.string(forKey: Keys.interfaceTheme) ?? "") ?? .system
    tabSize = TabSize(rawValue: defaults.string(forKey: Keys.tabSize) ?? "") ?? .regular
    terminalFontFamily = defaults.string(forKey: Keys.terminalFontFamily) ?? ""
    terminalFontSize = defaults.object(forKey: Keys.terminalFontSize) == nil
      ? Self.defaultTerminalFontSize
      : min(max(defaults.double(forKey: Keys.terminalFontSize), Self.terminalFontSizeRange.lowerBound), Self.terminalFontSizeRange.upperBound)
    terminalScrollbackLines = defaults.object(forKey: Keys.terminalScrollbackLines) == nil
      ? Self.defaultTerminalScrollbackLines
      : max(0, defaults.integer(forKey: Keys.terminalScrollbackLines))
    localEchoEnabled = defaults.bool(forKey: Keys.localEchoEnabled)
    showsRecentServers = defaults.object(forKey: Keys.showsRecentServers) == nil
      ? true
      : defaults.bool(forKey: Keys.showsRecentServers)
    onePasswordEnabled = defaults.bool(forKey: Keys.onePasswordEnabled)
    onePasswordItem = defaults.string(forKey: Keys.onePasswordItem) ?? ""
    onePasswordVault = defaults.string(forKey: Keys.onePasswordVault) ?? ""
    onePasswordAccount = defaults.string(forKey: Keys.onePasswordAccount) ?? ""
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

  /// The 1Password item to fill `tsh login` from, when autofill is enabled.
  var onePasswordLoginItem: String? {
    onePasswordEnabled ? Self.normalizedValue(onePasswordItem) : nil
  }

  var normalizedOnePasswordVault: String? {
    Self.normalizedValue(onePasswordVault)
  }

  var normalizedOnePasswordAccount: String? {
    Self.normalizedValue(onePasswordAccount)
  }

  var selectedTerminalApplication: TerminalApplication {
    TerminalApplication(rawValue: terminalApplicationID) ?? .systemDefault
  }

  private static func normalizedValue(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return normalized.isEmpty ? nil : normalized
  }
}
