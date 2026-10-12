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
let demo_ops =
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

let demo_store () = store_of demo_ops

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
  Alcotest.(check (list string)) "no drop files" [] cfg.drop_files;
  (match
     parse_args
       [ "--drop-file"; "/tmp/a"; "--drop-file"; "/tmp/b" ]
   with
   | Ok c ->
     Alcotest.(check (list string)) "drop files"
       [ "/tmp/b"; "/tmp/a" ] c.drop_files
   | Error m -> Alcotest.fail m);
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
  Alcotest.(check (option string)) "committed text paints from the native store"
    (Some "ab") (Lui_store.string_prop s 4 "text");
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
  Alcotest.(check (option string)) "deletion updates the displayed value"
    (Some "a") (Lui_store.string_prop s 4 "text");
  let meta = { Input.mods_none with meta = true } in
  ignore (Ui.handle ui s rects (Input.Key_down (Input.Other 29, meta, false)));
  Alcotest.(check (option string)) "undo restores the displayed value"
    (Some "ab") (Lui_store.string_prop s 4 "text");
  ignore
    (Ui.handle ui s rects
       (Input.Key_down (Input.Other 29, { meta with Input.shift = true }, false)));
  Alcotest.(check (option string)) "redo restores the displayed value"
    (Some "a") (Lui_store.string_prop s 4 "text");
  Ui.set_focused ui s 0;
  Ui.set_focused ui s 4;
  Alcotest.(check string) "refocusing preserves the committed field value"
    "a" (Ui.shadow ui);
  Lui_store.apply_op s (SetProp (4, TextValue, StringValue "model"));
  ignore (Ui.store_changed ui s);
  Alcotest.(check string) "model updates synchronize the focused edit buffer"
    "model" (Ui.shadow ui);
  Lui_store.apply_op s (SetProp (4, TextValue, StringValue "字"));
  ignore (Ui.store_changed ui s);
  Alcotest.(check int) "model updates keep the caret at a UTF-8 boundary"
    0 (Ui.caret ui);
  ignore (Ui.handle ui s rects (Input.Text_input "x"));
  Alcotest.(check (option string)) "typing after a UTF-8 model update stays valid"
    (Some "x字") (Lui_store.string_prop s 4 "text");
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

let test_caret_ops_wiring () =
  (* C7: with a caret model wired, keyboard moves and deletes consult
     it instead of the codepoint fallback — sentinel steps of 3 make
     the delegation observable. *)
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  Ui.set_caret_ops ui
    (fun _store _id _text ~lw:_ ~lh:_ ->
       { Ui.c_before = (fun i -> max 0 (i - 3));
         c_after = (fun i -> i + 3);
         c_up = (fun _ -> 0);
         c_down = (fun i -> i);
         c_rect = (fun _ -> (0., 0., 0.)) });
  Ui.set_focused ui s 4;
  ignore (Ui.handle ui s rects (Input.Text_input "abcde"));
  ignore
    (Ui.handle ui s rects
       (Input.Key_down (Input.Arrow_left, Input.mods_none, false)));
  Alcotest.(check int) "engine step left" 2 (Ui.caret ui);
  ignore
    (Ui.handle ui s rects
       (Input.Key_down (Input.Arrow_right, Input.mods_none, false)));
  Alcotest.(check int) "engine step right" 5 (Ui.caret ui);
  (* Backspace deletes back to the engine's boundary, not one
     codepoint *)
  (match
     press_actions
       (Ui.handle ui s rects
          (Input.Key_down (Input.Backspace, Input.mods_none, false)))
   with
   | [ TextChanged (4, "ab") ] -> ()
   | _ -> Alcotest.fail "expected boundary delete");
  ignore
    (Ui.handle ui s rects
       (Input.Key_down (Input.Arrow_up, Input.mods_none, false)));
  Alcotest.(check int) "engine up sentinel" 0 (Ui.caret ui)

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
  Alcotest.(check (float 0.001)) "x cap starts 0" 0.
    (Ui.scroll_cap_x ui 2);
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

let test_wheel_x () =
  (* a scroll container with horizontal range: wheel-x deltas and
     shift+wheel move the x offset; the y offset is untouched *)
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Scroll);
        CreateNode (3, Row); CreateNode (4, Text);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        InsertChild (3, 4, 0);
        SetProp (4, TextValue, StringValue "wide") ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  Ui.set_scroll_cap_x ui 2 90.;
  Ui.set_scroll_cap ui 2 80.;
  ignore (Ui.handle ui s rects (Input.Move (10., 10.)));
  (* a horizontal wheel delta scrolls right, clamped to the x cap *)
  ignore (Ui.handle ui s rects (Input.Wheel (1., 0.)));
  Alcotest.(check (float 0.001)) "wheel-x" 44. (Ui.scroll_offset_x ui 2);
  Alcotest.(check (float 0.001)) "y untouched" 0. (Ui.scroll_offset ui 2);
  (* shift+wheel turns the vertical delta horizontal *)
  ignore
    (Ui.handle ui s rects
       (Input.Wheel_mods
          (0., -1., { Input.mods_none with Input.shift = true })));
  Alcotest.(check (float 0.001)) "shift+wheel-x" 88.
    (Ui.scroll_offset_x ui 2);
  Alcotest.(check (float 0.001)) "still no y" 0. (Ui.scroll_offset ui 2);
  (* the next x move clamps at the cap *)
  ignore (Ui.handle ui s rects (Input.Wheel (1., 0.)));
  Alcotest.(check (float 0.001)) "clamped" 90. (Ui.scroll_offset_x ui 2);
  (* a plain vertical wheel still scrolls y *)
  ignore (Ui.handle ui s rects (Input.Wheel (0., -1.)));
  Alcotest.(check (float 0.001)) "y scrolls" 44. (Ui.scroll_offset ui 2);
  (* shrinking the x cap clamps the live x offset too *)
  Ui.set_scroll_cap_x ui 2 40.;
  Alcotest.(check (float 0.001)) "cap shrink" 40.
    (Ui.scroll_offset_x ui 2);
  (* scroll_to / scroll_by take an axis *)
  ignore (Ui.scroll_to ~axis:Ui.X ui s 2 10.);
  Alcotest.(check (float 0.001)) "scroll_to x" 10.
    (Ui.scroll_offset_x ui 2);
  ignore (Ui.scroll_by ~axis:Ui.X ui s 2 5.);
  Alcotest.(check (float 0.001)) "scroll_by x" 15.
    (Ui.scroll_offset_x ui 2);
  (* scroll_show reveals horizontally clipped nodes too *)
  Ui.set_content_rect ui
    (fun id ->
       match id with
       | 2 -> rect 0. 0. 100. 100.
       | 4 -> rect 200. 0. 100. 20.
       | _ -> Rects.zero);
  Ui.set_scroll_cap_x ui 2 300.;
  ignore (Ui.scroll_show ui s 4);
  Alcotest.(check (float 0.001)) "x reveal" 200.
    (Ui.scroll_offset_x ui 2)

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
  List.find_opt Sys.file_exists
    (match Sys.getenv_opt "LUI_WINDOW_MAIN" with
     | Some p -> p :: candidates
     | None -> candidates)

