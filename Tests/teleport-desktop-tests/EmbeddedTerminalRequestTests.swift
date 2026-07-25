import Foundation
import Testing
@testable import teleport_desktop

struct EmbeddedTerminalRequestTests {
  @Test func shellRequestStartsInteractiveLoginShell() {
    let request = EmbeddedTerminalRequest.shell(
      shellPath: "/bin/zsh",
      environment: ["PATH=/usr/bin"]
    )

    #expect(request.executable == "/bin/zsh")
    #expect(request.args == ["-l"])
    #expect(request.execName == "-zsh")
    #expect(request.title == "Local Shell")
  }

  @Test func commandRequestWrapsTeleportCommandInBootstrapShell() {
    let request = EmbeddedTerminalRequest.command(
      "tsh ssh ubuntu@example",
      title: "acme.web01",
      summary: "Running tsh ssh as ubuntu",
      environment: ["PATH=/usr/bin"]
    )

    #expect(request.executable == "/bin/zsh")
    #expect(request.args.count == 2)
    #expect(request.args[0] == "-lc")
    #expect(request.args[1].contains("tsh ssh ubuntu@example"))
    #expect(request.args[1].contains("command_status=$?"))
    #expect(!request.args[1].contains("\nstatus=$?\n"))
    #expect(request.args[1].contains("exit \"$command_status\""))
    #expect(!request.args[1].contains("exec \"${SHELL:-"))
  }
}
