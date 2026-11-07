// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LUI",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "LUIAppleBackend", type: .dynamic, targets: ["LUIAppleBackend"]),
        .library(name: "LUIAppleBackendStatic", type: .static, targets: ["LUIAppleBackend"]),
    ],
    targets: [
        .target(
            name: "LUIAppleBackend",
            path: "platform/apple/Sources/LUIAppleBackend",
            exclude: ["Skip", "LUISkipUIRoot.swift"]
        ),
        .testTarget(
            name: "LUIAppleBackendTests",
            dependencies: ["LUIAppleBackend"],
            path: "platform/apple/Tests/LUIAppleBackendTests",
            exclude: ["Skip"]
        ),
    ]
)
