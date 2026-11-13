import Foundation
import Testing
@testable import LUIAppleBackend

@MainActor
struct LUIAdmissionContractTests {
    @Test("Absolute split width preserves point units for layout and events")
    func absoluteSplitWidth() throws {
        for (value, available, expected) in [(246.0, 800.0, 246.0), (0, 800, 0), (900, 800, 800)] {
            #expect(LUISplitGeometry.firstPaneWidth(value: value, absolute: true,
                available: available, firstMinimum: 0, secondMinimum: 0) == expected)
        }
        #expect(LUISplitGeometry.firstPaneWidth(value: 246, absolute: true,
            available: 800, firstMinimum: 300, secondMinimum: 200) == 300)
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"split"},
          {"op":"set-prop","id":1,"property":"first-pane-width","value":246},
          {"op":"set-prop","id":1,"property":"change-enabled","value":true},
          {"op":"create-node","id":2,"kind":"box"},
          {"op":"create-node","id":3,"kind":"box"},
          {"op":"insert-child","parent":1,"child":2,"index":0},
          {"op":"insert-child","parent":1,"child":3,"index":1}
        ]}
        """)
        var events: [LUIEvent] = []
        backend.onEvent = { events.append($0) }
        try backend.performValueChange(node: 1, value: 280)
        #expect(events == [.valueChanged(node: 1, value: 280)])
        #expect(throws: LUIBackendError.self) {
            try backend.apply(json: """
            {"generation":2,"ops":[{"op":"set-prop","id":1,"property":"value","value":0.5}]}
            """)
        }
    }

    #if os(macOS)
    @Test("Canonical OCaml values are admitted independently of renderer support")
    func canonicalAdmission() throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("schema/apple-property-admission.json"))
        let contract = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let values = try #require(contract["values"] as? [[String: Any]])
        let properties = try #require(contract["properties"] as? [String: String])
        let kindValues = try #require(contract["kindValues"] as? [String: [String: String]])
        let kinds = try #require(contract["kinds"] as? [String: [String]])
        var failures: Set<String> = []
        for (kindName, names) in kinds {
            let kind = try #require(LUINodeKind(rawValue: kindName))
            for name in names {
                let property = try #require(LUIProperty(rawValue: name))
                let verdict = try #require(kindValues[kindName]?[name] ?? properties[name])
                for (index, bit) in verdict.enumerated() where bit == "1" {
                    let entry = values[index]
                    let value: LUIWireValue
                    switch entry["type"] as? String {
                    case "string": value = .string(try #require(entry["value"] as? String))
                    case "bool": value = .bool(try #require(entry["value"] as? Bool))
                    case "int": value = .int(try #require(entry["value"] as? Int))
                    default: value = .double(try #require(entry["value"] as? Double))
                    }
                    if !value.normalized(for: property).matches(property, on: kind) {
                        failures.insert("\(name)=\(value)")
                    }
                }
            }
        }
        #expect(failures.isEmpty, "Canonical admission refused: \(failures.sorted())")
        let backend = LUIAppleBackend()
        try backend.apply(json: """
        {"generation":1,"ops":[
          {"op":"create-node","id":1,"kind":"button"},
          {"op":"set-prop","id":1,"property":"text","value":"Action"},
          {"op":"set-prop","id":1,"property":"gap","value":4},
          {"op":"set-prop","id":1,"property":"press-enabled","value":true},
          {"op":"set-prop","id":1,"property":"size","value":"icon"},
          {"op":"set-prop","id":1,"property":"position","value":"sticky"},
          {"op":"create-node","id":2,"kind":"icon"},
          {"op":"set-prop","id":2,"property":"name","value":"check"},
          {"op":"set-prop","id":2,"property":"opacity","value":0.7},
          {"op":"create-node","id":3,"kind":"split"},
          {"op":"set-prop","id":3,"property":"first-pane-width","value":246},
          {"op":"set-prop","id":3,"property":"resize-handle-width","value":0},
          {"op":"create-node","id":4,"kind":"box"},
          {"op":"create-node","id":5,"kind":"box"},
          {"op":"insert-child","parent":3,"child":4,"index":0},
          {"op":"insert-child","parent":3,"child":5,"index":1}
        ]}
        """)
        #expect(backend.generation == 1)
    }
    #endif
}
