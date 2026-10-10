// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "Rewind",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "Rewind", targets: ["Rewind"]),
	],
	dependencies: [
		.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.2"),
		.package(url: "https://github.com/CocoaLumberjack/CocoaLumberjack", exact: "3.8.5"),
		.package(url: "https://github.com/sindresorhus/Defaults", from: "8.2.0"),
	],
	targets: [
		.target(
			name: "RewindObjCSupport",
			path: "Sources/RewindObjCSupport"
		),
		.executableTarget(
			name: "Rewind",
			dependencies: [
				.product(name: "Sparkle", package: "Sparkle"),
				.product(name: "CocoaLumberjackSwift", package: "CocoaLumberjack"),
				.product(name: "Defaults", package: "Defaults"),
				"RewindObjCSupport",
			],
			path: "Sources/Rewind",
			linkerSettings: [
				.linkedLibrary("sqlite3"),
				.unsafeFlags([
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
					"-Xlinker", "-rpath", "-Xlinker", "@executable_path",
				]),
			]
		),
		.testTarget(
			name: "RewindTests",
			dependencies: [
				"Rewind",
				.product(name: "Defaults", package: "Defaults"),
			],
			path: "Tests/RewindTests",
			linkerSettings: [
				.unsafeFlags([
					"-Xlinker", "-rpath", "-Xlinker", "@loader_path/../../..",
				]),
			]
		),
	]
)
