(* Encode/decode coverage for the patch wire and the generated schema.
   Canonical bytes live in test/fixtures/wire and are decoded again by MyGo. *)

open Lui_protocol

let source_root () =
  match Sys.getenv_opt "DUNE_SOURCEROOT" with
  | Some root -> root
  | None ->
    let rec ascend depth dir =
      if depth > 12 then failwith "could not locate repository root"
      else if
        Sys.file_exists (Filename.concat dir "dune-project")
        && not
             (String.equal (Filename.basename dir) "_build"
             || String.equal
                  (Filename.basename (Filename.dirname dir))
                  "_build")
      then dir
      else ascend (depth + 1) (Filename.dirname dir)
    in
    ascend 0 (Sys.getcwd ())

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      really_input_string channel (in_channel_length channel))

let fixture name =
  Filename.concat (source_root ())
    (Filename.concat "test/fixtures/wire" name)

let write_fixture name bytes =
  let path = fixture name in
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
      output_string channel bytes)

let edge_text = "\000\b\012\n\r\t\"\\你好🌍"

let reject label source =
  match Lui_wire.decode_batch source with
  | exception Lui_json.Parse_error _ -> ()
  | exception exn ->
    Alcotest.failf "%s raised %s" label (Printexc.to_string exn)
  | _ -> Alcotest.failf "%s accepted malformed input" label

let float_bits value =
  match value with
  | FloatValue number -> Int64.bits_of_float number
  | _ -> Alcotest.fail "expected a float value"

let test_every_kind_and_property_round_trips () =
  let kind_ops =
    List.mapi
      (fun index kind -> CreateNode (index + 1, kind))
      Lui_wire_schema.all_node_kinds
  in
  let property_ops =
    List.mapi
      (fun index property ->
        let value =
          match index mod 4 with
          | 0 ->
            StringValue
              (if index = 0 then ""
               else if index = 4 then edge_text
               else "v" ^ string_of_int index)
          | 1 -> BoolValue (index mod 8 <> 1)
          | 2 ->
            IntValue
              (if index = 2 then max_int
               else if index = 6 then min_int
               else index - 80)
          | _ ->
            FloatValue
              (if index = 3 then 0.
               else if index = 7 then 1.
               else if index = 11 then -2.5
               else float index /. 4.)
        in
        SetProp (20_000 + index, property, value))
      Lui_wire_schema.all_properties
  in
  let structural =
    [ CreateExtension (90_0001, "", "")
    ; CreateExtension (90_0002, "ext:\"你好", "fp\\")
    ; DropNode 90_0003
    ; DetachSubtree 90_0004
    ; RemoveProp (90_0005, TextValue)
    ; SetExtensionProp (90_0006, "", StringValue "")
    ; SetExtensionProp (90_0007, "label\n\"", StringValue edge_text)
    ; SetExtensionProp (90_0008, "n", IntValue min_int)
    ; SetExtensionProp (90_0009, "n", IntValue max_int)
    ; SetExtensionProp (90_0010, "f", FloatValue 1e20)
    ; SetExtensionProp (90_0011, "b", BoolValue false)
    ; RemoveExtensionProp (90_0012, "x\\y")
    ; InsertChild (1, 2, 0)
    ; RemoveChild (min_int, max_int)
    ; MoveChild (5, 6, 2)
    ]
  in
  let depth = 64 in
  let deep =
    let rec build index acc =
      if index = depth then List.rev acc
      else
        let parent = if index = 0 then 800_000 else 800_000 + index in
        let child = 800_001 + index in
        build (index + 1)
          (InsertChild (parent, child, 0)
          :: CreateNode (child, if index mod 2 = 0 then Column else Row)
          :: acc)
    in
    CreateNode (800_000, Box) :: build 0 []
  in
  let batch =
    { generation = max_int
    ; ops = kind_ops @ property_ops @ structural @ deep
    }
  in
  let encoded = Lui_wire.encode_batch batch in
  Alcotest.(check int) "decoded generation" batch.generation
    (Lui_wire.decode_batch encoded).generation;
  Alcotest.(check bool) "every kind, property and nested child round-trips" true
    (Lui_wire.decode_batch encoded = batch);
  Alcotest.(check bool) "wire transport matches the batch" true
    (Lui_wire.transcode Lui_wire.Wire batch = batch);
  Alcotest.(check bool) "in-process transport keeps the value" true
    (Lui_wire.transcode Lui_wire.In_process batch == batch);
  if Sys.getenv_opt "LUI_WRITE_WIRE_FIXTURE" = Some "1" then
    write_fixture "canonical.json" encoded
  else
    Alcotest.(check string) "canonical fixture bytes" (read_file (fixture "canonical.json"))
      encoded

