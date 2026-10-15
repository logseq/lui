(* End-to-end input flows through the real window input layer:
   Lui_window.Ui.handle turns Input.t into dispatch actions that reach
   real apps through Lui_app — IME composition and commit, key
   suppression while composing, context-menu and menu-button
   activation, and the a11y listing of a hand-built list. Everything
   stays headless: stores come from the e2e harness, rects from the
   real layout engine. *)

open Alcotest
open Lui_e2e
open Lui_scene
open Lui_protocol
open Lui_window

(* ---------- plumbing ---------- *)

let boot_view ~initial ~update ~view () =
  let h = E2e_harness.create () in
  let backend = E2e_harness.backend h (generic_profile ()) in
  let app = Lui_app.create backend initial update view in
  check bool "start" true (Lui_app.start app);
  check bool "flush" true (Lui_app.flush app);
  ignore (E2e_harness.repaint h);
  (h, app)

let boot () = boot_view ~initial:E2e_app.initial ~update:E2e_app.update
    ~view:E2e_app.view ()

let rects_of h =
  let rects = Lui_window.Rects.create () in
  let store = E2e_harness.store h in
  List.iter
    (fun n ->
      let id = Lui_store.node_id n in
      match Lui_host.layout_rect (E2e_harness.host h) id with
      | Some r -> Hashtbl.replace rects id r
      | None -> ())
    (Lui_store.all_nodes store);
  rects

let dispatched acts =
  List.filter_map (function Lui_window.Dispatch e -> Some e | _ -> None)
    acts

let deliver app acts =
  List.map (fun e -> (e, Lui_app.dispatch_event app e)) (dispatched acts)

let center (r : Lui_scene.rect) = (r.x +. r.w /. 2., r.y +. r.h /. 2.)

let left_click ui store rects r =
  let (x, y) = center r in
  Ui.handle ui store rects (Input.Move (x, y))
  @ Ui.handle ui store rects
      (Input.Button_down (x, y, Input.Left, 1, Input.mods_none))
  @ Ui.handle ui store rects
      (Input.Button_up (x, y, Input.Left, Input.mods_none))

