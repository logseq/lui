// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "LUISplitDemo",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../../../platform/apple"),
    ],
    targets: [
        .executableTarget(
            name: "LUISplitDemo",
            dependencies: [
                .product(name: "LUIAppleBackend", package: "apple"),
            ]
        ),
    ]
)
