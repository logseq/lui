open Alcotest

(* ---------- helpers ---------- *)

let node ?(id = 1) ?(role = Lui_a11y.Group) ?(name = None)
    ?(parent = None) ?(children = []) ?(value = None)
    ?(focusable = false) ?(focused = false) ?(selected = false)
    ?(checked = None) ?(disabled = false) ?(expanded = None)
    ?(read_only = false) ?(password = false) () : Lui_a11y.node_a11y =
  { id; kind = "k"; role; name; description = None;
    state =
      { focusable; focused; selected; checked; disabled; expanded;
        required = false; read_only; password };
    value; parent; children; ext_id = None }

let all_roles : Lui_a11y.role list =
  Lui_a11y.
    [ Window; Group; Static_text; Heading; Text_field; Text_area;
      Search_field; Button; Toggle_button; Check_box; Radio_button;
      Radio_group; Switch; Slider; Spin_button; Progress_indicator;
      Link; Image; List; List_item; Outline; Outline_item; Tab_group;
      Tab; Menu; Menu_item; Combo_box; Dialog; Sheet; Tooltip; Table;
      Table_row; Table_cell; Separator; Toolbar; Status_bar; Navigation;
      Split_group; Extension ]

(* ---------- role map completeness ---------- *)

let test_role_table_covers_all_roles () =
  List.iter
    (fun r ->
      let name = Lui_a11y.role_name r in
      match List.assoc_opt r Lui_ax.ax_role_table with
      | None -> fail ("no AX role for " ^ name)
      | Some (ax, sub) ->
        check bool (name ^ " has AX role") true (ax <> "");
        check bool (name ^ " role is AX-prefixed") true
          (String.length ax > 2 && String.sub ax 0 2 = "AX");
        check bool (name ^ " subrole prefixed or empty") true
          (sub = ""
           || (String.length sub > 2 && String.sub sub 0 2 = "AX")))
    all_roles

let test_role_table_spot_checks () =
  let get r = List.assoc r Lui_ax.ax_role_table in
  check (pair string string) "switch subrole" ("AXCheckBox", "AXSwitch")
    (get Lui_a11y.Switch);
  check (pair string string) "toggle button"
    ("AXCheckBox", "AXToggle") (get Lui_a11y.Toggle_button);
  check (pair string string) "search field"
    ("AXTextField", "AXSearchField") (get Lui_a11y.Search_field);
  check (pair string string) "tab" ("AXRadioButton", "AXTabButton")
    (get Lui_a11y.Tab);
  check (pair string string) "outline item"
    ("AXRow", "AXOutlineRow") (get Lui_a11y.Outline_item);
  check (pair string string) "list item" ("AXRow", "AXTableRow")
    (get Lui_a11y.List_item);
  check (pair string string) "list -> table" ("AXTable", "")
    (get Lui_a11y.List);
  check (pair string string) "dialog subrole" ("AXGroup", "AXDialog")
    (get Lui_a11y.Dialog);
  check (pair string string) "status bar"
    ("AXGroup", "AXApplicationStatus") (get Lui_a11y.Status_bar);
  check (pair string string) "stepper" ("AXIncrementor", "")
    (get Lui_a11y.Spin_button);
  check (pair string string) "window" ("AXWindow", "")
    (get Lui_a11y.Window)

let test_role_state_subroles () =
  let password_field =
    node ~role:Lui_a11y.Text_field ~password:true ()
  in
  check (pair string string) "password -> secure"
    ("AXTextField", "AXSecureTextField")
    (Lui_ax.ax_role_of password_field);
  let plain_field = node ~role:Lui_a11y.Text_field () in
  check (pair string string) "plain field"
    ("AXTextField", "") (Lui_ax.ax_role_of plain_field)

(* ---------- notification selection ---------- *)

let notif_testable =
  testable
    (fun fmt (name, tgt) ->
      Format.fprintf fmt "%s@%s" name
        (match tgt with
         | Lui_ax.On_element -> "self"
         | Lui_ax.On_parent -> "parent"
         | Lui_ax.On_view -> "view"))
    ( = )

let notifs ~old ~cur =
  List.sort compare (Lui_ax.notifications_of ~old ~cur)

let test_notif_removed () =
  let o = node ~id:2 ~role:Lui_a11y.Button () in
  check (list notif_testable) "removed -> destroyed on element"
    [ (Lui_ax.notif_destroyed, Lui_ax.On_element) ]
    (notifs ~old:(Some o) ~cur:None)