(* A right-click gesture at the rect's center: hover, press, release. *)
let right_click_to ui store rects (r : Lui_scene.rect) =
  let (x, y) = center r in
  Ui.handle ui store rects (Input.Move (x, y))
  @ Ui.handle ui store rects
      (Input.Button_down (x, y, Input.Right, 1, Input.mods_none))
  @ Ui.handle ui store rects
      (Input.Button_up (x, y, Input.Right, Input.mods_none))

let rect_of_id h id =
  match Lui_host.layout_rect (E2e_harness.host h) id with
  | Some r -> r
  | None -> fail "node has no layout rect"

let first_kind store kind =
  match E2e_harness.kind_nodes store kind with
  | id :: _ -> id
  | [] -> fail ("no node of kind " ^ kind)

(* ---------- IME ---------- *)

(* A composition on a focused field marks text without dispatching,
   suppresses keys, and commits the final string through TextChanged —
   the same path a real IME driver feeds. *)
let test_ime_composition () =
  let h, app = boot () in
  let store = E2e_harness.store h and rects = rects_of h in
  let fid = first_kind store "text-field" in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  let acts = left_click ui store rects (rect_of_id h fid) in
  check int "field focused" fid (Ui.focused ui);
  check bool "focus action" true
    (List.exists (function Lui_window.Focus_changed n -> n = fid
                          | _ -> false) acts);
  ignore (deliver app acts);
  (* Marked text arrives; nothing is dispatched to the app. *)
  let acts =
    Ui.handle ui store rects (Input.Text_editing ("にほ", 2, 0)) in
  check string "marked" "にほ" (Ui.marked ui);
  check int "no dispatch while composing" 0
    (List.length (dispatched acts));
  check bool "composing" true (Lui_ime.composing (Ui.ime ui));
  (* Keys belong to the IME while composing. *)
  let acts =
    Ui.handle ui store rects
      (Input.Key_down (Input.Return, Input.mods_none, false)) in
  check int "keys suppressed" 0 (List.length acts);
  (* Commit: the field's app sees the committed text. *)
  let acts = Ui.handle ui store rects (Input.Text_input "日本語") in
  check string "unmarked" "" (Ui.marked ui);
  (match dispatched acts with
   | [ TextChanged (n, s) ] ->
     check int "target" fid n;
     check string "committed" "日本語" s
   | _ -> fail "expected one TextChanged");
  List.iter
    (fun (e, ok) ->
      check bool "delivered" true ok;
      ignore e)
    (deliver app acts);
  check bool "app flush" true (Lui_app.flush app);
  let m : E2e_app.model = Lui_app.model app in
  check string "model draft" "日本語" m.E2e_app.draft

(* A tiny app with a textarea — the multiline input primitive — plus a
   menu button and a right-click target opening the same menu. *)
type m2 = { area : string; menu : string list; picked : string }

type a2 = Area of string | Open | Pick of string

let init2 = { area = ""; menu = []; picked = "" }

let upd2 m = function
  | Area s -> { m with area = s }
  | Open -> { m with menu = [ "copy"; "paste" ] }
  | Pick s -> { m with picked = s; menu = [] }

let view2 _ctx ms send : Lui_elements.t =
  let open Lui_elements in
  column ~padding:8
    [ textarea ~width:200 ~height:40
        ~text_signal:(reactive (fun m -> m.area) ms)
        ~on_context_menu:(press send Open)
        ~on_input:(on_input send (fun s -> Area s)) []
    ; button ~text:"menu" ~on_press:(press send Open)
        ~on_context_menu:(press send Open) []
    ; context_menu
        [ keyed ~source:(map (fun m -> m.menu) ms) ~key:(fun s -> s)
            ~cmp:String.compare
            ~mount:(fun s ->
              let item = sample s in
              menu_item ~text_signal:(reactive (fun v -> v) s)
                ~on_press:(press send (Pick item)) []) ] ]

let boot2 () = boot_view ~initial:init2 ~update:upd2 ~view:view2 ()

(* IME on a textarea: composition + commit reach the model. *)
let test_ime_textarea () =
  let h, app = boot2 () in
  let store = E2e_harness.store h and rects = rects_of h in
  let tid = first_kind store "textarea" in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  let acts = left_click ui store rects (rect_of_id h tid) in
  check int "area focused" tid (Ui.focused ui);
  ignore (deliver app acts);
  let acts =
    Ui.handle ui store rects (Input.Text_editing ("かな", 2, 0)) in
  ignore acts;
  check string "marked" "かな" (Ui.marked ui);
  let acts = Ui.handle ui store rects (Input.Text_input "仮名") in
  (match dispatched acts with
   | [ TextChanged (n, s) ] ->
     check int "target" tid n;
     check string "committed" "仮名" s
   | _ -> fail "expected one TextChanged");
  ignore (deliver app acts);
  check bool "flush" true (Lui_app.flush app);
  let m : m2 = Lui_app.model app in
  check string "model area" "仮名" m.area;
  (* Committed text splices at the caret inside existing text. *)
  ignore
    (Ui.handle ui store rects (Input.Key_down (Input.Home, Input.mods_none, false)));
  let acts = Ui.handle ui store rects (Input.Text_input "カ") in
  (match dispatched acts with
   | [ TextChanged (n, s) ] ->
     check int "target" tid n;
     check string "spliced" "カ仮名" s
   | _ -> fail "expected splice")

(* A left click focuses the field and the next text input reaches it at
   once — the focus assignment applies before the input is handled. *)
let test_input_follows_focus () =
  let h, app = boot () in
  let store = E2e_harness.store h and rects = rects_of h in
  let fid = first_kind store "text-field" in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  ignore (deliver app (left_click ui store rects (rect_of_id h fid)));
  check int "focused at once" fid (Ui.focused ui);
  let acts = Ui.handle ui store rects (Input.Text_input "typed") in
  (match dispatched acts with
   | [ TextChanged (n, s) ] ->
     check int "routed to focus" fid n;
     check string "text" "typed" s
   | _ -> fail "expected one TextChanged");
  ignore (deliver app acts);
  check bool "flush" true (Lui_app.flush app);
  let m : E2e_app.model = Lui_app.model app in
  check string "model draft" "typed" m.E2e_app.draft

(* Right-clicking a text input opens its context menu — the input is
   itself a context-menu host. *)
let test_input_context_menu () =
  let h, app = boot2 () in
  let store = E2e_harness.store h and rects = rects_of h in
  let tid = first_kind store "textarea" in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  let acts = right_click_to ui store rects (rect_of_id h tid) in
  check bool "context press on input" true
    (List.exists
       (function ContextMenuPress (n, d) ->
          n = tid && d.modifiers land 8 <> 0 | _ -> false)
       (dispatched acts));
  ignore (deliver app acts);
  check bool "flush" true (Lui_app.flush app);
  let m : m2 = Lui_app.model app in
  check (list string) "menu open" [ "copy"; "paste" ] m.menu

(* With nested context menus the press goes to the innermost host — a
   menu item with its own context menu inside a button's menu wins over
   the button that hosts the outer menu. *)
let test_innermost_menu () =
  let view _ctx _ms send : Lui_elements.t =
    let open Lui_elements in
    column
      [ button ~text:"outer" ~on_press:(press send Open)
          ~on_context_menu:(press send Open)
          [ menu_item ~text:"sub" ~on_press:(press send (Pick "sub"))
              ~on_context_menu:(press send (Pick "inner")) [] ] ]
  in
  let h, _app = boot_view ~initial:init2 ~update:upd2 ~view () in
  let store = E2e_harness.store h and rects = rects_of h in
  let sub =
    match E2e_harness.find_text_id store "menu-item" "sub" with
    | Some id -> id
    | None -> fail "sub item not found"
  in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  let r = rect_of_id h sub in
  Printf.printf "sub %d rect %g %g %g %g\n" sub r.x r.y r.w r.h;
  let (x, y) = center r in
  Printf.printf "hit %s\n"
    (String.concat ","
       (List.map (fun id -> Printf.sprintf "%d:%s" id (Lui_store.kind store id))
          (Lui_window.hit_path store rects ~x ~y)));
  let acts = right_click_to ui store rects r in
  List.iter
    (function Lui_window.Dispatch (ContextMenuPress (n, _)) ->
       Printf.printf "cmenu %d\n" n
      | Lui_window.Dispatch e ->
        Printf.printf "disp node %d\n" (Lui_protocol.event_node e)
      | _ -> ())
    acts;
  check bool "innermost host gets press" true
    (List.exists
       (function ContextMenuPress (n, _) -> n = sub | _ -> false)
       (dispatched acts))

(* Tab moves the focus to the next focusable node; the host sees a
   Focus_changed action for the second field. *)
let test_tab_focus () =
  let view _ctx ms send : Lui_elements.t =
    let open Lui_elements in
    column
      [ textarea ~width:200 ~height:20
          ~text_signal:(reactive (fun m -> m.area) ms)
          ~on_input:(on_input send (fun s -> Area s)) []
      ; textarea ~width:200 ~height:20
          ~text_signal:(reactive (fun m -> m.area) ms)
          ~on_input:(on_input send (fun s -> Area s)) [] ]
  in
  let h, _app = boot_view ~initial:init2 ~update:upd2 ~view () in
  let store = E2e_harness.store h and rects = rects_of h in
  let fields = E2e_harness.kind_nodes store "textarea" in
  check int "two focusables" 2 (List.length fields);
  let first = List.nth fields 0 and second = List.nth fields 1 in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  ignore (left_click ui store rects (rect_of_id h first));
  check int "clicked focused" first (Ui.focused ui);
  let acts =
    Ui.handle ui store rects
      (Input.Key_down (Input.Tab, Input.mods_none, false))
  in
  check int "focus moved" second (Ui.focused ui);
  check bool "focus action" true
    (List.exists (function Lui_window.Focus_changed n -> n = second
                          | _ -> false) acts)

(* Hover keeps tracking while a button is held: moving off the pressed
   node still reports PointerLeave/PointerEnter to the pointer layer. *)
let test_hover_while_pressed () =
  let h, _app = boot () in
  let store = E2e_harness.store h and rects = rects_of h in
  let bid =
    match E2e_harness.find_text_id store "button" "add" with
    | Some id -> id
    | None -> fail "add button not found"
  in
  let other =
    match E2e_harness.find_text_id store "button" "x-alpha" with
    | Some id -> id
    | None -> fail "item button not found"
  in
  (* Opt both buttons into pointer events; on_press alone does not. *)
  check bool "enable pointer" true
    (E2e_harness.apply_batch h
       { generation = 2;
         ops =
           [ SetProp (bid, PointerEnabled, BoolValue true);
             SetProp (other, PointerEnabled, BoolValue true) ] });
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  let r = rect_of_id h bid in
  let (x, y) = center r in
  ignore (Ui.handle ui store rects (Input.Move (x, y)));
  ignore
    (Ui.handle ui store rects
       (Input.Button_down (x, y, Input.Left, 1, Input.mods_none)));
  (* Drag (still held) over the other button: hover transitions fire. *)
  let (ox, oy) = center (rect_of_id h other) in
  let acts = Ui.handle ui store rects (Input.Move (ox, oy)) in
  check bool "leave emitted" true
    (List.exists
       (function Lui_window.Dispatch (PointerLeave _) -> true
                | _ -> false)
       acts);
  check bool "enter emitted" true
    (List.exists
       (function Lui_window.Dispatch (PointerEnter _) -> true
                | _ -> false)
       acts)

(* A resize at the very first frame reports Resize_host — the host
   picks the new drawable size up before any other input. *)
let test_resize_first_frame () =
  let h, _app = boot () in
  let store = E2e_harness.store h and rects = rects_of h in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  let acts = Ui.handle ui store rects (Input.Resize (160, 120)) in
  check bool "resize action" true
    (List.exists (function Lui_window.Resize_host (160, 120) -> true
                          | _ -> false) acts)

(* The in-content menu button opens a menu whose items press through —
   and the same menu opens from a right-click ContextMenuPress. *)
let open_menu_and_pick ~via_right_click () =
  let h, app = boot2 () in
  let store = E2e_harness.store h and rects = rects_of h in
  let bid =
    match E2e_harness.find_text_id store "button" "menu" with
    | Some id -> id
    | None -> fail "menu button not found"
  in
  let ui = Ui.create () in
  Ui.set_scale ui 1.;
  let r = rect_of_id h bid in
  let (x, y) = center r in
  ignore (Ui.handle ui store rects (Input.Move (x, y)));
  let acts_d =
    Ui.handle ui store rects
      (Input.Button_down
         (x, y, (if via_right_click then Input.Right else Input.Left),
          1, Input.mods_none))
  in
  let acts_u =
    Ui.handle ui store rects
      (Input.Button_up
         (x, y, (if via_right_click then Input.Right else Input.Left),
          Input.mods_none))
  in
  let acts = acts_d @ acts_u in
  let results = deliver app acts in
  let wanted =
    if via_right_click then
      List.exists (function ContextMenuPress (n, d) ->
          n = bid && d.modifiers land 8 <> 0 | _ -> false)
        (dispatched acts)
    else List.exists (function Press n -> n = bid | _ -> false)
        (dispatched acts)
  in
  check bool "activation event" true wanted;
  check bool "delivered" true (List.for_all snd results);
  check bool "flush" true (Lui_app.flush app);
  let m : m2 = Lui_app.model app in
  check (list string) "menu open" [ "copy"; "paste" ] m.menu;
  (* The menu items are real nodes now; pressing one picks it. *)
  ignore (E2e_harness.repaint h);
  let store = E2e_harness.store h and rects = rects_of h in
  let item =
    match E2e_harness.find_text_id store "menu-item" "copy" with
    | Some id -> id
    | None -> fail "menu item not found"
  in
  let ir = rect_of_id h item in
  let (ix, iy) = center ir in
  let acts_d =
    Ui.handle ui store rects
      (Input.Button_down (ix, iy, Input.Left, 1, Input.mods_none)) in
  let acts_u =
    Ui.handle ui store rects
      (Input.Button_up (ix, iy, Input.Left, Input.mods_none)) in
  let acts = acts_d @ acts_u in
  check bool "item press dispatched" true
    (List.exists (function Press n -> n = item | _ -> false)
       (dispatched acts));
  let results = deliver app acts in
  check bool "item delivered" true (List.for_all snd results);
  check bool "flush2" true (Lui_app.flush app);
  let m : m2 = Lui_app.model app in
  check string "picked" "copy" m.picked

let test_menu_button () = open_menu_and_pick ~via_right_click:false ()
let test_context_menu () = open_menu_and_pick ~via_right_click:true ()

(* ---------- observed events ---------- *)

(* An appear-enabled node admits a driver-sent Appear event; a node
   without the gate rejects it. The native driver's emission site is
   window-side, so the e2e half covers the admission channel. *)
type m3 = { seen : bool }

let init3 = { seen = false }
let upd3 _ = function `Seen -> { seen = true }

let view3 _ctx _ms send : Lui_elements.t =
  let open Lui_elements in
  column [ row ~on_appear:(press send `Seen) [] ]

