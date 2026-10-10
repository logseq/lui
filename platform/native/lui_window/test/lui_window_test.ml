(* Pure-part tests for the window host: CLI parsing, SDL-constant
   tables, event mapping and admission gating, rect hit testing, the
   layout stub, resize scale math and frame pacing. The SDL/GL path
   itself is exercised by running main.exe. *)

open Lui_scene
open Lui_protocol
open Lui_window
open Lui_window_demo

(* ---------- store helpers ---------- *)

let store_of ops =
  let s = Lui_store.create () in
  Lui_store.apply_batch s { generation = 1; ops };
  s

(* root 1: column 2 → button 3 (pointer-enabled), text-field 4,
   list-item 5, row 6 → button 7 *)
let demo_store () =
  store_of
    [ CreateNode (1, Root);
      CreateNode (2, Column);
      CreateNode (3, Button);
      CreateNode (4, TextField);
      CreateNode (5, ListItem);
      CreateNode (6, Row);
      CreateNode (7, Button);
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0);
      InsertChild (2, 4, 1);
      InsertChild (2, 5, 2);
      InsertChild (2, 6, 3);
      InsertChild (6, 7, 0);
      SetProp (2, Gap, IntValue 4);
      SetProp (3, PointerEnabled, BoolValue true);
      SetProp (4, TextValue, StringValue "");
      SetProp (5, TextValue, StringValue "item") ]

let host_stub () =
  Lui_host.create ~hooks:Lui_paint.default_hooks
    ~renderer:{ Lui_host.render = (fun _ -> Bytes.empty); name = "t" }
    ~width:100 ~height:100 ~scale:1. ()

(* ---------- arg parsing ---------- *)

let test_parse_args () =
  let cfg =
    match parse_args [ "--width"; "800"; "--height"; "600"; "--headless"; "5" ] with
    | Ok c -> c
    | Error m -> Alcotest.fail m
  in
  Alcotest.(check int) "width" 800 cfg.width;
  Alcotest.(check int) "height" 600 cfg.height;
  Alcotest.(check (option int)) "frames" (Some 5) cfg.headless_frames;
  Alcotest.(check bool) "bad flag" true
    (Result.is_error (parse_args [ "--bogus" ]));
  Alcotest.(check bool) "missing value" true
    (Result.is_error (parse_args [ "--width" ]));
  Alcotest.(check bool) "non-numeric" true
    (Result.is_error (parse_args [ "--width"; "abc" ]))

(* ---------- input tables ---------- *)

let test_input_tables () =
  let open Input in
  Alcotest.(check int) "none" 0 (mods_to_int mods_none);
  Alcotest.(check int) "ctrl" 1
    (mods_to_int { mods_none with ctrl = true });
  Alcotest.(check int) "shift+meta" 6
    (mods_to_int { mods_none with shift = true; meta = true });
  Alcotest.(check int) "all" 7
    (mods_to_int { ctrl = true; shift = true; alt = true; meta = true });
  (match button_of_sdl 1 with
   | Left -> ()
   | _ -> Alcotest.fail "button 1");
  (match button_of_sdl 3 with
   | Right -> ()
   | _ -> Alcotest.fail "button 3");
  (match key_of_sdl_scancode 40 with
   | Return -> ()
   | _ -> Alcotest.fail "return");
  (match key_of_sdl_scancode 88 with
   | Return -> ()
   | _ -> Alcotest.fail "keypad return");
  (match key_of_sdl_scancode 80 with
   | Arrow_left -> ()
   | _ -> Alcotest.fail "left");
  (match key_of_sdl_scancode 999 with
   | Other 999 -> ()
   | _ -> Alcotest.fail "other key")

(* ---------- admission gating ---------- *)

