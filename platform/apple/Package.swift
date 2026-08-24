// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LUIAppleBackend",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "LUIAppleBackend", type: .dynamic, targets: ["LUIAppleBackend"]),
    ],
    targets: [
        .target(name: "LUIAppleBackend"),
        .testTarget(name: "LUIAppleBackendTests", dependencies: ["LUIAppleBackend"]),
    ]
)
