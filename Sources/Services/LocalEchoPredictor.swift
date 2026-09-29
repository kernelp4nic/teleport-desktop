import Foundation

struct LocalEchoUpdate: Equatable {
  let bytesToDisplay: [UInt8]
}

struct LocalEchoPredictor {
  private static let maximumPendingBytes = 256

  private(set) var isReadyForInput = false
  private var pendingBytes: [UInt8] = []
  private var outputParser = OutputParser()
  private var suspendedUntilSubmit = false

  mutating func reset() {
    isReadyForInput = false
    suspendedUntilSubmit = false
    pendingBytes.removeAll(keepingCapacity: true)
    outputParser = OutputParser()
  }

  mutating func userInput(_ bytes: ArraySlice<UInt8>) -> LocalEchoUpdate {
    let input = Array(bytes)

    guard !input.isEmpty else { return LocalEchoUpdate(bytesToDisplay: []) }

    // Navigation, history, completion and deletion invalidate our append-only
    // model. Remove predictions before the remote shell moves its cursor.
    guard input.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e }),
          pendingBytes.count + input.count <= Self.maximumPendingBytes else {
      let update = cancelPendingInput()
      suspendedUntilSubmit = !input.contains(where: { $0 == 0x0a || $0 == 0x0d || $0 == 0x03 })
      outputParser = OutputParser()
      return update
    }

    guard isReadyForInput, !suspendedUntilSubmit else {
      return LocalEchoUpdate(bytesToDisplay: [])
    }

    pendingBytes.append(contentsOf: input)
    return LocalEchoUpdate(bytesToDisplay: underlined(input))
  }

  mutating func cancelPendingInput() -> LocalEchoUpdate {
    let rollback = pendingBytes.isEmpty ? [] : rollbackSequence(for: pendingBytes.count)
    pendingBytes.removeAll(keepingCapacity: true)
    isReadyForInput = false
    return LocalEchoUpdate(bytesToDisplay: rollback)
  }

  mutating func processOutput(_ bytes: ArraySlice<UInt8>) -> LocalEchoUpdate {
    var received = Array(bytes)
    var bytesToDisplay: [UInt8] = []

    if !pendingBytes.isEmpty {
      let pendingBeforeConfirmation = pendingBytes
      let matchingCount = zip(pendingBytes, received)
        .prefix(while: { $0 == $1 })
        .count

      if matchingCount > 0 {
        pendingBytes.removeFirst(matchingCount)
        received.removeFirst(matchingCount)
        bytesToDisplay.append(
          contentsOf: confirmationSequence(
            confirmed: Array(pendingBeforeConfirmation.prefix(matchingCount)),
            stillPending: pendingBytes,
            originalPendingCount: pendingBeforeConfirmation.count
          )
        )
      }

      if !received.isEmpty && !pendingBytes.isEmpty {
        bytesToDisplay.append(contentsOf: rollbackSequence(for: pendingBytes.count))
        pendingBytes.removeAll(keepingCapacity: true)
        isReadyForInput = false
      }
    }

    bytesToDisplay.append(contentsOf: received)
    // Include confirmed bytes so a stale prompt cannot re-arm prediction.
    outputParser.consume(Array(bytes))

    if !suspendedUntilSubmit, pendingBytes.isEmpty, outputParser.endsAtShellPrompt {
      isReadyForInput = true
    }

    return LocalEchoUpdate(bytesToDisplay: bytesToDisplay)
  }

  private func rollbackSequence(for characterCount: Int) -> [UInt8] {
    Array("\u{001B}[\(characterCount)D\u{001B}[K".utf8)
  }

  private func underlined(_ bytes: [UInt8]) -> [UInt8] {
    Array("\u{001B}[4m".utf8) + bytes + Array("\u{001B}[24m".utf8)
  }

  private func confirmationSequence(
    confirmed: [UInt8],
    stillPending: [UInt8],
    originalPendingCount: Int
  ) -> [UInt8] {
    var sequence = Array("\u{001B}[\(originalPendingCount)D\u{001B}[24m".utf8)
    sequence.append(contentsOf: confirmed)

    if !stillPending.isEmpty {
      sequence.append(contentsOf: underlined(stillPending))
    }

    return sequence
  }
}

private struct OutputParser {
  private enum EscapeState {
    case text
    case escape
    case controlSequence
    case operatingSystemCommand
    case operatingSystemCommandEscape
  }

  private var escapeState = EscapeState.text
  private var currentLine: [UInt8] = []

  var endsAtShellPrompt: Bool {
    let trimmed = currentLine.drop(while: { $0 == 0x20 || $0 == 0x09 })
    guard let last = trimmed.last else {
      return false
    }

    if last == 0x24 || last == 0x23 || last == 0x25 || last == 0x3e {
      return true
    }

    guard last == 0x20,
          let prompt = trimmed.dropLast().last else {
      return false
    }

    return prompt == 0x24 || prompt == 0x23 || prompt == 0x25 || prompt == 0x3e
  }

  mutating func consume(_ bytes: [UInt8]) {
    for byte in bytes {
      switch escapeState {
      case .text:
        switch byte {
        case 0x1b:
          escapeState = .escape
        case 0x0a, 0x0d:
          currentLine.removeAll(keepingCapacity: true)
        case 0x08:
          if !currentLine.isEmpty {
            currentLine.removeLast()
          }
        case 0x20...0x7e:
          currentLine.append(byte)
          if currentLine.count > 512 {
            currentLine.removeFirst(currentLine.count - 512)
          }
        default:
          break
        }

      case .escape:
        if byte == 0x5b {
          escapeState = .controlSequence
        } else if byte == 0x5d {
          escapeState = .operatingSystemCommand
        } else {
          escapeState = .text
        }

      case .controlSequence:
        if byte >= 0x40 && byte <= 0x7e {
          escapeState = .text
        }

      case .operatingSystemCommand:
        if byte == 0x07 {
          escapeState = .text
        } else if byte == 0x1b {
          escapeState = .operatingSystemCommandEscape
        }

      case .operatingSystemCommandEscape:
        escapeState = byte == 0x5c ? .text : .operatingSystemCommand
      }
    }
  }
}
