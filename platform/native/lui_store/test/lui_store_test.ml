open Lui_protocol
open Alcotest

let batch ops = { generation = 1; ops }

let apply t ops = Lui_store.apply_batch t (batch ops)

let test_create_and_insert () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Root);
      CreateNode (2, Column);
      CreateNode (3, Text);
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0) ];
  check int "nodes" 3 (Lui_store.node_count t);
  check (list int) "root children" [2] (Lui_store.child_ids t 1);
  check (list int) "col children" [3] (Lui_store.child_ids t 2);
  check (option int) "parent of 3" (Some 2) (Lui_store.parent t 3);
  check (list int) "preorder" [1; 2; 3] (Lui_store.preorder t)

let test_insert_order () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column); CreateNode (10, Text); CreateNode (11, Text);
      CreateNode (12, Text);
      InsertChild (1, 10, 0); InsertChild (1, 11, 1); InsertChild (1, 12, 1) ];
  check (list int) "middle insert" [10; 12; 11] (Lui_store.child_ids t 1)

let test_move_child () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column); CreateNode (10, Text); CreateNode (11, Text);
      InsertChild (1, 10, 0); InsertChild (1, 11, 1); MoveChild (1, 10, 1) ];
  check (list int) "moved" [11; 10] (Lui_store.child_ids t 1)

let test_move_across_parents () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column); CreateNode (2, Column); CreateNode (10, Text);
      InsertChild (1, 10, 0); InsertChild (2, 10, 0) ];
  check (list int) "old parent empty" [] (Lui_store.child_ids t 1);
  check (list int) "new parent" [10] (Lui_store.child_ids t 2);
  check (option int) "parent" (Some 2) (Lui_store.parent t 10)

let test_drop_subtree () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column); CreateNode (2, Row); CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0) ];
  apply t [ DropNode 2 ];
  check int "nodes" 1 (Lui_store.node_count t);
  check (list int) "children" [] (Lui_store.child_ids t 1);
  check bool "gone" false (Lui_store.mem t 3);
  let dirty = Lui_store.drain_dirty t in
  check bool "drop marks removed id" true (List.mem 2 dirty);
  check bool "drop marks old parent" true (List.mem 1 dirty)

let test_props () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Button);
      SetProp (1, TextValue, StringValue "hi") ] ;
  (match Lui_store.string_prop t 1 "text" with
   | Some "hi" -> ()
   | _ -> fail "expected text prop");
  apply t [ RemoveProp (1, TextValue) ];
  check bool "prop removed" true (Lui_store.prop t 1 "text" = None)

let test_extension () =
  let t = Lui_store.create () in
  apply t [ CreateExtension (5, "chart", "fp1"); SetExtensionProp (5, "data", StringValue "x") ];
  check string "kind" "extension:chart" (Lui_store.kind t 5);
  check (option string) "ext id" (Some "chart") (Lui_store.ext_id t 5);
  (match Lui_store.string_prop t 5 "data" with
   | Some "x" -> ()
   | _ -> fail "expected ext prop");
  apply t [ RemoveExtensionProp (5, "data") ];
  check bool "ext prop removed" true (Lui_store.prop t 5 "data" = None)

let test_dirty () =
  let t = Lui_store.create () in
  apply t [ CreateNode (1, Column); CreateNode (2, Text); InsertChild (1, 2, 0) ];
  let d1 = Lui_store.drain_dirty t |> List.sort compare in
  check (list int) "dirty set" [1; 2] d1;
  check (list int) "drained empty" [] (Lui_store.drain_dirty t);
  apply t [ SetProp (2, TextValue, StringValue "v") ];
  check (list int) "only touched" [2] (Lui_store.drain_dirty t)

(* Typed dirty masks: a paint-only prop reports only the paint bit, a
   layout prop reports layout|paint, and structure ops report
   structure. Consumers drain the same ids they always did — the mask
   rides along. *)
