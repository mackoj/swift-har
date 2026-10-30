// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-har",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        // HAR 1.2 models, entry builders from plain values, and JSON serialization.
        // No dependencies; uses FoundationEssentials where available.
        .library(name: "HARKit", targets: ["HARKit"]),
        // Conversions from URLRequest, HTTPURLResponse and URLSession task metrics.
        // Needs Foundation (and FoundationNetworking on Linux).
        .library(name: "HARKitURLSession", targets: ["HARKitURLSession"]),
    ],
    targets: [
        .target(name: "HARKit"),
        .target(
            name: "HARKitURLSession",
            dependencies: ["HARKit"]
        ),
        .testTarget(
            name: "HARKitTests",
            dependencies: ["HARKit"]
        ),
        .testTarget(
            name: "HARKitURLSessionTests",
            dependencies: ["HARKit", "HARKitURLSession"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
