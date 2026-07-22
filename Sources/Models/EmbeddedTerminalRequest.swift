import Foundation

struct EmbeddedTerminalRequest: Codable, Equatable, Hashable, Identifiable {
  let id: UUID
  let executable: String
  let args: [String]
  let environment: [String]
  let execName: String?
  let currentDirectory: String?
  let title: String
  let summary: String

  init(
    id: UUID = UUID(),
    executable: String,
    args: [String],
    environment: [String],
    execName: String?,
    currentDirectory: String? = nil,
    title: String,
    summary: String
  ) {
    self.id = id
    self.executable = executable
    self.args = args
    self.environment = environment
    self.execName = execName
    self.currentDirectory = currentDirectory
    self.title = title
    self.summary = summary
  }

  static func shell(
    shellPath: String = ShellBootstrap.shellPath(),
    environment: [String] = ShellBootstrap.environment(),
    currentDirectory: String? = nil
  ) -> EmbeddedTerminalRequest {
    EmbeddedTerminalRequest(
      executable: shellPath,
      args: ["-l"],
      environment: environment,
      execName: ShellBootstrap.execName(for: shellPath),
      currentDirectory: currentDirectory,
      title: "Local Shell",
      summary: "Interactive shell ready"
    )
  }

  static func command(
    _ command: String,
    title: String,
    summary: String,
    shellPath: String = "/bin/zsh",
    environment: [String] = ShellBootstrap.environment(),
    currentDirectory: String? = nil
  ) -> EmbeddedTerminalRequest {
    EmbeddedTerminalRequest(
      executable: shellPath,
      args: [
        "-lc",
        ShellBootstrap.commandBody(
          for: command,
          openInteractiveShellAfterCommand: false
        )
      ],
      environment: environment,
      execName: ShellBootstrap.execName(for: shellPath),
      currentDirectory: currentDirectory,
      title: title,
      summary: summary
    )
  }
}
