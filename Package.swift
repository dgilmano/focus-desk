// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FocusDesk",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FocusDesk", targets: ["FocusCarousel"]),
        .library(name: "FocusDeskWidget", targets: ["FocusCarouselWidget"])
    ],
    targets: [
        .target(
            name: "FocusCarouselCore",
            path: "Sources/FocusCarouselCore"
        ),
        .executableTarget(
            name: "FocusCarousel",
            dependencies: ["FocusCarouselCore"],
            path: "Sources/FocusCarouselApp"
        ),
        .target(
            name: "FocusCarouselWidget",
            dependencies: ["FocusCarouselCore"],
            path: "Sources/FocusCarouselWidget"
        ),
        .testTarget(
            name: "FocusCarouselCoreTests",
            dependencies: ["FocusCarouselCore"],
            path: "Tests/FocusCarouselCoreTests"
        )
    ]
)