let test_event_supported () =
  let s = demo_store () in
  Alcotest.(check bool) "button press" true
    (event_supported s 3 (Press 3));
  Alcotest.(check bool) "field press" false
    (event_supported s 4 (Press 4));
  Alcotest.(check bool) "field text" true
    (event_supported s 4 (TextChanged (4, "x")));
  Alcotest.(check bool) "field submit" true
    (event_supported s 4 (Submit 4));
  Alcotest.(check bool) "item double" true
    (event_supported s 5 (DoublePress 5));
  (* treeitem role switches admission to the gate properties *)
  let s' =
    store_of
      [ CreateNode (1, Root); CreateNode (2, ListItem);
        InsertChild (1, 2, 0);
        SetProp (2, RoleValue, StringValue "treeitem") ]
  in
  Alcotest.(check bool) "treeitem press off" false
    (event_supported s' 2 (Press 2));
  Lui_store.apply_batch s'
    { generation = 2; ops = [ SetProp (2, PressEnabled, BoolValue true) ] };
  Alcotest.(check bool) "treeitem press on" true
    (event_supported s' 2 (Press 2))

(* ---------- layout stub ---------- *)

let test_layout () =
  let s = demo_store () in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let r2 = Rects.get rects 2 in
  Alcotest.(check (float 0.001)) "column w" 200. r2.w;
  (* children stack vertically with gap 4: button(32) field(32)
     item(24) row(24) *)
  let r3 = Rects.get rects 3 in
  Alcotest.(check (float 0.001)) "btn y" 0. r3.y;
  Alcotest.(check (float 0.001)) "btn h" 32. r3.h;
  let r4 = Rects.get rects 4 in
  Alcotest.(check (float 0.001)) "field y" 36. r4.y;
  let r7 = Rects.get rects 7 in
  Alcotest.(check bool) "nested row child set" true (r7.h > 0.);
  (* scale doubles every device-pixel extent *)
  Layout.refresh s rects ~width:200 ~height:100 ~scale:2.
    ~measure:Layout.default_measure;
  let r3' = Rects.get rects 3 in
  Alcotest.(check (float 0.001)) "scaled w" 400. (Rects.get rects 2).w;
  Alcotest.(check (float 0.001)) "scaled btn h" 64. r3'.h;
  Alcotest.(check (float 0.001)) "scaled field y" 72. (Rects.get rects 4).y

let test_layout_props () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Button); CreateNode (4, Button);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        SetProp (2, PaddingValue, IntValue 10);
        SetProp (2, HeightValue, IntValue 200);
        SetProp (3, HeightValue, IntValue 50);
        SetProp (4, GrowValue, FloatValue 1.) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  (* column: pad 10 each side; btn3 fixed 50 at y=10; btn4 grows to
     fill 200 - 20 pad - 50 - 0 gap = 130 *)
  let r3 = Rects.get rects 3 in
  Alcotest.(check (float 0.001)) "pad x" 10. r3.x;
  Alcotest.(check (float 0.001)) "fixed h" 50. r3.h;
  Alcotest.(check (float 0.001)) "fixed w" 80. r3.w;
  let r4 = Rects.get rects 4 in
  Alcotest.(check (float 0.001)) "grow y" 60. r4.y;
  Alcotest.(check (float 0.001)) "grow h" 130. r4.h

(* ---------- hit test ---------- *)

let test_hit () =
  let s = demo_store () in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  (* button 3 occupies y 0..32; its point also sits inside column 2 and
     root 1 — deepest first. *)
  (match hit_path s rects ~x:5. ~y:10. with
   | [ 3; 2; 1 ] -> ()
   | p ->
     Alcotest.failf "path %s"
       (String.concat "," (List.map string_of_int p)));
  Alcotest.(check (option int)) "top hit" (Some 3)
    (hit s rects ~x:5. ~y:10.);
  (* in the gap between children: inside the column but on no leaf *)
  (match hit_path s rects ~x:5. ~y:34. with
   | [ 2; 1 ] -> ()
   | p ->
     Alcotest.failf "deep path %s"
       (String.concat "," (List.map string_of_int p)))

(* ---------- event mapping ---------- *)

let ui_store_fresh () =
  let s = demo_store () in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  (s, rects)

let press_actions acts =
  List.filter_map
    (function Dispatch e -> Some e | _ -> None)
    acts

let test_click_press () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  (* down+up on the button → PointerDown, then PointerUp + PressDetail
     + Press (button 3 is pointer-enabled) *)
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (5., 10., Input.Left, 1, Input.mods_none))
  in
  (match press_actions acts with
   | [ PointerDown (3, _) ] -> ()
   | _ -> Alcotest.fail "expected PointerDown");
  Alcotest.(check int) "pressed" 3 (Ui.pressed ui);
  let acts =
    Ui.handle ui s rects
      (Input.Button_up (5., 10., Input.Left, Input.mods_none))
  in
  (match press_actions acts with
   | [ PointerUp (3, _); PressDetail (3, _); Press 3 ] -> ()
   | _ -> Alcotest.fail "expected PointerUp + PressDetail + Press");
  Alcotest.(check int) "released" 0 (Ui.pressed ui)

