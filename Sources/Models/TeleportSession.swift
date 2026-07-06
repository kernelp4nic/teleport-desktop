import Foundation

struct TeleportSession: Equatable, Sendable {
  enum State: Equatable, Sendable {
    case unavailable
    case expired
    case active
  }

  let state: State
  let proxy: String?
  let cluster: String?
  let username: String?
  let logins: [String]
  let validUntil: Date?

  var isActive: Bool {
    state == .active
  }

  var statusText: String {
    switch state {
    case .active:
      return "Session active"
    case .expired:
      return "Session expired"
    case .unavailable:
      return "Session unavailable"
    }
  }

  static func unavailable(proxy: String?) -> TeleportSession {
    TeleportSession(
      state: .unavailable,
      proxy: proxy,
      cluster: nil,
      username: nil,
      logins: [],
      validUntil: nil
    )
  }
}