(* The window host's exe exists only where a backend builds it (macOS
   today); on Linux the headless cases skip while the pure ones run. *)
let with_main_exe f =
  match main_exe () with
  | Some exe -> f exe
  | None -> Alcotest.(check pass) "main.exe unavailable; test skipped" () ()

let test_headless_drop () =
  with_main_exe @@ fun exe ->
  let run () =
    let ic =
      Unix.open_process_in
        (Printf.sprintf
           "%s --headless 6 --drop-file /tmp/dropped.txt"
           (Filename.quote exe))
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
  (* the synthetic drop lands on the demo's file well *)
  Alcotest.(check bool) "drop landed" true
    (try
       ignore
         (Str.search_forward
            (Str.regexp "drop: payload=file:/tmp/dropped.txt") out1 0);
       true
     with Not_found -> false);
  (* deterministic: the same synthetic drop produces the same frames *)
  Alcotest.(check string) "deterministic" (checksum_of out1)
    (checksum_of out2)

let test_headless_checksum () =
  with_main_exe @@ fun exe ->
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
    "headless done: frames=6 checksum=10ad2bfdcbf7b0ad" c1

(* ---------- multi-window ---------- *)

(* A surface on the pure registry: a host (real store/layout/paint,
   no-op renderer) plus the demo ops so hit tests have targets — the
   same shape the SDL driver builds per window, minus the OS handle. *)
let surf_of ~id ~w ~h ~scale =
  let host = host_stub () in
  let store = Lui_host.store host in
  Lui_store.apply_batch store { generation = 1; ops = demo_ops };
  let rects = Rects.create () in
  Layout.refresh store rects ~width:w ~height:h ~scale
    ~measure:Layout.default_measure;
  Multi.make_surface ~id ~host ~driver:() ~ui:(Ui.create ()) ~rects
    ~scale_cell:(ref scale) ~w ~h

let test_multi_registry () =
  let t = Multi.create () in
  let s1 = surf_of ~id:11 ~w:200 ~h:200 ~scale:1. in
  let s2 = surf_of ~id:22 ~w:200 ~h:200 ~scale:1. in
  Multi.register t s1;
  Multi.register t s2;
  Alcotest.(check int) "count" 2 (Multi.count t);
  Alcotest.(check bool) "find" true
    (match Multi.find t 22 with Some w -> w == s2 | None -> false);
  Alcotest.(check bool) "first/last" true
    (match Multi.first t, Multi.last t with
     | Some a, Some b -> a == s1 && b == s2
     | _ -> false);
  Multi.set_focused t 22;
  Alcotest.(check int) "focused" 22 (Multi.focused t);
  Alcotest.(check bool) "find_focused" true
    (match Multi.find_focused t with Some w -> w == s2 | None -> false);
  (* rekey (driver recreates an OS window under a fresh id): the key
     moves but order and focus follow the surface. *)
  Alcotest.(check bool) "rekey" true (Multi.rekey t 22 99);
  Alcotest.(check bool) "old key gone" true (Multi.find t 22 = None);
  Alcotest.(check bool) "new key" true
    (match Multi.find t 99 with Some w -> w == s2 | None -> false);
  Alcotest.(check int) "focus followed" 99 (Multi.focused t);
  Alcotest.(check bool) "order kept" true
    (match Multi.last t with Some w -> w == s2 | None -> false);
  Alcotest.(check bool) "rekey unknown" false (Multi.rekey t 22 55);
  ignore (Multi.unregister t 99);
  s2.Multi.id <- 22;
  Multi.register t s2;
  Multi.set_focused t 22;
  (* unregistering the focused window clears focus; find_focused then
     falls back to the first registered *)
  ignore (Multi.unregister t 22);
  Alcotest.(check int) "focus cleared" 0 (Multi.focused t);
  Alcotest.(check bool) "fallback first" true
    (match Multi.find_focused t with Some w -> w == s1 | None -> false);
  Alcotest.(check int) "count after close" 1 (Multi.count t)

(* The routing contract the SDL driver relies on: dispatching into one
   window's Ui never leaks state into another's — each surface keeps
   independent focus/caret/interaction state. *)
let test_multi_dispatch_independence () =
  let s1 = surf_of ~id:1 ~w:200 ~h:200 ~scale:1. in
  let s2 = surf_of ~id:2 ~w:200 ~h:200 ~scale:1. in
  ignore
    (Multi.dispatch s1
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  Alcotest.(check int) "s1 field focused" 4 (Ui.focused s1.ui);
  Alcotest.(check int) "s2 untouched" 0 (Ui.focused s2.ui);
  ignore (Multi.dispatch s1 (Input.Text_input "ab"));
  Alcotest.(check int) "s1 caret" 2 (Ui.caret s1.ui);
  (* the same press on s2 now hits ITS field: identical coordinates,
     independent routing *)
  ignore
    (Multi.dispatch s2
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  Alcotest.(check int) "s2 field focused" 4 (Ui.focused s2.ui);
  Alcotest.(check int) "s2 caret empty" 0 (Ui.caret s2.ui);
  Alcotest.(check int) "s1 caret kept" 2 (Ui.caret s1.ui)

(* Logical resize → Resize_host action → drawable apply: the driver's
   chain for both window resizes and monitor-crossing scale changes. *)
let test_multi_resize_and_scale () =
  let s = surf_of ~id:1 ~w:200 ~h:200 ~scale:1. in
  (* scale math the driver uses everywhere *)
  Alcotest.(check bool) "2x" true
    (abs_float (Multi.drawable_scale 1920 960 -. 2.) < 1e-6);
  Alcotest.(check bool) "floor" true
    (abs_float (Multi.drawable_scale 0 960 -. 0.01) < 1e-6);
  (* unchanged drawable is a no-op — display events re-query all
     windows but only changed ones do work *)
  Alcotest.(check bool) "no-op" false
    (Multi.apply_drawable s ~dw:200 ~dh:200);
  (* moving to a Retina monitor: same logical size, double drawable *)
  Alcotest.(check bool) "retina change" true
    (Multi.apply_drawable s ~dw:400 ~dh:400);
  Alcotest.(check bool) "scale 2" true
    (abs_float (Multi.scale s -. 2.) < 1e-6);
  (* resize marks the host dirty; the next repaint lays out at the
     new device size — the scale-change relayout *)
  ignore (Lui_host.repaint s.host);
  Alcotest.(check int) "scene resized" 400
    (Lui_host.scene s.host).Lui_scene.width;
  (* logical resize arrives as a Ui action on the owning window only *)
  Multi.apply_logical_size s ~w:300 ~h:250;
  (match Multi.dispatch s (Input.Resize (300, 250)) with
   | [ Resize_host (300, 250) ] -> ()
   | a ->
     Alcotest.failf "expected [Resize_host], got %d actions"
       (List.length a))

let test_parse_windows () =
  (match parse_args [ "--windows"; "3" ] with
   | Ok c -> Alcotest.(check int) "windows" 3 c.windows
   | Error m -> Alcotest.fail m);
  (match parse_args [ "--windows"; "0" ] with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "windows 0 accepted");
  (match parse_args [ "--windows"; "9" ] with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "windows 9 accepted");
  (match parse_args [ "--windows" ] with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "missing value accepted")

(* Two real windows under the dummy driver: independent surfaces get
   independent frames and checksums; window 0's scene is byte-identical
   to the single-window golden, proving window 1's routed input (a Tab
   injected at frame 1) never leaked across. *)
let win_done_lines out =
  List.filter
    (fun l ->
       try
         ignore
           (Str.search_forward
              (Str.regexp "win=[0-9]+ done: frames=[0-9]+ checksum=") l 0);
         true
       with Not_found -> false)
    (String.split_on_char '\n' out)

let checksum_value l =
  try
    ignore
      (Str.search_forward
         (Str.regexp "checksum=\\([0-9a-f]+\\)") l 0);
    Str.matched_group 1 l
  with Not_found -> Alcotest.failf "no checksum in %s" l

let test_headless_multi () =
  with_main_exe @@ fun exe ->
  let run () =
    let ic =
      Unix.open_process_in
        (Printf.sprintf "%s --headless 6 --windows 2"
           (Filename.quote exe))
    in
    let out = read_all ic in
    match Unix.close_process_in ic with
    | Unix.WEXITED 0 -> out
    | _ -> Alcotest.failf "main.exe failed: %s" out
  in
  let out1 = run () and out2 = run () in
  (match win_done_lines out1 with
   | [ w0; w1 ] ->
     Alcotest.(check string) "win0 golden" "10ad2bfdcbf7b0ad"
       (checksum_value w0);
     Alcotest.(check bool) "independent checksums" true
       (checksum_value w0 <> checksum_value w1)
   | _ -> Alcotest.failf "expected two win= lines in:\n%s" out1);
  Alcotest.(check (list string)) "deterministic" (win_done_lines out1)
    (win_done_lines out2)

(* ---------- widget-layer interactions ---------- *)

let key ?(mods = Input.mods_none) k =
  Input.Key_down (k, mods, false)

let meta = { Input.mods_none with Input.meta = true }
let shift = { Input.mods_none with Input.shift = true }
let ctrl = { Input.mods_none with Input.ctrl = true }

let press_field s rects ui x y =
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (x, y, Input.Left, 1, Input.mods_none)))

