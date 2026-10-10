open Lui_protocol
open Alcotest

let batch ops = { generation = 1; ops }
let apply t ops = Lui_store.apply_batch t (batch ops)

let role_testable =
  testable
    (fun fmt r -> Format.pp_print_string fmt (Lui_a11y.role_name r))
    ( = )

let check_state_testable =
  testable
    (fun fmt c ->
      Format.pp_print_string fmt
        (match c with
         | Lui_a11y.Checked -> "checked"
         | Lui_a11y.Unchecked -> "unchecked"
         | Lui_a11y.Mixed -> "mixed"))
    ( = )

let find_exn t id : Lui_a11y.node_a11y =
  match Lui_a11y.find t id with
  | Some n -> n
  | None -> fail ("no a11y node " ^ string_of_int id)

let name_of t id = (find_exn t id).Lui_a11y.name
let flat_ids t = List.map (fun n -> n.Lui_a11y.id) (Lui_a11y.flatten t)

(* ---------- role mapping ---------- *)

let test_role_table_complete () =
  let missing =
    List.filter
      (fun k ->
        not
          (List.mem_assoc
             (Lui_wire_schema.node_kind_name k)
             Lui_a11y.kind_role_table))
      Lui_wire_schema.all_node_kinds
  in
  check int "every standard kind mapped" 0 (List.length missing);
  List.iter
    (fun (name, r) ->
      check role_testable name r (Lui_a11y.role_of_kind name))
    Lui_a11y.kind_role_table

let test_role_fallbacks () =
  check role_testable "unknown -> group" Lui_a11y.Group
    (Lui_a11y.role_of_kind "mystery-kind");
  check role_testable "extension" Lui_a11y.Extension
    (Lui_a11y.role_of_kind "extension:chart");
  check role_testable "button" Lui_a11y.Button
    (Lui_a11y.role_of_kind "button");
  check role_testable "scroll -> group" Lui_a11y.Group
    (Lui_a11y.role_of_kind "scroll");
  check role_testable "text" Lui_a11y.Static_text
    (Lui_a11y.role_of_kind "text");
  check role_testable "switch" Lui_a11y.Switch
    (Lui_a11y.role_of_kind "switch");
  check role_testable "tree" Lui_a11y.Outline
    (Lui_a11y.role_of_kind "tree");
  check role_testable "sheet" Lui_a11y.Sheet
    (Lui_a11y.role_of_kind "sheet")

let test_role_prop_override () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Tree);
      CreateNode (2, Row);
      InsertChild (1, 2, 0);
      SetProp (2, RoleValue, StringValue "treeitem");
      SetProp (2, Expanded, BoolValue true) ];
  let a = Lui_a11y.of_store t in
  check role_testable "tree" Lui_a11y.Outline (find_exn a 1).role;
  check role_testable "treeitem" Lui_a11y.Outline_item (find_exn a 2).role;
  check (option bool) "expanded" (Some true) (find_exn a 2).state.expanded

(* ---------- name / description precedence ---------- *)

let test_name_precedence () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Button);
      SetProp (1, TextValue, StringValue "text");
      SetExtensionProp (1, "label", StringValue "label");
      SetProp (1, PlaceholderValue, StringValue "placeholder");
      SetProp (1, TitleValue, StringValue "title");
      SetExtensionProp (1, "aria-label", StringValue "aria") ];
  let a = Lui_a11y.of_store t in
  ignore (Lui_store.drain_dirty t);
  check (option string) "text wins" (Some "text") (name_of a 1);
  apply t [ RemoveProp (1, TextValue) ];
  ignore (Lui_a11y.sync a);
  check (option string) "label next" (Some "label") (name_of a 1);
  apply t [ RemoveExtensionProp (1, "label") ];
  ignore (Lui_a11y.sync a);
  check (option string) "placeholder next" (Some "placeholder") (name_of a 1);
  apply t [ RemoveProp (1, PlaceholderValue) ];
  ignore (Lui_a11y.sync a);
  check (option string) "title next" (Some "title") (name_of a 1);
  apply t [ RemoveProp (1, TitleValue) ];
  ignore (Lui_a11y.sync a);
  check (option string) "aria-label last" (Some "aria") (name_of a 1);
  apply t [ RemoveExtensionProp (1, "aria-label") ];
  ignore (Lui_a11y.sync a);
  check (option string) "none left" None (name_of a 1)

