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
    let jobs = localURLs.map {
      TeleportFileTransferOperation.Job(arguments: ["scp", $0.path, destination])
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
      jobs: [.init(arguments: ["scp"] + arguments)]
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
  }

  enum Update: Sendable {
    case progress(Double)
    case failed(String)
  }

  /// Each job is its own `tsh scp` process (its own connection), so they run side by side.
  static let maxConcurrentJobs = 4

  private let jobs: [Job]
  private let lock = NSLock()
  private var cancelled = false
  private var processes: [Int: Process] = [:]

  init(jobs: [Job]) {
    self.jobs = jobs
  }

  /// Runs every job (a failed job does not stop the others) and throws once all have finished.
  func run(
    onUpdate: @escaping @Sendable (Int, Update) -> Void
  ) async throws {
    let failedCount = await withTaskGroup(of: Bool.self) { group in
      var indices = jobs.indices.makeIterator()
      var failedCount = 0

      for _ in 0..<Self.maxConcurrentJobs {
        guard let index = indices.next() else { break }
        group.addTask { await self.runJob(index, onUpdate: onUpdate) }
      }

      for await succeeded in group {
        if !succeeded {
          failedCount += 1
        }

        if let index = indices.next() {
          group.addTask { await self.runJob(index, onUpdate: onUpdate) }
        }
      }

      return failedCount
    }

    if lock.withLock({ cancelled }) {
      throw TeleportFileTransferError.cancelled
    }

    if failedCount > 0 {
      throw TeleportFileTransferError.commandFailed(
        jobs.count == 1
          ? "Teleport could not transfer the file."
          : "\(failedCount) of \(jobs.count) files could not be transferred."
      )
    }
  }

  func cancel() {
    let running = lock.withLock {
      cancelled = true
      return Array(processes.values)
    }

    running.forEach { $0.interrupt() }
  }

  private func runJob(
    _ index: Int,
    onUpdate: @escaping @Sendable (Int, Update) -> Void
  ) async -> Bool {
    await Task.detached { [self] in
      let process = Process()
      let stdoutPipe = Pipe()
      let stderrPipe = Pipe()
      let parser = TeleportFileTransferProgressParser { onUpdate(index, .progress($0)) }

      process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
      process.arguments = ["tsh"] + jobs[index].arguments
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

        processes[index] = process
        return true
      }

      guard shouldStart else {
        return true
      }

      defer {
        stdoutPipe.fileHandleForReading.readabilityHandler = nil
        lock.withLock {
          processes[index] = nil
        }
      }

      do {
        try process.run()
      } catch {
        onUpdate(index, .failed(error.localizedDescription))
        return false
      }

      process.waitUntilExit()
      parser.consume(stdoutPipe.fileHandleForReading.readDataToEndOfFile())

      if lock.withLock({ cancelled }) {
        return true
      }

      guard process.terminationStatus == 0 else {
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let message = String(decoding: errorData, as: UTF8.self)
          .trimmingCharacters(in: .whitespacesAndNewlines)

        onUpdate(index, .failed(message.isEmpty ? "Teleport could not transfer the file." : message))
        return false
      }

      onUpdate(index, .progress(1))
      return true
    }.value
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