let test_click_release_elsewhere () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 10., Input.Left, 1, Input.mods_none)));
  (* up inside the column but off the button: only PointerUp, no Press *)
  let acts =
    Ui.handle ui s rects
      (Input.Button_up (195., 190., Input.Left, Input.mods_none))
  in
  (match press_actions acts with
   | [ PointerUp (3, _) ] -> ()
   | _ -> Alcotest.fail "expected lone PointerUp")

let test_click_focus () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  (* down on the text field at y 36..68: Focus_changed, no PointerDown
     (field is not pointer-enabled) and no Press target *)
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none))
  in
  (match acts with
   | [ Focus_changed 4 ] -> ()
   | _ -> Alcotest.fail "expected Focus_changed 4");
  Alcotest.(check int) "focused" 4 (Ui.focused ui);
  (* the field itself takes no press, so the press bubbles to the
     first press-admissible ancestor — the column *)
  Alcotest.(check int) "press bubbles" 2 (Ui.pressed ui)

let test_text_input_and_keys () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  let acts = Ui.handle ui s rects (Input.Text_input "ab") in
  (match press_actions acts with
   | [ TextChanged (4, "ab") ] -> ()
   | _ -> Alcotest.fail "expected TextChanged ab");
  let acts =
    Ui.handle ui s rects
      (Input.Key_down (Input.Return, Input.mods_none, false))
  in
  (match press_actions acts with
   | [ Submit 4 ] -> ()
   | _ -> Alcotest.fail "expected Submit");
  (* Backspace drops the last UTF-8 char *)
  Lui_store.apply_batch s
    { generation = 2;
      ops = [ SetProp (4, TextValue, StringValue "ab") ] };
  Ui.set_focused ui s 4;
  let acts =
    Ui.handle ui s rects
      (Input.Key_down (Input.Backspace, Input.mods_none, false))
  in
  (match press_actions acts with
   | [ TextChanged (4, "a") ] -> ()
   | _ -> Alcotest.fail "expected TextChanged a");
  (* Escape blurs first, then quits *)
  (match
     Ui.handle ui s rects
       (Input.Key_down (Input.Escape, Input.mods_none, false))
   with
   | [ Focus_changed 0 ] -> ()
   | _ -> Alcotest.fail "expected blur");
  (match
     Ui.handle ui s rects
       (Input.Key_down (Input.Escape, Input.mods_none, false))
   with
   | [ Quit ] -> ()
   | _ -> Alcotest.fail "expected Quit")

let test_hover_detail () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  let acts =
    Ui.handle ui s rects (Input.Move (5., 10.))
  in
  (match press_actions acts with
   | [ PointerEnter 3 ] -> ()
   | _ -> Alcotest.fail "expected PointerEnter");
  Alcotest.(check int) "hovered" 3 (Ui.hovered ui);
  let acts =
    Ui.handle ui s rects (Input.Move (5., 40.))
  in
  (match press_actions acts with
   | [ PointerLeave 3 ] -> ()
   | _ -> Alcotest.fail "expected PointerLeave");
  Alcotest.(check int) "hovered" 4 (Ui.hovered ui)