let test_accessibility_label_prop () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Button);
      SetProp (1, AccessibilityLabel, StringValue "acc") ];
  check (option string) "accessibility-label" (Some "acc")
    (find_exn (Lui_a11y.of_store t) 1).name

let test_description_precedence () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      SetProp (1, TextValue, StringValue "n");
      SetProp (1, TitleValue, StringValue "title");
      SetProp (1, DescriptionValue, StringValue "desc");
      SetProp (1, MetaValue, StringValue "meta") ];
  let a = Lui_a11y.of_store t in
  ignore (Lui_store.drain_dirty t);
  let desc () = (find_exn a 1).Lui_a11y.description in
  check (option string) "title first" (Some "title") (desc ());
  apply t [ RemoveProp (1, TitleValue) ];
  ignore (Lui_a11y.sync a);
  check (option string) "description next" (Some "desc") (desc ());
  apply t [ RemoveProp (1, DescriptionValue) ];
  ignore (Lui_a11y.sync a);
  check (option string) "meta last" (Some "meta") (desc ())

let test_descendant_name () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Button);
      CreateNode (3, Text);
      CreateNode (4, Icon);
      CreateNode (5, Row);
      CreateNode (6, Text);
      CreateNode (7, Text);
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0);
      InsertChild (2, 4, 1);
      InsertChild (2, 5, 2);
      InsertChild (5, 6, 0);
      InsertChild (2, 7, 3);
      SetProp (3, TextValue, StringValue "Save");
      SetProp (4, IconName, StringValue "floppy");
      SetProp (6, TextValue, StringValue "now");
      SetProp (7, TextValue, StringValue "hidden");
      SetProp (7, Visible, BoolValue false) ];
  let a = Lui_a11y.of_store t in
  check (option string) "joined text" (Some "Save now") (name_of a 2);
  (* non-composite containers do not accumulate a name *)
  check (option string) "column no name" None (name_of a 1)

(* ---------- state flags ---------- *)

let test_checked_states () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Checkbox);
      CreateNode (2, Checkbox);
      CreateNode (3, Checkbox);
      CreateNode (4, Checkbox);
      CreateNode (5, Column);
      SetProp (1, Checked, BoolValue true);
      SetProp (2, Checked, BoolValue false);
      SetProp (3, Checked, StringValue "mixed") ];
  let a = Lui_a11y.of_store t in
  let st id = (find_exn a id).Lui_a11y.state.checked in
  check (option check_state_testable) "true" (Some Lui_a11y.Checked) (st 1);
  check (option check_state_testable) "false" (Some Lui_a11y.Unchecked) (st 2);
  check (option check_state_testable) "mixed" (Some Lui_a11y.Mixed) (st 3);
  check (option check_state_testable) "checkbox default"
    (Some Lui_a11y.Unchecked) (st 4);
  check (option check_state_testable) "column not checkable" None (st 5)

let test_state_flags () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Button);
      CreateNode (2, Button);
      CreateNode (3, ListItem);
      CreateNode (4, TextField);
      CreateNode (5, SecureField);
      CreateNode (6, Input);
      CreateNode (7, Column);
      CreateNode (8, Column);
      SetProp (2, Enabled, BoolValue false);
      SetProp (3, Selected, BoolValue true);
      SetExtensionProp (4, "required", BoolValue true);
      SetExtensionProp (4, "read-only", BoolValue true);
      SetProp (6, InputType, StringValue "password");
      SetExtensionProp (7, "focusable", BoolValue true) ];
  let a = Lui_a11y.of_store t in
  let st id = (find_exn a id).Lui_a11y.state in
  check bool "button focusable" true (st 1).focusable;
  check bool "button enabled" false (st 1).disabled;
  check bool "disabled button" true (st 2).disabled;
  check bool "disabled not focusable" false (st 2).focusable;
  check bool "selected" true (st 3).selected;
  check bool "required" true (st 4).required;
  check bool "read only" true (st 4).read_only;
  check bool "secure field password" true (st 5).password;
  check bool "input-type password" true (st 6).password;
  check bool "focusable prop" true (st 7).focusable;
  check bool "column not focusable default" false (st 8).focusable