let test_dirty_masks () =
  let t = Lui_store.create () in
  apply t [ CreateNode (1, Column); CreateNode (2, Text); InsertChild (1, 2, 0) ];
  ignore (Lui_store.drain_dirty_masked t);
  apply t [ SetProp (2, BackgroundValue, StringValue "#fff") ];
  (match Lui_store.drain_dirty_masked t with
   | [ (2, m) ] ->
     check bool "paint bit" true (Lui_store.mask_has m Lui_store.d_paint);
     check bool "no layout bit" false (Lui_store.mask_has m Lui_store.d_layout);
     check bool "no structure bit" false (Lui_store.mask_has m Lui_store.d_structure)
   | _ -> fail "expected one masked entry");
  apply t [ SetProp (2, WidthValue, IntValue 30) ];
  (match Lui_store.drain_dirty_masked t with
   | [ (2, m) ] ->
     check bool "layout bit" true (Lui_store.mask_has m Lui_store.d_layout);
     check bool "paint bit" true (Lui_store.mask_has m Lui_store.d_paint)
   | _ -> fail "expected one masked entry");
  apply t [ SetProp (2, DisplayValue, StringValue "none") ];
  (match Lui_store.drain_dirty_masked t with
   | [ (2, m) ] ->
     check bool "display is structure" true (Lui_store.mask_has m Lui_store.d_structure)
   | _ -> fail "expected one masked entry");
  (* masks accumulate across ops on one id *)
  apply t
    [ SetProp (2, BackgroundValue, StringValue "#000");
      SetProp (2, HeightValue, IntValue 10) ];
  (match Lui_store.drain_dirty_masked t with
   | [ (2, m) ] ->
     check bool "merged paint" true (Lui_store.mask_has m Lui_store.d_paint);
     check bool "merged layout" true (Lui_store.mask_has m Lui_store.d_layout)
   | _ -> fail "expected merged entry")

(* The layout revision moves only on geometry-relevant ops: paint churn
   leaves it (and therefore the layout memo) untouched. *)
let test_layout_rev () =
  let t = Lui_store.create () in
  apply t [ CreateNode (1, Column); CreateNode (2, Text); InsertChild (1, 2, 0) ];
  let r0 = Lui_store.layout_rev t in
  check bool "mount bumps" true (r0 > 0);
  apply t [ SetProp (2, BackgroundValue, StringValue "#fff") ];
  check int "paint only" r0 (Lui_store.layout_rev t);
  apply t [ SetProp (2, ZIndex, IntValue 2) ];
  check int "z-index paint only" r0 (Lui_store.layout_rev t);
  apply t [ SetProp (2, AccessibilityLabel, StringValue "x") ];
  check int "a11y prop not layout" r0 (Lui_store.layout_rev t);
  apply t [ SetProp (2, WidthValue, IntValue 10) ];
  check bool "width bumps" true (Lui_store.layout_rev t > r0)

(* changes_since replays ops in order for a consumer cursor; an unknown
   revision still yields everything reachable. *)
let test_changes_since () =
  let t = Lui_store.create () in
  apply t [ CreateNode (1, Column); CreateNode (2, Text); InsertChild (1, 2, 0) ];
  let rev = Lui_store.revision t in
  (match Lui_store.changes_since t rev with
   | Some [] -> ()
   | _ -> fail "expected no ops since head");
  apply t [ SetProp (2, TextValue, StringValue "a"); SetProp (2, WidthValue, IntValue 5) ];
  (match Lui_store.changes_since t rev with
   | Some [ SetProp (2, TextValue, StringValue "a"); SetProp (2, WidthValue, IntValue 5) ] -> ()
   | _ -> fail "expected the two SetProps in order");
  (match Lui_store.changes_since t 0 with
   | Some ops -> check bool "from scratch" true (List.length ops >= 5)
   | None -> fail "fresh journal covers rev 0")