let test_context_menu () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (5., 10., Input.Right, 1, Input.mods_none))
  in
  (match press_actions acts with
   | [ ContextMenuPress (3, d) ] ->
     Alcotest.(check int) "secondary bit" 8 (d.modifiers land 8)
   | _ -> Alcotest.fail "expected ContextMenuPress")

let test_disabled_gate () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Button);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        SetProp (3, PointerEnabled, BoolValue true);
        SetProp (3, Enabled, BoolValue false) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (5., 5., Input.Left, 1, Input.mods_none))
  in
  Alcotest.(check int) "no actions" 0 (List.length acts);
  Alcotest.(check int) "no press" 0 (Ui.pressed ui)

(* ---------- IME composition through Ui ---------- *)

let test_ime_editing_not_dispatched () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  (* text_editing marks text for display only — nothing dispatches *)
  let acts = Ui.handle ui s rects (Input.Text_editing ("ni", 1, 0)) in
  Alcotest.(check int) "no dispatch" 0 (List.length acts);
  Alcotest.(check string) "marked" "ni" (Ui.marked ui);
  let acts = Ui.handle ui s rects (Input.Text_editing ("nih", 3, 0)) in
  Alcotest.(check int) "still none" 0 (List.length acts);
  Alcotest.(check string) "marked grows" "nih" (Ui.marked ui);
  (* commit goes through the real input path: TextChanged with the
     committed text spliced at the caret *)
  let acts = Ui.handle ui s rects (Input.Text_input "hao") in
  (match press_actions acts with
   | [ TextChanged (4, "hao") ] -> ()
   | _ -> Alcotest.fail "expected TextChanged hao");
  Alcotest.(check string) "marked cleared" "" (Ui.marked ui)

let test_ime_keys_suppressed_while_composing () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  ignore (Ui.handle ui s rects (Input.Text_editing ("ni", 2, 0)));
  (* key edits are gated while marked text is on screen *)
  let acts =
    Ui.handle ui s rects
      (Input.Key_down (Input.Backspace, Input.mods_none, false))
  in
  Alcotest.(check int) "backspace gated" 0 (List.length acts);
  let acts =
    Ui.handle ui s rects
      (Input.Key_down (Input.Return, Input.mods_none, false))
  in
  Alcotest.(check int) "return gated" 0 (List.length acts);
  (* after commit they work again *)
  ignore (Ui.handle ui s rects (Input.Text_input "x"));
  let acts =
    Ui.handle ui s rects
      (Input.Key_down (Input.Backspace, Input.mods_none, false))
  in
  (match press_actions acts with
   | [ TextChanged (4, "") ] -> ()
   | _ -> Alcotest.fail "expected TextChanged \"\" after commit")

let test_ime_cancel_on_focus_move () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  ignore (Ui.handle ui s rects (Input.Text_editing ("ni", 2, 0)));
  Alcotest.(check bool) "composing" true
    (Lui_ime.composing (Ui.ime ui));
  (* click on the button blurs the field: composition cancels *)
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 10., Input.Left, 1, Input.mods_none)));
  Alcotest.(check string) "marked dropped" "" (Ui.marked ui);
  Alcotest.(check bool) "not composing" false
    (Lui_ime.composing (Ui.ime ui))

let test_ime_candidate_rect () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  let cr = Lui_scene.rect 20. 36. 2. 32. in
  (* caret moves while idle produce no candidate action *)
  let acts = Ui.handle ui s rects (Input.Caret cr) in
  Alcotest.(check int) "idle silent" 0 (List.length acts);
  (* composing start emits Ime_rect through the begin *)
  ignore (Ui.handle ui s rects (Input.Text_editing ("n", 1, 0)));
  let cr2 = Lui_scene.rect 36. 36. 2. 32. in
  let acts = Ui.handle ui s rects (Input.Caret cr2) in
  (match acts with
   | [ Ime_rect r ] ->
     Alcotest.(check (float 0.01)) "x" 36. r.Lui_scene.x
   | _ -> Alcotest.fail "expected Ime_rect");
  (* same rect again: dedup *)
  let acts = Ui.handle ui s rects (Input.Caret cr2) in
  Alcotest.(check int) "dedup" 0 (List.length acts)