let test_sel_shift_and_all () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  press_field s rects ui 5. 40.;
  ignore (Ui.handle ui s rects (Input.Text_input "hello"));
  (* caret at end: shift+Home selects the whole word *)
  ignore (Ui.handle ui s rects (key ~mods:shift Input.Home));
  Alcotest.(check int) "anchor stays" 5 (Ui.sel_anchor ui);
  Alcotest.(check int) "caret home" 0 (Ui.caret ui);
  (* plain Home collapses *)
  ignore (Ui.handle ui s rects (key Input.End));
  Alcotest.(check int) "collapsed" 5 (Ui.sel_anchor ui);
  (* Cmd/Ctrl+A selects all *)
  ignore (Ui.handle ui s rects (key ~mods:meta (Input.Other 4)));
  Alcotest.(check int) "sel all a" 0 (Ui.sel_anchor ui);
  Alcotest.(check int) "sel all c" 5 (Ui.caret ui)

let test_clipboard_cycle () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  press_field s rects ui 5. 40.;
  ignore (Ui.handle ui s rects (Input.Text_input "clip"));
  ignore (Ui.handle ui s rects (key ~mods:meta (Input.Other 4)));
  (* cut = clipboard + delete *)
  (match
     Ui.handle ui s rects (key ~mods:meta (Input.Other 27))
   with
   | [ Clipboard_write "clip"; Dispatch (TextChanged (4, "")) ] -> ()
   | a -> Alcotest.failf "cut: %d actions" (List.length a));
  (* paste requests the driver's clipboard read *)
  (match
     Ui.handle ui s rects (key ~mods:meta (Input.Other 25))
   with
   | [ Paste_request ] -> ()
   | _ -> Alcotest.fail "expected Paste_request");
  (* the driver feeds the text back through Input.Paste *)
  (match
     Ui.handle ui s rects (Input.Paste "back")
   with
   | [ Dispatch (TextChanged (4, "back")) ] -> ()
   | _ -> Alcotest.fail "expected paste splice");
  (* copy-only (mod+C) leaves the text *)
  ignore (Ui.handle ui s rects (key ~mods:meta (Input.Other 4)));
  (match
     Ui.handle ui s rects (key ~mods:ctrl (Input.Other 6))
   with
   | [ Clipboard_write "back" ] -> ()
   | _ -> Alcotest.fail "expected copy")

let test_undo_redo () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  press_field s rects ui 5. 40.;
  ignore (Ui.handle ui s rects (Input.Text_input "a"));
  ignore (Ui.handle ui s rects (Input.Text_input "b"));
  (* Cmd+Z undoes the second commit *)
  (match
     Ui.handle ui s rects (key ~mods:meta (Input.Other 29))
   with
   | [ Dispatch (TextChanged (4, "a")) ] -> ()
   | _ -> Alcotest.fail "expected undo");
  (* shift+Cmd+Z redoes it *)
  let m = { Input.mods_none with Input.meta = true; Input.shift = true } in
  (match
     Ui.handle ui s rects (key ~mods:m (Input.Other 29))
   with
   | [ Dispatch (TextChanged (4, "ab")) ] -> ()
   | _ -> Alcotest.fail "expected redo")

(* Text node with data-user-select for the static-selection path. *)
let sel_text_store () =
  store_of
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      SetProp (3, TextValue, StringValue "hello world");
      SetProp
        (3, DataAttrs,
          StringValue
            (Lui_protocol.data_attrs_encode
               [ ("data-user-select", "text") ])) ]