let test_scalar_edges () =
  let neg_zero = { generation = 1; ops = [ SetProp (1, Opacity, FloatValue (-0.)) ] } in
  let encoded = Lui_wire.encode_batch neg_zero in
  Alcotest.(check bool) "negative zero keeps its sign on the wire" true
    (String.ends_with ~suffix:"-0.0}]}" encoded);
  let decoded = Lui_wire.decode_batch encoded in
  (match decoded.ops with
  | [ SetProp (_, _, value) ] ->
    Alcotest.(check int64) "negative zero bits" (Int64.bits_of_float (-0.))
      (float_bits value)
  | _ -> Alcotest.fail "negative zero op missing");
  List.iter
    (fun (number, text) ->
      let batch = { generation = 0; ops = [ SetProp (1, Opacity, FloatValue number) ] } in
      let encoded = Lui_wire.encode_batch batch in
      Alcotest.(check bool) text true (Lui_wire.decode_batch encoded = batch))
    [ (0., "zero"); (1., "one"); (-2.5, "tenths")
    ; (1e20, "large magnitude"); (Float.max_float, "max finite")
    ; (Float.min_float, "min positive"); (epsilon_float, "epsilon")
    ; (Float.next_after 0. 1., "subnormal")
    ];
  let controls = String.init 32 Char.chr in
  let batch =
    { generation = min_int
    ; ops =
        [ SetProp (min_int, TextValue, StringValue "")
        ; SetProp (max_int, TextValue, StringValue controls)
        ; SetProp (0, TextValue, StringValue edge_text)
        ; SetExtensionProp (1, "", StringValue (String.make 4096 'x'))
        ]
    }
  in
  Alcotest.(check bool) "empty, controls, unicode and a long string" true
    (Lui_wire.decode_batch (Lui_wire.encode_batch batch) = batch);
  let escaped =
    {|{"generation":1,"ops":[{"op":"set-prop","id":1,"property":"text","value":"\u4f60\u597d\uD83D\uDC4B"}]}|}
  in
  (match (Lui_wire.decode_batch escaped).ops with
  | [ SetProp (_, _, StringValue text) ] ->
    Alcotest.(check string) "unicode and surrogate escapes" "你好👋" text
  | _ -> Alcotest.fail "escape decode shape")

