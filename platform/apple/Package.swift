// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LUIAppleBackend",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LUIAppleBackend", type: .dynamic, targets: ["LUIAppleBackend"]),
        .library(name: "LUIAppleBackendStatic", type: .static, targets: ["LUIAppleBackend"]),
    ],
    targets: [
        .target(
            name: "LUIAppleBackend",
            dependencies: []
        ),
        .testTarget(
            name: "LUIAppleBackendTests",
            dependencies: ["LUIAppleBackend"]
        ),
    ]
)
