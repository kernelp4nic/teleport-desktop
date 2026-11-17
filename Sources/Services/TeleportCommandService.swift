import Foundation
import os

struct NodeCommandResult: Equatable, Sendable {
  let output: String
  let exitStatus: Int32
}

/// Runs one non-interactive `tsh ssh login@host <command>`; cancelling the calling task kills the process.
struct TeleportCommandService: Sendable {
  /// shortcut: output past this is cut and the process killed; upgrade to streaming to a file if people need more.
  static let maxOutputBytes = 256 * 1024

  static func arguments(command: String, login: String, hostname: String) -> [String] {
    ["ssh", "\(login)@\(hostname)", command]
  }

  /// tsh colors its error lines even when it isn't writing to a terminal.
  static func stripColors(_ text: String) -> String {
    text.replacing(/\u{1B}\[[0-9;]*m/, with: "")
  }

  func run(command: String, login: String, hostname: String) async -> NodeCommandResult {
    let process = Process()
    let pipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["tsh"] + Self.arguments(command: command, login: login, hostname: hostname)
    process.standardInput = FileHandle.nullDevice
    // One pipe for both streams: nothing to drain separately, and the order matches a terminal.
    process.standardOutput = pipe
    process.standardError = pipe
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
    ) { _, new in
      new
    }

    let cancelled = OSAllocatedUnfairLock(initialState: false)

    return await withTaskCancellationHandler {
      await Task.detached {
        do {
          try process.run()
        } catch {
          return NodeCommandResult(output: error.localizedDescription, exitStatus: -1)
        }

        // Covers a cancel that landed before the process started.
        if cancelled.withLock({ $0 }) {
          process.terminate()
        }

        var data = Data()
        let handle = pipe.fileHandleForReading

        while true {
          let chunk = handle.availableData

          if chunk.isEmpty {
            break
          }

          data.append(chunk)

          if data.count > Self.maxOutputBytes {
            data = data.prefix(Self.maxOutputBytes)
            data.append(Data("\n… output truncated".utf8))
            process.terminate()
            break
          }
        }

        process.waitUntilExit()

        return NodeCommandResult(
          output: Self.stripColors(String(decoding: data, as: UTF8.self)),
          exitStatus: process.terminationStatus
        )
      }.value
    } onCancel: {
      cancelled.withLock { $0 = true }

      if process.isRunning {
        process.terminate()
      }
    }
  }
}
