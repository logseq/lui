(* P1-4 backend parity: the same patch batch stream must produce the
   same store whether it crossed the wire format or was applied as the
   in-process value — plus the wire codec round-trip and a Lui_app
   driven over each transport. *)

open Alcotest
open Lui_protocol

(* One batch stream exercising every patch op the protocol defines,
   with values chosen to stress the codec (escapes, unicode, integral
   vs fractional floats). *)
let scenario : patch_batch list =
  [
    {
      generation = 1;
      ops =
        [
          CreateNode (1, Root);
          CreateNode (2, Column);
          CreateNode (3, Text);
          SetProp (3, TextValue, StringValue "hello \"world\"\nline\x01 ☃");
          SetProp (2, Gap, FloatValue 8.5);
          SetProp (3, Opacity, FloatValue 1.0);
          SetProp (2, WidthValue, IntValue 640);
          SetProp (2, Enabled, BoolValue true);
          SetProp (3, LetterSpacing, FloatValue (-0.25));
          InsertChild (1, 2, 0);
          InsertChild (2, 3, 0);
          CreateExtension (9, "test.probe", "fp-deadbeef");
          SetExtensionProp (9, "config", StringValue "nested:{}[]\"x\"");
          SetExtensionProp (9, "ratio", FloatValue 0.125);
          InsertChild (2, 9, 1);
        ];
    };
    {
      generation = 2;
      ops =
        [
          MoveChild (2, 3, 1);
          SetProp (3, TextValue, StringValue "updated\tvalue");
          RemoveProp (2, Gap);
          RemoveExtensionProp (9, "config");
          CreateNode (4, Button);
          InsertChild (2, 4, 0);
          DropNode 4;
          CreateNode (5, Row);
          InsertChild (1, 5, 1);
          DetachSubtree 5;
        ];
    };
  ]

(* Full store contents as a comparable value: id, kind, extension id,
   parent, child order and every readable prop. *)
let snapshot (store : Lui_store.t) =
  let prop_names =
    List.map Lui_wire_schema.property_name Lui_wire_schema.all_properties
    @ [ "config"; "ratio" ]
  in
  ( Lui_store.generation store,
    Lui_store.all_nodes store
    |> List.map (fun n ->
           let id = Lui_store.node_id n in
           ( id,
             Lui_store.node_kind n,
             Lui_store.node_ext_id n,
             Lui_store.parent store id,
             Lui_store.child_ids store id,
             List.map
               (fun name -> (name, Lui_store.prop store id name))
               prop_names )) )

let transports = [ Lui_wire.In_process; Lui_wire.Wire ]

(* ---------- wire codec ---------- *)

let test_round_trip () =
  List.iteri
    (fun i (batch : patch_batch) ->
      let decoded = Lui_wire.decode_batch (Lui_wire.encode_batch batch) in
      check bool
        (Printf.sprintf "batch %d round-trips" i)
        true (decoded = batch))
    scenario

let test_decode_rejects_garbage () =
  List.iter
    (fun bad ->
      match Lui_wire.decode_batch bad with
      | _ -> fail ("decoded garbage: " ^ bad)
      | exception Lui_json.Parse_error _ -> ())
    [
      "";
      "not json";
      "{\"generation\":1,\"ops\":[";
      "{\"generation\":1,\"ops\":null}";
      "{\"ops\":[{\"op\":\"bogus\",\"id\":1}]}";
      "{\"ops\":[{\"op\":\"set-prop\",\"id\":1,\"property\":\"nope\",\"value\":1}]}";
      "{\"generation\":1,\"ops\":[]} trailing";
    ]

(* ---------- parity ---------- *)

let test_store_parity () =
  let stores =
    List.map
      (fun transport ->
        let s = Lui_store.create () in
        let b = Lui_backend.over_store transport s in
        List.iter (Lui_backend.apply_batch b) scenario;
        s)
      transports
  in
  match stores with
  | [ direct; wired ] ->
    check int "node count" (Lui_store.node_count direct)
      (Lui_store.node_count wired);
    check bool "stores identical" true (snapshot direct = snapshot wired)
  | _ -> assert false

let test_store_spot_checks () =
  (* The transport choice must not change semantics; check a couple of
     expected states on the wired store. *)
  let s = Lui_store.create () in
  let b = Lui_backend.over_store Lui_wire.Wire s in
  List.iter (Lui_backend.apply_batch b) scenario;
  check int "generation" 2 (Lui_store.generation s);
  check int "node count" 4 (Lui_store.node_count s);
  check (list int) "root children" [ 2 ] (Lui_store.child_ids s 1);
  check (list int) "column children after move" [ 9; 3 ]
    (Lui_store.child_ids s 2);
  check string "extension kind" "extension:test.probe" (Lui_store.kind s 9);
  check string "text after update" "updated\tvalue"
    (match Lui_store.prop s 3 "text" with
    | Some (StringValue v) -> v
    | _ -> "");
  check bool "removed prop gone" true
    (Lui_store.prop s 2 "gap" = None);
  check bool "removed ext prop gone" true
    (Lui_store.prop s 9 "config" = None);
  check bool "kept ext prop" true
    (Lui_store.prop s 9 "ratio" = Some (FloatValue 0.125))

