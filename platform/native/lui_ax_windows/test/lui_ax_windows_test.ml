open Alcotest

(* ---------- helpers ---------- *)

let node ?(id = 1) ?(role = Lui_a11y.Group) ?(name = None)
    ?(parent = None) ?(children = []) ?(value = None)
    ?(focusable = false) ?(focused = false) ?(selected = false)
    ?(checked = None) ?(disabled = false) ?(expanded = None)
    ?(required = false) ?(read_only = false) ?(password = false) ()
    : Lui_a11y.node_a11y =
  { Lui_a11y.id; kind = "k"; role; name; description = None;
    state =
      { Lui_a11y.focusable; focused; selected; checked; disabled;
        expanded; required; read_only; password };
    value; parent; children; ext_id = None }

let all_roles : Lui_a11y.role list =
  Lui_a11y.
    [ Window; Group; Static_text; Heading; Text_field; Text_area;
      Search_field; Button; Toggle_button; Check_box; Radio_button;
      Radio_group; Switch; Slider; Spin_button; Progress_indicator;
      Link; Image; List; List_item; Outline; Outline_item; Tab_group;
      Tab; Menu; Menu_item; Combo_box; Dialog; Sheet; Tooltip; Table;
      Table_row; Table_cell; Separator; Toolbar; Status_bar;
      Navigation; Split_group; Extension ]

(* ---------- control type completeness ---------- *)

let test_table_covers_all_roles () =
  List.iter
    (fun r ->
      let name = Lui_a11y.role_name r in
      match List.assoc_opt r Lui_ax_windows.control_type_table with
      | None -> fail ("no control type for " ^ name)
      | Some ct ->
        check bool (name ^ " in UIA control-type range") true
          (ct >= 50000 && ct < 50100))
    all_roles;
  check int "no role mapped twice" (List.length all_roles)
    (List.length Lui_ax_windows.control_type_table)

let test_spot_checks () =
  let get r =
    List.assoc r Lui_ax_windows.control_type_table
  in
  check int "button" 50000 (get Lui_a11y.Button);
  check int "check box" 50002 (get Lui_a11y.Check_box);
  check int "combo box" 50003 (get Lui_a11y.Combo_box);
  check int "edit field" 50004 (get Lui_a11y.Text_field);
  check int "search is edit" 50004 (get Lui_a11y.Search_field);
  check int "link" 50005 (get Lui_a11y.Link);
  check int "image" 50006 (get Lui_a11y.Image);
  check int "list" 50008 (get Lui_a11y.List);
  check int "list item" 50007 (get Lui_a11y.List_item);
  check int "menu" 50009 (get Lui_a11y.Menu);
  check int "menu item" 50011 (get Lui_a11y.Menu_item);
  check int "progress" 50012 (get Lui_a11y.Progress_indicator);
  check int "radio" 50013 (get Lui_a11y.Radio_button);
  check int "slider" 50015 (get Lui_a11y.Slider);
  check int "spinner" 50016 (get Lui_a11y.Spin_button);
  check int "status bar" 50017 (get Lui_a11y.Status_bar);
  check int "tabs" 50018 (get Lui_a11y.Tab_group);
  check int "tab" 50019 (get Lui_a11y.Tab);
  check int "text" 50020 (get Lui_a11y.Static_text);
  check int "toolbar" 50021 (get Lui_a11y.Toolbar);
  check int "tooltip" 50022 (get Lui_a11y.Tooltip);
  check int "tree" 50023 (get Lui_a11y.Outline);
  check int "tree item" 50024 (get Lui_a11y.Outline_item);
  check int "data item" 50029 (get Lui_a11y.Table_row);
  check int "window" 50032 (get Lui_a11y.Window);
  check int "dialog as pane" 50033 (get Lui_a11y.Dialog);
  check int "table grid" 50036 (get Lui_a11y.Table);
  check int "separator" 50038 (get Lui_a11y.Separator)

let test_localized_type () =
  let of_role r =
    Lui_ax_windows.localized_type_of (node ~role:r ())
  in
  List.iter
    (fun r ->
      let _ : string = of_role r in
      ())
    all_roles;
  check string "switch reads as toggle" "toggle switch"
    (of_role Lui_a11y.Switch);
  check string "dialog reads as dialog" "dialog" (of_role Lui_a11y.Dialog);
  check string "button uses the type name" "" (of_role Lui_a11y.Button)