let test_notif_value () =
  let v x =
    Some Lui_a11y.{ numeric = Some x; minimum = Some 0.; maximum = Some 1.;
                   text = None }
  in
  let o = node ~role:Lui_a11y.Slider ~value:(v 0.5) () in
  let n = node ~role:Lui_a11y.Slider ~value:(v 0.7) () in
  check (list notif_testable) "numeric change -> value on element"
    [ (Lui_ax.notif_value, Lui_ax.On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  (* checked state feeds the toggle's AX value too *)
  let o = node ~role:Lui_a11y.Check_box ~checked:(Some Lui_a11y.Unchecked) () in
  let n = node ~role:Lui_a11y.Check_box ~checked:(Some Lui_a11y.Checked) () in
  check (list notif_testable) "checked change -> value"
    [ (Lui_ax.notif_value, Lui_ax.On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n))

let test_notif_title_and_focus () =
  let o = node ~role:Lui_a11y.Static_text ~name:(Some "a") () in
  let n = node ~role:Lui_a11y.Static_text ~name:(Some "b") () in
  check (list notif_testable) "name change -> title"
    [ (Lui_ax.notif_title, Lui_ax.On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  let calm = node ~role:Lui_a11y.Button ~name:(Some "a") () in
  let n = node ~role:Lui_a11y.Button ~name:(Some "a") ~focused:true () in
  check (list notif_testable) "new focus -> focused"
    [ (Lui_ax.notif_focused, Lui_ax.On_element) ]
    (notifs ~old:(Some calm) ~cur:(Some n));
  (* losing focus alone is not announced *)
  check (list notif_testable) "blur quiet" []
    (notifs ~old:(Some n) ~cur:(Some calm))

let test_notif_selection_and_expanded () =
  let o = node ~role:Lui_a11y.List_item ~selected:false () in
  let n = node ~role:Lui_a11y.List_item ~selected:true () in
  check (list notif_testable) "row selected -> selected-rows on parent"
    [ (Lui_ax.notif_selected_rows, Lui_ax.On_parent) ]
    (notifs ~old:(Some o) ~cur:(Some n));
  let o = node ~role:Lui_a11y.Outline_item ~expanded:(Some false) () in
  let n = node ~role:Lui_a11y.Outline_item ~expanded:(Some true) () in
  check (list notif_testable) "expanded -> expanded on element"
    [ (Lui_ax.notif_expanded, Lui_ax.On_element) ]
    (notifs ~old:(Some o) ~cur:(Some n))

let test_notif_quiet_changes () =
  let o = node ~role:Lui_a11y.Button () in
  let n = node ~role:Lui_a11y.Button ~disabled:true () in
  check (list notif_testable) "enabled-only change posts nothing" []
    (notifs ~old:(Some o) ~cur:(Some n))

let test_structure_changed () =
  let sc ~old ~cur = Lui_ax.structure_changed ~old ~cur in
  let a = node ~id:1 ~role:Lui_a11y.Group ~children:[ 2; 3 ] () in
  let b = node ~id:1 ~role:Lui_a11y.Group ~children:[ 2; 3; 4 ] () in
  check bool "children changed" true (sc ~old:(Some a) ~cur:(Some b));
  check bool "same tree" false (sc ~old:(Some a) ~cur:(Some a));
  check bool "added" true (sc ~old:None ~cur:(Some a));
  check bool "removed" true (sc ~old:(Some a) ~cur:None);
  let reparented = node ~id:1 ~role:Lui_a11y.Group ~parent:(Some 9) () in
  check bool "reparent" true (sc ~old:(Some a) ~cur:(Some reparented));
  let roled = node ~id:1 ~role:Lui_a11y.Button () in
  check bool "role swap" true (sc ~old:(Some a) ~cur:(Some roled))

(* ---------- action mask ---------- *)

let has bit m = m land bit <> 0

let test_action_masks () =
  let m =
    Lui_ax.actions_of (node ~role:Lui_a11y.Button ~focusable:true ())
  in
  check bool "button press" true (has 1 m);
  check bool "button focus" true (has 8 m);
  check bool "button scroll" true (has 32 m);
  check bool "button no incr" false (has 2 m);
  let m = Lui_ax.actions_of (node ~role:Lui_a11y.Slider ()) in
  check bool "slider incr" true (has 2 m);
  check bool "slider decr" true (has 4 m);
  check bool "slider no press" false (has 1 m);
  let m =
    Lui_ax.actions_of
      (node ~role:Lui_a11y.Text_field ~focusable:true ())
  in
  check bool "field set-value" true (has 16 m);
  let m =
    Lui_ax.actions_of
      (node ~role:Lui_a11y.Text_field ~focusable:true ~read_only:true ())
  in
  check bool "read-only no set-value" false (has 16 m);
  let m =
    Lui_ax.actions_of
      (node ~role:Lui_a11y.Outline_item ~expanded:(Some false) ())
  in
  check bool "outline disclose" true (has 64 m);
  let m = Lui_ax.actions_of (node ~role:Lui_a11y.Static_text ()) in
  check bool "text: scroll only" true (m = 32)

(* ---------- pure helpers ---------- *)

let test_y_flip () =
  let r = Lui_ax.y_flip ~container_height:100.
      { Lui_ax.x = 5.; y = 10.; w = 30.; h = 20. } in
  check (float 1e-9) "flipped y" 70. r.y;
  check (float 1e-9) "x kept" 5. r.x;
  check (float 1e-9) "size kept" 20. r.h;
  (* top-edge (y=0) and bottom-edge boxes swap exactly *)
  let r = Lui_ax.y_flip ~container_height:100.
      { Lui_ax.x = 0.; y = 0.; w = 1.; h = 100. } in
  check (float 1e-9) "full height stays" 0. r.y

let test_utf16_length () =
  check int "ascii" 3 (Lui_ax.utf16_length "abc");
  check int "bmp" 3 (Lui_ax.utf16_length "a\xC3\xA9\xE4\xB8\xAD");
  check int "astral counts 2" 5
    (Lui_ax.utf16_length "ab\xF0\x9F\x98\x80c")

let () =
  run "lui_ax"
    [ ( "roles",
        [ test_case "every role mapped" `Quick
            test_role_table_covers_all_roles;
          test_case "spot checks" `Quick test_role_table_spot_checks;
          test_case "state subroles" `Quick test_role_state_subroles ] );
      ( "notifications",
        [ test_case "removed" `Quick test_notif_removed;
          test_case "value" `Quick test_notif_value;
          test_case "title + focus" `Quick test_notif_title_and_focus;
          test_case "selection + expanded" `Quick
            test_notif_selection_and_expanded;
          test_case "quiet" `Quick test_notif_quiet_changes;
          test_case "structure" `Quick test_structure_changed ] );
      ( "actions", [ test_case "masks" `Quick test_action_masks ] );
      ( "helpers",
        [ test_case "y flip" `Quick test_y_flip;
          test_case "utf16 length" `Quick test_utf16_length ] ) ]
