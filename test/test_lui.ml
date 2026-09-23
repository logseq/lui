(* Smoke tests for the lui OCaml runtime: protocol helpers, the element DSL,
   and the Lui_app reducer-app lifecycle against a recording backend. *)

let batches = ref []

let recording_backend () =
  batches := [];
  {
    Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch = (fun batch -> batches := batch :: !batches; true);
  }

let all_ops () = List.concat_map (fun (b : Lui_protocol.patch_batch) -> b.ops)
                   (List.rev !batches)

let flush_app app = ignore (Lui_app.flush app)

let todo_view _context model_source send =
  let items = Signal.sample model_source in
  Lui_elements.column ~gap:8
    (Lui_elements.text ~value:"Todos" []
     :: List.map
          (fun (item : string) ->
             Lui_elements.row
               [ Lui_elements.text ~value:item [];
                 Lui_elements.button ~text:"Done"
                   ~on_press:(Lui_elements.press send (`Done item)) [] ])
          items)

let test_app_lifecycle () =
  let app =
    Lui_app.create (recording_backend ()) [ "write tests" ]
      (fun model action ->
         match action with
         | `Done item -> List.filter (fun x -> x <> item) model
         | `Add item -> model @ [ item ])
      todo_view
  in
  Alcotest.(check bool) "not disposed" false (Lui_app.disposed app);
  Alcotest.(check bool) "start" true (Lui_app.start app);
  Alcotest.(check bool) "send" true (Lui_app.send app (`Add "ship it"));
  flush_app app;
  Alcotest.(check (list string)) "model updated"
    [ "write tests"; "ship it" ] (Lui_app.model app);
  Alcotest.(check bool) "send done" true
    (Lui_app.send app (`Done "write tests"));
  flush_app app;
  Alcotest.(check (list string)) "model after done" [ "ship it" ]
    (Lui_app.model app);
  Alcotest.(check bool) "dispose" true (Lui_app.dispose app);
  Alcotest.(check bool) "disposed" true (Lui_app.disposed app);
  Alcotest.(check bool) "send after dispose" false
    (Lui_app.send app (`Add "ignored"))

let test_backend_receives_patches () =
  let app =
    Lui_app.create (recording_backend ()) []
      (fun model _action -> model)
      todo_view
  in
  ignore (Lui_app.start app);
  flush_app app;
  let ops = all_ops () in
  Alcotest.(check bool) "column created" true
    (List.exists
       (function Lui_protocol.CreateNode (_, Lui_protocol.Column) -> true
               | _ -> false)
       ops);
  Alcotest.(check bool) "batches non-empty" true (ops <> []);
  Alcotest.(check bool) "generations positive" true
    (List.for_all (fun (b : Lui_protocol.patch_batch) -> b.generation > 0)
       !batches);
  ignore (Lui_app.dispose app)

let test_protocol_helpers () =
  Alcotest.(check bool) "modal dialog" true
    (Lui_protocol.modal_surface Lui_protocol.Dialog);
  Alcotest.(check bool) "row not modal" false
    (Lui_protocol.modal_surface Lui_protocol.Row);
  Alcotest.(check bool) "row is container" true
    (Lui_protocol.tree_row_kind Lui_protocol.Row);
  Alcotest.(check bool) "event node" true
    (Lui_protocol.event_node (Lui_protocol.Press 7) = 7);
  let profile = Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.SwiftUIHost in
  Alcotest.(check bool) "profile os" true
    (profile.profile_os = Lui_protocol.MacOS)

(* Extension fingerprint sync: the gallery declares its extension schemas
   once in Extension_schemas (OCaml); host apps mirror the canonical
   fingerprint strings as literals. Lui_extension_check compares the two so
   drift fails here instead of surfacing as a runtime "extension fingerprint
   mismatch" blank screen. *)

let source_root () =
  match Sys.getenv_opt "DUNE_SOURCEROOT" with
  | Some root -> root
  | None ->
    let rec ascend depth dir =
      if depth > 12 then
        failwith "could not locate repository root (dune-project)"
      else if
        Sys.file_exists (Filename.concat dir "dune-project")
        && not
             (String.equal (Filename.basename dir) "_build"
             || String.equal (Filename.basename (Filename.dirname dir))
                  "_build")
      then dir
      else ascend (depth + 1) (Filename.dirname dir)
    in
    ascend 0 (Sys.getcwd ())

let read_file path =
  let channel = open_in_bin path in
  let contents =
    really_input_string channel (in_channel_length channel)
  in
  close_in channel;
  contents

let gallery_source () =
  read_file
    (Filename.concat (source_root ())
       "examples/components/ios-swiftui/Sources/LUIComponentsApp/GalleryExtensions.swift")

let contains source pattern =
  let n = String.length pattern in
  let last = String.length source - n in
  let rec loop i = i <= last && (String.sub source i n = pattern || loop (i + 1)) in
  loop 0

let replace_first source pattern replacement =
  let n = String.length pattern in
  let last = String.length source - n in
  let rec loop i =
    if i > last then None
    else if String.sub source i n = pattern then
      Some
        (String.sub source 0 i ^ replacement
        ^ String.sub source (i + n) (String.length source - i - n))
    else loop (i + 1)
  in
  loop 0

let gallery_schema identifier =
  let registry = Extension_schemas.registry () in
  match Lui_extension.schema registry identifier with
  | Some schema -> schema
  | None -> Alcotest.fail ("unregistered schema " ^ identifier)

let test_fingerprint_format () =
  Alcotest.(check string) "apple-map fingerprint"
    "lui-extension-v1|9:apple-map|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:16:apple-map-marker|properties:14:latitude-delta:float:required:none,15:longitude-delta:float:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:"
    (Lui_extension.fingerprint (gallery_schema "apple-map"));
  Alcotest.(check string) "marker fingerprint"
    "lui-extension-v1|16:apple-map-marker|profiles:ios/swiftui,macos/swiftui|standard-children:0|children:|properties:5:title:string:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:"
    (Lui_extension.fingerprint (gallery_schema "apple-map-marker"));
  Alcotest.(check string) "tweak fingerprint"
    "lui-tweak-v1|14:gallery-accent|profiles:android/flutter,ios/flutter,ios/swiftui,linux/flutter,macos/flutter,macos/swiftui,web/web,windows/flutter|properties:"
    (Lui_extension.tweak_fingerprint (gallery_schema "gallery-accent"))

let test_host_literals_in_sync () =
  let registry = Extension_schemas.registry () in
  match
    Lui_extension_check.check_registry registry (gallery_source ())
  with
  | [] -> ()
  | mismatches ->
    Alcotest.failf "extension fingerprint drift:\n%s"
      (Lui_extension_check.describe_mismatches mismatches)

let test_drift_is_caught () =
  let registry = Extension_schemas.registry () in
  let source = gallery_source () in
  (* Drop the marker child from apple-map's host literal only. *)
  let drifted =
    match
      replace_first source "|children:16:apple-map-marker|" "|children:|"
    with
    | Some value -> value
    | None -> Alcotest.fail "gallery source did not contain the expected literal"
  in
  (match Lui_extension_check.check_registry registry drifted with
   | [ Lui_extension_check.Drifted { declaration; expected } ] ->
     Alcotest.(check string) "drifted identifier" "apple-map"
       declaration.host_identifier;
     Alcotest.(check bool) "expected keeps the child" true
       (contains expected "16:apple-map-marker")
   | _ -> Alcotest.fail "expected exactly one drifted fingerprint");
  (* A host literal for an extension the OCaml side never declared. *)
  let undeclared =
    source
    ^ "\n    fingerprint: \"lui-extension-v1|8:fake-map|profiles:ios/swiftui|standard-children:0|children:|properties:|events:\"\n"
  in
  (match Lui_extension_check.check_registry registry undeclared with
   | [ Lui_extension_check.Undeclared_identifier declaration ] ->
     Alcotest.(check string) "undeclared identifier" "fake-map"
       declaration.host_identifier
   | _ -> Alcotest.fail "expected exactly one undeclared identifier");
  (* Dart host registrations use single-quoted literals: same extraction. *)
  let dart_source =
    "LUIFlutterExtension(\n\
    \  identifier: 'apple-map',\n\
    \  fingerprint: 'lui-extension-v1|9:apple-map|profiles:ios/swiftui,macos/swiftui|standard-children:1|children:16:apple-map-marker|properties:14:latitude-delta:float:required:none,15:longitude-delta:float:required:none,8:latitude:float:required:none,9:longitude:float:required:none|events:',\n\
    \  builder: (_) => const SizedBox.shrink(),\n\
    )"
  in
  match Lui_extension_check.check_registry registry dart_source with
  | [ Lui_extension_check.Drifted { declaration; expected } ] ->
    Alcotest.(check string) "dart identifier" "apple-map"
      declaration.host_identifier;
    Alcotest.(check bool) "expected has standard-children:0" true
      (contains expected "standard-children:0")
  | _ -> Alcotest.fail "expected exactly one drifted Dart fingerprint"

let () =
  Alcotest.run "lui"
    [
      ( "app",
        [
          Alcotest.test_case "lifecycle" `Quick test_app_lifecycle;
          Alcotest.test_case "backend patches" `Quick
            test_backend_receives_patches;
        ] );
      ( "protocol",
        [ Alcotest.test_case "helpers" `Quick test_protocol_helpers ] );
      ( "extension fingerprints",
        [
          Alcotest.test_case "canonical format" `Quick
            test_fingerprint_format;
          Alcotest.test_case "host literals in sync" `Quick
            test_host_literals_in_sync;
          Alcotest.test_case "drift is caught" `Quick test_drift_is_caught;
        ] );
    ]
