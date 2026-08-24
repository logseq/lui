// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LUITodos",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../../../platform/apple"),
    ],
    targets: [
        .executableTarget(
            name: "LUITodos",
            dependencies: [
                .product(name: "LUIAppleBackend", package: "apple"),
            ]
        ),
    ]
)
