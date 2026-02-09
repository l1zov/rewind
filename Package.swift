// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "Rewind",
  platforms: [.macOS(.v13)],
  products: [
    .executable(name: "Rewind", targets: ["Rewind"])
  ],
  targets: [
    .executableTarget(
      name: "Rewind",
      path: "Sources/Rewind",
      linkerSettings: [
        .linkedLibrary("sqlite3")
      ]
    ),
    .testTarget(
      name: "RewindTests",
      dependencies: ["Rewind"],
      path: "Tests/RewindTests"
    )
  ]
)