(* ---------- resize scale math ---------- *)

let test_resize_scale () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  Ui.set_scale ui 2.;
  (* logical (10,20) → device (20,40): the text field's rect at
     scale 1 is y 36..68, so device-y 40 lands on it *)
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (10., 20., Input.Left, 1, Input.mods_none))
  in
  (match acts with
   | [ Focus_changed 4 ] -> ()
   | _ -> Alcotest.fail "expected Focus_changed 4 at 2x");
  Alcotest.(check int) "focused@2x" 4 (Ui.focused ui);
  let acts = Ui.handle ui s rects (Input.Resize (640, 480)) in
  (match acts with
   | [ Resize_host (640, 480) ] -> ()
   | _ -> Alcotest.fail "expected Resize_host")

(* ---------- frame pacing ---------- *)

let test_pacing () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  let host = host_stub () in
  (* fresh ui: dirty → frame wanted *)
  Alcotest.(check bool) "initial" true (Ui.want_frame ui host);
  Ui.frame_done ui;
  Alcotest.(check bool) "settled" false (Ui.want_frame ui host);
  (* hover change marks the frame dirty *)
  ignore (Ui.handle ui s rects (Input.Move (5., 10.)));
  Alcotest.(check bool) "hover dirty" true (Ui.want_frame ui host);
  Ui.frame_done ui;
  (* a store repaint request also schedules a frame *)
  Lui_store.apply_batch (Lui_host.store host)
    { generation = 1;
      ops = [ CreateNode (9, Text) ] };
  ignore
    (Lui_host.apply_batch host
       { generation = 2; ops = [ DropNode 9 ] });
  Alcotest.(check bool) "host dirty" true (Ui.want_frame ui host)

(* ---------- checksum ---------- *)

let test_checksum () =
  let s, _ = ui_store_fresh () in
  ignore s;
  let scene1 = Lui_scene.create ~mask_atlas:(Lui_scene.Atlas.create ~bpp:1 ~w:8 ~h:8)
      ~color_atlas:(Lui_scene.Atlas.create ~bpp:4 ~w:8 ~h:8) in
  scene1.width <- 100;
  scene1.height <- 100;
  scene1.ops <-
    [ Fill
        { frect = rect 0. 0. 10. 10.;
          fradii = (0., 0., 0., 0.); fcontinuous = false;
          fcolor = color 1 2 3 255; fpaint = Solid;
          fcolor2 = color 0 0 0 0; fgradient = (0., 0., 0., 0.);
          fborder = (0., 0., 0., 0.); fborder_color = color 0 0 0 0;
          fdashed = false; fwide = 0; fopacity = 1. } ];
  let c1 = Checksum.create () and c2 = Checksum.create () in
  Checksum.add_scene c1 scene1;
  Checksum.add_scene c2 scene1;
  Alcotest.(check bool) "deterministic" true
    (Checksum.value c1 = Checksum.value c2);
  scene1.ops <- Pop_clip :: scene1.ops;
  Checksum.add_scene c2 scene1;
  Alcotest.(check bool) "changes" true
    (Checksum.value c1 <> Checksum.value c2)

(* ---------- scroll containers ---------- *)

