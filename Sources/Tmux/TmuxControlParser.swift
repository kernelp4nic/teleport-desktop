import Foundation

enum TmuxControlEvent: Equatable {
  case output(paneID: String, data: [UInt8])
  case paneSnapshot(paneID: String, data: [UInt8])
  case windowAdded(String)
  case windowClosed(String)
  case paneClosed(String)
  case activeWindowChanged(String)
  case windowRenamed(id: String, name: String)
  case sessionChanged(id: String, name: String)
  case inventoryRecord([String])
  case inventoryCompleted(kind: String)
  case commandError(String)
  case exited
}

struct TmuxControlParser {
  private var buffer: [UInt8] = []
  private var responseLines: [String]?
  private var pendingSnapshotPaneID: String?

  mutating func append(_ bytes: ArraySlice<UInt8>) -> [TmuxControlEvent] {
    buffer.append(contentsOf: bytes)
    var events: [TmuxControlEvent] = []

    while let newline = buffer.firstIndex(of: 0x0a) {
      var lineBytes = Array(buffer[..<newline])
      buffer.removeSubrange(...newline)
      if lineBytes.last == 0x0d {
        lineBytes.removeLast()
      }
      events.append(contentsOf: parseLine(lineBytes))
    }

    return events
  }

  private mutating func parseLine(_ bytes: [UInt8]) -> [TmuxControlEvent] {
    guard !bytes.isEmpty else { return [] }

    if bytes.starts(with: Array("%output ".utf8)) ||
        bytes.starts(with: Array("%extended-output ".utf8)) {
      return parseOutput(bytes).map { [$0] } ?? []
    }

    let line = String(decoding: bytes, as: UTF8.self)

    if line.hasPrefix("%begin ") {
      responseLines = []
      return []
    }
    if line.hasPrefix("%end ") {
      let lines = responseLines ?? []
      responseLines = nil
      if let paneID = snapshotMarkerPaneID(lines.first) {
        let contentLines = Array(lines.dropFirst())
        if contentLines.isEmpty {
          pendingSnapshotPaneID = paneID
          return []
        }
        return [makePaneSnapshot(paneID: paneID, lines: contentLines)]
      }
      if let paneID = pendingSnapshotPaneID {
        pendingSnapshotPaneID = nil
        return [makePaneSnapshot(paneID: paneID, lines: lines)]
      }
      if let snapshot = parsePaneSnapshot(lines) {
        return [snapshot]
      }
      let records = lines.compactMap(parseInventoryRecord)
      guard let kind = records.compactMap(inventoryKind).first else {
        return records
      }
      return records + [.inventoryCompleted(kind: kind)]
    }
    if line.hasPrefix("%error ") {
      let message = (responseLines ?? []).joined(separator: "\n")
      responseLines = nil
      pendingSnapshotPaneID = nil
      return [.commandError(message)]
    }
    if responseLines != nil, !line.hasPrefix("%") {
      responseLines?.append(line)
      return []
    }

    if line.hasPrefix("%window-add ") {
      return [.windowAdded(String(line.dropFirst("%window-add ".count)))]
    }
    if line.hasPrefix("%window-close ") ||
        line.hasPrefix("%unlinked-window-close ") {
      let windowID = line.split(separator: " ").dropFirst().first.map(String.init)
      return windowID.map { [.windowClosed($0)] } ?? []
    }
    if line.hasPrefix("%pane-exited ") ||
        line.hasPrefix("%pane-died ") {
      let paneID = line.split(separator: " ").dropFirst().first.map(String.init)
      return paneID.map { [.paneClosed($0)] } ?? []
    }
    if line.hasPrefix("%session-window-changed ") {
      let fields = line.split(separator: " ")
      guard fields.count >= 3 else { return [] }
      return [.activeWindowChanged(String(fields[2]))]
    }
    if line.hasPrefix("%window-renamed ") {
      let fields = line.dropFirst("%window-renamed ".count).split(separator: " ", maxSplits: 1)
      guard fields.count == 2 else { return [] }
      return [.windowRenamed(id: String(fields[0]), name: String(fields[1]))]
    }
    if line.hasPrefix("%session-changed ") {
      let fields = line.dropFirst("%session-changed ".count).split(separator: " ", maxSplits: 1)
      guard fields.count == 2 else { return [] }
      return [.sessionChanged(id: String(fields[0]), name: String(fields[1]))]
    }
    if line == "%sessions-changed" ||
        line.hasPrefix("%window-pane-changed ") ||
        line.hasPrefix("%layout-change ") {
      return [.inventoryRecord(["REFRESH"])]
    }
    if line.hasPrefix("%exit") {
      return [.exited]
    }
    return []
  }