let test_static_select () =
  let s = sel_text_store () in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  let r = Rects.get rects 3 in
  (* double-click near the left edge selects the first word *)
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (r.x +. 2., r.y +. 2., Input.Left, 2,
          Input.mods_none)));
  (match Ui.sel_text ui with
   | Some (3, 0, 3, 5) -> ()
   | a -> Alcotest.failf "word sel: %s"
            (match a with
             | Some (i, x, y, z) ->
               Printf.sprintf "(%d,%d,%d,%d)" i x y z
             | None -> "none"));
  (* drag-select extends the range to the drop point *)
  ignore
    (Ui.handle ui s rects
       (Input.Move (r.x +. 90., r.y +. 2.)));
  (match Ui.sel_text ui with
   | Some (3, 0, 3, e) when e > 5 -> ()
   | a -> Alcotest.failf "drag extend: %s"
            (match a with
             | Some (i, x, y, z) ->
               Printf.sprintf "(%d,%d,%d,%d)" i x y z
             | None -> "none"));
  ignore
    (Ui.handle ui s rects
       (Input.Button_up (r.x +. 90., r.y +. 2., Input.Left,
          Input.mods_none)));
  (* copy on the static selection writes the substring *)
  (match
     Ui.handle ui s rects (key ~mods:meta (Input.Other 6))
   with
   | [ Clipboard_write t ] ->
     Alcotest.(check bool) "copied slice" true
       (String.length t > 5 && String.sub t 0 5 = "hello")
   | _ -> Alcotest.fail "expected copy of selection")

(* Column with three selectable text siblings (3, 5, 6) separated by
   a non-selectable line (4) — the bound the cross-node selection
   tests below exercise. *)
let sel_sibs_store () =
  let da id =
    SetProp
      (id, DataAttrs,
        StringValue
          (Lui_protocol.data_attrs_encode
             [ ("data-user-select", "text") ]))
  in
  store_of
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text); CreateNode (4, Text);
      CreateNode (5, Text); CreateNode (6, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      InsertChild (2, 4, 1); InsertChild (2, 5, 2);
      InsertChild (2, 6, 3);
      SetProp (3, TextValue, StringValue "alpha line");
      SetProp (4, TextValue, StringValue "plain line");
      SetProp (5, TextValue, StringValue "beta line");
      SetProp (6, TextValue, StringValue "gamma line");
      da 3; da 5; da 6 ]

let copy_of ui s rects =
  match
    Ui.handle ui s rects (key ~mods:meta (Input.Other 6))
  with
  | [ Clipboard_write t ] -> t
  | _ -> Alcotest.fail "expected copy of selection"

