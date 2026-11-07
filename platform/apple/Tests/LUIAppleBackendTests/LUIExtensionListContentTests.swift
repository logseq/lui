import SwiftUI
import XCTest
@testable import LUIAppleBackend

@MainActor final class LUIExtensionListContentTests: XCTestCase {
    func testListItemMayContainOnlyExtensionContent() throws {
        let registry = LUIAppleExtensionRegistry()
        try registry.register(LUIAppleExtension(identifier: "test-content", fingerprint: "test-content-v1") { _ in
            AnyView(Text("Native date picker"))
        })
        let backend = try LUIAppleBackend(extensionRegistry: registry)
        XCTAssertNoThrow(try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"root"},
          {"op":"create-node","id":2,"kind":"list"},
          {"op":"create-node","id":3,"kind":"list-item"},
          {"op":"create-extension","id":4,"identifier":"test-content","fingerprint":"test-content-v1"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":2,"child":3,"index":0},
          {"op":"insert-child","parent":3,"child":4,"index":0}
        ]}
        """))
    }
}
