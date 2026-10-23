import SwiftUI

enum InterfaceTheme: String, CaseIterable, Identifiable {
  case system, light, dark

  var id: String { rawValue }

  var title: String {
    switch self {
    case .system: return "System"
    case .light: return "Light"
    case .dark: return "Dark"
    }
  }

  /// nil follows the macOS appearance.
  var colorScheme: ColorScheme? {
    switch self {
    case .system: return nil
    case .light: return .light
    case .dark: return .dark
    }
  }
}

enum TabSize: String, CaseIterable, Identifiable {
  case compact, regular, large

  var id: String { rawValue }

  var title: String {
    switch self {
    case .compact: return "Compact"
    case .regular: return "Regular"
    case .large: return "Large"
    }
  }

  var font: Font {
    switch self {
    case .compact: return .caption
    case .regular: return .subheadline
    case .large: return .body
    }
  }

  var verticalPadding: CGFloat {
    switch self {
    case .compact: return 4
    case .regular: return 8
    case .large: return 12
    }
  }
}
