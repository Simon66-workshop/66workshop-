// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaskLightPackage",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TaskLightCore", targets: ["TaskLightCore"]),
        .executable(name: "TaskLightApp", targets: ["TaskLightApp"]),
        .executable(name: "TaskLightChecks", targets: ["TaskLightChecks"])
    ],
    targets: [
        .target(name: "TaskLightCore"),
        .executableTarget(
            name: "TaskLightApp",
            dependencies: ["TaskLightCore"]
        ),
        .executableTarget(
            name: "TaskLightChecks",
            dependencies: ["TaskLightCore"]
        )
    ]
)
