// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "StreamDeckKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(
            name: "StreamDeckKit",
            targets: ["StreamDeckKit"]
        ),
        .library(
            name: "StreamDeckSimulator",
            targets: ["StreamDeckSimulator"]
        )
    ],
    dependencies: [
        .package(
            url: "https://github.com/pointfreeco/swift-snapshot-testing",
            from: "1.12.0"
        ),
        .package(
            url: "https://github.com/mallexxx/SwiftSerial.git",
            revision: "f9b315b5b4f152c4298220c094da3b98a7c3029e"
        ),
    ],
    targets: [
        .target(
            name: "StreamDeckSimulator",
            dependencies: ["StreamDeckKit"],
            resources: [.process("Resources")]
        ),
        .target(
            name: "StreamDeckKit",
            dependencies: ["StreamDeckCApi", "SwiftSerial"]
        ),
        .target(
            name: "StreamDeckCApi",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "StreamDeckSDKTests",
            dependencies: [
                "StreamDeckKit",
                "StreamDeckSimulator",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing")
            ]
        )
    ]
)
