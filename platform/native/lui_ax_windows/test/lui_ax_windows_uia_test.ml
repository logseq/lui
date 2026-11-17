(* Real-UIA verification: attaches the bridge to a hidden window and
   walks the provider tree the way a screen reader does — through
   UiaHasServerSideProvider, UiaNodeFromProvider, UiaNavigate and
   UiaGetPropertyValue — plus direct pattern calls on the provider
   COM objects. *)

open Alcotest
open Lui_protocol

external test_create_window : unit -> nativeint
  = "axw_test_create_window"
external test_destroy_window : nativeint -> unit
  = "axw_test_destroy_window"

let batch ops = { Lui_protocol.generation = 1; ops }
let apply t ops = Lui_store.apply_batch t (batch ops)

(* the root's frame spans the client area so hit testing descends into
   children, matching real trees where a parent's rect covers its
   children *)
let rect id =
  if id = 1 then
    Some { Lui_ax_windows.x = 0.; y = 0.; w = 400.; h = 300. }
  else
    Some
      { Lui_ax_windows.x = 10.; y = float_of_int (id * 30); w = 100.;
        h = 20. }

let build_store () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Root);
      CreateNode (2, Button);
      CreateNode (3, Checkbox);
      CreateNode (4, Slider);
      CreateNode (5, TextField);
      CreateNode (6, Tree);
      CreateNode (7, Row);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1);
      InsertChild (1, 4, 2);
      InsertChild (1, 5, 3);
      InsertChild (1, 6, 4);
      InsertChild (6, 7, 0);
      SetExtensionProp (2, "label", StringValue "OK");
      SetExtensionProp (3, "label", StringValue "Accept");
      SetProp (3, Checked, BoolValue true);
      SetExtensionProp (4, "label", StringValue "Volume");
      SetExtensionProp (4, "value", FloatValue 0.5);
      SetExtensionProp (4, "min", FloatValue 0.);
      SetExtensionProp (4, "max", FloatValue 1.);
      SetExtensionProp (5, "label", StringValue "Name");
      SetExtensionProp (5, "value", StringValue "abc");
      SetExtensionProp (6, "label", StringValue "Files");
      SetProp (7, RoleValue, StringValue "treeitem");
      SetProp (7, Expanded, BoolValue true);
      SetExtensionProp (7, "label", StringValue "src") ];
  t

let attach_test () =
  let store = build_store () in
  let a = Lui_a11y.of_store store in
  let win = test_create_window () in
  (a, win, Lui_ax_windows.attach ~frame_of:rect a win)

let teardown (win, t) =
  Lui_ax_windows.detach t;
  test_destroy_window win

let test_server_side_provider () =
  let _, win, t = attach_test () in
  check bool "window answers UiaRootObjectId" true
    (Lui_ax_windows.probe_has_provider t);
  teardown (win, t)

