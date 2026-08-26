// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LUI",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LUIAppleBackend", type: .dynamic, targets: ["LUIAppleBackend"]),
        .library(name: "LUIAppleBackendStatic", type: .static, targets: ["LUIAppleBackend"]),
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", exact: "1.9.5"),
        .package(url: "https://source.skip.tools/skip-ui.git", exact: "1.59.1"),
    ],
    targets: [
        .target(
            name: "LUIAppleBackend",
            dependencies: [.product(name: "SkipUI", package: "skip-ui")],
            path: "platform/apple/Sources/LUIAppleBackend",
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .testTarget(
            name: "LUIAppleBackendTests",
            dependencies: [
                "LUIAppleBackend",
                .product(name: "SkipTest", package: "skip"),
            ],
            path: "platform/apple/Tests/LUIAppleBackendTests",
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
    ]
)