let test_value () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Slider);
      CreateNode (2, TextField);
      CreateNode (3, Progress);
      CreateNode (4, Column);
      SetProp (1, ProgressValue, FloatValue 0.5);
      SetProp (1, MinValue, FloatValue 0.0);
      SetProp (1, MaxValue, FloatValue 1.0);
      SetProp (2, TextValue, StringValue "abc");
      SetProp (3, ProgressValue, FloatValue 0.25) ];
  let a = Lui_a11y.of_store t in
  let v id = (find_exn a id).Lui_a11y.value in
  (match v 1 with
   | Some { numeric = Some 0.5; minimum = Some 0.0; maximum = Some 1.0; _ } ->
     ()
   | _ -> fail "slider value");
  (match v 2 with
   | Some { text = Some "abc"; _ } -> ()
   | _ -> fail "field text value");
  (match v 3 with
   | Some { numeric = Some 0.25; _ } -> ()
   | _ -> fail "progress value");
  check bool "column no value" true (v 4 = None)

(* ---------- build / structure ---------- *)

let test_build_forest () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Column);
      CreateNode (3, Text);
      InsertChild (1, 3, 0);
      InsertChild (2, 3, 0) ];
  (* 3 reparented under 2; roots are 1 and 2 in store order *)
  let forest = Lui_a11y.build t in
  check int "roots" 2 (List.length forest);
  check (list int) "root order" [ 1; 2 ]
    (List.map (fun n -> n.Lui_a11y.id) forest);
  check (list int) "root1 children" [] (List.nth forest 0).children;
  check (list int) "root2 children" [ 3 ] (List.nth forest 1).children

let test_flatten_preorder () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Row);
      CreateNode (3, Text);
      CreateNode (4, Text);
      InsertChild (1, 2, 0);
      InsertChild (1, 4, 1);
      InsertChild (2, 3, 0) ];
  let a = Lui_a11y.of_store t in
  check (list int) "preorder" [ 1; 2; 3; 4 ] (flat_ids a)

let test_hidden_excluded () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Column);
      CreateNode (3, Text);
      CreateNode (4, Column);
      CreateNode (5, Text);
      CreateNode (6, Text);
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0);
      InsertChild (1, 4, 1);
      InsertChild (4, 5, 0);
      InsertChild (1, 6, 2);
      SetProp (2, Visible, BoolValue false);
      SetProp (4, DisplayValue, StringValue "none") ];
  let a = Lui_a11y.of_store t in
  check (list int) "only visible" [ 1; 6 ] (flat_ids a);
  check (list int) "children" [ 6 ] (find_exn a 1).children;
  check bool "hidden subtree gone" false (Lui_a11y.mem a 3);
  check bool "display none gone" false (Lui_a11y.mem a 5)

let test_extension_kept () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateExtension (9, "chart", "fp1");
      InsertChild (1, 9, 0);
      SetExtensionProp (9, "title", StringValue "Chart") ];
  let a = Lui_a11y.of_store t in
  let n = find_exn a 9 in
  check role_testable "role" Lui_a11y.Extension n.role;
  check (option string) "ext id" (Some "chart") n.ext_id;
  check string "kind" "extension:chart" n.kind;
  check (option string) "ext name" (Some "Chart") n.name

(* ---------- incremental update ---------- *)

