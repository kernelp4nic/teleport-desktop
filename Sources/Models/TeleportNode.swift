import Foundation

struct TeleportLabel: Identifiable, Equatable, Codable, Sendable {
  let key: String
  let value: String

  var id: String {
    "\(key)=\(value)"
  }
}

struct TeleportNode: Identifiable, Equatable, Codable, Sendable {
  let id: String
  let hostname: String
  let address: String
  let labels: [TeleportLabel]
  let labelMap: [String: String]

  func groupValue(for labelKey: String?) -> String {
    guard let labelKey,
          let value = labelMap[labelKey],
          !value.isEmpty else {
      return "Ungrouped"
    }

    return value
  }

  func preferredLogin(labelKey: String?, fallback: String?, allowedLogins: [String]) -> String? {
    let filteredLogins = allowedLogins.filter { !$0.hasPrefix("-teleport-") }

    if let labelKey,
       let labeledLogin = labelMap[labelKey],
       !labeledLogin.isEmpty,
       filteredLogins.isEmpty || filteredLogins.contains(labeledLogin) {
      return labeledLogin
    }

    if let fallback,
       !fallback.isEmpty,
       filteredLogins.isEmpty || filteredLogins.contains(fallback) {
      return fallback
    }

    return filteredLogins.first
  }

  func matches(searchText: String, additionalText: String? = nil) -> Bool {
    let trimmedSearch = searchText
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()

    guard !trimmedSearch.isEmpty else {
      return true
    }

    let haystack = ([hostname, address, additionalText].compactMap { $0 }
      + labels.map { "\($0.key) \($0.value)" })
      .joined(separator: " ")
      .lowercased()

    return trimmedSearch
      .split(separator: " ")
      .allSatisfy { haystack.contains($0) }
  }

  func displayLabels(groupKey: String?, loginKey: String?, limit: Int = 4) -> [TeleportLabel] {
    var ordered: [TeleportLabel] = []
    var seenKeys = Set<String>()

    for key in [groupKey, loginKey, "roles", "hostname"] {
      guard let key,
            !seenKeys.contains(key),
            let value = labelMap[key],
            !value.isEmpty else {
        continue
      }

      ordered.append(TeleportLabel(key: key, value: value))
      seenKeys.insert(key)
    }

    for label in labels where !seenKeys.contains(label.key) {
      ordered.append(label)
      seenKeys.insert(label.key)
    }

    return Array(ordered.prefix(limit))
  }
}
