// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StandFifty",
    platforms: [.macOS(.v14)],
    targets: [
        // 纯逻辑层：可以脱离 UI 单测
        .target(name: "StandFiftyCore", path: "Sources/StandFiftyCore"),
        .executableTarget(
            name: "StandFifty",
            dependencies: ["StandFiftyCore"],
            path: "Sources/StandFifty"
        ),
        .testTarget(
            name: "StandFiftyCoreTests",
            dependencies: ["StandFiftyCore"],
            path: "Tests/StandFiftyCoreTests"
        ),
    ]
)
