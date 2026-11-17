import Testing
@testable import teleport_desktop

struct NotesPanelViewTests {
  @Test func splitsProseAndFencedCode() {
    let source = "# Deploy\n```sh\nls -la\ndf -h\n```\nafter"

    #expect(NotesPanelView.segments(of: source) == [
      .text("# Deploy"),
      .code("ls -la\ndf -h"),
      .text("after"),
    ])
  }

  @Test func unclosedFenceRunsToEnd() {
    #expect(NotesPanelView.segments(of: "```\nuptime") == [.code("uptime")])
  }

  @Test func keepsEmptyCodeBlocks() {
    #expect(NotesPanelView.segments(of: "```sh\n\n```") == [.code("")])
  }

  @Test func replacesOnlyTheNthBlock() {
    let source = "a\n```sh\none\n```\nb\n```sh\ntwo\n```\nc"

    #expect(
      NotesPanelView.replacingCode(at: 1, with: "x\ny", in: source)
        == "a\n```sh\none\n```\nb\n```sh\nx\ny\n```\nc"
    )
  }

  @Test func fillsAnEmptyBlock() {
    #expect(NotesPanelView.replacingCode(at: 0, with: "ls", in: "```sh\n\n```\n") == "```sh\nls\n```\n")
  }
}
