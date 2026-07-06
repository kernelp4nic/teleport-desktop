// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MenuShell",
  platforms: [
    .macOS(.v14)
  ],
  products: [
    .executable(
      name: "MenuShell",
      targets: ["MenuShell"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.13.0")
  ],
  targets: [
    .executableTarget(
      name: "MenuShell",
      dependencies: [
        .product(name: "SwiftTerm", package: "SwiftTerm")
      ],
      path: "Sources"
    ),
    .testTarget(
      name: "MenuShellTests",
      dependencies: ["MenuShell"],
      path: "Tests/MenuShellTests"
    )
  ]
)
