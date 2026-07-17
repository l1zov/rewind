// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "Rewind",
	platforms: [.macOS(.v13)],
	products: [
		.executable(name: "Rewind", targets: ["Rewind"]),
	],
	dependencies: [
		.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.2"),
	],
	targets: [
		.executableTarget(
			name: "Rewind",
			dependencies: [
				.product(name: "Sparkle", package: "Sparkle"),
			],
			path: "Sources/Rewind",
			swiftSettings: [
				// Blank out the readable field/property/type names in Swift reflection
				// metadata so class-dump-style tools can't recover the app's structure.
				// Uses -disable-reflection-names (not -disable-reflection-metadata): it
				// keeps the field-metadata records that SwiftUI walks at runtime to find
				// @State/@Published, so the UI keeps working — only the names go away.
				.unsafeFlags(
					["-Xfrontend", "-disable-reflection-names"],
					.when(configuration: .release)
				),
			],
			linkerSettings: [
				.linkedLibrary("sqlite3"),
				.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
				// Release hardening: -dead_strip drops unreachable code (smaller attack
				// surface), and -x strips local symbols at link time so *any* release
				// build is hardened, not only the one produced by build-package.sh.
				.unsafeFlags(
					["-Xlinker", "-dead_strip", "-Xlinker", "-x"],
					.when(configuration: .release)
				),
			]
		),
		.testTarget(
			name: "RewindTests",
			dependencies: ["Rewind"],
			path: "Tests/RewindTests"
		),
	]
)
