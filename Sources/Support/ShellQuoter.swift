import Foundation

enum ShellQuoter {
  static func join(_ segments: [String]) -> String {
    segments.map(quote).joined(separator: " ")
  }

  private static func quote(_ value: String) -> String {
    let safePattern = #"^[A-Za-z0-9_@%+=:,./-]+$"#

    if value.range(of: safePattern, options: .regularExpression) != nil {
      return value
    }

    return "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
  }
}