  private func parseOutput(_ bytes: [UInt8]) -> TmuxControlEvent? {
    let extended = bytes.starts(with: Array("%extended-output ".utf8))
    let prefixCount = extended ? "%extended-output ".utf8.count : "%output ".utf8.count
    let remainder = bytes.dropFirst(prefixCount)
    guard let firstSpace = remainder.firstIndex(of: 0x20) else { return nil }
    let paneID = String(decoding: remainder[..<firstSpace], as: UTF8.self)
    var payload = remainder[remainder.index(after: firstSpace)...]

    if extended, let marker = findColonMarker(in: payload) {
      payload = payload[payload.index(marker, offsetBy: 2)...]
    }

    return .output(paneID: paneID, data: decodeEscapedBytes(payload))
  }

  private func findColonMarker(in bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8>.Index? {
    var index = bytes.startIndex
    while index < bytes.endIndex {
      if bytes[index] == 0x3a,
         bytes.index(after: index) < bytes.endIndex,
         bytes[bytes.index(after: index)] == 0x20 {
        return index
      }
      index = bytes.index(after: index)
    }
    return nil
  }

  private func decodeEscapedBytes(_ bytes: ArraySlice<UInt8>) -> [UInt8] {
    var result: [UInt8] = []
    var index = bytes.startIndex

    while index < bytes.endIndex {
      if bytes[index] == 0x5c {
        let one = bytes.index(after: index)
        if one < bytes.endIndex {
          let two = bytes.index(after: one)
          let three = two < bytes.endIndex ? bytes.index(after: two) : bytes.endIndex
          if two < bytes.endIndex, three < bytes.endIndex,
             let value = octal(bytes[one], bytes[two], bytes[three]) {
            result.append(value)
            index = bytes.index(after: three)
            continue
          }
        }
      }
      result.append(bytes[index])
      index = bytes.index(after: index)
    }
    return result
  }

  private func octal(_ a: UInt8, _ b: UInt8, _ c: UInt8) -> UInt8? {
    guard (0x30...0x37).contains(a),
          (0x30...0x37).contains(b),
          (0x30...0x37).contains(c) else { return nil }
    return (a - 0x30) * 64 + (b - 0x30) * 8 + (c - 0x30)
  }

  private func parseInventoryRecord(_ line: String) -> TmuxControlEvent? {
    guard line.hasPrefix("TD|") else { return nil }
    return .inventoryRecord(line.split(separator: "|", omittingEmptySubsequences: false).map(String.init))
  }

  private func parsePaneSnapshot(_ lines: [String]) -> TmuxControlEvent? {
    guard let paneID = snapshotMarkerPaneID(lines.first) else { return nil }
    return makePaneSnapshot(paneID: paneID, lines: Array(lines.dropFirst()))
  }

  private func snapshotMarkerPaneID(_ line: String?) -> String? {
    guard let line, line.hasPrefix("TD|C|") else { return nil }
    return String(line.dropFirst("TD|C|".count))
  }

  private func makePaneSnapshot(
    paneID: String,
    lines: [String]
  ) -> TmuxControlEvent {
    var contentLines = lines
    while contentLines.last?.isEmpty == true {
      contentLines.removeLast()
    }
    return .paneSnapshot(
      paneID: paneID,
      data: Array(contentLines.joined(separator: "\r\n").utf8)
    )
  }

  private func inventoryKind(_ event: TmuxControlEvent) -> String? {
    guard case .inventoryRecord(let fields) = event, fields.count >= 2 else {
      return nil
    }
    return fields[1]
  }
}
