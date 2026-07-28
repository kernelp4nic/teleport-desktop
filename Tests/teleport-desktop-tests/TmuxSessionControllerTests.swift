import Testing
@testable import teleport_desktop

struct TmuxSessionControllerTests {
  @Test
  func tmuxArgumentsEscapeQuotesBackslashesAndNewlines() {
    #expect(
      TmuxSessionController.quoteTmuxArgument("API \"logs\"\\prod\nnext") ==
        "\"API \\\"logs\\\"\\\\prod next\""
    )
  }

  @Test
  func identifiesCommonShellCommands() {
    #expect(TmuxSessionController.isShellCommand("bash"))
    #expect(TmuxSessionController.isShellCommand("/bin/zsh"))
    #expect(!TmuxSessionController.isShellCommand("vim"))
  }
}
