import Foundation

struct OnePasswordCredentials: Equatable, Sendable {
  let username: String?
  let password: String
}

struct OnePasswordAccount: Equatable, Identifiable, Sendable {
  let id: String
  let url: String
  let email: String

  var displayName: String {
    email.isEmpty ? url : "\(email) (\(url))"
  }
}

enum OnePasswordError: LocalizedError, Equatable {
  case cliNotFound
  case commandFailed(String)
  case missingPassword
  case invalidOneTimePassword

  var errorDescription: String? {
    switch self {
    case .cliNotFound:
      return "1Password CLI (op) was not found. Install it with `brew install 1password-cli`."
    case .commandFailed(let message):
      return message
    case .missingPassword:
      return "The 1Password item has no password field."
    case .invalidOneTimePassword:
      return "The 1Password item has no one-time password."
    }
  }
}

/// Reads Teleport credentials through the 1Password CLI. With the 1Password
/// app integration enabled, `op` prompts for Touch ID instead of a password.
struct OnePasswordService: Sendable {
  private let runner: CommandRunning

  init(runner: CommandRunning = ProcessRunner()) {
    self.runner = runner
  }

  /// Lists the accounts signed in to the CLI. Does not require unlocking.
  func listAccounts() throws -> [OnePasswordAccount] {
    try Self.parseAccounts(from: run(arguments: ["account", "list", "--format=json"]))
  }

  func loadCredentials(item: String, vault: String?, account: String?) throws -> OnePasswordCredentials {
    let output = try run(arguments: itemArguments(item: item, vault: vault, account: account) + ["--format=json"])
    return try Self.parseCredentials(from: output)
  }

  func loadOneTimePassword(item: String, vault: String?, account: String?) throws -> String {
    let output = try run(arguments: itemArguments(item: item, vault: vault, account: account) + ["--otp"])
    let code = output.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !code.isEmpty, code.allSatisfy(\.isNumber) else {
      throw OnePasswordError.invalidOneTimePassword
    }

    return code
  }

  static func parseCredentials(from json: String) throws -> OnePasswordCredentials {
    let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    let fields = item.fields ?? []

    func value(purpose: String, label: String) -> String? {
      let field = fields.first { $0.purpose == purpose }
        ?? fields.first { $0.label?.lowercased() == label }
      return field?.value.flatMap { $0.isEmpty ? nil : $0 }
    }

    guard let password = value(purpose: "PASSWORD", label: "password") else {
      throw OnePasswordError.missingPassword
    }

    return OnePasswordCredentials(
      username: value(purpose: "USERNAME", label: "username"),
      password: password
    )
  }

  static func parseAccounts(from json: String) throws -> [OnePasswordAccount] {
    try JSONDecoder().decode([Account].self, from: Data(json.utf8)).map { account in
      OnePasswordAccount(id: account.accountUUID, url: account.url ?? "", email: account.email ?? "")
    }
  }

  private func itemArguments(item: String, vault: String?, account: String?) -> [String] {
    var arguments = ["item", "get", item]

    if let vault = vault?.trimmingCharacters(in: .whitespacesAndNewlines), !vault.isEmpty {
      arguments.append("--vault=\(vault)")
    }

    if let account = account?.trimmingCharacters(in: .whitespacesAndNewlines), !account.isEmpty {
      arguments.append("--account=\(account)")
    }

    return arguments
  }

  private func run(arguments: [String]) throws -> String {
    let result = try runner.run(command: "op", arguments: arguments)

    // `/usr/bin/env` exits with 127 when the command is not on PATH.
    if result.exitStatus == 127 {
      throw OnePasswordError.cliNotFound
    }

    guard result.exitStatus == 0 else {
      let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      throw OnePasswordError.commandFailed(
        message.isEmpty ? "1Password CLI exited with status \(result.exitStatus)." : message
      )
    }

    return result.stdout
  }

  private struct Account: Decodable {
    let url: String?
    let email: String?
    let accountUUID: String

    enum CodingKeys: String, CodingKey {
      case url
      case email
      case accountUUID = "account_uuid"
    }
  }

  private struct Item: Decodable {
    let fields: [Field]?
  }

  private struct Field: Decodable {
    let purpose: String?
    let label: String?
    let value: String?
  }
}

/// Watches `tsh login` output and reports each credential prompt once, so a
/// rejected password falls back to manual entry instead of looping.
struct LoginPromptDetector {
  enum Prompt: Equatable {
    case password
    case oneTimePassword
  }

  // "Enter your OTP token:", "Enter an OTP code from a device:" and
  // "Tap any security key or enter a code from a OTP device".
  private static let oneTimePasswordPhrases = ["otp token", "otp code", "otp device"]

  private var buffer = ""
  private var answered: [Prompt] = []

  mutating func consume(_ text: String) -> Prompt? {
    buffer += text.lowercased()

    if buffer.count > 1_024 {
      buffer = String(buffer.suffix(1_024))
    }

    let prompt: Prompt?

    if buffer.contains("enter password for teleport user") {
      prompt = .password
    } else if Self.oneTimePasswordPhrases.contains(where: buffer.contains) {
      prompt = .oneTimePassword
    } else {
      prompt = nil
    }

    guard let prompt else {
      return nil
    }

    buffer = ""

    guard !answered.contains(prompt) else {
      return nil
    }

    answered.append(prompt)
    return prompt
  }
}
