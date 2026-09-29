import Testing
@testable import teleport_desktop

struct LocalEchoPredictorTests {
  @Test func predictsPrintableInputAfterShellPrompt() {
    var predictor = LocalEchoPredictor()

    _ = predictor.processOutput(Array("host % ".utf8)[...])
    let update = predictor.userInput(Array("hello".utf8)[...])

    #expect(predictor.isReadyForInput)
    #expect(
      String(decoding: update.bytesToDisplay, as: UTF8.self)
        == "\u{001B}[4mhello\u{001B}[24m"
    )
  }

  @Test func confirmedRemoteEchoRemovesPredictionUnderline() {
    var predictor = LocalEchoPredictor()
    _ = predictor.processOutput(Array("$ ".utf8)[...])
    _ = predictor.userInput(Array("hello".utf8)[...])

    let first = predictor.processOutput(Array("hel".utf8)[...])
    let second = predictor.processOutput(Array("lo".utf8)[...])

    #expect(
      String(decoding: first.bytesToDisplay, as: UTF8.self)
        == "\u{001B}[5D\u{001B}[24mhel\u{001B}[4mlo\u{001B}[24m"
    )
    #expect(
      String(decoding: second.bytesToDisplay, as: UTF8.self)
        == "\u{001B}[2D\u{001B}[24mlo"
    )
  }

  @Test func rollsBackUnconfirmedPredictionWhenOutputDiffers() {
    var predictor = LocalEchoPredictor()
    _ = predictor.processOutput(Array("$ ".utf8)[...])
    _ = predictor.userInput(Array("hello".utf8)[...])

    let update = predictor.processOutput(Array("permission denied".utf8)[...])
    let rendered = String(decoding: update.bytesToDisplay, as: UTF8.self)

    #expect(rendered == "\u{001B}[5D\u{001B}[Kpermission denied")
    #expect(!predictor.isReadyForInput)
  }

  @Test func doesNotPredictPasswordOrProgramInput() {
    var predictor = LocalEchoPredictor()

    _ = predictor.processOutput(Array("Password: ".utf8)[...])
    let password = predictor.userInput(Array("secret".utf8)[...])
    _ = predictor.processOutput(Array("\r\n$ ".utf8)[...])
    _ = predictor.userInput(Array("cat".utf8)[...])
    _ = predictor.userInput([0x0d][...])
    let programInput = predictor.userInput(Array("hidden".utf8)[...])

    #expect(password.bytesToDisplay.isEmpty)
    #expect(programInput.bytesToDisplay.isEmpty)
  }

  @Test func recognizesColoredPrompt() {
    var predictor = LocalEchoPredictor()

    _ = predictor.processOutput(Array("\u{001B}[32mhost\u{001B}[0m $ ".utf8)[...])

    let update = predictor.userInput(Array("pwd".utf8)[...])
    #expect(
      String(decoding: update.bytesToDisplay, as: UTF8.self)
        == "\u{001B}[4mpwd\u{001B}[24m"
    )
  }

  @Test func suspendsPredictionAfterBackspaceAndRetype() {
    var predictor = LocalEchoPredictor()
    _ = predictor.processOutput(Array("$ ".utf8)[...])

    _ = predictor.userInput(Array("wrong".utf8)[...])
    _ = predictor.processOutput(Array("wrong".utf8)[...])
    _ = predictor.userInput([0x7f][...])
    _ = predictor.processOutput([0x08, 0x20, 0x08][...])
    let replacement = predictor.userInput(Array("g".utf8)[...])

    #expect(!predictor.isReadyForInput)
    #expect(replacement.bytesToDisplay.isEmpty)
  }

  @Test func historyHomeAndMiddleInsertionPreserveRemoteRedraw() {
    var predictor = LocalEchoPredictor()
    _ = predictor.processOutput(Array("$ ".utf8)[...])
    _ = predictor.userInput(Array("\u{001B}[A".utf8)[...])
    _ = predictor.processOutput(Array("zgrep \"previous command\" file.gz".utf8)[...])
    _ = predictor.userInput(Array("\u{001B}[H".utf8)[...])
    _ = predictor.processOutput(Array("\r$ ".utf8)[...])
    _ = predictor.userInput(Array("\u{001B}[C".utf8)[...])
    let insertion = predictor.userInput(Array("-".utf8)[...])
    let redraw = Array("-\"previous command\" file.gz\u{001B}[25D".utf8)

    #expect(insertion.bytesToDisplay.isEmpty)
    #expect(predictor.processOutput(redraw[...]).bytesToDisplay == redraw)
    #expect(!predictor.isReadyForInput)

    _ = predictor.userInput([0x0d][...])
    _ = predictor.processOutput(Array("\r\n$ ".utf8)[...])
    #expect(!predictor.userInput(Array("pwd".utf8)[...]).bytesToDisplay.isEmpty)
  }

  @Test func navigationRollsBackPendingEchoBeforeCursorMoves() {
    var predictor = LocalEchoPredictor()
    _ = predictor.processOutput(Array("$ ".utf8)[...])
    _ = predictor.userInput(Array("abc".utf8)[...])
    let navigation = predictor.userInput(Array("\u{001B}[D".utf8)[...])
    #expect(String(decoding: navigation.bytesToDisplay, as: UTF8.self) == "\u{001B}[3D\u{001B}[K")
    let remote = Array("abc\u{0008}".utf8)
    #expect(predictor.processOutput(remote[...]).bytesToDisplay == remote)
    #expect(predictor.userInput(Array("x".utf8)[...]).bytesToDisplay.isEmpty)
  }

  @Test func disablingWithPendingEchoRestoresRemotePassthrough() {
    var predictor = LocalEchoPredictor()
    _ = predictor.processOutput(Array("$ ".utf8)[...])
    _ = predictor.userInput(Array("abc".utf8)[...])
    #expect(!predictor.cancelPendingInput().bytesToDisplay.isEmpty)
    #expect(predictor.cancelPendingInput().bytesToDisplay.isEmpty)
    predictor.reset()
    let remote = Array("abc".utf8)
    #expect(predictor.processOutput(remote[...]).bytesToDisplay == remote)
    #expect(!predictor.isReadyForInput)
  }
}
