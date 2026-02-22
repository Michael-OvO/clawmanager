// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClawManager",
    platforms: [
        .macOS(.v15)
    ],
    targets: [
        .executableTarget(
            name: "ClawManager",
            path: "Sources/ClawManager"
        ),
        .testTarget(
            name: "ClawManagerTests",
            dependencies: ["ClawManager"],
            path: "Tests/ClawManagerTests"
        )
    ]
)
