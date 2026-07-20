import Foundation

enum TeleportFileTransferError: LocalizedError {
  case commandFailed(String)
  case invalidPath

  var errorDescription: String? {
    switch self {
    case .commandFailed(let message):
      return message
    case .invalidPath:
      return "Enter a remote file path."
    }
  }
}

struct TeleportFileTransferService: Sendable {
  private let runner: CommandRunning

  init(runner: CommandRunning = ProcessRunner()) {
    self.runner = runner
  }

  func upload(
    localURLs: [URL],
    remotePath: String,
    login: String,
    hostname: String
  ) async throws {
    let remotePath = try Self.normalizedRemotePath(remotePath)
    let arguments = localURLs.map(\.path) + ["\(login)@\(hostname):\(remotePath)"]

    try await run(arguments: arguments)
  }

  func download(
    remotePath: String,
    localDirectoryURL: URL,
    login: String,
    hostname: String
  ) async throws {
    let remotePath = try Self.normalizedRemotePath(remotePath)
    let arguments = ["\(login)@\(hostname):\(remotePath)", localDirectoryURL.path]

    try await run(arguments: arguments)
  }

  private func run(arguments: [String]) async throws {
    let result = try await Task.detached {
      try runner.run(command: "tsh", arguments: ["scp"] + arguments)
    }.value

    guard result.exitStatus == 0 else {
      let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
      throw TeleportFileTransferError.commandFailed(
        message.isEmpty ? "Teleport could not transfer the file." : message
      )
    }
  }

  private static func normalizedRemotePath(_ path: String) throws -> String {
    let path = path.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !path.isEmpty else {
      throw TeleportFileTransferError.invalidPath
    }

    return path
  }
}
