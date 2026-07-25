// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "teleport-desktop",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "teleport-desktop",
      targets: ["teleport-desktop"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0")
  ],
  targets: [
    .executableTarget(
      name: "teleport-desktop",
      dependencies: [
        .product(name: "SwiftTerm", package: "SwiftTerm")
      ],
      path: "Sources"
    ),
    .testTarget(
      name: "teleport-desktop-tests",
      dependencies: ["teleport-desktop"],
      path: "Tests/teleport-desktop-tests"
    )
  ]
)
