// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TestChimpRum",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
    ],
    products: [
        .library(name: "TestChimpRum", targets: ["TestChimpRum"]),
    ],
    targets: [
        .target(
            name: "TestChimpRum",
            path: "Sources/TestChimpRum"
        ),
        .testTarget(
            name: "TestChimpRumTests",
            dependencies: ["TestChimpRum"],
            path: "Tests/TestChimpRumTests"
        ),
    ]
)