let test_sel_siblings () =
  let s = sel_sibs_store () in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  let r3 = Rects.get rects 3 and r5 = Rects.get rects 5
  and r6 = Rects.get rects 6 in
  (* press at the left edge of node 3, then drag down onto node 5 *)
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (r3.x +. 2., r3.y +. 2., Input.Left, 1,
          Input.mods_none)));
  ignore
    (Ui.handle ui s rects
       (Input.Move (r5.x +. 24., r5.y +. 2.)));
  (match Ui.sel_text ui with
   | Some (3, a, 5, f) when a < 4 && f > 0 -> ()
   | a -> Alcotest.failf "cross-node sel: %s"
            (match a with
             | Some (i, x, y, z) ->
               Printf.sprintf "(%d,%d,%d,%d)" i x y z
             | None -> "none"));
  ignore
    (Ui.handle ui s rects
       (Input.Button_up (r5.x +. 24., r5.y +. 2., Input.Left,
          Input.mods_none)));
  (* the copy joins endpoints in document order across the sibling
     boundary — the non-selectable node 4 never enters it *)
  let copied = copy_of ui s rects in
  Alcotest.(check bool) "doc order" true
    (String.length copied > 12
     && String.sub copied 0 10 = "alpha line"
     && copied.[String.length "alpha line"] = '\n');
  (* Cmd+A spans every selectable sibling of the container *)
  ignore
    (Ui.handle ui s rects (key ~mods:meta (Input.Other 4)));
  Alcotest.(check string) "select-all" "alpha line\nbeta line\ngamma line"
    (copy_of ui s rects);
  (* a drag below the last sibling clamps to its end *)
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (r3.x +. 2., r3.y +. 2., Input.Left, 1,
          Input.mods_none)));
  ignore
    (Ui.handle ui s rects
       (Input.Move (r6.x +. 5., r6.y +. r6.h +. 40.)));
  Alcotest.(check string) "clamp end" "alpha line\nbeta line\ngamma line"
    (copy_of ui s rects)

let test_tab_activation () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  (* Tab now tours every activatable control: button 3, field 4,
     button 7 — keyboard focus shows the ring *)
  (match Ui.handle ui s rects (key Input.Tab) with
   | [ Focus_changed 3 ] -> ()
   | a -> Alcotest.failf "tab1: %d acts" (List.length a));
  Alcotest.(check bool) "kbd focus" true (Ui.focus_visible ui);
  (match Ui.handle ui s rects (key Input.Tab) with
   | [ Focus_changed 4 ] -> ()
   | _ -> Alcotest.fail "tab2 expected field");
  (match Ui.handle ui s rects (key Input.Tab) with
   | [ Focus_changed 7 ] -> ()
   | _ -> Alcotest.fail "tab3 expected nested button");
  (* shift+Tab walks back *)
  (match
     Ui.handle ui s rects (key ~mods:shift Input.Tab)
   with
   | [ Focus_changed 4 ] -> ()
   | _ -> Alcotest.fail "shift-tab expected field");
  ignore (Ui.handle ui s rects (key ~mods:shift Input.Tab));
  Alcotest.(check int) "back on btn" 3 (Ui.focused ui);
  (* Space activates the focused control *)
  (match Ui.handle ui s rects (key Input.Space) with
   | [ Dispatch (Press 3) ] -> ()
   | _ -> Alcotest.fail "space should press");
  (* pointer focus does not show the ring *)
  press_field s rects ui 5. 40.;
  Alcotest.(check bool) "ptr focus" false (Ui.focus_visible ui)

let test_control_keys () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, NumberStepper); CreateNode (4, Slider);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        InsertChild (2, 4, 1);
        SetProp (3, MinValue, FloatValue 0.);
        SetProp (3, MaxValue, FloatValue 10.);
        SetProp (3, StepValue, FloatValue 0.5);
        SetProp (4, ProgressValue, FloatValue 0.5) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  Ui.set_focused ui s 3;
  (match Ui.handle ui s rects (key Input.Arrow_right) with
   | [ Dispatch (ValueChanged (3, v)) ] ->
     Alcotest.(check (float 0.001)) "step" 0.5 v
   | _ -> Alcotest.fail "stepper arrow");
  Ui.set_focused ui s 4;
  (match Ui.handle ui s rects (key Input.Arrow_left) with
   | [ Dispatch (ValueChanged (4, v)) ] ->
     Alcotest.(check (float 0.001)) "slider" 0.45 v
   | _ -> Alcotest.fail "slider arrow");
  (* radio arrows move inside the group *)
  let s' =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Radio); CreateNode (4, Radio);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        InsertChild (2, 4, 1) ]
  in
  Ui.set_focused ui s' 3;
  (match Ui.handle ui s' rects (key Input.Arrow_down) with
   | Focus_changed 4 :: _ -> ()
   | _ -> Alcotest.fail "radio move")

(* A list (ListContainer) with keyed items, for scroll/typeahead. *)
let list_store () =
  store_of
    [ CreateNode (1, Root); CreateNode (2, ListContainer);
      CreateNode (3, ListItem); CreateNode (4, ListItem);
      CreateNode (5, ListItem);
      InsertChild (1, 2, 0);
      InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      InsertChild (2, 5, 2);
      SetProp (3, KeyValue, StringValue "item-a");
      SetProp (3, TextValue, StringValue "apple");
      SetProp (4, KeyValue, StringValue "item-b");
      SetProp (4, TextValue, StringValue "banana");
      SetProp (5, KeyValue, StringValue "item-c");
      SetProp (5, TextValue, StringValue "cherry") ]

let test_list_typeahead () =
  let s = list_store () in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:40 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  Ui.set_content_rect ui (fun id -> Rects.get rects id);
  (* click the first item: becomes the highlight, scopes typeahead *)
  let r3 = Rects.get rects 3 in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down
          (r3.x +. 2., r3.y +. 2., Input.Left, 1, Input.mods_none)));
  Alcotest.(check int) "hl" 3 (Ui.hl_item ui);
  (* 'b' jumps to banana *)
  ignore
    (Ui.handle ui s rects (key (Input.Other 5)));
  Alcotest.(check int) "typeahead b" 4 (Ui.hl_item ui);
  Alcotest.(check string) "buf" "b" (Ui.typeahead ui);
  (* arrows move the highlight; Enter presses it *)
  ignore (Ui.handle ui s rects (key Input.Arrow_down));
  Alcotest.(check int) "arrow" 5 (Ui.hl_item ui);
  (match Ui.handle ui s rects (key Input.Return) with
   | [ Dispatch (Press 5) ] -> ()
   | _ -> Alcotest.fail "enter should press highlighted item")

