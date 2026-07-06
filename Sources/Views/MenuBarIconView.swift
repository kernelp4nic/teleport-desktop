import SwiftUI

struct MenuBarIconView: View {
  var body: some View {
    ZStack {
      Image(systemName: "gearshape.fill")
        .symbolRenderingMode(.monochrome)
        .font(.system(size: 15, weight: .medium))

      Text(">")
        .font(.system(size: 8, weight: .black, design: .rounded))
        .offset(y: 0.25)
        .blendMode(.destinationOut)
    }
    .foregroundStyle(.primary)
    .compositingGroup()
    .frame(width: 18, height: 18)
    .accessibilityLabel("Teleport")
  }
}
