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

let () =
  run "lui_store"
    [ ("tree",
       [ test_case "create+insert" `Quick test_create_and_insert;
         test_case "insert order" `Quick test_insert_order;
         test_case "move" `Quick test_move_child;
         test_case "move across parents" `Quick test_move_across_parents;
         test_case "drop subtree" `Quick test_drop_subtree;
         test_case "roots" `Quick test_root_ids ]);
      ("props",
       [ test_case "set/remove" `Quick test_props;
         test_case "extension" `Quick test_extension ]);
      ("dirty",
       [ test_case "drain" `Quick test_dirty;
         test_case "missing ids ignored" `Quick test_ops_on_missing_are_ignored ]) ]
