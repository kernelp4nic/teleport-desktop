import Testing
@testable import teleport_desktop

struct TmuxControlParserTests {
  @Test
  func parsesFragmentedPaneOutputAndOctalEscapes() {
    var parser = TmuxControlParser()

    #expect(parser.append(ArraySlice("%out".utf8)).isEmpty)
    let events = parser.append(ArraySlice("put %3 hello\\040world\\015\\012\n".utf8))

    #expect(events == [
      .output(paneID: "%3", data: Array("hello world\r\n".utf8))
    ])
  }

  @Test
  func parsesInventoryInsideCommandResponse() {
    var parser = TmuxControlParser()
    let input = """
      %begin 123 9 1
      TD|W|@2|editor|120|40|1
      %end 123 9 1
      %begin 123 10 1
      TD|P|%4|@2|0|0|120|40|1
      %end 123 10 1

      """

    #expect(parser.append(ArraySlice(input.utf8)) == [
      .inventoryRecord(["TD", "W", "@2", "editor", "120", "40", "1"]),
      .inventoryCompleted(kind: "W"),
      .inventoryRecord(["TD", "P", "%4", "@2", "0", "0", "120", "40", "1"]),
      .inventoryCompleted(kind: "P")
    ])
  }

  @Test
  func parsesWindowAndSessionNotifications() {
    var parser = TmuxControlParser()
    let input = """
      %session-changed $1 work
      %window-add @3
      %window-renamed @3 logs
      %pane-exited %8
      %session-window-changed $1 @2
      %window-close @3
      %exit

      """

    #expect(parser.append(ArraySlice(input.utf8)) == [
      .sessionChanged(id: "$1", name: "work"),
      .windowAdded("@3"),
      .windowRenamed(id: "@3", name: "logs"),
      .paneClosed("%8"),
      .activeWindowChanged("@2"),
      .windowClosed("@3"),
      .exited
    ])
  }

  @Test
  func parsesCapturedPaneSnapshotAndTrimsBlankTail() {
    var parser = TmuxControlParser()
    let input = """
      %begin 123 11 1
      TD|C|%7
      %end 123 11 1
      %begin 123 12 1
      ubuntu@server:~$ 


      %end 123 12 1

      """

    #expect(parser.append(ArraySlice(input.utf8)) == [
      .paneSnapshot(paneID: "%7", data: Array("ubuntu@server:~$ ".utf8))
    ])
  }
}
