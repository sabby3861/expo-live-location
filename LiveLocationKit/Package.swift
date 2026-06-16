// swift-tools-version: 6.0
import PackageDescription

/// LiveLocationKit turns Apple's CoreLocation APIs into a single, testable
/// `AsyncStream` of location samples.
///
/// It deliberately has no Expo, React Native, or UI dependency: the package can
/// be built and unit-tested in isolation (`swift test`, no simulator required)
/// and reused from any Swift target. The Expo layer is a thin adapter on top.
///
/// This is the one canonical copy of the core. The Expo pod compiles the same
/// sources directly from here (see `ExpoLiveLocation.podspec` at the repo root),
/// so there's no duplication and nothing to keep in sync.
let package = Package(
    name: "LiveLocationKit",
    platforms: [
        .iOS(.v16),
        .macOS(.v14),
    ],
    products: [
        .library(name: "LiveLocationKit", targets: ["LiveLocationKit"]),
    ],
    targets: [
        .target(
            name: "LiveLocationKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LiveLocationKitTests",
            dependencies: ["LiveLocationKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