let test_malformed_and_truncated () =
  let valid = {|{"generation":1,"ops":[{"op":"drop-node","id":1}]}|} in
  List.iter
    (fun source -> reject "truncated or empty" source)
    [ ""; "{"; "{\"generation\":1"; "{\"generation\":1,\"ops\":"
    ; "{\"generation\":1,\"ops\":["
    ; "{\"generation\":1,\"ops\":[{\"op\":\"drop-node\",\"id\":"
    ; "{\"generation\":1,\"ops\":[{\"op\":\"drop-node\",\"id\":1}"
    ; String.sub valid 0 (String.length valid - 1)
    ];
  List.iter
    (fun source -> reject "malformed batch" source)
    [ "null"; "[]"; "\"batch\""; "1"
    ; {|{"generation":1,"ops":{}}|}
    ; {|{"generation":1,"ops":null}|}
    ; {|{"generation":"1","ops":[]}|}
    ; {|{"generation":1.5,"ops":[]}|}
    ; {|{"generation":1,"ops":[null]}|}
    ; {|{"generation":1,"ops":[[]]}|}
    ; {|{"generation":1,"ops":[{}]}|}
    ; {|{"generation":1,"ops":[{"op":"invented","id":1}]}|}
    ; {|{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"not-a-kind"}]}|}
    ; {|{"generation":1,"ops":[{"op":"set-prop","id":1,"property":"not-a-property","value":1}]}|}
    ; {|{"generation":1,"ops":[{"op":"drop-node","id":1}]} trailing|}
    ; {|{"generation":1,"ops":[{"op":"drop-node","id":true}]}|}
    ; {|{"generation":1,"ops":[{"op":"drop-node","id":"1"}]}|}
    ; {|{"generation":1,"ops":[{"op":"set-prop","id":1,"property":"text","value":{"nested":1}}]}|}
    ; {|{"generation":1,"ops":[{"op":"set-prop","id":1,"property":"text","value":[1]}]}|}
    ; {|{"generation":1,"ops":[{"op":"set-prop","id":1,"property":"text","value":null}]}|}
    ; {|{"generation":9223372036854775807,"ops":[]}|}
    ; {|{"generation":1,"ops":[{"op":"drop-node","id":9223372036854775807}]}|}
    ; {|{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"text\u"}]}}|}
    ; {|{"generation":1,"ops":[{"op":"create-node","id":1,"kind":"\q"}]}|}
    ; " \t\n"
    ];
  let spaced =
    " \n{\n \"generation\" : 4 , \"ops\" : [ { \"op\" : \"drop-node\" , \"id\" : 8 } ] }\n "
  in
  Alcotest.(check bool) "insignificant whitespace" true
    (Lui_wire.decode_batch spaced = { generation = 4; ops = [ DropNode 8 ] });
  Alcotest.(check bool) "missing generation defaults to zero" true
    (Lui_wire.decode_batch {|{"ops":[]}|} = { generation = 0; ops = [] });
  Alcotest.(check bool) "missing ops defaults to none" true
    (Lui_wire.decode_batch {|{"generation":6}|} = { generation = 6; ops = [] });
  (* Encoder output never repeats a key. The decoder keeps the first
     operation field and the last generation, which is this runtime's
     contract; MyGo's encoding/json layer keeps the last field. *)
  Alcotest.(check bool) "duplicate generation keeps the last value" true
    (Lui_wire.decode_batch
       {|{"generation":1,"generation":2,"ops":[{"op":"drop-node","id":1,"id":9}]}|}
     = { generation = 2; ops = [ DropNode 1 ] })

let rec nested_unknown depth =
  if depth = 0 then "0"
  else "{\"k\":[" ^ nested_unknown (depth - 1) ^ ",null]}"

let test_forward_compat_and_schema_version () =
  let schema =
    Yojson.Basic.from_file
      (Filename.concat (source_root ()) "schema/components.json")
  in
  let member name = function
    | `Assoc fields -> List.assoc name fields
    | _ -> Alcotest.fail "schema object"
  in
  let string_field name json =
    match member name json with
    | `String value -> value
    | _ -> Alcotest.fail name
  in
  let strings json =
    match json with
    | `List items ->
      List.map
        (function
          | `String value -> value
          | _ -> Alcotest.fail "string list")
        items
    | _ -> Alcotest.fail "list"
  in
  let objects json =
    match json with
    | `List items -> items
    | _ -> Alcotest.fail "object list"
  in
  (match member "schemaVersion" schema with
  | `Int 1 -> ()
  | _ -> Alcotest.fail "schemaVersion must stay 1");
  let wire_names json key =
    objects (member key json) |> List.map (string_field "wire") |> List.sort String.compare
  in
  let kind_names =
    Lui_wire_schema.all_node_kinds
    |> List.map Lui_wire_schema.node_kind_name
    |> List.sort String.compare
  in
  let property_names =
    Lui_wire_schema.all_properties
    |> List.map Lui_wire_schema.property_name
    |> List.sort String.compare
  in
  Alcotest.(check (list string)) "node kind wire names match schema version 1"
    (wire_names schema "nodeKinds") kind_names;
  Alcotest.(check (list string)) "property wire names match schema version 1"
    (wire_names schema "properties") property_names;
  Alcotest.(check bool) "kind names are unique" true
    (List.length kind_names = List.length Lui_wire_schema.all_node_kinds);
  Alcotest.(check bool) "property names are unique" true
    (List.length property_names = List.length Lui_wire_schema.all_properties);
  List.iter
    (fun name ->
      Alcotest.(check bool) name true (Lui_wire_schema.standard_node_name name))
    kind_names;
  List.iter
    (fun name ->
      Alcotest.(check bool) name false (Lui_wire_schema.standard_node_name name))
    [ ""; "Root"; "button "; "not-a-kind"; "text\n" ];
  let public_names =
    objects (member "publicElements" schema) |> List.map (string_field "name")
  in
  (* Catalog names that are not wire node kinds: separator is the divider
     node, reactions is bubble chrome, and badge/skeleton have no kind. *)
  let public_exceptions =
    List.filter
      (fun name -> not (Lui_wire_schema.standard_node_name name))
      public_names
    |> List.sort String.compare
  in
  Alcotest.(check (list string)) "public elements without a node kind"
    [ "badge"; "reactions"; "separator"; "skeleton" ]
    public_exceptions;
  let named_lists key =
    match member key schema with
    | `Assoc fields ->
      List.map
        (fun (name, value) -> (name, strings value |> List.sort String.compare))
        fields
      |> List.sort (fun (a, _) (b, _) -> String.compare a b)
    | _ -> Alcotest.fail key
  in
  let ocaml_matrix =
    Lui_wire_schema.all_node_kinds
    |> List.filter_map (fun kind ->
           match Lui_wire_schema.kind_property_matrix kind with
           | None -> None
           | Some properties ->
             Some
               ( Lui_wire_schema.node_kind_name kind
               , properties |> List.map Lui_wire_schema.property_name
                 |> List.sort String.compare ))
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  in
  let ocaml_extras =
    Lui_wire_schema.all_node_kinds
    |> List.filter_map (fun kind ->
           match Lui_wire_schema.kind_extra_properties kind with
           | [] -> None
           | properties ->
             Some
               ( Lui_wire_schema.node_kind_name kind
               , properties |> List.map Lui_wire_schema.property_name
                 |> List.sort String.compare ))
    |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  in
  let pair = Alcotest.(list (pair string (list string))) in
  Alcotest.check pair "kind property matrix matches the schema"
    (named_lists "kindProperties") ocaml_matrix;
  Alcotest.check pair "kind extra properties match the schema"
    (named_lists "kindExtraProperties") ocaml_extras;
  let without_contract = [ Root; ListSectionHeader; ListSectionFooter ] in
  List.iter
    (fun kind ->
      let present = Lui_wire_schema.view_contract kind <> None in
      let expected = not (List.mem kind without_contract) in
      Alcotest.(check bool)
        ("view contract " ^ Lui_wire_schema.node_kind_name kind)
        expected present)
    Lui_wire_schema.all_node_kinds;
  List.iter
    (fun name ->
      Alcotest.(check bool) name true
        (Lui_wire_schema.extension_view_contract name <> None))
    [ "split-view"; "split-branch"; "split-pane"; "split-tab" ];
  Alcotest.(check bool) "unknown extension" false
    (Lui_wire_schema.extension_view_contract "not-an-extension" <> None);
  let compat = read_file (fixture "compat.json") in
  let batch = Lui_wire.decode_batch compat in
  Alcotest.(check int) "compat generation" 3 batch.generation;
  (match batch.ops with
  | [ DropNode 1
    ; SetExtensionProp (2, "label", StringValue "你好🌍")
    ; SetProp (3, Opacity, FloatValue number)
    ] ->
    Alcotest.(check int64) "compat negative zero" (Int64.bits_of_float (-0.))
      (Int64.bits_of_float number)
  | _ -> Alcotest.fail "compat ops");
  let deep =
    "{\"schemaVersion\":1,\"meta\":" ^ nested_unknown 32
    ^ ",\"generation\":9,\"ops\":[{\"op\":\"detach-subtree\",\"id\":4,\"trace\":"
    ^ nested_unknown 8 ^ "}]}"
  in
  Alcotest.(check bool) "deep unknown nesting is skipped" true
    (Lui_wire.decode_batch deep
     = { generation = 9; ops = [ DetachSubtree 4 ] })

let test_random_batches_round_trip () =
  let kinds = Array.of_list Lui_wire_schema.all_node_kinds in
  let properties = Array.of_list Lui_wire_schema.all_properties in
  let state = ref 0x5A17C0DEl in
  let next () =
    state := Int32.(logxor !state (shift_left !state 13));
    state := Int32.(logxor !state (shift_right_logical !state 17));
    state := Int32.(logxor !state (shift_left !state 5));
    Int32.to_int !state land 0x7fffffff
  in
  let pick items = items.(next () mod Array.length items) in
  let random_string () =
    match next () mod 6 with
    | 0 -> ""
    | 1 -> edge_text
    | 2 -> String.init (next () mod 24) (fun _ -> Char.chr (32 + (next () mod 95)))
    | 3 -> "你好"
    | 4 -> String.make (next () mod 8) '\000'
    | _ -> "a\\b\"c\n"
  in
  let random_value () =
    match next () mod 4 with
    | 0 -> StringValue (random_string ())
    | 1 -> BoolValue (next () mod 2 = 0)
    | 2 ->
      IntValue
        (match next () mod 5 with
        | 0 -> 0
        | 1 -> min_int
        | 2 -> max_int
        | 3 -> -1
        | _ -> next () - 40_000)
    | _ ->
      FloatValue
        (match next () mod 5 with
        | 0 -> 0.
        | 1 -> 1.
        | 2 -> -2.5
        | 3 -> float (next () mod 1000)
        | _ -> 1e20)
  in
  let random_op () =
    match next () mod 11 with
    | 0 -> CreateNode (next (), pick kinds)
    | 1 -> CreateExtension (next (), random_string (), random_string ())
    | 2 -> DropNode (next ())
    | 3 -> DetachSubtree (next ())
    | 4 -> SetProp (next (), pick properties, random_value ())
    | 5 -> RemoveProp (next (), pick properties)
    | 6 -> SetExtensionProp (next (), random_string (), random_value ())
    | 7 -> RemoveExtensionProp (next (), random_string ())
    | 8 -> InsertChild (next (), next (), next () mod 8)
    | 9 -> RemoveChild (next (), next ())
    | _ -> MoveChild (next (), next (), next () mod 8)
  in
  for case = 0 to 79 do
    let count = next () mod 12 in
    let batch = { generation = next (); ops = List.init count (fun _ -> random_op ()) } in
    let decoded = Lui_wire.decode_batch (Lui_wire.encode_batch batch) in
    if decoded <> batch then
      Alcotest.failf "random batch %d failed to round-trip" case
  done

let () =
  Alcotest.run "lui wire"
    [ ( "round trip"
      , [ Alcotest.test_case "every kind, property, edge and deep tree" `Quick
            test_every_kind_and_property_round_trips
        ; Alcotest.test_case "scalar edges and escapes" `Quick test_scalar_edges
        ; Alcotest.test_case "random batches" `Quick test_random_batches_round_trip
        ] )
    ; ( "rejection"
      , [ Alcotest.test_case "malformed and truncated input" `Quick
            test_malformed_and_truncated
        ] )
    ; ( "schema"
      , [ Alcotest.test_case "version, names and forward compatible extras" `Quick
            test_forward_compat_and_schema_version
        ] )
    ]