let test_observed_events () =
  let h, app = boot_view ~initial:init3 ~update:upd3 ~view:view3 () in
  let store = E2e_harness.store h in
  let rid = first_kind store "row" in
  (* appear-enabled gate present from the handler registration. *)
  check bool "appear-enabled" true
    (match Lui_store.prop store rid "appear-enabled" with
     | Some (BoolValue true) -> true
     | _ -> false);
  check bool "appear delivered" true
    (Lui_app.dispatch_event app (Appear rid));
  check bool "flush" true (Lui_app.flush app);
  let m : m3 = Lui_app.model app in
  check bool "model saw appear" true m.seen

(* ---------- a11y ---------- *)

(* List rows expose their roles, names and selected state through the
   a11y derivation, the way a screen reader's list query sees them. *)
let test_a11y_list () =
  let h = E2e_harness.create () in
  check bool "apply" true
    (E2e_harness.apply_batch h
       { generation = 1;
         ops =
           [ CreateNode (1, ListContainer);
             CreateNode (2, ListItem);
             SetProp (2, TextValue, StringValue "alpha");
             CreateNode (3, ListItem);
             SetProp (3, TextValue, StringValue "beta");
             SetProp (3, Selected, BoolValue true);
             InsertChild (1, 2, 0);
             InsertChild (1, 3, 1) ] });
  let a = Lui_a11y.of_store (E2e_harness.store h) in
  let find id =
    match Lui_a11y.find a id with
    | Some n -> n
    | None -> fail "a11y node missing"
  in
  let l = find 1 and i1 = find 2 and i2 = find 3 in
  check bool "list role" true (l.Lui_a11y.role = Lui_a11y.List);
  check bool "item role" true (i1.Lui_a11y.role = Lui_a11y.List_item);
  check bool "item2 role" true (i2.Lui_a11y.role = Lui_a11y.List_item);
  check (option string) "item name" (Some "alpha") i1.Lui_a11y.name;
  check (option string) "item2 name" (Some "beta") i2.Lui_a11y.name;
  check bool "item2 selected" true i2.Lui_a11y.state.selected;
  check bool "item1 unselected" false i1.Lui_a11y.state.selected;
  check (list int) "list children" [ 2; 3 ] l.Lui_a11y.children;
  check (option int) "item parent" (Some 1) i1.Lui_a11y.parent;
  check (list int) "flatten order" [ 1; 2; 3 ]
    (List.map (fun n -> n.Lui_a11y.id) (Lui_a11y.flatten a))

(* Table structure maps to grid roles the same way: table/row/cell with
   names and hierarchy intact. *)
let test_a11y_table () =
  let h = E2e_harness.create () in
  check bool "apply" true
    (E2e_harness.apply_batch h
       { generation = 1;
         ops =
           [ CreateNode (1, Table);
             CreateNode (2, TableRow);
             CreateNode (3, TableCell);
             SetProp (3, TextValue, StringValue "cell a");
             CreateNode (4, TableCell);
             SetProp (4, TextValue, StringValue "cell b");
             InsertChild (1, 2, 0);
             InsertChild (2, 3, 0);
             InsertChild (2, 4, 1) ] });
  let a = Lui_a11y.of_store (E2e_harness.store h) in
  let find id =
    match Lui_a11y.find a id with
    | Some n -> n
    | None -> fail "a11y node missing"
  in
  let t = find 1 and r = find 2 and c1 = find 3 and c2 = find 4 in
  check bool "table role" true (t.Lui_a11y.role = Lui_a11y.Table);
  check bool "row role" true (r.Lui_a11y.role = Lui_a11y.Table_row);
  check bool "cell role" true (c1.Lui_a11y.role = Lui_a11y.Table_cell);
  check bool "cell2 role" true (c2.Lui_a11y.role = Lui_a11y.Table_cell);
  check (option string) "cell name" (Some "cell a") c1.Lui_a11y.name;
  check (list int) "row children" [ 3; 4 ] r.Lui_a11y.children;
  check (option int) "cell parent" (Some 2) c1.Lui_a11y.parent

let () =
  Alcotest.run "e2e input"
    [ ( "ime",
        [ Alcotest.test_case "composition commits" `Quick
            test_ime_composition;
          Alcotest.test_case "textarea" `Quick test_ime_textarea ] );
      ( "menus",
        [ Alcotest.test_case "menu button" `Quick test_menu_button;
          Alcotest.test_case "context menu" `Quick test_context_menu;
          Alcotest.test_case "input context menu" `Quick
            test_input_context_menu;
          Alcotest.test_case "innermost menu" `Quick test_innermost_menu ] );
      ( "focus",
        [ Alcotest.test_case "input follows focus" `Quick
            test_input_follows_focus;
          Alcotest.test_case "tab focus" `Quick test_tab_focus;
          Alcotest.test_case "hover while pressed" `Quick
            test_hover_while_pressed ] );
      ( "window",
        [ Alcotest.test_case "resize first frame" `Quick
            test_resize_first_frame ] );
      ( "events",
        [ Alcotest.test_case "observed appear" `Quick test_observed_events
        ] );
      ( "a11y",
        [ Alcotest.test_case "list rows" `Quick test_a11y_list;
          Alcotest.test_case "table" `Quick test_a11y_table ] ) ]
