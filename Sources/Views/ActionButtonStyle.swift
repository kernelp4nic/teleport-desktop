import SwiftUI

struct ActionButtonStyle: ButtonStyle {
  var prominent = false

  func makeBody(configuration: Configuration) -> some View {
    ActionButtonBody(
      configuration: configuration,
      prominent: prominent
    )
  }
}

private struct ActionButtonBody: View {
  let configuration: ButtonStyle.Configuration
  let prominent: Bool
  @Environment(\.isEnabled) private var isEnabled
  @State private var isHovering = false

  var body: some View {
    configuration.label
      .foregroundStyle(prominent ? Color.white : Color.primary)
      .padding(.horizontal, 9)
      .padding(.vertical, 5)
      .background {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(backgroundColor)
      }
      .overlay {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
          .strokeBorder(borderColor, lineWidth: 1)
      }
      .shadow(
        color: prominent && isHovering ? Color.accentColor.opacity(0.24) : .clear,
        radius: 5
      )
      .scaleEffect(configuration.isPressed ? 0.96 : isHovering ? 1.02 : 1)
      .opacity(isEnabled ? 1 : 0.45)
      .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
      .animation(.easeOut(duration: 0.16), value: isHovering)
      .onHover { isHovering = isEnabled && $0 }
  }

  private var backgroundColor: Color {
    if prominent {
      return Color.accentColor.opacity(configuration.isPressed ? 0.72 : 1)
    }
    if configuration.isPressed {
      return Color.accentColor.opacity(0.18)
    }
    return isHovering ? Color.primary.opacity(0.1) : Color.primary.opacity(0.045)
  }

  private var borderColor: Color {
    if prominent {
      return Color.accentColor
    }
    return isHovering ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.1)
  }
}