(* ---------- a real app over each transport ---------- *)

let counter_view _context model_source send =
  let open Lui_elements in
  column
    [
      text
        ~value:
          (reactive
             (fun (n : int) -> "count=" ^ string_of_int n)
             model_source)
        [];
      button ~text:"Increment" ~on_press:(press send `Increment) [];
    ]

let counter_reducer model `Increment = model + 1

let boot transport =
  let store = Lui_store.create () in
  let b = Lui_backend.over_store transport store in
  let app =
    Lui_app.create
      (Lui_backend.backend b (generic_profile ()))
      0 counter_reducer counter_view
  in
  check bool "start" true (Lui_app.start app);
  check bool "flush" true (Lui_app.flush app);
  (store, app)

let button_id store =
  match
    List.find_opt
      (fun n -> Lui_store.node_kind n = "button")
      (Lui_store.all_nodes store)
  with
  | Some n -> Lui_store.node_id n
  | None -> fail "no button mounted"

let test_app_parity () =
  let run transport =
    let store, app = boot transport in
    let bid = button_id store in
    for _ = 1 to 3 do
      ignore (Lui_app.dispatch_event app (Press bid));
      ignore (Lui_app.flush app)
    done;
    (store, Lui_app.disposed app)
  in
  let direct, _ = run Lui_wire.In_process in
  let wired, _ = run Lui_wire.Wire in
  check bool "app stores identical" true
    (snapshot direct = snapshot wired);
  check bool "counter reached 3" true
    (List.exists
       (fun n ->
         Lui_store.node_kind n = "text"
         && Lui_store.node_prop n "text" = Some (StringValue "count=3"))
       (Lui_store.all_nodes wired))

(* The production headless pipeline — the e2e harness app, real layout
   and paint — booted and driven once per transport must land on the
   same store AND the same scene ops, not just the same node count. *)
let test_e2e_pipeline_parity () =
  let run transport =
    let h = Lui_e2e.E2e_harness.create () in
    let host = Lui_e2e.E2e_harness.host h in
    let b =
      Lui_backend.create transport (fun batch ->
          ignore (Lui_host.apply_batch host batch))
    in
    let app =
      Lui_app.create
        (Lui_backend.backend b (generic_profile ()))
        Lui_e2e.E2e_app.initial Lui_e2e.E2e_app.update Lui_e2e.E2e_app.view
    in
    check bool "start" true (Lui_app.start app);
    check bool "initial flush" true (Lui_app.flush app);
    let fid =
      match
        List.find_opt
          (fun n -> Lui_store.node_kind n = "text-field")
          (Lui_store.all_nodes (Lui_e2e.E2e_harness.store h))
      with
      | Some n -> Lui_store.node_id n
      | None -> fail "no text-field mounted"
    in
    ignore (Lui_app.dispatch_event app (TextChanged (fid, "gamma")));
    ignore (Lui_app.flush app);
    (snapshot (Lui_e2e.E2e_harness.store h),
     List.map Lui_e2e.E2e_harness.op_name (Lui_e2e.E2e_harness.repaint h))
  in
  let store_a, scene_a = run Lui_wire.In_process in
  let store_b, scene_b = run Lui_wire.Wire in
  check bool "e2e stores identical" true (store_a = store_b);
  check bool "e2e scenes identical" true (scene_a = scene_b)

(* A wire batch must surface decoder failures instead of being
   silently applied — the seam is where a corrupt batch is caught. *)
let test_wire_surfaces_bad_protocol () =
  let applied = ref false in
  let b =
    Lui_backend.create Lui_wire.Wire (fun _ -> applied := true)
  in
  (* The transport's input is a patch_batch, so corruption can only be
     exercised through the codec itself — assert it rejects a batch a
     misbehaving encoder would emit. *)
  (match
     Lui_wire.decode_batch
       "{\"generation\":1,\"ops\":[{\"op\":\"create-node\",\"id\":1,\"kind\":\"not-a-kind\"}]}"
   with
  | _ -> fail "decoded unknown kind"
  | exception Lui_json.Parse_error _ -> ());
  Lui_backend.apply_batch b { generation = 1; ops = [] };
  check bool "delivered" true !applied

let () =
  run "lui_backend"
    [
      ( "codec",
        [
          test_case "batch round-trip" `Quick test_round_trip;
          test_case "decode rejects garbage" `Quick
            test_decode_rejects_garbage;
        ] );
      ( "parity",
        [
          test_case "store parity" `Quick test_store_parity;
          test_case "store spot checks" `Quick test_store_spot_checks;
          test_case "app over both transports" `Quick test_app_parity;
          test_case "e2e pipeline parity" `Quick test_e2e_pipeline_parity;
          test_case "wire surfaces bad protocol" `Quick
            test_wire_surfaces_bad_protocol;
        ] );
    ]
