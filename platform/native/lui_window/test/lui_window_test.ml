(* Pure-part tests for the window host: CLI parsing, SDL-constant
   tables, event mapping and admission gating, rect hit testing, the
   layout stub, resize scale math and frame pacing. The SDL/GL path
   itself is exercised by running main.exe. *)

open Lui_scene
open Lui_protocol
open Lui_window

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
      ( "resize",
        [ Alcotest.test_case "scale" `Quick test_resize_scale ] );
      ( "pacing",
        [ Alcotest.test_case "dirty" `Quick test_pacing ] );
      ( "checksum",
        [ Alcotest.test_case "ops" `Quick test_checksum ] ) ]
