// swift-tools-version: 6.0

import PackageDescription

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
            path: "Sources/FocusDeskApp"
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
        )
    ]
)