(* O(N) wide removals: the intrusive child list detaches each child in
   O(1), so dropping 20k siblings one op at a time — or dropping their
   parent — stays linear. The old compacting array re-scanned the
   siblings per removal and took seconds here. *)
let test_wide_removal_complexity () =
  let n = 20_000 in
  let t = Lui_store.create () in
  apply t [ CreateNode (1, Column) ];
  apply t
    (List.concat_map
       (fun i -> [ CreateNode (10 + i, Text); InsertChild (1, 10 + i, i) ])
       (List.init n Fun.id));
  let t0 = Sys.time () in
  apply t (List.init n (fun i -> RemoveChild (1, 10 + i)));
  let remove_ms = (Sys.time () -. t0) *. 1000. in
  check (list int) "all detached" [] (Lui_store.child_ids t 1);
  (* Repopulate, then drop the whole subtree at once. *)
  apply t
    (List.concat_map
       (fun i -> [ CreateNode (10 + i, Text); InsertChild (1, 10 + i, i) ])
       (List.init n Fun.id));
  let t1 = Sys.time () in
  apply t [ DropNode 1 ];
  let drop_ms = (Sys.time () -. t1) *. 1000. in
  check int "dropped" 0 (Lui_store.node_count t);
  (* ~2ms at linear; the quadratic version needed ~seconds. *)
  check bool "remove under 500ms" true (remove_ms < 500.);
  check bool "drop under 500ms" true (drop_ms < 500.)

let test_root_ids () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column); CreateNode (2, Column); CreateNode (9, Text);
      InsertChild (1, 9, 0) ];
  check (list int) "roots" [1; 2] (Lui_store.root_ids t)

let test_ops_on_missing_are_ignored () =
  let t = Lui_store.create () in
  apply t
    [ SetProp (99, TextValue, StringValue "x");
      InsertChild (99, 98, 0);
      RemoveChild (99, 98);
      DropNode 99 ];
  check int "still empty" 0 (Lui_store.node_count t)

(* Recreate must drop the previous subtree: otherwise children of the
   old node stay in the table with parent=Some id while the replacement
   starts empty. *)
let test_create_replaces_drops_subtree () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column); CreateNode (2, Row); CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0) ];
  check int "before" 3 (Lui_store.node_count t);
  apply t [ CreateNode (1, Stack) ];
  check int "after recreate" 1 (Lui_store.node_count t);
  check bool "old child gone" false (Lui_store.mem t 2);
  check bool "old grandchild gone" false (Lui_store.mem t 3);
  check string "kind replaced" "stack" (Lui_store.kind t 1);
  check (list int) "no children" [] (Lui_store.child_ids t 1);
  (* same for CreateExtension *)
  apply t
    [ CreateNode (10, Column); CreateNode (11, Text); InsertChild (10, 11, 0) ];
  apply t [ CreateExtension (10, "chart", "fp") ];
  check bool "ext child gone" false (Lui_store.mem t 11);
  check string "ext kind" "extension:chart" (Lui_store.kind t 10)

let test_extension_input_mask () =
  let t = Lui_store.create () in
  Lui_store.set_extension_prop_mask t ~identifier:"editor" ~property:"caret"
    (Lui_store.d_input lor Lui_store.d_paint);
  apply t [CreateExtension (1, "editor", "editor-fingerprint")];
  ignore (Lui_store.drain_dirty_masked t);
  let revision = Lui_store.layout_rev t in
  apply t [SetExtensionProp (1, "caret", IntValue 2)];
  check int "caret does not change layout" revision (Lui_store.layout_rev t);
  let dirty = List.assoc 1 (Lui_store.drain_dirty_masked t) in
  check bool "caret repaints" true (Lui_store.mask_has dirty Lui_store.d_paint);
  check bool "caret updates input" true (Lui_store.mask_has dirty Lui_store.d_input);
  apply t [RemoveExtensionProp (1, "caret")];
  check int "caret removal does not change layout" revision (Lui_store.layout_rev t);
  apply t [SetExtensionProp (1, "width", IntValue 40)];
  check bool "unknown extension props remain conservative" true
    (Lui_store.layout_rev t > revision);
  let other = Lui_store.create () in
  apply other [CreateExtension (1, "editor", "editor-fingerprint")];
  let before = Lui_store.layout_rev other in
  apply other [SetExtensionProp (1, "caret", IntValue 2)];
  check bool "classification belongs to the host store" true
    (Lui_store.layout_rev other > before)

