#if canImport(AppKit)
import AppKit
import LUIAppleBackend
import SwiftUI

// The fingerprint mirrors `Extension_schemas.markdown_editor_schema` on the
// OCaml side — test_lui.ml's "extension fingerprints" check fails if they
// drift.
@MainActor
func markdownExtensionRegistry() -> LUIAppleExtensionRegistry {
    let registry = LUIAppleExtensionRegistry()
    do {
        try registry.register(
            LUIAppleExtension(
                identifier: "markdown-editor",
                fingerprint:
                    "lui-extension-v1|15:markdown-editor|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:|properties:11:placeholder:string:optional:none,4:text:string:required:none,8:readonly:bool:optional:none|events:12:path-changed[4:path:string:required],12:text-changed[4:text:string:required,5:caret:int:optional],6:cursor[5:caret:int:optional]",
                properties: [
                    LUIExtensionProperty(name: "text", kind: .string, isRequired: true),
                    LUIExtensionProperty(name: "placeholder", kind: .string),
                    LUIExtensionProperty(name: "readonly", kind: .bool),
                ],
                events: [
                    LUIExtensionEvent(name: "text-changed", fields: [
                        LUIExtensionEventField(name: "text", kind: .string, isRequired: true),
                        LUIExtensionEventField(name: "caret", kind: .int),
                    ]),
                    LUIExtensionEvent(name: "cursor", fields: [
                        LUIExtensionEventField(name: "caret", kind: .int),
                    ]),
                    LUIExtensionEvent(name: "path-changed", fields: [
                        LUIExtensionEventField(name: "path", kind: .string, isRequired: true),
                    ]),
                ]
            ) { context in
                AnyView(MarkdownEditorView(context: context))
            }
        )
        try registry.freeze()
    } catch {
        assertionFailure("markdown extension registry failed: \(error)")
    }
    return registry
}

// Host-side flat encoding matching Lui_json.parse_values on the OCaml side.
func luiExtensionValuesJSON(_ values: [String: LUIExtensionValue]) -> String {
    func escape(_ string: String) -> String {
        var result = ""
        for scalar in string.unicodeScalars {
            switch scalar {
            case "\\": result += "\\\\"
            case "\"": result += "\\\""
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
    let fields = values
        .sorted { $0.key < $1.key }
        .map { name, value -> String in
            switch value {
            case let .string(text):
                return "\"\(escape(name))\":\"\(escape(text))\""
            case let .bool(flag):
                return "\"\(escape(name))\":\(flag ? "true" : "false")"
            case let .int(number):
                return "\"\(escape(name))\":\(number)"
            case let .double(number):
                return "\"\(escape(name))\":\(number)"
            }
        }
    return "{\(fields.joined(separator: ","))}"
}
#endif
