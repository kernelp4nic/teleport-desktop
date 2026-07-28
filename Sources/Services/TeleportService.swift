import Foundation

enum TeleportServiceError: LocalizedError {
  case commandFailed(String)
  case invalidResponse(String)

  var errorDescription: String? {
    switch self {
    case .commandFailed(let message):
      return message
    case .invalidResponse(let message):
      return message
    }
  }
}

struct TeleportService {
  private let runner: CommandRunning
  private let now: () -> Date

  init(
    runner: CommandRunning = ProcessRunner(),
    now: @escaping () -> Date = Date.init
  ) {
    self.runner = runner
    self.now = now
  }

  func loadSession(proxyOverride: String?) -> TeleportSession {
    do {
      let result = try runner.run(
        command: "tsh",
        arguments: ["status", "--format=json"]
      )

      guard result.exitStatus == 0 else {
        return .unavailable(proxy: Self.normalizeProxyAddress(proxyOverride))
      }

      return try Self.parseSession(
        from: result.stdout,
        now: now(),
        proxyOverride: proxyOverride
      )
    } catch {
      return .unavailable(proxy: Self.normalizeProxyAddress(proxyOverride))
    }
  }

  func loadNodes(proxyOverride: String?) throws -> [TeleportNode] {
    var arguments = ["ls", "--format=json"]

    if let proxyOverride = Self.normalizeProxyAddress(proxyOverride) {
      arguments.append("--proxy=\(proxyOverride)")
    }

    let result = try runner.run(command: "tsh", arguments: arguments)

    guard result.exitStatus == 0 else {
      let message = result.stderr
        .trimmingCharacters(in: .whitespacesAndNewlines)

      throw TeleportServiceError.commandFailed(
        message.isEmpty ? "Teleport returned an unknown error." : message
      )
    }

    return try Self.parseNodes(from: result.stdout)
  }

  func loginCommand(proxy: String?) -> String {
    var segments = ["tsh", "login"]

    if let proxy = Self.normalizeProxyAddress(proxy) {
      segments.append("--proxy=\(proxy)")
    }

    return ShellQuoter.join(segments)
  }

  func connectCommand(
    for node: TeleportNode,
    settings: SettingsStore,
    session: TeleportSession
  ) -> String? {
    let login = node.preferredLogin(
      labelKey: settings.normalizedLoginLabelKey,
      fallback: settings.normalizedFallbackLogin,
      allowedLogins: session.logins
    )

    guard let login else {
      return nil
    }

    return ShellQuoter.join(["tsh", "ssh", "\(login)@\(node.hostname)"])
  }

  func tmuxControlCommand(
    for node: TeleportNode,
    settings: SettingsStore,
    session: TeleportSession
  ) -> String? {
    let login = node.preferredLogin(
      labelKey: settings.normalizedLoginLabelKey,
      fallback: settings.normalizedFallbackLogin,
      allowedLogins: session.logins
    )

    guard let login else {
      return nil
    }

    return ShellQuoter.join([
      "tsh", "ssh", "-t", "\(login)@\(node.hostname)",
      "tmux", "-CC", "new-session", "-A", "-s", "teleport-desktop",
      "-x", "120", "-y", "40"
    ])
  }

  static func normalizeProxyAddress(_ value: String?) -> String? {
    guard let value = value?
      .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty else {
      return nil
    }

    var normalized = value

    if normalized.hasPrefix("https://") {
      normalized.removeFirst("https://".count)
    } else if normalized.hasPrefix("http://") {
      normalized.removeFirst("http://".count)
    }

    while normalized.hasSuffix("/") {
      normalized.removeLast()
    }

    return normalized.isEmpty ? nil : normalized
  }