let test_preorder_allocation () =
  let t = Lui_store.create () in
  for id = 1 to 6000 do
    Lui_store.apply_op t (CreateNode (id, Column));
    if id > 1 then Lui_store.apply_op t (InsertChild (id-1, id, 0))
  done;
  let before = Gc.allocated_bytes () in
  let ids = Lui_store.preorder t in
  let allocated = Gc.allocated_bytes () -. before in
  check (list int) "deep preorder stays ordered" (List.init 6000 (fun i -> i+1)) ids;
  check bool (Printf.sprintf "preorder allocation %.0f bytes" allocated) true (allocated < 512000.);
  let count = ref 0 in
  let visit _ = incr count in
  let before = Gc.allocated_bytes () in
  for _ = 1 to 20 do Lui_store.iter_preorder t visit done;
  let allocated = Gc.allocated_bytes () -. before in
  check int "every node visited once per pass" 120000 !count;
  check bool (Printf.sprintf "streamed traversal allocation %.0f bytes" allocated)
    true (allocated < 32768.)

let test_iter_preorder_order () =
  let t = Lui_store.create () in
  apply t [CreateNode (20, Column); CreateNode (1, Column); CreateNode (3, Text);
    CreateNode (2, Column); CreateNode (4, Text); InsertChild (1,2,0);
    InsertChild (1,3,1); InsertChild (2,4,0)];
  let collect ?root () =
    let ids = ref [] in
    Lui_store.iter_preorder ?root t (fun id -> ids := id :: !ids);
    List.rev !ids in
  check (list int) "forest root order and sibling order" [1;2;4;3;20] (collect ());
  check (list int) "rooted traversal excludes siblings" [2;4] (collect ~root:2 ());
  check (list int) "missing root visits nothing" [] (collect ~root:99 ());
  apply t [MoveChild (1,3,0)];
  check (list int) "updated sibling order" [1;3;2;4;20] (collect ())

let test_kind_lookup_allocation () =
  let t = Lui_store.create () in
  apply t [CreateNode (1, Column); CreateExtension (2, "editor", "editor-fingerprint")];
  check string "missing node kind" "" (Lui_store.kind t 99);
  check string "extension node kind" "extension:editor" (Lui_store.kind t 2);
  let correct = ref true in
  let before = Gc.allocated_bytes () in
  for _ = 1 to 10000 do
    if Lui_store.kind t 1 <> "column" then correct := false
  done;
  let allocated = Gc.allocated_bytes () -. before in
  check bool "ordinary node kind" true !correct;
  check bool (Printf.sprintf "kind lookup allocation %.0f bytes" allocated)
    true (allocated <= 1024.);
  apply t [DropNode 1];
  check string "dropped node kind" "" (Lui_store.kind t 1)

let read_store () =
  let t = Lui_store.create () in
  apply t [CreateNode (1, Column); CreateExtension (2, "editor", "fingerprint");
    InsertChild (1,2,0); SetExtensionProp (2,"flag",BoolValue true);
    SetExtensionProp (2,"label",StringValue "hello");
    SetExtensionProp (2,"amount",FloatValue 12.5);
    SetExtensionProp (2,"count",IntValue 7)];
  t

