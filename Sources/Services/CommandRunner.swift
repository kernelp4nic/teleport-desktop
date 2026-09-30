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

    // Drain both pipes before waiting: a child that fills the pipe buffer
    // (~64KB, e.g. a large `tsh ls` JSON) blocks until someone reads it.
    let stderrReader = PipeReader(stderrPipe.fileHandleForReading)
    let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
    let stderrData = stderrReader.wait()
    process.waitUntilExit()

    return CommandResult(
      stdout: String(decoding: stdoutData, as: UTF8.self),
      stderr: String(decoding: stderrData, as: UTF8.self),
      exitStatus: process.terminationStatus
    )
  }
}

private final class PipeReader: @unchecked Sendable {
  private let group = DispatchGroup()
  private var data = Data()

  init(_ handle: FileHandle) {
    group.enter()
    DispatchQueue.global(qos: .utility).async {
      self.data = handle.readDataToEndOfFile()
      self.group.leave()
    }
  }

  func wait() -> Data {
    group.wait()
    return data
  }
}
