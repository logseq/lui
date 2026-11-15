import Foundation
import SwiftUI
import Testing

@testable import LUIAppleBackend

@MainActor
@Suite("Sparse virtual list atomic contract", .serialized)
struct LUISparseVirtualContractTests {
    @Test("navigation flags follow the exact canonical finite kind set", arguments:
        ["button", "text-field", "secure-field", "input", "search-field", "textarea"])
    func galleryNavigationFlag(_ kind: String) throws {
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[{"op":"create-node","id":1,"kind":"\(kind)"},{"op":"set-prop","id":1,"property":"text","value":"Event navigation"},{"op":"set-prop","id":1,"property":"navigate-enabled","value":true}]}
        """)
        #expect(backend.model(id: 1)?.property(.navigateEnabled)?.boolValue == true)
        #expect(throws: (any Error).self) {
            try backend.apply(json: #"{"generation":2,"ops":[{"op":"create-node","id":2,"kind":"text"},{"op":"set-prop","id":2,"property":"navigate-enabled","value":true}]}"#)
        }
        #expect(backend.model(id: 2) == nil)
    }
  @Test("whole-valued item extents from the real OCaml encoder remain valid")
  func integralExtent() throws {
    let b = try backend()
    try apply([["op": "set-prop", "id": 1, "property": "item-extent", "value": 32]], to: b)
    #expect(b.model(id: 1)?.property(.itemExtent) != nil)
  }
  @Test("virtual parents accept canonical scroll and visibility requests")
  func virtualScrollProperties() throws {
    let b = try backend()
    try apply(
      [
        ["op": "set-prop", "id": 1, "property": "scroll-target", "value": "row-99999"],
        ["op": "set-prop", "id": 1, "property": "scroll-token", "value": 1],
        ["op": "set-prop", "id": 1, "property": "scroll-anchor", "value": "top"],
        ["op": "set-prop", "id": 1, "property": "scroll-animated", "value": false],
        ["op": "set-prop", "id": 1, "property": "track-visible-range", "value": true],
      ], to: b)
    #expect(b.model(id: 1)?.property(.scrollToken)?.intValue == 1)
  }
  private func backend() throws -> LUIAppleBackend {
    let backend = LUIAppleBackend()
    try backend.apply(
      json:
        #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},{"op":"create-node","id":2,"kind":"text"},{"op":"set-prop","id":2,"property":"text","value":"preserved"},{"op":"insert-child","parent":1,"child":2,"index":0}]}"#
    )
    return backend
  }

  private func metadata(
    _ count: Int = 100000, generation: Int = 1,
    indices: String = "[0]"
  ) -> [[String: Any]] {
    [
      ("virtual-total-count", count as Any), ("virtual-generation", generation as Any),
      ("virtual-indices", indices as Any),
    ].map {
      ["op": "set-prop", "id": 1, "property": $0.0, "value": $0.1]
    }
  }

  private func apply(
    _ ops: [[String: Any]], to backend: LUIAppleBackend,
    generation: Int = 2
  ) throws {
    let data = try JSONSerialization.data(withJSONObject: ["generation": generation, "ops": ops])
    try backend.apply(json: String(decoding: data, as: UTF8.self))
  }

  @Test("sparse relations validate only the final tree and permit eager transitions")
  func finalRelationsAndTransitions() throws {
    let b = try backend()
    try apply(metadata(), to: b)
    #expect(b.model(id: 1)?.property(.virtualTotalCount)?.intValue == 100000)
    #expect(b.model(id: 1)?.children == [2])
    try apply(
      [["op": "detach-subtree", "id": 2]] + metadata(0, generation: 2, indices: "[]"), to: b,
      generation: 3)
    #expect(b.model(id: 1)?.children.isEmpty == true)
    try apply(
      ["virtual-total-count", "virtual-generation", "virtual-indices"].map {
        ["op": "remove-prop", "id": 1, "property": $0]
      }, to: b, generation: 4)
    #expect(b.model(id: 1)?.property(.virtualTotalCount) == nil)
  }

  @Test("malformed and incomplete sparse metadata rolls back all preceding operations")
  func invalidRelationsAreAtomic() throws {
    let bad: [[[String: Any]]] = [
      Array(metadata().prefix(1)), Array(metadata().prefix(2)),
      metadata(-1), metadata(generation: 0), metadata(indices: "[]"),
      metadata(indices: "[0,1]"), metadata(indices: "[100000]"),
      metadata(indices: "[-1]"), metadata(indices: "[0,0]"),
      metadata(indices: "[1,0]"), metadata(indices: "[ 0]"),
      metadata(indices: "[0.0]"), metadata(indices: "[+0]"),
      metadata(indices: "null"), metadata(indices: "{}"),
      metadata() + [
        ["op": "set-prop", "id": 1, "property": "virtual-scroll-index", "value": 100000]
      ],
      metadata() + [["op": "set-prop", "id": 1, "property": "virtual-scroll-index", "value": -2]],
    ]
    for operations in bad {
      let b = try backend()
      let row = try #require(b.model(id: 2))
      #expect(throws: (any Error).self) {
        try apply(
          [
            ["op": "set-prop", "id": 2, "property": "text", "value": "rejected"],
            ["op": "create-node", "id": 3, "kind": "text"],
          ] + operations, to: b)
      }
      #expect(b.model(id: 2) === row)
      #expect(row.property(.text)?.stringValue == "preserved")
      #expect(b.model(id: 3) == nil)
      #expect(b.model(id: 1)?.children == [2])
      try apply(
        [["op": "set-prop", "id": 2, "property": "text", "value": "next valid"]], to: b,
        generation: 3)
      #expect(row.property(.text)?.stringValue == "next valid")
    }

    func set(_ id: Int, _ property: String, _ value: Any) -> [String: Any] {
      ["op": "set-prop", "id": id, "property": property, "value": value]
    }
    func source(_ id: Int, owner: Int) -> [[String: Any]] {
      [
        ["op": "create-node", "id": id, "kind": "virtual-list"],
        set(id, "virtual-total-count", 0), set(id, "virtual-generation", 1),
        set(id, "virtual-indices", "[]"), set(id, "virtual-row-keys", "[]"),
        set(id, "virtual-owner-node", owner), set(id, "virtual-owner-epoch", 1),
      ]
    }
    let nestedRow = [set(12, "virtual-total-count", 1), set(12, "virtual-indices", "[0]"),
      set(12, "virtual-row-keys", #"["nested"]"#)]
    let topologies: [[[String: Any]]] = [
      // A second source can be outside the first source's validation scope.
      source(40, owner: 10) + [["op": "insert-child", "parent": 11, "child": 40, "index": 1]],
      nestedRow + [
        ["op": "create-node", "id": 40, "kind": "column"],
        ["op": "create-node", "id": 41, "kind": "virtual-list"],
        ["op": "insert-child", "parent": 40, "child": 41, "index": 0],
        ["op": "insert-child", "parent": 12, "child": 40, "index": 0],
      ],
      nestedRow + [["op": "create-node", "id": 40, "kind": "scroll"],
        set(40, "virtual-viewport-epoch", 1)] + source(41, owner: 40) + [
        ["op": "insert-child", "parent": 40, "child": 41, "index": 0],
        ["op": "insert-child", "parent": 12, "child": 40, "index": 0],
      ],
      [
        ["op": "create-node", "id": 40, "kind": "virtual-list"],
        ["op": "remove-child", "parent": 11, "child": 12],
        ["op": "insert-child", "parent": 11, "child": 40, "index": 0],
        ["op": "insert-child", "parent": 40, "child": 12, "index": 0],
      ],
      [["op": "insert-child", "parent": 31, "child": 10, "index": 0]],
      [["op": "insert-child", "parent": 11, "child": 20, "index": 1]],
    ]
    for operations in topologies {
      let b = LUIAppleBackend()
      try apply([
        ["op": "create-node", "id": 10, "kind": "scroll"], set(10, "virtual-viewport-epoch", 1),
        ["op": "create-node", "id": 11, "kind": "column"],
        ["op": "insert-child", "parent": 10, "child": 11, "index": 0],
        ["op": "create-node", "id": 20, "kind": "scroll"], set(20, "virtual-viewport-epoch", 1),
        ["op": "create-node", "id": 30, "kind": "virtual-list"],
        ["op": "create-node", "id": 31, "kind": "virtual-list"],
        ["op": "insert-child", "parent": 30, "child": 31, "index": 0],
      ] + source(12, owner: 10) + source(22, owner: 20) + [
        ["op": "insert-child", "parent": 11, "child": 12, "index": 0],
        ["op": "insert-child", "parent": 20, "child": 22, "index": 0],
      ], to: b, generation: 1)
      let owner = try #require(b.model(id: 10))
      #expect(b.model(id: 22)?.parent == 20, "Independent owners remain supported")
      #expect(b.model(id: 31)?.parent == 30, "Opt-out standalone nesting remains unchanged")
      #expect(throws: (any Error).self) {
        try apply([set(10, "width", 999), ["op": "create-node", "id": 50, "kind": "column"]]
          + operations, to: b)
      }
      #expect(b.model(id: 10) === owner)
      #expect(owner.property(.width) == nil)
      #expect(b.model(id: 50) == nil)
      #expect(b.model(id: 40) == nil)
      #expect(b.model(id: 11)?.children == [12])
      #expect(b.model(id: 12)?.children == [])
      #expect(b.model(id: 20)?.parent == nil)
      try apply([set(10, "width", 400)], to: b, generation: 3)
      #expect(owner.property(.width)?.intValue == 400)
    }
  }

  @Test("sparse indices retain exact integers beyond double precision")
  func exactIntegerIndices() throws {
    let b = try backend()
    let index = 9_007_199_254_740_993
    try apply(
      metadata(index + 1, generation: index, indices: "[\(index)]") + [
        ["op": "set-prop", "id": 1, "property": "virtual-scroll-index", "value": index]
      ], to: b)
    #expect(b.model(id: 1)?.property(.virtualGeneration)?.intValue == index)
    #expect(b.model(id: 1)?.property(.virtualIndices)?.stringValue == "[\(index)]")
  }

  @Test("sparse metadata is restricted to the virtual parent")
  func kindAdmission() throws {
    for kind in ["column", "list", "list-item", "text-field"] {
      let b = LUIAppleBackend()
      #expect(throws: (any Error).self) {
        try apply(
          [["op": "create-node", "id": 1, "kind": kind]] + metadata(0, indices: "[]"), to: b,
          generation: 1)
      }
      #expect(b.model(id: 1) == nil)
    }
  }

  @Test("arbitrary registered extension roots need no row properties")
  func extensionRoots() throws {
    let registry = LUIAppleExtensionRegistry()
    try registry.register(
      LUIAppleExtension(identifier: "sparse-root", fingerprint: "v1") { _ in
        AnyView(Color.clear.frame(height: 32))
      })
    let b = try LUIAppleBackend(extensionRegistry: registry)
    try apply(
      [
        ["op": "create-node", "id": 1, "kind": "virtual-list"],
        ["op": "create-extension", "id": 20, "identifier": "sparse-root", "fingerprint": "v1"],
        ["op": "insert-child", "parent": 1, "child": 20, "index": 0],
      ] + metadata(indices: "[99999]"), to: b, generation: 1)
    #expect(b.extensionModel(id: 20) != nil)
    #expect(b.model(id: 1)?.children == [20])
  }
}