let test_update_marks_only_changed () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Text);
      CreateNode (3, Button);
      CreateNode (4, Text);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1);
      InsertChild (3, 4, 0);
      SetProp (2, TextValue, StringValue "a");
      SetProp (4, TextValue, StringValue "hi") ];
  let a = Lui_a11y.of_store t in
  ignore (Lui_store.drain_dirty t);
  apply t [ SetProp (2, TextValue, StringValue "b") ];
  check (list int) "only text changed" [ 2 ] (Lui_a11y.sync a);
  (* a descendant text change also updates the accumulating button *)
  apply t [ SetProp (4, TextValue, StringValue "yo") ];
  check (list int) "button name propagates" [ 3; 4 ] (Lui_a11y.sync a);
  check (option string) "new name" (Some "yo") (name_of a 3);
  (* prop that does not change the record: same value again *)
  apply t [ SetProp (2, TextValue, StringValue "b") ];
  check (list int) "no-op change" [] (Lui_a11y.sync a)

let test_update_structure () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Button);
      CreateNode (3, Text);
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0) ];
  let a = Lui_a11y.of_store t in
  ignore (Lui_store.drain_dirty t);
  apply t [ DropNode 2 ];
  check (list int) "drop subtree" [ 1; 2; 3 ] (Lui_a11y.sync a);
  check bool "gone" false (Lui_a11y.mem a 2);
  (* hide then unhide *)
  apply t [ CreateNode (4, Text); InsertChild (1, 4, 0) ];
  ignore (Lui_a11y.sync a);
  apply t [ SetProp (4, Visible, BoolValue false) ];
  check (list int) "hidden out" [ 1; 4 ] (Lui_a11y.sync a);
  check bool "hidden absent" false (Lui_a11y.mem a 4);
  apply t [ SetProp (4, Visible, BoolValue true) ];
  check (list int) "visible in" [ 1; 4 ] (Lui_a11y.sync a);
  check bool "visible back" true (Lui_a11y.mem a 4)

(* ---------- focus ---------- *)

let test_focus_tracking () =
  let t = Lui_store.create () in
  apply t
    [ CreateNode (1, Column);
      CreateNode (2, Button);
      CreateNode (3, Button);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1) ];
  let a = Lui_a11y.of_store t in
  check (option int) "no focus" None (Lui_a11y.focused a);
  check (list int) "focus 2" [ 2 ] (Lui_a11y.set_focused a 2);
  check bool "focused flag" true (find_exn a 2).state.focused;
  check (option int) "focus id" (Some 2) (Lui_a11y.focused a);
  check (list int) "focus moves" [ 2; 3 ] (Lui_a11y.set_focused a 3);
  check bool "old cleared" false (find_exn a 2).state.focused;
  check bool "new set" true (find_exn a 3).state.focused;
  (* focus survives an unrelated update *)
  ignore (Lui_store.drain_dirty t);
  apply t [ SetProp (2, TextValue, StringValue "x") ];
  ignore (Lui_a11y.sync a);
  check bool "still focused" true (find_exn a 3).state.focused;
  check (list int) "clear" [ 3 ] (Lui_a11y.clear_focused a);
  check (option int) "none" None (Lui_a11y.focused a)

let () =
  run "lui_a11y"
    [ ( "roles",
        [ test_case "table covers all kinds" `Quick test_role_table_complete;
          test_case "fallbacks" `Quick test_role_fallbacks;
          test_case "role prop override" `Quick test_role_prop_override ] );
      ( "names",
        [ test_case "precedence" `Quick test_name_precedence;
          test_case "accessibility-label" `Quick test_accessibility_label_prop;
          test_case "description precedence" `Quick test_description_precedence;
          test_case "descendant text" `Quick test_descendant_name ] );
      ( "state",
        [ test_case "tri-state checked" `Quick test_checked_states;
          test_case "flags" `Quick test_state_flags;
          test_case "value" `Quick test_value ] );
      ( "tree",
        [ test_case "build forest" `Quick test_build_forest;
          test_case "flatten preorder" `Quick test_flatten_preorder;
          test_case "hidden excluded" `Quick test_hidden_excluded;
          test_case "extension keeps id" `Quick test_extension_kept ] );
      ( "update",
        [ test_case "changed ids" `Quick test_update_marks_only_changed;
          test_case "structure" `Quick test_update_structure;
          test_case "focus" `Quick test_focus_tracking ] ) ]