(* ---------- patterns ---------- *)

let has bit m = m land bit <> 0

let test_patterns () =
  let of_role r = Lui_ax_windows.patterns_of (node ~role:r ()) in
  (* scroll-into-view on everything *)
  List.iter
    (fun r ->
      check bool (Lui_a11y.role_name r ^ " scrollable") true
        (has 128 (of_role r)))
    all_roles;
  check bool "button invokes" true (has 1 (of_role Lui_a11y.Button));
  check bool "link invokes" true (has 1 (of_role Lui_a11y.Link));
  check bool "checkbox toggles" true (has 2 (of_role Lui_a11y.Check_box));
  check bool "switch toggles" true (has 2 (of_role Lui_a11y.Switch));
  check bool "toggle button toggles" true
    (has 2 (of_role Lui_a11y.Toggle_button));
  check bool "checkbox does not invoke" false
    (has 1 (of_role Lui_a11y.Check_box));
  check bool "slider ranges" true (has 16 (of_role Lui_a11y.Slider));
  check bool "spin ranges" true (has 16 (of_role Lui_a11y.Spin_button));
  check bool "progress ranges" true
    (has 16 (of_role Lui_a11y.Progress_indicator));
  check bool "field edits" true (has 32 (of_role Lui_a11y.Text_field));
  check bool "textarea edits" true (has 32 (of_role Lui_a11y.Text_area));
  check bool "combo edits" true (has 32 (of_role Lui_a11y.Combo_box));
  check bool "list selects" true (has 8 (of_role Lui_a11y.List));
  check bool "table selects" true (has 8 (of_role Lui_a11y.Table));
  check bool "tab group selects" true
    (has 8 (of_role Lui_a11y.Tab_group));
  check bool "radio group selects" true
    (has 8 (of_role Lui_a11y.Radio_group));
  check bool "radio is a selection item" true
    (has 4 (of_role Lui_a11y.Radio_button));
  check bool "tab is a selection item" true (has 4 (of_role Lui_a11y.Tab));
  check bool "combo expands" true (has 64 (of_role Lui_a11y.Combo_box));
  (* state-dependent bits *)
  let li = node ~role:Lui_a11y.List_item ~focusable:true () in
  check bool "focusable row is a selection item" true
    (has 4 (Lui_ax_windows.patterns_of li));
  let tree_item =
    node ~role:Lui_a11y.Outline_item ~expanded:(Some false) ()
  in
  check bool "expandable tree item" true
    (has 64 (Lui_ax_windows.patterns_of tree_item));
  check bool "plain tree item is a leaf but still has the pattern"
    true
    (has 64
       (Lui_ax_windows.patterns_of
          (node ~role:Lui_a11y.Outline_item ())))

let test_states () =
  let ts role chk =
    Lui_ax_windows.toggle_state_of (node ~role ~checked:chk ())
  in
  check int "checked" 1 (ts Lui_a11y.Check_box (Some Lui_a11y.Checked));
  check int "unchecked" 0
    (ts Lui_a11y.Check_box (Some Lui_a11y.Unchecked));
  check int "mixed" 2 (ts Lui_a11y.Switch (Some Lui_a11y.Mixed));
  check int "checkable menu item" 1
    (ts Lui_a11y.Menu_item (Some Lui_a11y.Checked));
  check int "button does not toggle" (-1)
    (ts Lui_a11y.Button (Some Lui_a11y.Checked));
  let es role expanded =
    Lui_ax_windows.expand_state_of
      (node ~role ~expanded ())
  in
  check int "expanded" 1 (es Lui_a11y.Outline_item (Some true));
  check int "collapsed" 0 (es Lui_a11y.Outline_item (Some false));
  check int "leaf" 3 (es Lui_a11y.Outline_item None);
  check int "no expand" (-1) (es Lui_a11y.Button None)

