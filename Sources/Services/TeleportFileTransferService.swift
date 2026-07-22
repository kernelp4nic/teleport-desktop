import Foundation

enum TeleportFileTransferError: LocalizedError {
  case cancelled
  case commandFailed(String)
  case invalidPath

  var errorDescription: String? {
    switch self {
    case .cancelled:
      return "Transfer cancelled."
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

  func uploadOperation(
    localURLs: [URL],
    remotePath: String,
    login: String,
    hostname: String
  ) throws -> TeleportFileTransferOperation {
    let remotePath = try Self.normalizedRemotePath(remotePath)
    let destination = "\(login)@\(hostname):\(remotePath)"
    let jobs = localURLs.map { url in
      let fileSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 1

      return TeleportFileTransferOperation.Job(
        arguments: ["scp", url.path, destination],
        weight: Int64(max(fileSize, 1))
      )
    }

    return TeleportFileTransferOperation(jobs: jobs)
  }

  func downloadOperation(
    remotePath: String,
    localDirectoryURL: URL,
    login: String,
    hostname: String
  ) throws -> TeleportFileTransferOperation {
    let remotePath = try Self.normalizedRemotePath(remotePath)
    let arguments = ["\(login)@\(hostname):\(remotePath)", localDirectoryURL.path]

    return TeleportFileTransferOperation(
      jobs: [.init(arguments: ["scp"] + arguments, weight: 1)]
    )
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

final class TeleportFileTransferOperation: @unchecked Sendable {
  struct Job: Sendable {
    let arguments: [String]
    let weight: Int64
  }

  private let jobs: [Job]
  private let lock = NSLock()
  private var cancelled = false
  private var process: Process?

  init(jobs: [Job]) {
    self.jobs = jobs
  }

  func run(
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws {
    try await Task.detached { [self] in
      let totalWeight = max(jobs.reduce(Int64(0)) { $0 + $1.weight }, 1)
      var completedWeight: Int64 = 0

      for job in jobs {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let completedFraction = Double(completedWeight) / Double(totalWeight)
        let jobFraction = Double(job.weight) / Double(totalWeight)
        let parser = TeleportFileTransferProgressParser { progress in
          onProgress(completedFraction + (progress * jobFraction))
        }

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["tsh"] + job.arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = ProcessInfo.processInfo.environment.merging(
          ["PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"]
        ) { _, new in
          new
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
          parser.consume(handle.availableData)
        }

        let shouldStart = lock.withLock {
          guard !cancelled else {
            return false
          }

          self.process = process
          return true
        }

        guard shouldStart else {
          throw TeleportFileTransferError.cancelled
        }

        defer {
          stdoutPipe.fileHandleForReading.readabilityHandler = nil
          lock.withLock {
            self.process = nil
          }
        }

        try process.run()
        process.waitUntilExit()
        parser.consume(stdoutPipe.fileHandleForReading.readDataToEndOfFile())

        if lock.withLock({ cancelled }) {
          throw TeleportFileTransferError.cancelled
        }

        guard process.terminationStatus == 0 else {
          let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
          let message = String(decoding: errorData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

          throw TeleportFileTransferError.commandFailed(
            message.isEmpty ? "Teleport could not transfer the file." : message
          )
        }

        completedWeight += job.weight
        onProgress(Double(completedWeight) / Double(totalWeight))
      }

      onProgress(1)
    }.value
  }

  func cancel() {
    let process = lock.withLock {
      cancelled = true
      return self.process
    }

    process?.interrupt()
  }
}

final class TeleportFileTransferProgressParser: @unchecked Sendable {
  private let onProgress: @Sendable (Double) -> Void
  private let lock = NSLock()
  private var bufferedOutput = ""
  private var lastProgress: Double?

  init(onProgress: @escaping @Sendable (Double) -> Void) {
    self.onProgress = onProgress
  }

  func consume(_ data: Data) {
    guard !data.isEmpty else {
      return
    }

    let progress = lock.withLock { () -> Double? in
      bufferedOutput.append(String(decoding: data, as: UTF8.self))

      if bufferedOutput.count > 8_192 {
        bufferedOutput.removeFirst(bufferedOutput.count - 8_192)
      }

      guard let progress = Self.lastProgress(in: bufferedOutput),
            progress != lastProgress else {
        return nil
      }

      lastProgress = progress
      return progress
    }

    if let progress {
      onProgress(progress)
    }
  }

  static func lastProgress(in output: String) -> Double? {
    let pattern = #"(?<!\d)(\d{1,3})%"#

    guard let expression = try? NSRegularExpression(pattern: pattern),
          let match = expression.matches(
            in: output,
            range: NSRange(output.startIndex..., in: output)
          ).last,
          let range = Range(match.range(at: 1), in: output),
          let percentage = Double(output[range]) else {
      return nil
    }

    return min(max(percentage / 100, 0), 1)
  }
}
