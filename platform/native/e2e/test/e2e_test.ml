(* Headless end-to-end coverage for the native backend pipeline:
   Lui_app.create → reducer_app → flush emits patch_batch →
   Lui_host.apply_batch → Lui_store mirror → Lui_paint → Lui_scene ops
   → stub renderer. Store-level create/insert/remove/move coverage
   uses hand-built patch batches on the same backend entry point. *)

open Alcotest
open Lui_e2e
open Lui_scene
open Lui_protocol

(* A custom extension renderer proving the extension dispatch path:
   emits a Hole op at the node's rect. *)
let () =
  Lui_paint.register_extension ~identifier:"test.hole"
    { paint =
        (fun _hooks _store _node r ->
          [ Hole
              { hrect = r; hradii = (0., 0., 0., 0.);
                hcontinuous = false; hopacity = 1. } ]) }

let boot () =
  let h = E2e_harness.create () in
  let backend = E2e_harness.backend h (generic_profile ()) in
  let app =
    Lui_app.create backend E2e_app.initial E2e_app.update E2e_app.view
  in
  check bool "start" true (Lui_app.start app);
  check bool "initial flush" true (Lui_app.flush app);
  (h, app)

let require_id = function
  | Some id -> id
  | None -> fail "node not found"

let kind_id store kind =
  match E2e_harness.kind_nodes store kind with
  | id :: _ -> id
  | [] -> fail ("no node of kind " ^ kind)

let ops_named name ops =
  List.filter (fun o -> E2e_harness.op_name o = name) ops

(* ---------- app pipeline ---------- *)

let test_boot_pipeline () =
  let h, _app = boot () in
  let store = E2e_harness.store h in
  check int "generation 1" 1 (Lui_store.generation store);
  check int "node count" 12 (Lui_store.node_count store);
  check (list int) "single root" [ 1 ] (Lui_store.root_ids store);
  check string "root kind" "column" (Lui_store.kind store 1);
  check int "columns" 1 (List.length (E2e_harness.kind_nodes store "column"));
  check int "texts" 3 (List.length (E2e_harness.kind_nodes store "text"));
  check int "fields" 1
    (List.length (E2e_harness.kind_nodes store "text-field"));
  check int "buttons" 5
    (List.length (E2e_harness.kind_nodes store "button"));
  check int "rows" 2 (List.length (E2e_harness.kind_nodes store "row"));
  let fid = kind_id store "text-field" in
  check string "field placeholder" "new item"
    (match Lui_store.prop store fid "placeholder" with
     | Some (StringValue s) -> s
     | _ -> "");
  check string "add button text" "add"
    (E2e_harness.text_prop store
       (require_id (E2e_harness.find_text_id store "button" "add")));
  check string "add button background" "#3366ff"
    (match Lui_store.prop store
             (require_id (E2e_harness.find_text_id store "button" "add"))
             "background" with
     | Some (StringValue s) -> s
     | _ -> "");
  check bool "repaint wanted" true (E2e_harness.wants_repaint h);
  let ops = E2e_harness.repaint h in
  check bool "repaint clears dirty" false (E2e_harness.wants_repaint h);
  check (list string) "op sequence"
    [ "glyphs"; "glyphs"; "fill"; "glyphs"; "glyphs"; "glyphs";
      "glyphs"; "glyphs"; "glyphs"; "glyphs" ]
    (E2e_harness.op_names ops);
  check int "one frame" 1 (E2e_harness.cap h).frames;
  check int "pixel bytes" (320 * 240 * 4) (E2e_harness.cap h).bytes;
  (match
     List.find_opt (function Lui_scene.Fill _ -> true | _ -> false) ops
   with
   | Some (Fill f) ->
     let add = require_id (E2e_harness.find_text_id store "button" "add") in
     let r = E2e_harness.rect_of h add in
     check int "fill r" 51 f.fcolor.r;
     check int "fill g" 102 f.fcolor.g;
     check int "fill b" 255 f.fcolor.b;
     check (float 0.001) "fill x" r.x f.frect.x;
     check (float 0.001) "fill w" r.w f.frect.w
   | _ -> fail "expected the add-button fill op")

let test_text_changed () =
  let h, app = boot () in
  let store = E2e_harness.store h in
  ignore (Lui_store.drain_dirty store);
  let fid = kind_id store "text-field" in
  check bool "dispatch text" true
    (Lui_app.dispatch_event app (TextChanged (fid, "gamma")));
  check bool "flush" true (Lui_app.flush app);
  let m : E2e_app.model = Lui_app.model app in
  check string "model draft" "gamma" m.E2e_app.draft;
  check string "field prop" "gamma" (E2e_harness.text_prop store fid);
  ignore (require_id (E2e_harness.find_text_id store "text" "items=2 draft=gamma"));
  let dirty = Lui_store.drain_dirty store in
  check bool "field marked dirty" true (List.mem fid dirty);
  let ops = E2e_harness.repaint h in
  check int "glyph ops" 9 (List.length (ops_named "glyphs" ops));
  match ops with
  | Glyphs g :: _ ->
    check int "summary len" (String.length "items=2 draft=gamma") g.gend
  | _ -> fail "first op must be the summary glyphs"

let test_press_add_remove_promote () =
  let h, app = boot () in
  let store = E2e_harness.store h in
  ignore (Lui_store.drain_dirty store);
  let fid = kind_id store "text-field" in
  ignore (Lui_app.dispatch_event app (TextChanged (fid, "gamma")));
  ignore (Lui_app.flush app);
  ignore (Lui_store.drain_dirty store);
  let add = require_id (E2e_harness.find_text_id store "button" "add") in
  check bool "dispatch press" true (Lui_app.dispatch_event app (Press add));
  check bool "flush" true (Lui_app.flush app);
  let m : E2e_app.model = Lui_app.model app in
  check (list string) "items" [ "alpha"; "beta"; "gamma" ] m.E2e_app.items;
  check int "nodes" 16 (Lui_store.node_count store);
  let kids = Lui_store.child_ids store 1 in
  check int "column children" 6 (List.length kids);
  let gamma_row = List.nth kids 5 in
  check string "gamma label" "item:gamma"
    (match Lui_store.child_ids store gamma_row with
     | c :: _ -> E2e_harness.text_prop store c
     | [] -> "");
  let dirty = Lui_store.drain_dirty store in
  check bool "new row dirty" true (List.mem gamma_row dirty);
  let ops = E2e_harness.repaint h in
  check (list string) "op sequence"
    [ "glyphs"; "glyphs"; "fill"; "glyphs"; "glyphs"; "glyphs";
      "glyphs"; "glyphs"; "glyphs"; "glyphs"; "glyphs"; "glyphs";
      "glyphs" ]
    (E2e_harness.op_names ops);

  (* promote moves the gamma row to the front of the keyed list *)
  let up = require_id (E2e_harness.find_text_id store "button" "^-gamma") in
  ignore (Lui_app.dispatch_event app (Press up));
  ignore (Lui_app.flush app);
  let m : E2e_app.model = Lui_app.model app in
  check (list string) "items reordered" [ "gamma"; "alpha"; "beta" ]
    m.E2e_app.items;
  let row_texts =
    Lui_store.child_ids store 1
    |> List.filter (fun id -> Lui_store.kind store id = "row")
    |> List.map (fun r ->
        match Lui_store.child_ids store r with
        | c :: _ -> E2e_harness.text_prop store c
        | [] -> "")
  in
  check (list string) "row order" [ "item:gamma"; "item:alpha"; "item:beta" ]
    row_texts;

  (* delete drops the row subtree from the store *)
  let beta_row =
    match Lui_store.parent store
            (require_id (E2e_harness.find_text_id store "text" "item:beta"))
    with
    | Some p -> p
    | None -> fail "beta text has no parent"
  in
  let beta_kids = Lui_store.child_ids store beta_row in
  let del = require_id (E2e_harness.find_text_id store "button" "x-beta") in
  ignore (Lui_app.dispatch_event app (Press del));
  ignore (Lui_app.flush app);
  let m : E2e_app.model = Lui_app.model app in
  check (list string) "items" [ "gamma"; "alpha" ] m.E2e_app.items;
  check int "nodes" 12 (Lui_store.node_count store);
  check bool "row gone" false (Lui_store.mem store beta_row);
  List.iter
    (fun c -> check bool "child gone" false (Lui_store.mem store c))
    beta_kids;
  let dirty = Lui_store.drain_dirty store in
  List.iter
    (fun c -> check bool "dropped id dirty" true (List.mem c dirty))
    (beta_row :: beta_kids)

let test_unsupported_event_rejected () =
  let _h, app = boot () in
  let store = E2e_harness.store _h in
  let fid = kind_id store "text-field" in
  check_raises "value change on text-field"
    (Invalid_argument "event is unsupported by node kind")
    (fun () -> ignore (Lui_app.dispatch_event app (ValueChanged (fid, 0.5))));
  check_raises "press on text-field"
    (Invalid_argument "event is unsupported by node kind")
    (fun () -> ignore (Lui_app.dispatch_event app (Press fid)))

let test_echo_suppressed () =
  let _h, app = boot () in
  let store = E2e_harness.store _h in
  let fid = kind_id store "text-field" in
  (* re-reporting the current value is an echo: dispatched but the
     handler is suppressed, so no model change and no new batch *)
  check bool "echo dispatched" true
    (Lui_app.dispatch_event app (TextChanged (fid, "")));
  check bool "flush" true (Lui_app.flush app);
  check int "no new generation" 1 (Lui_store.generation store)

let test_dispose () =
  let h, app = boot () in
  check bool "dispose" true (Lui_app.dispose app);
  check bool "disposed" true (Lui_app.disposed app);
  check int "store emptied" 0 (Lui_store.node_count (E2e_harness.store h))

(* ---------- store / scene half: hand-built patch batches ---------- *)

let scene_batch =
  { generation = 1;
    ops =
      [ CreateNode (1, Scroll);
        CreateNode (2, Box);
        SetProp (2, BackgroundValue, StringValue "#ff0000");
        CreateNode (3, Box);
        SetProp (3, BackgroundValue, StringValue "accent");
        CreateNode (4, Image);
        CreateNode (5, Box);
        SetProp (5, Shadow, StringValue "card");
        SetProp (5, BackgroundValue, StringValue "#00ff00");
        InsertChild (1, 2, 0);
        InsertChild (1, 3, 1);
        InsertChild (1, 4, 2);
        InsertChild (1, 5, 3);
        CreateExtension (8, "test.hole", "");
        SetExtensionProp (8, "w", IntValue 1);
        InsertChild (1, 8, 4);
        CreateNode (6, Column);
        SetProp (6, Visible, BoolValue false);
        CreateNode (7, Box);
        SetProp (7, BackgroundValue, StringValue "#0000ff");
        InsertChild (6, 7, 0) ] }

let test_scene_ops () =
  let h = E2e_harness.create () in
  let store = E2e_harness.store h in
  check bool "apply" true (E2e_harness.apply_batch h scene_batch);
  check int "node count" 8 (Lui_store.node_count store);
  check (list int) "roots" [ 1; 6 ] (Lui_store.root_ids store);
  check (list int) "scroll children" [ 2; 3; 4; 5; 8 ]
    (Lui_store.child_ids store 1);
  check string "ext kind" "extension:test.hole" (Lui_store.kind store 8);
  check (option string) "ext id" (Some "test.hole")
    (Lui_store.ext_id store 8);
  let ops = E2e_harness.repaint h in
  check (list string) "op sequence"
    [ "push_clip"; "fill"; "fill"; "image"; "shadow"; "fill"; "hole";
      "pop_clip" ]
    (E2e_harness.op_names ops);
  let clip = match List.hd ops with
    | Push_clip c -> c
    | _ -> fail "first op must be push_clip"
  in
  let r1 = E2e_harness.rect_of h 1 in
  check (float 0.001) "clip x" r1.x clip.crect.x;
  check (float 0.001) "clip h" r1.h clip.crect.h;
  let fills = ops_named "fill" ops in
  (match fills with
   | [ Fill f2; Fill f3; Fill f5 ] ->
     check int "fill2 r" 255 f2.fcolor.r;
     check int "fill3 accent r" 10 f3.fcolor.r;
     check int "fill3 accent g" 20 f3.fcolor.g;
     check int "fill5 g" 255 f5.fcolor.g;
     let r5 = E2e_harness.rect_of h 5 in
     check (float 0.001) "fill5 y" r5.y f5.frect.y
   | _ -> fail "expected three fills");
  (match ops_named "image" ops with
   | [ Image i ] ->
     check int "image w" 2 i.iimage.iw;
     let r4 = E2e_harness.rect_of h 4 in
     check (float 0.001) "image x" r4.x i.irect2.x
   | _ -> fail "expected one image op");
  (match ops_named "shadow" ops with
   | [ Shadow s ] ->
     let r5 = E2e_harness.rect_of h 5 in
     check (float 0.001) "shadow dy" (r5.y +. 2.) s.srect.y;
     check (float 0.001) "shadow blur" 6. s.sblur;
     check int "shadow alpha" 80 s.scolor.a;
     check bool "not inset" false s.sinset
   | _ -> fail "expected one shadow op");
  (match ops_named "hole" ops with
   | [ Hole hole ] ->
     let r8 = E2e_harness.rect_of h 8 in
     check (float 0.001) "hole y" r8.y hole.hrect.y
   | _ -> fail "expected one hole op");
  (* invisible subtree emits nothing: node 7's #0000ff never appears *)
  check bool "invisible skipped" true
    (List.for_all
       (fun o ->
         match o with
         | Fill f -> not (f.fcolor.b = 255 && f.fcolor.r = 0 && f.fcolor.g = 0)
         | _ -> true)
       ops)

let test_move_remove_drop () =
  let h = E2e_harness.create () in
  let store = E2e_harness.store h in
  ignore (E2e_harness.apply_batch h scene_batch);
  ignore (Lui_store.drain_dirty store);

  (* move: reorder children inside the scroll node *)
  ignore (E2e_harness.apply_batch h
            { generation = 2; ops = [ MoveChild (1, 3, 0) ] });
  check (list int) "moved order" [ 3; 2; 4; 5; 8 ]
    (Lui_store.child_ids store 1);
  let dirty = Lui_store.drain_dirty store in
  check bool "parent dirty" true (List.mem 1 dirty);
  check bool "child dirty" true (List.mem 3 dirty);
  let ops = E2e_harness.repaint h in
  (match ops with
   | _clip :: Fill f :: _ ->
     check int "first fill is accent" 10 f.fcolor.r
   | _ -> fail "expected clip then fill");

  (* remove: orphan node 4 becomes a forest root and keeps painting *)
  ignore (E2e_harness.apply_batch h
            { generation = 3; ops = [ RemoveChild (1, 4) ] });
  check (list int) "after remove" [ 3; 2; 5; 8 ] (Lui_store.child_ids store 1);
  check (option int) "node4 parent" None (Lui_store.parent store 4);
  check bool "node4 is root" true (List.mem 4 (Lui_store.root_ids store));
  let ops = E2e_harness.repaint h in
  check int "image still paints" 1 (List.length (ops_named "image" ops));
  ignore (Lui_store.drain_dirty store);

  (* drop: subtree gone, ids marked dirty *)
  ignore (E2e_harness.apply_batch h
            { generation = 4; ops = [ DropNode 5 ] });
  check bool "dropped" false (Lui_store.mem store 5);
  check (list int) "after drop" [ 3; 2; 8 ] (Lui_store.child_ids store 1);
  let dirty = Lui_store.drain_dirty store in
  check bool "dropped id dirty" true (List.mem 5 dirty);
  (* The .mli says a drop marks the removed id AND its old parent
     dirty — fixed after e2e flagged the gap. *)
  check bool "old parent dirty" true (List.mem 1 dirty);
  let ops = E2e_harness.repaint h in
  check int "no shadow now" 0 (List.length (ops_named "shadow" ops))

let test_invalid_ops_ignored () =
  let h = E2e_harness.create () in
  let store = E2e_harness.store h in
  ignore (E2e_harness.apply_batch h
            { generation = 1;
              ops =
                [ SetProp (99, Gap, IntValue 4);
                  RemoveProp (99, Gap);
                  InsertChild (1, 99, 0);
                  RemoveChild (1, 99);
                  DropNode 99 ] });
  check int "empty store" 0 (Lui_store.node_count store);
  (* DropNode on a nonexistent id touches nothing — not even the
     dirty set. *)
  check int "nothing dirtied" 0
    (List.length (Lui_store.drain_dirty store))

let test_host_flags_and_resize () =
  let h = E2e_harness.create () in
  check bool "clean" false (E2e_harness.wants_repaint h);
  check bool "apply" true
    (E2e_harness.apply_batch h
       { generation = 1; ops = [ CreateNode (1, Box) ] });
  check bool "dirty" true (E2e_harness.wants_repaint h);
  ignore (E2e_harness.repaint h);
  check bool "clean again" false (E2e_harness.wants_repaint h);
  E2e_harness.resize h ~width:64 ~height:48 ~scale:2.;
  check bool "resize dirty" true (E2e_harness.wants_repaint h);
  ignore (E2e_harness.repaint h);
  let cap = E2e_harness.cap h in
  check int "resized bytes" (64 * 48 * 4) cap.bytes;
  check int "scene width" 64 (E2e_harness.scene h).width;
  check (float 0.001) "scene scale" 2. (E2e_harness.scene h).scale

let () =
  run "lui_e2e"
    [ ("app",
       [ test_case "boot pipeline" `Quick test_boot_pipeline;
         test_case "text changed" `Quick test_text_changed;
         test_case "add/remove/promote" `Quick test_press_add_remove_promote;
         test_case "unsupported event" `Quick test_unsupported_event_rejected;
         test_case "echo suppressed" `Quick test_echo_suppressed;
         test_case "dispose" `Quick test_dispose ]);
      ("store+scene",
       [ test_case "scene ops" `Quick test_scene_ops;
         test_case "move/remove/drop" `Quick test_move_remove_drop;
         test_case "invalid ops" `Quick test_invalid_ops_ignored;
         test_case "host flags+resize" `Quick test_host_flags_and_resize ]) ]
