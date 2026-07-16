// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KillPort",
    platforms: [
        .macOS(.v12)
    ],
    targets: [
        .executableTarget(
            name: "KillPort",
            path: "Sources/KillPort"
        )
    ]
)
