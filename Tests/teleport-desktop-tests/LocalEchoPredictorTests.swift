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

  @Test func keepsPredictingAfterBackspaceAndRetype() {
    var predictor = LocalEchoPredictor()
    _ = predictor.processOutput(Array("$ ".utf8)[...])

    _ = predictor.userInput(Array("wrong".utf8)[...])
    _ = predictor.processOutput(Array("wrong".utf8)[...])
    _ = predictor.userInput([0x7f][...])
    _ = predictor.processOutput([0x08, 0x20, 0x08][...])
    let replacement = predictor.userInput(Array("g".utf8)[...])

    #expect(predictor.isReadyForInput)
    #expect(
      String(decoding: replacement.bytesToDisplay, as: UTF8.self)
        == "\u{001B}[4mg\u{001B}[24m"
    )
  }
}
