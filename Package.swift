// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokensVSRainForest",
    defaultLocalization: "de",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "RainforestCore", targets: ["RainforestCore"]),
        .executable(name: "TokensVSRainForest", targets: ["TokensVSRainForest"]),
        .executable(name: "rainforest", targets: ["rainforest"]),
    ],
    targets: [
        .target(name: "RainforestCore"),
        .executableTarget(
            name: "TokensVSRainForest",
            dependencies: ["RainforestCore"]),
        .executableTarget(
            name: "rainforest",
            dependencies: ["RainforestCore"]),
        .testTarget(
            name: "RainforestCoreTests",
            dependencies: ["RainforestCore"]),
    ])
