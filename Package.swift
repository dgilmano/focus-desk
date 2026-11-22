// swift-tools-version: 6.0

import Foundation
import PackageDescription

let microphoneInfo = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Config/SwiftPackageVoiceInfo.plist")

let package = Package(
    name: "FocusDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FocusDesk", targets: ["FocusDesk"]),
        .library(name: "FocusDeskWidget", targets: ["FocusDeskWidget"])
    ],
    targets: [
        .target(
            name: "FocusDeskCore",
            path: "Sources/FocusDeskCore"
        ),
        .executableTarget(
            name: "FocusDesk",
            dependencies: ["FocusDeskCore"],
            path: "Sources/FocusDeskApp",
            resources: [.copy("Brand/FocusDeskMark.svg")],
            linkerSettings: [
                // swift run starts a standalone executable, so macOS reads its privacy usage string from Mach-O.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                    "-Xlinker", microphoneInfo.path
                ], .when(platforms: [.macOS], configuration: .debug))
            ]
        ),
        .target(
            name: "FocusDeskWidget",
            dependencies: ["FocusDeskCore"],
            path: "Sources/FocusDeskWidget"
        ),
        .testTarget(
            name: "FocusDeskCoreTests",
            dependencies: ["FocusDeskCore"],
            path: "Tests/FocusDeskCoreTests"
        ),
        .testTarget(
            name: "FocusDeskAppTests",
            dependencies: ["FocusDesk"],
            path: "Tests/FocusDeskAppTests"
        )
    ]
)
