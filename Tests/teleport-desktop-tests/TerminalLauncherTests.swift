import Foundation
import Testing
@testable import teleport_desktop

struct TerminalLauncherTests {
  @Test func makeScriptCreatesCommandFile() throws {
    let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
      .appendingPathComponent(UUID().uuidString, isDirectory: true)

    try FileManager.default.createDirectory(
      at: temporaryDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let scriptURL = try TerminalLauncher.makeScript(
      command: "tsh ssh ubuntu@example",
      label: "teleport-login",
      temporaryDirectory: temporaryDirectory
    )

    let contents = try String(contentsOf: scriptURL, encoding: .utf8)

    #expect(scriptURL.pathExtension == "command")
    #expect(contents.contains("tsh ssh ubuntu@example"))
    #expect(contents.contains("exec \"${SHELL:-"))
  }

  @Test func openArgumentsTargetTheChosenTerminalApplication() {
    let scriptURL = URL(fileURLWithPath: "/tmp/test.command")
    let applicationURL = URL(fileURLWithPath: "/Applications/iTerm.app")

    let arguments = TerminalLauncher.openArguments(
      for: scriptURL,
      applicationURL: applicationURL
    )

    #expect(arguments == ["-a", "/Applications/iTerm.app", "/tmp/test.command"])
  }
}
