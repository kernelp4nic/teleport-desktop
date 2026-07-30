import Foundation
import Observation

@Observable
final class SettingsStore {
  static let defaultTerminalScrollbackLines = 10_000

  private enum Keys {
    static let proxyAddress = "proxyAddress"
    static let groupingLabelKey = "groupingLabelKey"
    static let loginLabelKey = "loginLabelKey"
    static let fallbackLogin = "fallbackLogin"
    static let terminalApplicationID = "terminalApplicationID"
    static let terminalScrollbackLines = "terminalScrollbackLines"
  }

  @ObservationIgnored private let defaults: UserDefaults

  var proxyAddress: String {
    didSet {
      defaults.set(proxyAddress, forKey: Keys.proxyAddress)
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

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    proxyAddress = defaults.string(forKey: Keys.proxyAddress) ?? ""
    groupingLabelKey = defaults.string(forKey: Keys.groupingLabelKey) ?? "customer"
    loginLabelKey = defaults.string(forKey: Keys.loginLabelKey) ?? "user"
    fallbackLogin = defaults.string(forKey: Keys.fallbackLogin) ?? ""
    terminalApplicationID = defaults.string(forKey: Keys.terminalApplicationID)
      ?? TerminalApplication.systemDefault.rawValue
    terminalScrollbackLines = defaults.object(forKey: Keys.terminalScrollbackLines) == nil
      ? Self.defaultTerminalScrollbackLines
      : max(0, defaults.integer(forKey: Keys.terminalScrollbackLines))
  }

  var normalizedProxyAddress: String? {
    TeleportService.normalizeProxyAddress(proxyAddress)
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
