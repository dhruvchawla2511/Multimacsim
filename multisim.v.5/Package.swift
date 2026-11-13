// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MultiSim",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MultiSim", targets: ["MultiSim"]),
        .library(name: "MultiSimEngine", targets: ["MultiSimEngine"])
    ],
    targets: [
        .target(
            name: "MultiSimEngine",
            dependencies: []
        ),
        .executableTarget(
            name: "MultiSim",
            dependencies: ["MultiSimEngine"]
        ),
        .testTarget(
            name: "MultiSimEngineTests",
            dependencies: ["MultiSimEngine"]
        )
    ]
)