let test_scroll_request () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, ListContainer);
        CreateNode (3, ListItem); CreateNode (4, ListItem);
        CreateNode (5, ListItem);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        InsertChild (2, 5, 2);
        SetProp (3, KeyValue, StringValue "item-a");
        SetProp (4, KeyValue, StringValue "item-b");
        SetProp (5, KeyValue, StringValue "item-c");
        SetProp (2, ScrollTarget, StringValue "item-c");
        SetProp (2, ScrollToken, IntValue 1);
        SetProp (2, TrackVisibleRange, BoolValue true);
        (* a 20px viewport over 72px of items: scrolling has range *)
        SetProp (2, HeightValue, IntValue 20) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  Ui.set_content_rect ui (fun id -> Rects.get rects id);
  Ui.set_scroll_cap ui 2 200.;
  (* the sync pass honors the new scroll-target token *)
  let acts = Ui.store_changed ui s in
  (match press_actions acts with
   | [ ScrollCompleted (2, 1, "succeeded") ] -> ()
   | [ VisibleRange _; ScrollCompleted (2, 1, "succeeded") ]
   | [ ScrollCompleted (2, 1, "succeeded"); VisibleRange _ ] -> ()
   | _ -> Alcotest.fail "expected ScrollCompleted");
  Alcotest.(check bool) "scrolled" true (Ui.scroll_offset ui 2 > 0.);
  (* a missing target reports missing-target *)
  Lui_store.apply_batch s
    { generation = 2;
      ops =
        [ SetProp (2, ScrollTarget, StringValue "nope");
          SetProp (2, ScrollToken, IntValue 2) ] };
  (match press_actions (Ui.store_changed ui s) with
   | [ ScrollCompleted (2, 2, "missing-target") ]
   | [ VisibleRange _; ScrollCompleted (2, 2, "missing-target") ]
   | [ ScrollCompleted (2, 2, "missing-target"); VisibleRange _ ] -> ()
   | a -> Alcotest.failf "missing: %d" (List.length a));
  (* programmatic APIs clamp and move *)
  ignore (Ui.scroll_to ui s 2 9999.);
  Alcotest.(check (float 0.001)) "cap" 200. (Ui.scroll_offset ui 2);
  ignore (Ui.scroll_by ui s 2 (-50.));
  Alcotest.(check (float 0.001)) "by" 150. (Ui.scroll_offset ui 2)

let test_drag_drop () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Row); CreateNode (4, Row);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        SetProp (3, HeightValue, IntValue 20);
        SetProp (4, HeightValue, IntValue 20);
        SetProp
          (3, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("draggable", "true");
                   ("data-drag-payload", "row-payload") ]));
        SetProp
          (4, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("data-drop-target", "true");
                   ("data-drop-accept", "row-") ])) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:60 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  let r3 = Rects.get rects 3 and r4 = Rects.get rects 4 in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down
          (r3.x +. 4., r3.y +. 4., Input.Left, 1, Input.mods_none)));
  (* small move stays a plain press; past 6px the grab promotes *)
  ignore (Ui.handle ui s rects (Input.Move (r3.x +. 7., r3.y +. 5.)));
  Alcotest.(check bool) "not yet" false (Ui.drag_active ui);
  ignore (Ui.handle ui s rects (Input.Move (r3.x +. 30., r3.y +. 20.)));
  Alcotest.(check bool) "dragging" true (Ui.drag_active ui);
  (* over the accepting target, then release: drop completes *)
  ignore
    (Ui.handle ui s rects
       (Input.Move (r4.x +. 5., r4.y +. 5.)));
  ignore
    (Ui.handle ui s rects
       (Input.Button_up
          (r4.x +. 5., r4.y +. 5., Input.Left, Input.mods_none)));
  (match Ui.last_drop ui with
   | Some (4, "row-payload", 1) -> ()
   | a -> Alcotest.failf "drop: %s"
            (match a with
             | Some (i, p, n) -> Printf.sprintf "(%d,%s,%d)" i p n
             | None -> "none"))

let test_file_drop () =
  (* an OS file drop lands on the deepest node whose accept list
     matches the namespaced payload; non-matching targets stay empty *)
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Text); CreateNode (4, Text);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        InsertChild (2, 4, 1);
        SetProp (3, TextValue, StringValue "os drops here");
        SetProp
          (3, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("data-drop-target", "true");
                   ("data-drop-accept", "file:,text:") ]));
        SetProp (4, TextValue, StringValue "rows here");
        SetProp
          (4, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("data-drop-target", "true");
                   ("data-drop-accept", "row-") ])) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  let r3 = Rects.get rects 3 and r4 = Rects.get rects 4 in
  (* pointer parked on the file well: the path arrives namespaced *)
  ignore
    (Ui.handle ui s rects
       (Input.Move (r3.x +. 5., r3.y +. 2.)));
  ignore (Ui.handle ui s rects (Input.Drop_file "/tmp/a.png"));
  (match Ui.last_drop ui with
   | Some (3, "file:/tmp/a.png", 1) -> ()
   | a -> Alcotest.failf "file drop: %s"
            (match a with
             | Some (i, p, n) -> Printf.sprintf "(%d,%s,%d)" i p n
             | None -> "none"));
  (* a repeated identical drop still bumps the serial *)
  ignore (Ui.handle ui s rects (Input.Drop_file "/tmp/a.png"));
  Alcotest.(check bool) "serial bumps" true
    (match Ui.last_drop ui with
     | Some (3, "file:/tmp/a.png", 2) -> true
     | _ -> false);
  (* the row-only well rejects a file payload — no new drop *)
  ignore
    (Ui.handle ui s rects
       (Input.Move (r4.x +. 5., r4.y +. 2.)));
  ignore (Ui.handle ui s rects (Input.Drop_file "/tmp/b.png"));
  Alcotest.(check bool) "no accept" true
    (match Ui.last_drop ui with
     | Some (3, "file:/tmp/a.png", 2) -> true
     | _ -> false);
  (* dropped text uses the "text:" namespace *)
  ignore
    (Ui.handle ui s rects
       (Input.Move (r3.x +. 5., r3.y +. 2.)));
  ignore (Ui.handle ui s rects (Input.Drop_text "hello"));
  Alcotest.(check bool) "text drop" true
    (match Ui.last_drop ui with
     | Some (3, "text:hello", 3) -> true
     | _ -> false)

