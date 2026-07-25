import Foundation
import Testing
@testable import teleport_desktop

struct TeleportFileTransferServiceTests {
  @Test func uploadBuildsTshScpCommand() async throws {
    let runner = RecordingCommandRunner()
    let service = TeleportFileTransferService(runner: runner)

    try await service.upload(
      localURLs: [
        URL(fileURLWithPath: "/tmp/first file.txt"),
        URL(fileURLWithPath: "/tmp/second.txt")
      ],
      remotePath: "~/uploads/",
      login: "ubuntu",
      hostname: "usa.web03"
    )

    #expect(runner.recordedCommand == "tsh")
    #expect(
      runner.recordedArguments == [
        "scp",
        "/tmp/first file.txt",
        "/tmp/second.txt",
        "ubuntu@usa.web03:~/uploads/"
      ]
    )
  }

  @Test func downloadBuildsTshScpCommand() async throws {
    let runner = RecordingCommandRunner()
    let service = TeleportFileTransferService(runner: runner)

    try await service.download(
      remotePath: "~/report.csv",
      localDirectoryURL: URL(fileURLWithPath: "/tmp/downloads"),
      login: "ubuntu",
      hostname: "usa.web03"
    )

    #expect(runner.recordedCommand == "tsh")
    #expect(
      runner.recordedArguments == [
        "scp",
        "ubuntu@usa.web03:~/report.csv",
        "/tmp/downloads"
      ]
    )
  }

  @Test func rejectsEmptyRemotePath() async {
    let runner = RecordingCommandRunner()
    let service = TeleportFileTransferService(runner: runner)

    await #expect(throws: TeleportFileTransferError.self) {
      try await service.download(
        remotePath: " ",
        localDirectoryURL: URL(fileURLWithPath: "/tmp"),
        login: "ubuntu",
        hostname: "usa.web03"
      )
    }
  }

  @Test func parsesLatestTshProgressPercentage() {
    let output = "report.csv  12% |█         | (1.2/10 MB)\\rreport.csv  48% |████      |"

    #expect(TeleportFileTransferProgressParser.lastProgress(in: output) == 0.48)
  }

  @Test func ignoresOutputWithoutProgressPercentage() {
    #expect(TeleportFileTransferProgressParser.lastProgress(in: "Connecting...") == nil)
  }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
  private let lock = NSLock()
  private var command: String?
  private var arguments: [String]?

  var recordedCommand: String? {
    lock.withLock { command }
  }

  var recordedArguments: [String]? {
    lock.withLock { arguments }
  }

  func run(command: String, arguments: [String]) throws -> CommandResult {
    lock.withLock {
      self.command = command
      self.arguments = arguments
    }

    return CommandResult(stdout: "", stderr: "", exitStatus: 0)
  }
}
