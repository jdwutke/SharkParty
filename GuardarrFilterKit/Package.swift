// swift-tools-version: 6.0

import PackageDescription

/// Guardarr content filtering: the filter-list wire format, the fetch policy and the
/// playback timeline. Foundation only, so it runs under `swift test` on macOS and Linux.
let package = Package(
    name: "GuardarrFilterKit",
    platforms: [
        .iOS(.v18),
        .tvOS(.v18),
        .macOS(.v14),
    ],
    products: [
        .library(name: "GuardarrFilterKit", targets: ["GuardarrFilterKit"]),
    ],
    targets: [
        .target(name: "GuardarrFilterKit"),
        .testTarget(name: "GuardarrFilterKitTests", dependencies: ["GuardarrFilterKit"]),
    ],
    swiftLanguageModes: [.v5]
)