  static func parseSession(
    from json: String,
    now: Date,
    proxyOverride: String? = nil
  ) throws -> TeleportSession {
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    let envelope = try decoder.decode(StatusEnvelope.self, from: data)
    guard let active = envelope.active else {
      return .unavailable(proxy: normalizeProxyAddress(proxyOverride))
    }

    let validUntil = active.validUntil.flatMap(Self.parseDate)
    let state: TeleportSession.State

    if let validUntil, validUntil <= now {
      state = .expired
    } else {
      state = .active
    }

    return TeleportSession(
      state: state,
      proxy: normalizeProxyAddress(active.profileURL) ?? normalizeProxyAddress(proxyOverride),
      cluster: active.cluster,
      username: active.username,
      logins: active.logins.filter { !$0.hasPrefix("-teleport-") },
      validUntil: validUntil
    )
  }

  static func parseNodes(from json: String) throws -> [TeleportNode] {
    let data = Data(json.utf8)
    let decoder = JSONDecoder()
    let rawNodes = try decoder.decode([RawNode].self, from: data)

    return rawNodes.map { rawNode in
      let hostname = rawNode.spec?.hostname
        ?? rawNode.metadata?.labels?["hostname"]
        ?? rawNode.metadata?.name
        ?? "unknown"

      let dynamicLabels = (rawNode.spec?.commandLabels ?? [:]).reduce(into: [String: String]()) {
        partialResult, entry in
        if let stringValue = entry.value.stringValue {
          partialResult[entry.key] = stringValue
        } else if let resultValue = entry.value.objectValue?["result"]?.stringValue {
          partialResult[entry.key] = resultValue
        }
      }

      var labelMap = rawNode.metadata?.labels ?? [:]

      for (key, value) in dynamicLabels where !value.isEmpty {
        labelMap[key] = value
      }

      if labelMap["hostname"] == nil {
        labelMap["hostname"] = hostname
      }

      let address = rawNode.spec?.addr.flatMap { value in
        value.isEmpty ? nil : value
      } ?? ((rawNode.spec?.useTunnel ?? false) ? "Tunnel" : "Unknown")

      return TeleportNode(
        id: rawNode.metadata?.name ?? hostname,
        hostname: hostname,
        address: address,
        labels: labelMap
          .map { TeleportLabel(key: $0.key, value: $0.value) }
          .sorted { lhs, rhs in
            lhs.key == rhs.key
              ? lhs.value.localizedCaseInsensitiveCompare(rhs.value) == .orderedAscending
              : lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
          },
        labelMap: labelMap
      )
    }
    .sorted { lhs, rhs in
      lhs.hostname.localizedCaseInsensitiveCompare(rhs.hostname) == .orderedAscending
    }
  }

  private static func parseDate(_ rawDate: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    if let date = formatter.date(from: rawDate) {
      return date
    }

    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: rawDate)
  }
}

private struct StatusEnvelope: Decodable {
  let active: ActiveProfile?

  struct ActiveProfile: Decodable {
    let profileURL: String?
    let cluster: String?
    let username: String?
    let logins: [String]
    let validUntil: String?

    enum CodingKeys: String, CodingKey {
      case profileURL = "profile_url"
      case cluster
      case username
      case logins
      case validUntil = "valid_until"
    }
  }
}

private struct RawNode: Decodable {
  let metadata: Metadata?
  let spec: Spec?

  struct Metadata: Decodable {
    let name: String?
    let labels: [String: String]?
  }

  struct Spec: Decodable {
    let hostname: String?
    let addr: String?
    let useTunnel: Bool?
    let commandLabels: [String: JSONValue]?

    enum CodingKeys: String, CodingKey {
      case hostname
      case addr
      case useTunnel = "use_tunnel"
      case commandLabels = "cmd_labels"
    }
  }
}

private enum JSONValue: Decodable {
  case string(String)
  case object([String: JSONValue])
  case array([JSONValue])
  case bool(Bool)
  case number(Double)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else {
      throw DecodingError.typeMismatch(
        JSONValue.self,
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "Unsupported JSON value"
        )
      )
    }
  }

  var stringValue: String? {
    guard case .string(let value) = self else {
      return nil
    }

    return value
  }

  var objectValue: [String: JSONValue]? {
    guard case .object(let value) = self else {
      return nil
    }

    return value
  }
}
