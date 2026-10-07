// swift-tools-version: 5.9
import PackageDescription

// Wraps zsign (https://github.com/zhlynn/zsign, MIT) for on-device signing.
// The vendored sources live in Sources/ZSignC/zsign; see ZSIGN_VERSION and LICENSE-zsign.
let package = Package(
	name: "ZSignKit",
	platforms: [.iOS(.v16)],
	products: [
		.library(name: "ZSignC", targets: ["ZSignC"]),
	],
	dependencies: [
		.package(url: "https://github.com/krzyzanowskim/OpenSSL", from: "3.3.3001"),
	],
	targets: [
		.target(
			name: "ZSignC",
			dependencies: [.product(name: "OpenSSL", package: "OpenSSL")],
			path: "Sources/ZSignC",
			publicHeadersPath: "include",
			cxxSettings: [
				.headerSearchPath("zsign"),
				.headerSearchPath("zsign/common"),
				.define("ZSIGN_NO_SHELL"),
				.unsafeFlags(["-w"]),
			]
		),
	],
	cxxLanguageStandard: .cxx17
)