let test_read_lookup_allocation () =
  let t = read_store () in
  let correct = ref true in
  let before = Gc.allocated_bytes () in
  for _=1 to 10000 do
    if not (Lui_store.bool_prop t 2 "flag") || Lui_store.child_count t 1 <> 1
       || Lui_store.parent t 2 <> Some 1 || Lui_store.ext_id t 2 <> Some "editor"
    then correct := false
  done;
  let allocated = Gc.allocated_bytes () -. before in
  check bool "readers return the stored values" true !correct;
  check bool (Printf.sprintf "scalar and stored-option reads allocated %.0f bytes" allocated)
    true (allocated <= 1024.)

let test_property_lookup_allocation () =
  let t = read_store () in
  let correct = ref true in
  let before = Gc.allocated_bytes () in
  for _=1 to 10000 do
    if Lui_store.string_prop t 2 "label" <> Some "hello"
       || Lui_store.float_prop t 2 "amount" <> Some 12.5
       || Lui_store.int_prop t 2 "count" <> Some 7
       || Lui_store.prop t 2 "flag" <> Some (BoolValue true)
    then correct := false
  done;
  let allocated = Gc.allocated_bytes () -. before in
  check bool "typed and raw property values" true !correct;
  check bool (Printf.sprintf "property reads allocated %.0f bytes" allocated)
    true (allocated <= 800000.)

let test_read_lookup_missing () =
  let t = read_store () in
  List.iter (fun id ->
    List.iter (fun name ->
      check bool "missing or mistyped boolean" false (Lui_store.bool_prop t id name);
      check (option string) "missing or mistyped string" None (Lui_store.string_prop t id name);
      check (option (float 0.)) "missing or mistyped float" None (Lui_store.float_prop t id name);
      check (option int) "missing or mistyped integer" None (Lui_store.int_prop t id name)
    ) ["missing"]
  ) [2;99];
  check bool "string is not a boolean" false (Lui_store.bool_prop t 2 "label");
  check (option string) "boolean is not a string" None (Lui_store.string_prop t 2 "flag");
  check (option (float 0.)) "integer is not a float" None (Lui_store.float_prop t 2 "count");
  check (option int) "float is not an integer" None (Lui_store.int_prop t 2 "amount");
  apply t [DropNode 2];
  check (option int) "removed parent" None (Lui_store.parent t 2);
  check (option string) "removed extension" None (Lui_store.ext_id t 2);
  check int "removed child count" 0 (Lui_store.child_count t 2);
  check bool "removed property" true (Lui_store.prop t 2 "flag" = None)

let () =
  run "lui_store"
    [ ("tree",
       [ test_case "create+insert" `Quick test_create_and_insert;
         test_case "insert order" `Quick test_insert_order;
         test_case "move" `Quick test_move_child;
         test_case "move across parents" `Quick test_move_across_parents;
         test_case "drop subtree" `Quick test_drop_subtree;
         test_case "recreate drops subtree" `Quick
           test_create_replaces_drops_subtree;
         test_case "roots" `Quick test_root_ids;
         test_case "preorder allocation" `Quick test_preorder_allocation;
         test_case "streamed preorder order" `Quick test_iter_preorder_order;
         test_case "kind lookup allocation" `Quick test_kind_lookup_allocation ]);
      ("props",
       [ test_case "set/remove" `Quick test_props;
         test_case "extension" `Quick test_extension;
         test_case "scalar lookup allocation" `Quick test_read_lookup_allocation;
         test_case "property lookup allocation" `Quick test_property_lookup_allocation;
         test_case "missing lookups" `Quick test_read_lookup_missing ]);
      ("dirty",
       [ test_case "drain" `Quick test_dirty;
         test_case "typed masks" `Quick test_dirty_masks;
         test_case "extension input mask" `Quick test_extension_input_mask;
         test_case "layout rev" `Quick test_layout_rev;
         test_case "changes since" `Quick test_changes_since;
         test_case "wide removal complexity" `Quick test_wide_removal_complexity;
         test_case "missing ids ignored" `Quick test_ops_on_missing_are_ignored ]) ]
