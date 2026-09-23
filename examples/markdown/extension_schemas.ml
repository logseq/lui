(* Extension schema for the markdown editor example.

   Hand-written (the gallery equivalent is generated): one `markdown-editor`
   component that mounts a native editing surface on Apple hosts. The host
   mirrors this declaration in MarkdownExtensions.swift — the fingerprint
   literal there must equal `Lui_extension.fingerprint markdown_editor_schema`,
   enforced by the "extension fingerprints" runtest case. *)

open Lui_protocol

let apple_profiles =
  [
    { profile_os = MacOS; profile_host = SwiftUIHost };
    { profile_os = IOS; profile_host = SwiftUIHost };
  ]

let markdown_editor_schema =
  Lui_extension.component "markdown-editor" apple_profiles false []
    [
      Lui_extension.property "text" Lui_extension.StringScalar true None;
      Lui_extension.property "placeholder" Lui_extension.StringScalar false
        None;
      Lui_extension.property "readonly" Lui_extension.BoolScalar false None;
    ]
    [
      Lui_extension.event "text-changed"
        [
          Lui_extension.event_field "text" Lui_extension.StringScalar true;
          Lui_extension.event_field "caret" Lui_extension.IntScalar false;
        ];
      Lui_extension.event "cursor"
        [
          Lui_extension.event_field "caret" Lui_extension.IntScalar false;
        ];
      Lui_extension.event "path-changed"
        [
          Lui_extension.event_field "path" Lui_extension.StringScalar true;
        ];
    ]

let registry () =
  let registry = Lui_extension.registry () in
  Lui_extension.register_component registry markdown_editor_schema;
  Lui_extension.freeze registry;
  registry

let markdown_editor ?key ?text ?text_signal ?placeholder ?readonly ~on_event ()
    : Lui_elements.t =
 fun context parent ->
  let node = Lui_ui.extension context "markdown-editor" in
  Option.iter (Lui_ui.key context node) key;
  Option.iter
    (fun value ->
       Lui_ui.extension_property context node "text" (StringValue value))
    text;
  Option.iter
    (fun signal ->
       Lui_ui.extension_property_signal context node "text"
         (Signal.map (fun value -> StringValue value) signal))
    text_signal;
  Option.iter
    (fun value ->
       Lui_ui.extension_property context node "placeholder"
         (StringValue value))
    placeholder;
  Option.iter
    (fun value ->
       Lui_ui.extension_property context node "readonly" (BoolValue value))
    readonly;
  (match parent with
   | Some parent -> Lui_ui.append context parent node
   | None -> ());
  Lui_ui.on_event context node on_event;
  node
