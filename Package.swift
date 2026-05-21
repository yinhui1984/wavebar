// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Wavebar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "wavebar", targets: ["wavebar"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "wavebar",
            dependencies: [],
            path: "Sources",
            exclude: ["LiquidGel.metal", "AppIcon.icns"],
            resources: [
                .process("default.metallib")
            ]
        )
    ]
)