let test_scroll () =
  (* a scroll kind with children taller than its viewport: wheel input
     must move the container's offset, clamped to the driver-supplied
     cap *)
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Scroll);
        CreateNode (3, ListItem);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0) ]
  in
  Alcotest.(check bool) "scroll kind" true (Ui.scrollable s 2);
  Alcotest.(check bool) "plain kind" false (Ui.scrollable s 3);
  (* an overflow=scroll prop marks any container scrollable too *)
  let s' =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        InsertChild (1, 2, 0);
        SetProp (2, Overflow, StringValue "scroll") ]
  in
  Alcotest.(check bool) "overflow scroll" true (Ui.scrollable s' 2);
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  Ui.set_scroll_cap ui 2 80.;
  Alcotest.(check (float 0.001)) "cap" 80. (Ui.scroll_cap ui 2);
  Alcotest.(check (float 0.001)) "starts at 0" 0. (Ui.scroll_offset ui 2);
  (* park the pointer inside the scroll container, then wheel down *)
  ignore (Ui.handle ui s rects (Input.Move (10., 10.)));
  ignore (Ui.handle ui s rects (Input.Wheel (0., -1.)));
  Alcotest.(check (float 0.001)) "scrolled" 44. (Ui.scroll_offset ui 2);
  (* two more wheels clamp at the cap *)
  ignore (Ui.handle ui s rects (Input.Wheel (0., -1.)));
  ignore (Ui.handle ui s rects (Input.Wheel (0., -1.)));
  Alcotest.(check (float 0.001)) "clamped" 80. (Ui.scroll_offset ui 2);
  (* wheel up scrolls back but not past zero *)
  ignore (Ui.handle ui s rects (Input.Wheel (0., 3.)));
  Alcotest.(check (float 0.001)) "floor" 0. (Ui.scroll_offset ui 2);
  (* shrinking the cap clamps the live offset too *)
  Ui.set_scroll_cap ui 2 30.;
  Alcotest.(check (float 0.001)) "cap shrink" 0. (Ui.scroll_offset ui 2)

(* ---------- demo dispatch flow ---------- *)

(* Boot the real demo app against a store-mirroring backend, then feed
   protocol events down the same paths SDL input takes: dispatch_event
   → mounted handler → reducer → flush → store/model assertions. *)
let demo_backend store =
  { Lui_protocol.backend_profile = Lui_protocol.generic_profile ();
    apply_batch =
      (fun batch -> Lui_store.apply_batch store batch; true) }

let find_prop_id store kind prop value =
  List.find_map
    (fun n ->
      if Lui_store.node_kind n = kind
         && Lui_store.node_prop n prop = Some (Lui_protocol.StringValue value)
      then Some (Lui_store.node_id n)
      else None)
    (Lui_store.all_nodes store)

let find_kind_id store kind =
  List.find_map
    (fun n ->
      if Lui_store.node_kind n = kind then Some (Lui_store.node_id n)
      else None)
    (Lui_store.all_nodes store)

let require_id = function Some id -> id | None -> Alcotest.fail "node"

let test_demo_dispatch () =
  let store = Lui_store.create () in
  let app = Demo_app.create (demo_backend store) in
  Alcotest.(check bool) "start" true (Lui_app.start app);
  Alcotest.(check bool) "initial flush" true (Lui_app.flush app);
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check bool) "initial tab" true (m.tab = Demo_app.Inputs);
  Alcotest.(check int) "initial items" 6 (List.length m.items);
  (* bottom-tab press switches sections — the Lists section mounts the
     todo field the next events target *)
  let lists_id =
    require_id (find_prop_id store "bottom-tab" "title" "lists")
  in
  Alcotest.(check bool) "lists press" true
    (Lui_app.dispatch_event app (Press lists_id));
  Alcotest.(check bool) "lists flush" true (Lui_app.flush app);
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check bool) "lists tab" true (m.tab = Demo_app.Lists);
  (* text-field input flows through on_input → Draft *)
  let draft_id =
    require_id (find_prop_id store "text-field" "placeholder" "new item")
  in
  Alcotest.(check bool) "draft event" true
    (Lui_app.dispatch_event app (TextChanged (draft_id, "gamma")));
  Alcotest.(check bool) "draft flush" true (Lui_app.flush app);
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check string) "draft stored" "gamma" m.draft;
  Alcotest.(check string) "field prop" "gamma"
    (match Lui_store.prop store draft_id "text" with
     | Some (Lui_protocol.StringValue s) -> s
     | _ -> "");
  (* the add button fires on_press → Add, appending the draft *)
  let add_id =
    require_id (find_prop_id store "button" "text" "add")
  in
  Alcotest.(check bool) "add press" true
    (Lui_app.dispatch_event app (Press add_id));
  Alcotest.(check bool) "add flush" true (Lui_app.flush app);
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check int) "item appended" 7 (List.length m.items);
  Alcotest.(check string) "draft tail" "gamma"
    (List.nth m.items 6);
  Alcotest.(check string) "draft cleared" "" m.draft;
  (* bottom-tab press switches sections *)
  let controls_id =
    require_id (find_prop_id store "bottom-tab" "title" "controls")
  in
  Alcotest.(check bool) "tab press" true
    (Lui_app.dispatch_event app (Press controls_id));
  Alcotest.(check bool) "tab flush" true (Lui_app.flush app);
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check bool) "controls tab" true (m.tab = Demo_app.Controls);
  (* every section mounts cleanly — pressing each tab flushes a mount;
     an unsupported prop on any element raises here *)
  List.iter
    (fun title ->
      let id =
        require_id (find_prop_id store "bottom-tab" "title" title)
      in
      Alcotest.(check bool)
        (Printf.sprintf "%s press" title)
        true (Lui_app.dispatch_event app (Press id));
      Alcotest.(check bool)
        (Printf.sprintf "%s flush" title)
        true (Lui_app.flush app))
    [ "inputs"; "controls"; "lists"; "overlays"; "deco" ];
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check bool) "deco tab" true (m.tab = Demo_app.Deco);
  (* back to Controls for the control-kind event paths *)
  let controls_id =
    require_id (find_prop_id store "bottom-tab" "title" "controls")
  in
  ignore (Lui_app.dispatch_event app (Press controls_id));
  Alcotest.(check bool) "controls flush" true (Lui_app.flush app);
  (* the Controls section mounted: checkbox toggle flows through *)
  let cb_id = require_id (find_prop_id store "checkbox" "text" "notify me") in
  Alcotest.(check bool) "toggle event" true
    (Lui_app.dispatch_event app (ToggleChanged (cb_id, false)));
  Alcotest.(check bool) "toggle flush" true (Lui_app.flush app);
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check bool) "unsubscribed" false m.subscribed;
  (* slider ValueChanged carries the float through on_change *)
  let sl_id = require_id (find_kind_id store "slider") in
  Alcotest.(check bool) "value event" true
    (Lui_app.dispatch_event app (ValueChanged (sl_id, 0.5)));
  Alcotest.(check bool) "value flush" true (Lui_app.flush app);
  let m : Demo_app.model = Lui_app.model app in
  Alcotest.(check (float 0.001)) "volume" 0.5 m.volume;
  (* overlay flow: Open mounts the dialog kind, Close drops it *)
  Alcotest.(check bool) "dialog absent" true
    (find_kind_id store "dialog" = None);
  ignore (Lui_app.send app (Demo_app.Open Demo_app.P_dialog));
  Alcotest.(check bool) "open flush" true (Lui_app.flush app);
  Alcotest.(check bool) "dialog mounted" true
    (find_kind_id store "dialog" <> None);
  ignore (Lui_app.send app (Demo_app.Close Demo_app.P_dialog));
  Alcotest.(check bool) "close flush" true (Lui_app.flush app);
  Alcotest.(check bool) "dialog dropped" true
    (find_kind_id store "dialog" = None);
  ignore (Lui_app.dispose app)

