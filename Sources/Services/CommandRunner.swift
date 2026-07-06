import Foundation

struct CommandResult: Sendable {
  let stdout: String
  let stderr: String
  let exitStatus: Int32
}

protocol CommandRunning: Sendable {
  func run(command: String, arguments: [String]) throws -> CommandResult
}

struct ProcessRunner: CommandRunning, Sendable {
  func run(command: String, arguments: [String]) throws -> CommandResult {
    let process = Process()
    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = [command] + arguments
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    ) { _, new in
      new
    }

    try process.run()
    process.waitUntilExit()

    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

    return CommandResult(
      stdout: String(decoding: stdoutData, as: UTF8.self),
      stderr: String(decoding: stderrData, as: UTF8.self),
      exitStatus: process.terminationStatus
    )
  }
}
