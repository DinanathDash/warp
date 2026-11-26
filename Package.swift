// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Warp",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Warp", type: .dynamic, targets: ["Warp"])
    ],
    dependencies: [
        .package(url: "https://gitlab.com/droppyformac1/droppykit.git", from: "1.28.0")
    ],
    targets: [
        .target(
            name: "Warp",
            dependencies: [.product(name: "DroppyKit", package: "droppykit")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "WarpHarness",
            dependencies: [
                "Warp",
                .product(name: "DroppyKitHarness", package: "droppykit")
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