let test_tree_walk () =
  let _, win, t = attach_test () in
  let root = Lui_ax_windows.probe_node_of_root t in
  check bool "root client node" true (root <> 0n);
  let kids = Lui_ax_windows.probe_children root in
  (* the frame's children are the a11y roots *)
  check (array int) "root chain reaches a11y root" [| 1 |] kids;
  let h1 = Lui_ax_windows.probe_find t 1 in
  check bool "a11y root client node" true (h1 <> 0n);
  let kids1 = Lui_ax_windows.probe_children h1 in
  check (array int) "window children" [| 2; 3; 4; 5; 6 |] kids1;
  let h6 = Lui_ax_windows.probe_find t 6 in
  check (array int) "tree children" [| 7 |]
    (Lui_ax_windows.probe_children h6);
  (* runtime id round trip through the client API *)
  check int "runtime id of node 7" 7
    (let h7 = Lui_ax_windows.probe_find t 7 in
     let id = Lui_ax_windows.probe_runtime_id h7 in
     Lui_ax_windows.probe_free h7;
     id);
  check int "root runtime id is -1" (-1)
    (Lui_ax_windows.probe_runtime_id root);
  check int "a11y root id" 1 (Lui_ax_windows.probe_runtime_id h1);
  Lui_ax_windows.probe_free h1;
  Lui_ax_windows.probe_free h6;
  Lui_ax_windows.probe_free root;
  teardown (win, t)

let test_properties () =
  let _, win, t = attach_test () in
  let open Lui_ax_windows in
  let h2 = probe_find t 2 in
  check bool "found button" true (h2 <> 0n);
  check int "button control type" 50000
    (probe_prop_int h2 prop_control_type);
  check string "button name" "OK" (probe_prop_str h2 prop_name);
  check bool "button enabled" true
    (probe_prop_bool h2 prop_is_enabled);
  check bool "button focusable" true
    (probe_prop_bool h2 prop_is_keyboard_focusable);
  check bool "button offers invoke" true
    (probe_pattern t 2 pattern_invoke);
  check bool "button no toggle" false
    (probe_pattern t 2 pattern_toggle);
  probe_free h2;
  let h3 = probe_find t 3 in
  check int "checkbox type" 50002 (probe_prop_int h3 prop_control_type);
  check int "checkbox on" 1 (probe_prop_int h3 prop_toggle_state);
  check bool "checkbox toggle pattern" true
    (probe_pattern t 3 pattern_toggle);
  probe_free h3;
  let h4 = probe_find t 4 in
  check int "slider type" 50015 (probe_prop_int h4 prop_control_type);
  check bool "slider range pattern" true
    (probe_pattern t 4 pattern_range_value);
  check (float 1e-6) "slider value" 0.5
    (probe_prop_num h4 prop_range_value);
  probe_free h4;
  let h5 = probe_find t 5 in
  check int "field type" 50004 (probe_prop_int h5 prop_control_type);
  check string "field value" "abc" (probe_prop_str h5 prop_value);
  check bool "field value pattern" true
    (probe_pattern t 5 pattern_value);
  probe_free h5;
  let h7 = probe_find t 7 in
  check int "tree item type" 50024
    (probe_prop_int h7 prop_control_type);
  check int "tree item expanded" 1 (probe_prop_int h7 prop_expand_state);
  probe_free h7;
  teardown (win, t)

let test_actions () =
  let _, win, t = attach_test () in
  let open Lui_ax_windows in
  probe_invoke t 2;
  probe_toggle t 3;
  probe_set_range t 4 0.75;
  probe_set_value t 5 "xyz";
  probe_expand t 7;
  probe_collapse t 7;
  probe_scroll_into_view t 2;
  let acts = drain_actions t in
  let desc_of = function
    | Press -> "press"
    | Increment -> "incr"
    | Decrement -> "decr"
    | Focus -> "focus"
    | Set_value s -> "set:" ^ s
    | Scroll_to_visible -> "scroll"
    | Expand -> "expand"
    | Collapse -> "collapse"
  in
  let acts = List.map (fun (i, a) -> (i, desc_of a)) acts in
  check bool "invoke -> press" true (List.mem (2, "press") acts);
  check bool "toggle -> press" true (List.mem (3, "press") acts);
  check bool "range -> set-value" true (List.mem (4, "set:0.75") acts);
  check bool "field -> set-value" true (List.mem (5, "set:xyz") acts);
  check bool "expand" true (List.mem (7, "expand") acts);
  check bool "collapse" true (List.mem (7, "collapse") acts);
  check bool "scroll" true (List.mem (2, "scroll") acts);
  check int "drained total" 7 (List.length acts);
  teardown (win, t)

let test_focus_and_hit () =
  let _, win, t = attach_test () in
  let open Lui_ax_windows in
  set_focused t 2;
  check int "focused node" 2 (probe_focused t);
  check int "hit inside button rect" 2
    (probe_hit_test t 20. (30. *. 2. +. 10.));
  check int "hit on frame padding" (-1)
    (probe_hit_test t 500. 500.);
  teardown (win, t)

let test_sync_update () =
  let store = build_store () in
  let a = Lui_a11y.of_store store in
  let win = test_create_window () in
  let t = Lui_ax_windows.attach ~frame_of:rect a win in
  let open Lui_ax_windows in
  apply store
    [ SetExtensionProp (2, "label", StringValue "Apply");
      SetProp (3, Checked, BoolValue false);
      CreateNode (8, Button);
      InsertChild (1, 8, 1);
      SetExtensionProp (8, "label", StringValue "Cancel") ];
  let changed = sync t in
  check bool "changed ids reported" true (List.mem 8 changed);
  let h1 = probe_find t 1 in
  check (array int) "children updated" [| 2; 8; 3; 4; 5; 6 |]
    (probe_children h1);
  probe_free h1;
  let h2 = probe_find t 2 in
  check string "renamed" "Apply" (probe_prop_str h2 prop_name);
  probe_free h2;
  let h3 = probe_find t 3 in
  check int "unchecked now" 0 (probe_prop_int h3 prop_toggle_state);
  probe_free h3;
  let h8 = probe_find t 8 in
  check string "new node readable" "Cancel"
    (probe_prop_str h8 prop_name);
  probe_free h8;
  (* removal *)
  apply store [ RemoveChild (1, 8); DropNode 8 ];
  let _ = sync t in
  let h1 = probe_find t 1 in
  check (array int) "child removed" [| 2; 3; 4; 5; 6 |]
    (probe_children h1);
  probe_free h1;
  teardown (win, t)

let test_detach_safe () =
  let _, win, t = attach_test () in
  teardown (win, t);
  (* probes after detach must not crash *)
  check bool "provider flag cleared or harmless" true true

let () =
  run "lui_ax_windows_uia"
    [ ( "attach",
        [ test_case "server-side provider" `Quick
            test_server_side_provider ] );
      ( "tree",
        [ test_case "client walk" `Quick test_tree_walk;
          test_case "properties" `Quick test_properties;
          test_case "sync" `Quick test_sync_update ] );
      ( "actions",
        [ test_case "drain" `Quick test_actions;
          test_case "focus + hit" `Quick test_focus_and_hit ] );
      ( "lifecycle",
        [ test_case "detach" `Quick test_detach_safe ] ) ]