let test_action_masks () =
  let m = Lui_ax_windows.actions_of (node ~role:Lui_a11y.Button
                                       ~focusable:true ()) in
  check bool "button press" true (has 1 m);
  check bool "button focus" true (has 8 m);
  check bool "button scroll" true (has 32 m);
  check bool "button no incr" false (has 2 m);
  let m = Lui_ax_windows.actions_of (node ~role:Lui_a11y.Slider ()) in
  check bool "slider incr" true (has 2 m);
  check bool "slider decr" true (has 4 m);
  check bool "slider no press" false (has 1 m);
  let m =
    Lui_ax_windows.actions_of
      (node ~role:Lui_a11y.Text_field ~focusable:true ())
  in
  check bool "field set-value" true (has 16 m);
  let m =
    Lui_ax_windows.actions_of
      (node ~role:Lui_a11y.Text_field ~focusable:true
         ~read_only:true ())
  in
  check bool "read-only no set-value" false (has 16 m);
  let m =
    Lui_ax_windows.actions_of
      (node ~role:Lui_a11y.Outline_item ~expanded:(Some false) ())
  in
  check bool "outline disclose" true (has 64 m);
  let m = Lui_ax_windows.actions_of (node ~role:Lui_a11y.Static_text ())
  in
  check bool "text: scroll only" true (m = 32)

(* ---------- notifications ---------- *)

let notif_testable =
  testable
    (fun fmt (n, tgt) ->
      let nname =
        match n with
        | Lui_ax_windows.Prop (p, _, _) -> "prop:" ^ string_of_int p
        | Lui_ax_windows.Event e -> "event:" ^ string_of_int e
      in
      Format.fprintf fmt "%s@%s" nname
        (match tgt with
         | Lui_ax_windows.On_element -> "self"
         | Lui_ax_windows.On_parent -> "parent"
         | Lui_ax_windows.On_root -> "root"))
    ( = )

let notifs ~old ~cur =
  List.sort compare (Lui_ax_windows.notifications_of ~old ~cur)

let test_notif_quiet_endpoints () =
  let o = node ~id:2 ~role:Lui_a11y.Button () in
  check (list notif_testable) "removal posts nothing here" []
    (notifs ~old:(Some o) ~cur:None);
  check (list notif_testable) "creation posts nothing here" []
    (notifs ~old:None ~cur:(Some o))

