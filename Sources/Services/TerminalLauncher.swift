import AppKit
import Foundation

enum TerminalLauncherError: LocalizedError {
  case unableToOpenTerminal
  case terminalApplicationNotFound(String)
  case terminalOpenFailed(String)

  var errorDescription: String? {
    switch self {
    case .unableToOpenTerminal:
      return "Could not open the default terminal application."
    case .terminalApplicationNotFound(let applicationName):
      return "\(applicationName) is not installed."
    case .terminalOpenFailed(let message):
      return message
    }
  }
}

struct TerminalLauncher {
  func open(
    command: String,
    label: String,
    terminalApplication: TerminalApplication = .systemDefault
  ) throws {
    let scriptURL = try Self.makeScript(command: command, label: label)

    if terminalApplication == .systemDefault {
      guard NSWorkspace.shared.open(scriptURL) else {
        throw TerminalLauncherError.unableToOpenTerminal
      }

      return
    }

    guard let applicationURL = terminalApplication.applicationURL else {
      throw TerminalLauncherError.terminalApplicationNotFound(terminalApplication.displayName)
    }

    let process = Process()
    let stderrPipe = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = Self.openArguments(for: scriptURL, applicationURL: applicationURL)
    process.standardError = stderrPipe

    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
      let errorOutput = String(
        decoding: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
        as: UTF8.self
      )
      .trimmingCharacters(in: .whitespacesAndNewlines)

      throw TerminalLauncherError.terminalOpenFailed(
        errorOutput.isEmpty
          ? "Could not open \(terminalApplication.displayName)."
          : errorOutput
      )
    }
  }

  static func openArguments(for scriptURL: URL, applicationURL: URL) -> [String] {
    ["-a", applicationURL.path, scriptURL.path]
  }

  static func makeScript(
    command: String,
    label: String,
    fileManager: FileManager = .default,
    temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
  ) throws -> URL {
    let scriptsDirectory = temporaryDirectory
      .appendingPathComponent("teleport-desktop", isDirectory: true)
      .appendingPathComponent("commands", isDirectory: true)

    try fileManager.createDirectory(
      at: scriptsDirectory,
      withIntermediateDirectories: true,
      attributes: nil
    )

    let safeLabel = label.replacingOccurrences(
      of: #"[^A-Za-z0-9_-]+"#,
      with: "-",
      options: .regularExpression
    )

    let scriptURL = scriptsDirectory
      .appendingPathComponent("\(safeLabel)-\(UUID().uuidString)")
      .appendingPathExtension("command")

    try scriptContents(for: command).write(
      to: scriptURL,
      atomically: true,
      encoding: .utf8
    )

    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: scriptURL.path
    )

    return scriptURL
  }

  static func scriptContents(for command: String) -> String {
    """
    #!/bin/zsh

    \(ShellBootstrap.commandBody(for: command))
    """
  }
}