(* ---------- headless checksum regression ---------- *)

(* The demo doubles as the pipeline regression: a fixed number of
   headless frames must always produce the same scene checksum.
   Spawns the real binary so the assertion covers the whole chain —
   Lui_app → store → flex → paint → scene ops — not a mock. *)
let read_all ic =
  let buf = Buffer.create 1024 in
  (try
     while true do
       Buffer.add_string buf (input_line ic);
       Buffer.add_char buf '\n'
     done
   with End_of_file -> ());
  Buffer.contents buf

let main_exe () =
  let candidates = [ "../main.exe"; "./main.exe" ] in
  match
    List.find_opt Sys.file_exists
      (match Sys.getenv_opt "LUI_WINDOW_MAIN" with
       | Some p -> p :: candidates
       | None -> candidates)
  with
  | Some p -> p
  | None -> Alcotest.fail "main.exe not found next to the test binary"

let test_headless_checksum () =
  let exe = main_exe () in
  let run () =
    let ic =
      Unix.open_process_in
        (Printf.sprintf "%s --headless 6" (Filename.quote exe))
    in
    let out = read_all ic in
    match Unix.close_process_in ic with
    | Unix.WEXITED 0 -> out
    | _ -> Alcotest.failf "main.exe failed: %s" out
  in
  let checksum_of out =
    match
      List.find_opt
        (fun l ->
          try
            ignore (Str.search_forward (Str.regexp "checksum=") l 0);
            true
          with Not_found -> false)
        (String.split_on_char '\n' out)
    with
    | Some l -> l
    | None -> Alcotest.failf "no checksum line in:\n%s" out
  in
  let out1 = run () and out2 = run () in
  Alcotest.(check bool) "noop renderer" true
    (try
       ignore (Str.search_forward (Str.regexp "renderer=noop") out1 0);
       true
     with Not_found -> false);
  let c1 = checksum_of out1 and c2 = checksum_of out2 in
  Alcotest.(check string) "deterministic" c1 c2;
  (* the recorded value pins the demo's initial scene: any render-path
     change shows up here *)
  Alcotest.(check string) "golden"
    "headless done: frames=6 checksum=68b1be2fbd3e039d" c1

