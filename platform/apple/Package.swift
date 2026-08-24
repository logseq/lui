// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LUIAppleBackend",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "LUIAppleBackend", type: .dynamic, targets: ["LUIAppleBackend"]),
        .executable(name: "LUITodos", targets: ["LUITodos"]),
    ],
    targets: [
        .target(name: "LUIAppleBackend"),
        .executableTarget(name: "LUITodos", dependencies: ["LUIAppleBackend"]),
        .testTarget(name: "LUIAppleBackendTests", dependencies: ["LUIAppleBackend"]),
    ]
)
