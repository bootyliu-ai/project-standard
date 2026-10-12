// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProjectStandard",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ProjectStandardCore", targets: ["ProjectStandardCore"]),
        .executable(name: "ProjectStandard", targets: ["ProjectStandardApp"]),
        .executable(name: "ProjectStandardProbe", targets: ["ProjectStandardProbe"])
    ],
    targets: [
        .target(name: "ProjectStandardCore"),
        .executableTarget(
            name: "ProjectStandardApp",
            dependencies: ["ProjectStandardCore"]
        ),
        .executableTarget(
            name: "ProjectStandardProbe",
            dependencies: ["ProjectStandardCore"]
        ),
        .testTarget(
            name: "ProjectStandardCoreTests",
            dependencies: ["ProjectStandardCore"]
        )
    ]
)