let test_notif_props () =
  let open Lui_ax_windows in
  let o = node ~role:Lui_a11y.Static_text ~name:(Some "a") () in
  let n = node ~role:Lui_a11y.Static_text ~name:(Some "b") () in
  check (list notif_testable) "rename"
    [ (Prop (prop_name, V_str "a", V_str "b"), On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  let o = node ~role:Lui_a11y.Button () in
  let n = node ~role:Lui_a11y.Button ~disabled:true () in
  check (list notif_testable) "disable"
    [ (Prop (prop_is_enabled, V_bool true, V_bool false), On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  let o = node ~role:Lui_a11y.Check_box ~checked:(Some Lui_a11y.Unchecked)
              () in
  let n = node ~role:Lui_a11y.Check_box ~checked:(Some Lui_a11y.Checked)
              () in
  check (list notif_testable) "check toggles ToggleState"
    [ (Prop (prop_toggle_state, V_int 0, V_int 1), On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n))

let test_notif_value () =
  let open Lui_ax_windows in
  let v x =
    Some Lui_a11y.{ numeric = Some x; minimum = Some 0.;
                    maximum = Some 1.; text = None }
  in
  let o = node ~role:Lui_a11y.Slider ~value:(v 0.5) () in
  let n = node ~role:Lui_a11y.Slider ~value:(v 0.7) () in
  check (list notif_testable) "numeric -> RangeValue.Value"
    [ (Prop (prop_range_value, V_num 0.5, V_num 0.7), On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  let vt s =
    Some Lui_a11y.{ numeric = None; minimum = None; maximum = None;
                    text = Some s }
  in
  let o = node ~role:Lui_a11y.Text_field ~value:(vt "a") () in
  let n = node ~role:Lui_a11y.Text_field ~value:(vt "ab") () in
  check (list notif_testable) "text -> Value.Value"
    [ (Prop (prop_value, V_str "a", V_str "ab"), On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n))

let test_notif_events () =
  let open Lui_ax_windows in
  let o = node ~role:Lui_a11y.Button ~name:(Some "a") () in
  let n = node ~role:Lui_a11y.Button ~name:(Some "a") ~focused:true () in
  check (list notif_testable) "new focus -> focus event"
    [ (Event event_focus_changed, On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  let o = node ~role:Lui_a11y.List_item ~focusable:true () in
  let n =
    node ~role:Lui_a11y.List_item ~focusable:true ~selected:true ()
  in
  check (list notif_testable) "select -> prop + event"
    [ (Prop (prop_is_selected, V_bool false, V_bool true), On_element);
      (Event event_element_selected, On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  let o = node ~role:Lui_a11y.Outline_item ~expanded:(Some false) () in
  let n = node ~role:Lui_a11y.Outline_item ~expanded:(Some true) () in
  check (list notif_testable) "expand -> prop"
    [ (Prop (prop_expand_state, V_int 0, V_int 1), On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n))

(* ---------- structure ---------- *)

let test_structure () =
  let sc ~old ~cur = Lui_ax_windows.structure_changed ~old ~cur in
  let inv ~old ~cur = Lui_ax_windows.struct_invalidations ~old ~cur in
  let a = node ~id:1 ~role:Lui_a11y.Group ~children:[ 2; 3 ] () in
  let b = node ~id:1 ~role:Lui_a11y.Group ~children:[ 2; 3; 4 ] () in
  check bool "children changed" true (sc ~old:(Some a) ~cur:(Some b));
  check bool "same tree" false (sc ~old:(Some a) ~cur:(Some a));
  check bool "added" true (sc ~old:None ~cur:(Some a));
  check bool "removed" true (sc ~old:(Some a) ~cur:None);
  let reparented = node ~id:1 ~role:Lui_a11y.Group ~parent:(Some 9) () in
  check bool "reparent" true (sc ~old:(Some a) ~cur:(Some reparented));
  let roled = node ~id:1 ~role:Lui_a11y.Button () in
  check bool "role swap" true (sc ~old:(Some a) ~cur:(Some roled));
  check (list int) "children list invalidates self" [ 1 ]
    (inv ~old:(Some a) ~cur:(Some b));
  check (list int) "new child invalidates its parent" [ 1 ]
    (inv ~old:None
       ~cur:(Some (node ~id:4 ~role:Lui_a11y.Group ~parent:(Some 1) ())));
  check (list int) "root removal invalidates the frame" [ -1 ]
    (inv ~old:(Some a) ~cur:None)

(* ---------- utf16 ---------- *)

let test_utf16 () =
  check int "ascii" 3 (Lui_ax_windows.utf16_length "abc");
  check int "bmp" 3
    (Lui_ax_windows.utf16_length "a\xC3\xA9\xE4\xB8\xAD");
  check int "astral counts 2" 5
    (Lui_ax_windows.utf16_length "ab\xF0\x9F\x98\x80c");
  check (array int) "astral pair"
    [| 0x61; 0xD83D; 0xDE00 |]
    (Lui_ax_windows.utf16_encode "a\xF0\x9F\x98\x80");
  check (array int) "lone continuation becomes replacement"
    [| 0xFFFD; 0x61 |]
    (Lui_ax_windows.utf16_encode "\x80a");
  check int "invalid counts like encoding" 2
    (Lui_ax_windows.utf16_length "\x80a")

let () =
  run "lui_ax_windows"
    [ ( "control types",
        [ test_case "every role mapped" `Quick
            test_table_covers_all_roles;
          test_case "spot checks" `Quick test_spot_checks;
          test_case "localized names" `Quick test_localized_type ] );
      ( "patterns",
        [ test_case "pattern bits" `Quick test_patterns;
          test_case "state enums" `Quick test_states;
          test_case "action masks" `Quick test_action_masks ] );
      ( "notifications",
        [ test_case "endpoints quiet" `Quick test_notif_quiet_endpoints;
          test_case "properties" `Quick test_notif_props;
          test_case "values" `Quick test_notif_value;
          test_case "events" `Quick test_notif_events;
          test_case "structure" `Quick test_structure ] );
      ("helpers", [ test_case "utf16" `Quick test_utf16 ]) ]
