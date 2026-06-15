// swift-tools-version: 6.0
import PackageDescription

/// LiveLocationKit turns Apple's CoreLocation APIs into a single, testable
/// `AsyncStream` of location samples.
///
/// It deliberately has no Expo, React Native, or UI dependency: the package can
/// be built and unit-tested in isolation (`swift test`, no simulator required)
/// and reused from any Swift target. The Expo layer is a thin adapter on top.
///
/// The Kit sources live in `ios/LiveLocationKit` so that exactly one canonical
/// copy is both unit-tested by this package and compiled into the Expo pod (whose
/// podspec can only reference files within its own `ios/` directory). The folder
/// still imports nothing from Expo — the decoupling is by dependency, not path.
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
            path: "ios/LiveLocationKit",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "LiveLocationKitTests",
            dependencies: ["LiveLocationKit"],
            path: "Tests/LiveLocationKitTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
