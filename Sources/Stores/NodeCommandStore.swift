import Foundation
import Observation

struct CommandTarget: Identifiable, Sendable {
  let node: TeleportNode
  let name: String
  let login: String
  let icon: String?

  var id: String { node.id }
}

/// Runs one command on many nodes at once and keeps each node's result for the run sheet.
@MainActor
@Observable
final class NodeCommandStore {
  enum State: Equatable {
    case pending
    case running
    case finished(NodeCommandResult)
    case cancelled
  }

  struct Row: Identifiable {
    let target: CommandTarget
    var state: State = .pending

    var id: String { target.id }
  }

  static let maxConcurrent = 8

  var command = ""
  private(set) var rows: [Row] = []
  private(set) var isRunning = false

  private let execute: @Sendable (CommandTarget, String) async -> NodeCommandResult
  private var task: Task<Void, Never>?

  init(
    execute: @escaping @Sendable (CommandTarget, String) async -> NodeCommandResult = { target, command in
      await TeleportCommandService().run(command: command, login: target.login, hostname: target.node.hostname)
    }
  ) {
    self.execute = execute
  }

  func run(on targets: [CommandTarget]) {
    let command = command.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !isRunning, !command.isEmpty, !targets.isEmpty else {
      return
    }

    rows = targets.map { Row(target: $0) }
    isRunning = true

    task = Task {
      await withTaskGroup(of: (Int, NodeCommandResult).self) { group in
        var next = 0
        var inFlight = 0

        while next < targets.count || inFlight > 0 {
          while inFlight < Self.maxConcurrent, next < targets.count, !Task.isCancelled {
            let index = next
            rows[index].state = .running
            group.addTask { [execute] in (index, await execute(targets[index], command)) }
            next += 1
            inFlight += 1
          }

          guard let (index, result) = await group.next() else {
            break
          }

          inFlight -= 1
          rows[index].state = Task.isCancelled ? .cancelled : .finished(result)
        }
      }

      for index in rows.indices where rows[index].state == .pending {
        rows[index].state = .cancelled
      }

      isRunning = false
    }
  }

  func cancel() {
    task?.cancel()
  }
}
