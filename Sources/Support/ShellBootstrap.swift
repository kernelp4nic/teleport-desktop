import Foundation

enum ShellBootstrap {
  private static let preferredPathPrefix = "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

  static func shellPath(processInfo: ProcessInfo = .processInfo) -> String {
    let shellPath = processInfo.environment["SHELL"]?
      .trimmingCharacters(in: .whitespacesAndNewlines)

    if let shellPath, !shellPath.isEmpty {
      return shellPath
    }

    return "/bin/zsh"
  }

  static func execName(for shellPath: String) -> String {
    "-\(URL(fileURLWithPath: shellPath).lastPathComponent)"
  }

  static func environment(processInfo: ProcessInfo = .processInfo) -> [String] {
    var values = [
      "COLORTERM": "truecolor",
      "LANG": processInfo.environment["LANG"] ?? "en_US.UTF-8",
      "PATH": pathValue(from: processInfo),
      "TERM": "xterm-256color"
    ]

    for key in ["HOME", "LOGNAME", "SHELL", "USER"] {
      if let value = processInfo.environment[key], !value.isEmpty {
        values[key] = value
      }
    }

    return values.keys.sorted().map { key in
      "\(key)=\(values[key]!)"
    }
  }

  static func commandBody(
    for command: String,
    shellPath: String? = nil,
    processInfo: ProcessInfo = .processInfo
  ) -> String {
    let shellPath = shellPath ?? self.shellPath(processInfo: processInfo)

    return """
    export PATH="\(pathValue(from: processInfo))"

    \(command)
    command_status=$?

    if [[ $command_status -ne 0 ]]; then
      echo
      echo "Command exited with status $command_status"
    fi

    exec "${SHELL:-\(shellPath)}" -l
    """
  }

  private static func pathValue(from processInfo: ProcessInfo) -> String {
    if let currentPath = processInfo.environment["PATH"], !currentPath.isEmpty {
      return "\(preferredPathPrefix):\(currentPath)"
    }

    return preferredPathPrefix
  }
}
