// swift-tools-version: 6.2
import PackageDescription
import Foundation
let inputs = ProcessInfo.processInfo.environment["LUI_NAVIGATION_LINK_INPUTS"]?.split(separator: ":").map(String.init) ?? []
let package = Package(
    name: "NavigationDemo", platforms: [.iOS(.v17), .macOS(.v14)],
    dependencies: [.package(path: "../../../platform/apple")],
    targets: [.executableTarget(name: "NavigationDemo",
        dependencies: [.product(name: "LUIAppleBackendStatic", package: "apple")],
        linkerSettings: [.unsafeFlags(inputs)])]
)