let () =
  Alcotest.run "lui_window"
    [ ("config", [ Alcotest.test_case "parse_args" `Quick test_parse_args ]);
      ( "input",
        [ Alcotest.test_case "tables" `Quick test_input_tables ] );
      ( "admission",
        [ Alcotest.test_case "event_supported" `Quick test_event_supported ] );
      ( "layout",
        [ Alcotest.test_case "stack" `Quick test_layout;
          Alcotest.test_case "props" `Quick test_layout_props ] );
      ( "hit",
        [ Alcotest.test_case "path" `Quick test_hit ] );
      ( "events",
        [ Alcotest.test_case "click" `Quick test_click_press;
          Alcotest.test_case "release elsewhere" `Quick
            test_click_release_elsewhere;
          Alcotest.test_case "focus" `Quick test_click_focus;
          Alcotest.test_case "text+keys" `Quick test_text_input_and_keys;
          Alcotest.test_case "hover detail" `Quick test_hover_detail;
          Alcotest.test_case "context menu" `Quick test_context_menu;
          Alcotest.test_case "disabled gate" `Quick test_disabled_gate ] );
      ( "ime",
        [ Alcotest.test_case "editing not dispatched" `Quick
            test_ime_editing_not_dispatched;
          Alcotest.test_case "keys suppressed" `Quick
            test_ime_keys_suppressed_while_composing;
          Alcotest.test_case "cancel on blur" `Quick
            test_ime_cancel_on_focus_move;
          Alcotest.test_case "candidate rect" `Quick
            test_ime_candidate_rect ] );
      ( "resize",
        [ Alcotest.test_case "scale" `Quick test_resize_scale ] );
      ( "pacing",
        [ Alcotest.test_case "dirty" `Quick test_pacing ] );
      ( "checksum",
        [ Alcotest.test_case "ops" `Quick test_checksum ] );
      ( "scroll",
        [ Alcotest.test_case "wheel" `Quick test_scroll ] );
      ( "demo",
        [ Alcotest.test_case "dispatch flow" `Quick test_demo_dispatch ] );
      ( "headless",
        [ Alcotest.test_case "checksum" `Quick test_headless_checksum ] ) ]