let test_overlay_close () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, TextField); CreateNode (4, Dialog);
        CreateNode (5, Button); CreateNode (6, Popover);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        InsertChild (4, 5, 0); InsertChild (2, 6, 2);
        SetProp (3, TextValue, StringValue "") ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  (* popover is topmost (later in paint order): Escape dismisses it *)
  (match Ui.handle ui s rects (key Input.Escape) with
   | [ Dispatch (Dismiss 6) ] -> ()
   | a -> Alcotest.failf "esc popover: %d" (List.length a));
  (* the app closes it — drop the node so the dialog becomes top *)
  Lui_store.apply_batch s
    { generation = 2; ops = [ DropNode 6 ] };
  (* dialog is modal: a press outside its subtree is swallowed —
     no PointerDown, no focus move *)
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (5., 5., Input.Left, 1, Input.mods_none))
  in
  Alcotest.(check int) "modal swallows" 0 (List.length acts);
  Alcotest.(check int) "no focus steal" 0 (Ui.focused ui);
  (* Escape on the modal dialog dismisses through the wire *)
  (match Ui.handle ui s rects (key Input.Escape) with
   | [ Dispatch (Dismiss 4) ] -> ()
   | _ -> Alcotest.fail "esc dialog")

let test_light_dismiss () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, TextField); CreateNode (4, Popover);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        SetProp (3, TextValue, StringValue "") ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  (* click outside a light-dismiss surface: Dismiss + normal press *)
  (match
     Ui.handle ui s rects
       (Input.Button_down (5., 5., Input.Left, 1, Input.mods_none))
   with
   | Dispatch (Dismiss 4) :: _ -> ()
   | _ -> Alcotest.fail "expected Dismiss on click outside")

let test_autofocus () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Button); CreateNode (4, TextField);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        SetProp (3, TextValue, StringValue "ok");
        SetProp (4, TextValue, StringValue "");
        SetProp (4, Autofocus, BoolValue true) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  (* the autofocus-marked field takes focus once, at mount *)
  (match Ui.store_changed ui s with
   | [ Focus_changed 4 ] -> ()
   | a -> Alcotest.failf "autofocus: %d acts" (List.length a));
  Alcotest.(check int) "focused" 4 (Ui.focused ui);
  (* never steals focus again *)
  Ui.set_focused ui s 0;
  Alcotest.(check int) "once" 0
    (List.length (Ui.store_changed ui s));
  Ui.set_focused ui s 3;
  let change ops =
    Lui_store.apply_batch s { generation = 2; ops };
    ignore (Ui.store_changed ui s)
  in
  change
    [ CreateNode (5, Popover); CreateNode (6, TextField);
      CreateNode (14, TextField);
      CreateNode (7, TextField); CreateNode (8, TextField);
      CreateNode (9, Button);
      InsertChild (2, 5, 2); InsertChild (5, 6, 0);
      InsertChild (5, 14, 1); InsertChild (5, 7, 2);
      InsertChild (5, 8, 3); InsertChild (5, 9, 4);
      SetProp (6, Enabled, BoolValue false);
      SetProp (6, Autofocus, BoolValue true);
      SetProp (14, Visible, BoolValue false);
      SetProp (14, Autofocus, BoolValue true);
      SetProp (7, Autofocus, BoolValue true) ];
  Alcotest.(check int) "dynamic popover autofocus" 7 (Ui.focused ui);
  ignore (Ui.handle ui s rects (key Input.Tab));
  Alcotest.(check int) "Tab advances to label" 8 (Ui.focused ui);
  ignore (Ui.store_changed ui s);
  Alcotest.(check int) "frame preserves label focus" 8 (Ui.focused ui);
  ignore (Ui.handle ui s rects (key Input.Tab));
  Alcotest.(check int) "Tab advances to button" 9 (Ui.focused ui);
  change [ DropNode 5 ];
  Ui.set_focused ui s 3;
  let modal =
    [ CreateNode (10, Dialog); CreateNode (11, TextField);
      InsertChild (2, 10, 2); InsertChild (10, 11, 0);
      SetProp (11, Autofocus, BoolValue true) ]
  in
  change modal;
  Alcotest.(check int) "modal autofocus" 11 (Ui.focused ui);
  change
    [ CreateNode (12, TextField); InsertChild (2, 12, 3);
      SetProp (12, Autofocus, BoolValue true) ];
  Alcotest.(check int) "background mount cannot steal modal focus" 11
    (Ui.focused ui);
  change [ DropNode 10 ];
  Alcotest.(check int) "modal removal restores focus" 3 (Ui.focused ui);
  change modal;
  Alcotest.(check int) "reopened modal autofocus" 11 (Ui.focused ui);
  Ui.set_focused ui s 3;
  ignore (Ui.store_changed ui s);
  Alcotest.(check int) "explicit focus is not stolen back" 3 (Ui.focused ui)

