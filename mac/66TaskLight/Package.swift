// swift-tools-version: 6.0
import Foundation
import PackageDescription

let developerDirectory = ProcessInfo.processInfo.environment["DEVELOPER_DIR"] ?? "/Library/Developer/CommandLineTools"
let developerFrameworks = "\(developerDirectory)/Library/Developer/Frameworks"
let developerLibraries = "\(developerDirectory)/Library/Developer/usr/lib"
let testingSearchPath: [SwiftSetting] = FileManager.default.fileExists(atPath: developerFrameworks)
    ? [.unsafeFlags(["-F", developerFrameworks])]
    : []
let testingLinkerSearchPath: [LinkerSetting] = FileManager.default.fileExists(atPath: developerFrameworks)
    ? [.unsafeFlags([
        "-F", developerFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", developerFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", developerLibraries
    ])]
    : []

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
        ),
        .target(
            name: "TaskLightTestSuite",
            dependencies: ["TaskLightCore"],
            path: "Tests/TaskLightTestSuite",
            swiftSettings: testingSearchPath,
            linkerSettings: testingLinkerSearchPath
        ),
        .executableTarget(
            name: "TaskLightTestRunner",
            dependencies: ["TaskLightTestSuite"],
            swiftSettings: testingSearchPath,
            linkerSettings: testingLinkerSearchPath
        ),
        .testTarget(
            name: "TaskLightCoreTests",
            dependencies: ["TaskLightTestSuite"],
            swiftSettings: testingSearchPath,
            linkerSettings: testingLinkerSearchPath
        )
    ],
    swiftLanguageModes: [.v5]
)
