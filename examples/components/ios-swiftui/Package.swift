// swift-tools-version: 6.0

import PackageDescription
import Foundation

let nativeLinkInputs = ProcessInfo.processInfo.environment["LUI_COMPONENTS_NATIVE_LINK_INPUTS"]?
    .split(separator: ":")
    .map(String.init) ?? []
let nativeLinkerSettings: [LinkerSetting] = nativeLinkInputs.isEmpty ? [] : [
    .unsafeFlags(nativeLinkInputs, .when(platforms: [.iOS, .macOS])),
]

let package = Package(
    name: "LUIComponentsIOS",
    platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [
        .package(path: "../../../platform/apple"),
    ],
    targets: [
        .executableTarget(
            name: "LUIComponentsApp",
            dependencies: [
                .product(name: "LUIAppleBackendStatic", package: "apple"),
            ],
            linkerSettings: nativeLinkerSettings
        ),
    ]
)
