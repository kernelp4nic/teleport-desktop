import Foundation
import Testing
@testable import teleport_desktop

struct OnePasswordServiceTests {
  @Test func parsesUsernameAndPasswordByPurpose() throws {
    let json = """
    {
      "id": "abc",
      "fields": [
        {"id": "username", "type": "STRING", "purpose": "USERNAME", "label": "username", "value": "sebastian"},
        {"id": "password", "type": "CONCEALED", "purpose": "PASSWORD", "label": "password", "value": "s3cret"},
        {"id": "notesPlain", "type": "STRING", "purpose": "NOTES", "label": "notesPlain"},
        {"id": "totp", "type": "OTP", "label": "one-time password", "value": "otpauth://totp/x", "totp": "123456"}
      ]
    }
    """

    let credentials = try OnePasswordService.parseCredentials(from: json)

    #expect(credentials == OnePasswordCredentials(username: "sebastian", password: "s3cret"))
  }

  @Test func fallsBackToFieldLabels() throws {
    let json = """
    {"fields": [
      {"label": "Username", "value": "ops"},
      {"label": "Password", "value": "pw"}
    ]}
    """

    let credentials = try OnePasswordService.parseCredentials(from: json)

    #expect(credentials == OnePasswordCredentials(username: "ops", password: "pw"))
  }

  @Test func missingPasswordThrows() {
    let json = #"{"fields": [{"purpose": "USERNAME", "value": "ops"}]}"#

    #expect(throws: OnePasswordError.missingPassword) {
      try OnePasswordService.parseCredentials(from: json)
    }
  }

  @Test func loadsCredentialsFromVault() throws {
    let runner = StubCommandRunner(
      result: CommandResult(stdout: #"{"fields": [{"purpose": "PASSWORD", "value": "pw"}]}"#, stderr: "", exitStatus: 0)
    )

    let credentials = try OnePasswordService(runner: runner)
      .loadCredentials(item: "Teleport", vault: "Work", account: "ACCOUNT1")

    #expect(credentials == OnePasswordCredentials(username: nil, password: "pw"))
    #expect(runner.calls == [["op", "item", "get", "Teleport", "--vault=Work", "--account=ACCOUNT1", "--format=json"]])
  }

  @Test func loadsOneTimePasswordWithoutVault() throws {
    let runner = StubCommandRunner(result: CommandResult(stdout: "654321\n", stderr: "", exitStatus: 0))

    let code = try OnePasswordService(runner: runner)
      .loadOneTimePassword(item: "Teleport", vault: " ", account: nil)

    #expect(code == "654321")
    #expect(runner.calls == [["op", "item", "get", "Teleport", "--otp"]])
  }

  @Test func parsesAccounts() throws {
    let json = """
    [
      {"url": "my.1password.com", "email": "me@example.com", "user_uuid": "U1", "account_uuid": "A1"},
      {"url": "work.1password.com", "email": "me@work.com", "user_uuid": "U2", "account_uuid": "A2"}
    ]
    """

    let accounts = try OnePasswordService.parseAccounts(from: json)

    #expect(accounts.map(\.id) == ["A1", "A2"])
    #expect(accounts[1].displayName == "me@work.com (work.1password.com)")
  }

  @Test func reportsMissingCLI() {
    let runner = StubCommandRunner(result: CommandResult(stdout: "", stderr: "", exitStatus: 127))

    #expect(throws: OnePasswordError.cliNotFound) {
      try OnePasswordService(runner: runner).loadOneTimePassword(item: "Teleport", vault: nil, account: nil)
    }
  }

  @Test func surfacesCLIErrors() {
    let runner = StubCommandRunner(
      result: CommandResult(stdout: "", stderr: "[ERROR] \"Nope\" isn't an item.\n", exitStatus: 1)
    )

    #expect(throws: OnePasswordError.commandFailed("[ERROR] \"Nope\" isn't an item.")) {
      try OnePasswordService(runner: runner).loadCredentials(item: "Nope", vault: nil, account: nil)
    }
  }
}

struct LoginPromptDetectorTests {
  @Test func detectsPasswordThenOneTimePassword() {
    var detector = LoginPromptDetector()

    #expect(detector.consume("Enter password for Teleport ") == nil)
    #expect(detector.consume("user sebastian:\r\n") == .password)
    #expect(detector.consume("Enter an OTP code from a device: ") == .oneTimePassword)
  }

  @Test func detectsOTPTokenPrompt() {
    var detector = LoginPromptDetector()

    #expect(detector.consume("Enter password for Teleport user sebastianm:\r\n") == .password)
    #expect(detector.consume("Enter your OTP token:\r\n") == .oneTimePassword)
  }

  @Test func detectsCombinedSecurityKeyPrompt() {
    var detector = LoginPromptDetector()

    #expect(detector.consume("Tap any security key or enter a code from a OTP device") == .oneTimePassword)
  }

  @Test func answersEachPromptOnlyOnce() {
    var detector = LoginPromptDetector()

    #expect(detector.consume("Enter password for Teleport user ops:") == .password)
    #expect(detector.consume("ERROR: invalid credentials\nEnter password for Teleport user ops:") == nil)
  }
}

private final class StubCommandRunner: CommandRunning, @unchecked Sendable {
  private let lock = NSLock()
  private let result: CommandResult
  private var recordedCalls: [[String]] = []

  init(result: CommandResult) {
    self.result = result
  }

  var calls: [[String]] {
    lock.withLock { recordedCalls }
  }

  func run(command: String, arguments: [String]) throws -> CommandResult {
    lock.withLock { recordedCalls.append([command] + arguments) }
    return result
  }
}
