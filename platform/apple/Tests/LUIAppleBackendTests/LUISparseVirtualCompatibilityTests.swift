import Testing
@testable import LUIAppleBackend

@MainActor
@Suite("Eager virtual list host compatibility", .serialized)
struct LUISparseVirtualCompatibilityTests {
    @Test("unsupported sparse metadata rejects the entire batch")
    func sparseMetadataIsRejectedAtomically() throws {
        let properties = [
            #""virtual-total-count","value":100000"#,
            #""virtual-generation","value":1"#,
            #""virtual-indices","value":"[0]""#,
            #""virtual-scroll-index","value":99999"#,
        ]
        for property in properties {
            let backend = LUIAppleBackend()
            try backend.apply(json: #"{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"virtual-list"},{"op":"set-prop","id":1,"property":"overscan","value":0},{"op":"set-prop","id":1,"property":"item-extent","value":24.5},{"op":"create-node","id":2,"kind":"list-item"},{"op":"set-prop","id":2,"property":"text","value":"Eager row"},{"op":"insert-child","parent":1,"child":2,"index":0}]}"#)
            let original = try #require(backend.model(id: 2))
            #expect(throws: (any Error).self) {
                try backend.apply(json: """
                {"generation":2,"ops":[
                  {"op":"set-prop","id":2,"property":"text","value":"must roll back"},
                  {"op":"create-node","id":3,"kind":"list-item"},
                  {"op":"set-prop","id":1,"property":\(property)}
                ]}
                """)
            }
            #expect(backend.model(id: 2) === original)
            #expect(original.property(.text)?.stringValue == "Eager row")
            #expect(backend.model(id: 1)?.children == [2])
            #expect(backend.model(id: 3) == nil)
            let propertyName = property.prefix { $0 != "," }
            #expect(throws: (any Error).self) {
                try backend.apply(json: """
                {"generation":3,"ops":[
                  {"op":"set-prop","id":2,"property":"text","value":"must also roll back"},
                  {"op":"remove-prop","id":1,"property":\(propertyName)}
                ]}
                """)
            }
            #expect(original.property(.text)?.stringValue == "Eager row")
            try backend.apply(json: #"{"generation":4,"ops":[{"op":"set-prop","id":2,"property":"text","value":"Eager update"}]}"#)
            #expect(backend.model(id: 2)?.property(.text)?.stringValue == "Eager update")
        }
    }
}
