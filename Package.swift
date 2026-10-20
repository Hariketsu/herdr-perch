// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HerdrPerch",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "PerchCore", targets: ["PerchCore"]),
        .executable(name: "PerchApp", targets: ["PerchApp"]),
        .executable(name: "perchctl", targets: ["perchctl"]),
    ],
    targets: [
        .target(name: "PerchCore"),
        .executableTarget(name: "PerchApp", dependencies: ["PerchCore"]),
        .executableTarget(name: "perchctl", dependencies: ["PerchCore"]),
        .testTarget(
            name: "PerchCoreTests",
            dependencies: ["PerchCore"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "PerchAppTests", dependencies: ["PerchApp", "PerchCore"]),
    ]
)