let test_modal_focus_scope () =
  (* C3: a modal dialog without autofocus children still owns the
     keyboard — the pre-modal focus is cleared into its scope and
     restored on close, and background lists keep their highlight. *)
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, TextField); CreateNode (4, ListContainer);
        CreateNode (5, ListItem); CreateNode (6, ListItem);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        InsertChild (2, 4, 1); InsertChild (4, 5, 0);
        InsertChild (4, 6, 1);
        SetProp (3, TextValue, StringValue "bg");
        SetProp (5, TextValue, StringValue "one");
        SetProp (6, TextValue, StringValue "two") ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  (* click the background list so it owns a keyboard highlight *)
  let r5 = Rects.get rects 5 in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down
          (r5.x +. 2., r5.y +. 2., Input.Left, 1, Input.mods_none)));
  Alcotest.(check int) "list item highlighted" 5 (Ui.hl_item ui);
  Ui.set_focused ui s 3;
  (* a modal with no autofocus child mounts over the focused field *)
  Lui_store.apply_batch s
    { generation = 2;
      ops =
        [ CreateNode (7, Dialog); CreateNode (8, TextField);
          InsertChild (2, 7, 2); InsertChild (7, 8, 0);
          SetProp (8, TextValue, StringValue "") ] };
  ignore (Ui.store_changed ui s);
  Alcotest.(check int) "focus cleared into modal scope" 0
    (Ui.focused ui);
  (* typing no longer reaches the background field *)
  let acts = Ui.handle ui s rects (Input.Text_input "x") in
  Alcotest.(check int) "keystroke swallowed" 0
    (List.length (press_actions acts));
  Alcotest.(check (option string)) "background text untouched"
    (Some "bg") (Lui_store.string_prop s 3 "text");
  (* arrows and Return leave the background list untouched *)
  ignore (Ui.handle ui s rects (key Input.Arrow_down));
  ignore (Ui.handle ui s rects (key Input.Return));
  Alcotest.(check int) "highlight frozen" 5 (Ui.hl_item ui);
  (* Tab stays inside the dialog's scope *)
  ignore (Ui.handle ui s rects (key Input.Tab));
  Alcotest.(check int) "tab into dialog field" 8 (Ui.focused ui);
  (match
     press_actions (Ui.handle ui s rects (Input.Text_input "y"))
   with
   | [ TextChanged (8, "y") ] -> ()
   | _ -> Alcotest.fail "expected TextChanged on dialog field");
  (* closing restores the pre-modal focus *)
  Lui_store.apply_batch s { generation = 3; ops = [ DropNode 7 ] };
  ignore (Ui.store_changed ui s);
  Alcotest.(check int) "focus restored" 3 (Ui.focused ui);
  (match
     press_actions (Ui.handle ui s rects (Input.Text_input "z"))
   with
   | [ TextChanged (3, _) ] -> ()
   | _ -> Alcotest.fail "expected TextChanged back on field 3")

let test_appear_once () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Text);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        SetProp (3, AppearEnabled, BoolValue true);
        SetProp (3, TextValue, StringValue "hi") ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  (* mount lifecycle: Appear fires once, not per frame *)
  (match press_actions (Ui.store_changed ui s) with
   | [ Appear 3 ] -> ()
   | _ -> Alcotest.fail "expected Appear 3");
  Alcotest.(check int) "once" 0
    (List.length (press_actions (Ui.store_changed ui s)))

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
          Alcotest.test_case "caret ops" `Quick test_caret_ops_wiring;
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
        [ Alcotest.test_case "wheel" `Quick test_scroll;
          Alcotest.test_case "wheel-x" `Quick test_wheel_x ] );
      ( "demo",
        [ Alcotest.test_case "dispatch flow" `Quick test_demo_dispatch ] );
      ( "selection",
        [ Alcotest.test_case "shift+all" `Quick test_sel_shift_and_all;
          Alcotest.test_case "static text" `Quick test_static_select;
          Alcotest.test_case "siblings" `Quick test_sel_siblings ] );
      ( "clipboard",
        [ Alcotest.test_case "cut/copy/paste" `Quick test_clipboard_cycle;
          Alcotest.test_case "undo/redo" `Quick test_undo_redo ] );
      ( "keys",
        [ Alcotest.test_case "tab activation" `Quick test_tab_activation;
          Alcotest.test_case "control keys" `Quick test_control_keys ] );
      ( "list",
        [ Alcotest.test_case "typeahead" `Quick test_list_typeahead;
          Alcotest.test_case "scroll request" `Quick test_scroll_request ] );
      ( "dnd",
        [ Alcotest.test_case "drag drop" `Quick test_drag_drop;
          Alcotest.test_case "file drop" `Quick test_file_drop ] );
      ( "overlay",
        [ Alcotest.test_case "modal+esc" `Quick test_overlay_close;
          Alcotest.test_case "light dismiss" `Quick test_light_dismiss;
          Alcotest.test_case "appear once" `Quick test_appear_once;
          Alcotest.test_case "autofocus" `Quick test_autofocus;
          Alcotest.test_case "modal focus scope" `Quick
            test_modal_focus_scope ] );
      ( "multi-window",
        [ Alcotest.test_case "registry" `Quick test_multi_registry;
          Alcotest.test_case "dispatch" `Quick
            test_multi_dispatch_independence;
          Alcotest.test_case "resize+scale" `Quick
            test_multi_resize_and_scale;
          Alcotest.test_case "windows flag" `Quick test_parse_windows ] );
      ( "headless",
        [ Alcotest.test_case "checksum" `Quick test_headless_checksum;
          Alcotest.test_case "drop-file" `Quick test_headless_drop;
          Alcotest.test_case "two windows" `Quick test_headless_multi ] ) ]
