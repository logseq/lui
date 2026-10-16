(* Pure-part tests for the window host: CLI parsing, SDL-constant
   tables, event mapping and admission gating, rect hit testing, the
   layout stub, resize scale math and frame pacing. The SDL/GL path
   itself is exercised by running main.exe. *)

open Lui_scene
open Lui_protocol
open Lui_window
open Lui_window_demo

let test_css_percentage_colors () =
  List.iter
    (fun (css, (r, g, b, a)) ->
      let actual = Option.get (Theme.color_of css) in
      Alcotest.(check int) (css ^ " alpha") a actual.a;
      Alcotest.(check int) (css ^ " red") r actual.r;
      Alcotest.(check int) (css ^ " green") g actual.g;
      Alcotest.(check int) (css ^ " blue") b actual.b)
    [
      ("rgb(18 52 86 / 50%)", (18, 52, 86, 128));
      ("rgba(18, 52, 86, 0.5)", (18, 52, 86, 128));
      ("hsl(0 0% 100% / 50%)", (255, 255, 255, 128));
      ("hsla(0, 0%, 100%, 0.5)", (255, 255, 255, 128));
      ("rgb(50% 50% 50%)", (128, 128, 128, 255));
      ("rgb(0% 50% 100% / 0%)", (0, 128, 255, 0));
      ("rgb(0% 50% 100% / 100%)", (0, 128, 255, 255));
    ]

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

let test_presentation_meter () =
  let m = Presentation_meter.create ~now_ms:100. ~displayed_frames:20 in
  Alcotest.(check (option (float 0.001))) "wait for complete window" None
    (Presentation_meter.sample m ~now_ms:600. ~displayed_frames:70);
  Alcotest.(check (option (float 0.001))) "actual 100 Hz display" (Some 100.)
    (Presentation_meter.sample m ~now_ms:1100. ~displayed_frames:120);
  Alcotest.(check (option (float 0.001))) "irregular window uses elapsed time" (Some 60.)
    (Presentation_meter.sample m ~now_ms:2600. ~displayed_frames:210);
  Alcotest.(check (option (float 0.001))) "idle display rate falls to zero" (Some 0.)
    (Presentation_meter.sample m ~now_ms:3600. ~displayed_frames:210)

let test_presentation_meter_rejects_regression () =
  let m = Presentation_meter.create ~now_ms:100. ~displayed_frames:20 in
  ignore (Presentation_meter.sample m ~now_ms:600. ~displayed_frames:70);
  Alcotest.check_raises "reject decreasing display counter"
    (Invalid_argument "presentation counters must be monotonic")
    (fun () -> ignore (Presentation_meter.sample m ~now_ms:650. ~displayed_frames:69));
  Alcotest.check_raises "reject decreasing clock"
    (Invalid_argument "presentation counters must be monotonic")
    (fun () -> ignore (Presentation_meter.sample m ~now_ms:599. ~displayed_frames:70))

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

let test_layout_padding_edges () =
  List.iter
    (fun scale ->
      List.iter
        (fun kind ->
          let store =
            store_of
              [
                CreateNode (1, Root);
                CreateNode (2, kind);
                CreateNode (3, Box);
                InsertChild (1, 2, 0);
                InsertChild (2, 3, 0);
                SetProp (2, WidthValue, IntValue 100);
                SetProp (2, HeightValue, IntValue 80);
                SetProp (2, PaddingHorizontal, IntValue 10);
                SetProp (2, PaddingVertical, IntValue 6);
                SetProp (2, PaddingTop, IntValue 3);
                SetProp (2, PaddingRight, IntValue 8);
                SetProp (2, PaddingBottom, IntValue 9);
                SetProp (2, PaddingLeft, IntValue 28);
                SetProp (3, GrowValue, FloatValue 1.);
              ]
          in
          let rects = Rects.create () in
          Layout.refresh store rects ~width:200 ~height:120 ~scale
            ~measure:Layout.default_measure;
          let child = Rects.get rects 3 in
          List.iter
            (fun (label, expected, actual) ->
              Alcotest.(check (float 0.001)) label (expected *. scale) actual)
            [
              ("child left", 28., child.x);
              ("child top", 3., child.y);
              ("child width", 64., child.w);
              ("child height", 68., child.h);
            ])
        [ Column; Row ])
    [ 1.; 2. ]

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

let rects_of lst =
  let t = Rects.create () in
  List.iter (fun (id, r) -> Hashtbl.replace t id r) lst;
  t

(* DOM order [z2, z1]: the z2 node paints on top even though it is the
   first child, so it must head the hit path — paint order, not store
   order, decides who wins a click. *)
let test_hit_z_order () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Stack);
        CreateNode (3, Button); CreateNode (4, Button);
        InsertChild (1, 2, 0);
        InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        SetProp (3, ZIndex, IntValue 2); SetProp (4, ZIndex, IntValue 1) ]
  in
  let r = rect 0. 0. 100. 40. in
  let rects = rects_of [ (1, r); (2, r); (3, r); (4, r) ] in
  Alcotest.(check (option int)) "z2 paints on top" (Some 3)
    (hit s rects ~x:10. ~y:10.)

(* A popover inside a clipped scroll container paints OUTSIDE the
   clip — it is a promoted overlay. A click in that region must reach
   the popover's child, not die on the scroll clip like an in-flow
   child does. *)
let test_hit_popup_escapes_clip () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Scroll);
        CreateNode (3, Popover); CreateNode (4, Button);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        InsertChild (3, 4, 0) ]
  in
  let rects =
    rects_of
      [ (1, rect 0. 0. 100. 100.); (2, rect 0. 0. 100. 100.);
        (3, rect 0. 120. 80. 30.); (4, rect 0. 130. 80. 10.) ]
  in
  Alcotest.(check (option int)) "popover's child hits" (Some 4)
    (hit s rects ~x:10. ~y:135.)

(* A mid-tree popup paints above siblings that come after it, so its
   content wins the click even when a later sibling covers the same
   spot. *)
let test_hit_popup_promoted () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Popover);
        CreateNode (3, Button); CreateNode (4, Button);
        InsertChild (1, 2, 0); InsertChild (1, 4, 1);
        InsertChild (2, 3, 0) ]
  in
  let r = rect 0. 0. 100. 100. in
  let rects = rects_of [ (1, r); (2, r); (3, r); (4, r) ] in
  Alcotest.(check (option int)) "popup over later sibling" (Some 3)
    (hit s rects ~x:10. ~y:10.)

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
  (* Escape blurs the field and leaves an unfocused window open. *)
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
   | [] -> ()
   | _ -> Alcotest.fail "unfocused Escape must leave the window open");
  (match Ui.handle ui s rects Input.Quit_input with
   | [ Quit ] -> ()
   | _ -> Alcotest.fail "explicit quit must still close the window")

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

let test_text_revisions () =
  (* P1-2: the text session counts host-local edits and adopted
     model revisions separately — a Ui-visible window into the
     edit protocol. *)
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  let s0, _, _ = Ui.text_revisions ui in
  Ui.set_focused ui s 4;
  ignore (Ui.handle ui s rects (Input.Text_input "ab"));
  let s1, l1, m1 = Ui.text_revisions ui in
  Alcotest.(check bool) "new session" true (s1 <> s0);
  Alcotest.(check int) "local edit counted" 1 l1;
  Alcotest.(check int) "no model adoption yet" 0 m1;
  (* a model-side write adopts into the session *)
  Lui_store.apply_batch s
    { generation = 2;
      ops = [ SetProp (4, TextValue, StringValue "remote") ] };
  ignore (Ui.store_changed ui s);
  Alcotest.(check string) "model text adopted" "remote"
    (Ui.shadow ui);
  let _, _, m2 = Ui.text_revisions ui in
  Alcotest.(check int) "model revision" 1 m2

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
  Ui.tick_scrollbars ui ~now_ms:100.;
  Alcotest.(check bool) "scrollbar hidden at rest" false (Ui.scrollbar_visible ui 2);
  Alcotest.(check (float 0.001)) "cap" 80. (Ui.scroll_cap ui 2);
  Alcotest.(check (float 0.001)) "x cap starts 0" 0.
    (Ui.scroll_cap_x ui 2);
  Alcotest.(check (float 0.001)) "starts at 0" 0. (Ui.scroll_offset ui 2);
  (* park the pointer inside the scroll container, then wheel down *)
  ignore (Ui.handle ui s rects (Input.Move (10., 10.)));
  ignore (Ui.handle ui s rects (Input.Wheel (0., -1.)));
  Alcotest.(check (float 0.001)) "scrolled" 44. (Ui.scroll_offset ui 2);
  Alcotest.(check bool) "scrollbar visible while scrolling" true (Ui.scrollbar_visible ui 2);
  Ui.tick_scrollbars ui ~now_ms:1000.;
  Alcotest.(check bool) "scrollbar hides after inactivity" false (Ui.scrollbar_visible ui 2);
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

let test_live_scroll_readers () =
  let store =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Scroll); InsertChild (1, 2, 0) ]
  in
  let ui = Ui.create () in
  (* Drivers retain these callbacks before the first layout and wheel. *)
  let offset_y = Ui.scroll_offset ui and offset_x = Ui.scroll_offset_x ui in
  let cap_y = Ui.scroll_cap ui and cap_x = Ui.scroll_cap_x ui in
  List.iter
    (fun (axis, set_cap, offset, cap) ->
      List.iter
        (fun range ->
          set_cap ui 2 range;
          Alcotest.(check (float 0.001))
            "retained reader sees new range" range (cap 2);
          List.iter
            (fun target ->
              ignore (Ui.scroll_to ~axis ui store 2 target);
              Alcotest.(check (float 0.001))
                "retained reader sees movement and reversal"
                (Float.min range target) (offset 2))
            [ 0.; 44.; 200.; 12.; 0. ])
        [ 80.; 30.; 0. ])
    [
      (Ui.Y, Ui.set_scroll_cap, offset_y, cap_y);
      (Ui.X, Ui.set_scroll_cap_x, offset_x, cap_x);
    ]

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

(* ---------- pixel snapping contract ---------- *)

(* The stub layout snaps stored rects to device-pixel edges at
   fractional scales, and stacked siblings share the snapped
   boundary — the same edge the paint pass and scroll extents see. *)
let test_snap_stub_layout () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Button); CreateNode (4, Button);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        SetProp (2, PaddingValue, IntValue 3);
        SetProp (3, HeightValue, IntValue 20);
        SetProp (4, HeightValue, IntValue 20) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.5
    ~measure:Layout.default_measure;
  let aligned (r : rect) =
    r.x = Float.round r.x && r.y = Float.round r.y
    && r.w = Float.round r.w && r.h = Float.round r.h
  in
  List.iter
    (fun id ->
       Alcotest.(check bool)
         (Printf.sprintf "node %d aligned" id) true
         (aligned (Rects.get rects id)))
    [ 1; 2; 3; 4 ];
  let r3 = Rects.get rects 3 and r4 = Rects.get rects 4 in
  (* pad 3 logical = 4.5 device px: node 3 spans 4.5..34.5 → 5..35,
     node 4 starts exactly on that shared edge. *)
  Alcotest.(check (float 0.001)) "shared edge" 35. (r3.y +. r3.h);
  Alcotest.(check (float 0.001)) "shared edge" 35. r4.y

(* The 0.5 px phantom scroll: a fractional cap — the overshoot a
   fractional layout could leave — rounds onto the device-pixel grid
   instead of opening a sub-pixel scroll range the rasterizer cannot
   paint. *)
let test_snap_phantom_scroll () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Scroll);
        CreateNode (3, ListItem);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let ui = Ui.create () in
  ignore (Ui.handle ui s rects (Input.Move (10., 10.)));
  let epoch0 = Ui.scroll_epoch ui in
  (* 0.4 px of range snaps shut: no scrollable range, no move. *)
  Ui.set_scroll_cap ui 2 0.4;
  Alcotest.(check (float 0.001)) "cap snapped shut" 0.
    (Ui.scroll_cap ui 2);
  ignore (Ui.handle ui s rects (Input.Wheel (0., -1.)));
  Alcotest.(check (float 0.001)) "no phantom offset" 0.
    (Ui.scroll_offset ui 2);
  Alcotest.(check int) "no scroll epoch" epoch0 (Ui.scroll_epoch ui);
  (* A fractional cap rounds to the pixel the content edges snapped
     to. *)
  Ui.set_scroll_cap ui 2 80.6;
  Alcotest.(check (float 0.001)) "cap rounds" 81. (Ui.scroll_cap ui 2);
  Ui.set_scroll_cap_x ui 2 40.4;
  Alcotest.(check (float 0.001)) "x cap rounds" 40.
    (Ui.scroll_cap_x ui 2)

(* Hit-testing honours the snapped edges: a point inside the
   fractional band the rect snapped away from belongs to the
   neighbour the edge moved to — exactly where the rasterizer drew
   the boundary. *)
let test_snap_hit_boundary () =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, Button); CreateNode (4, Button);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
        SetProp (2, PaddingValue, IntValue 3);
        SetProp (3, HeightValue, IntValue 20);
        SetProp (4, HeightValue, IntValue 20) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:100 ~height:100 ~scale:1.5
    ~measure:Layout.default_measure;
  (* the snapped boundary sits at device y 35: the fractional band
     34.5..35 belongs to node 3 and the point just past it to node 4 —
     unsnapped, the boundary would have been 34.5 and node 3's hit
     strip would have ended where its painted edge does not. *)
  Alcotest.(check (option int)) "below edge" (Some 3)
    (hit s rects ~x:15. ~y:34.8);
  Alcotest.(check (option int)) "on edge" (Some 4)
    (hit s rects ~x:15. ~y:35.1)

(* The caret rect is snapped before it reaches the IME state machine —
   the candidate window anchors on the same device-pixel edges the
   field painted. *)
let test_snap_caret () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Caret (rect 10.4 5.6 2.4 12.2)));
  match (Ui.ime ui).Lui_ime.caret_rect with
  | Some r ->
    Alcotest.(check (float 0.001)) "x" 10. r.Lui_scene.x;
    Alcotest.(check (float 0.001)) "y" 6. r.Lui_scene.y;
    Alcotest.(check (float 0.001)) "w" 3. r.Lui_scene.w;
    Alcotest.(check (float 0.001)) "h" 12. r.Lui_scene.h
  | None -> Alcotest.fail "caret rect not recorded"

(* Paint and hit-test resolve a placement through the same
   [Lui_paint.resolve_rect]; its output is snapped, so a fractional
   layout rect can never produce a strip the raster did not paint but
   the hit-test still counts. *)
let test_snap_resolve_parity () =
  let s = demo_store () in
  let p =
    Lui_paint.placement_of_rect (rect 10.4 5.6 30.4 20.3)
  in
  let r =
    Lui_paint.resolve_rect ~scale:1. ~viewport:(rect 0. 0. 200. 200.) s 3
      "button" p (rect 0. 0. 200. 200.)
  in
  Alcotest.(check (float 0.001)) "x" 10. r.Lui_scene.x;
  Alcotest.(check (float 0.001)) "y" 6. r.Lui_scene.y;
  Alcotest.(check (float 0.001)) "w" 31. r.Lui_scene.w;
  Alcotest.(check (float 0.001)) "h" 20. r.Lui_scene.h

(* ---------- frame scheduler ---------- *)

(* Mutation → dirty → frame callback → present: the first frame always
   paints, presents clear the flag, a clean scheduler is Idle so the
   loop may sleep. *)
let test_frame_dirty_cycle () =
  let f = Frame.create () in
  Alcotest.(check bool) "starts dirty" true (Frame.dirty f);
  (match Frame.poll f ~now_ms:0. ~vsync:false with
   | Frame.Present -> ()
   | _ -> Alcotest.fail "first frame must present");
  Frame.presented f ~now_ms:0.;
  (match Frame.poll f ~now_ms:1. ~vsync:false with
   | Frame.Idle -> ()
   | _ -> Alcotest.fail "clean scheduler is idle");
  Frame.request_frame f;
  (match Frame.poll f ~now_ms:1. ~vsync:false with
   | Frame.Wait_ms _ -> ()
   | _ -> Alcotest.fail "dirty inside the period waits")

(* Non-vsync pacing: presents hold to the monitor's refresh period,
   vsync presents whenever dirty (the swap itself blocks). *)
let test_frame_pacing () =
  let f = Frame.create () in
  Frame.presented f ~now_ms:0.;
  Frame.request_frame f;
  (match Frame.poll f ~now_ms:5. ~vsync:false with
   | Frame.Wait_ms ms ->
     (* 60 Hz → 16.67 ms period; ~11.6 remains *)
     Alcotest.(check bool) "waits the rest" true
       (ms > 10. && ms < 13.)
   | _ -> Alcotest.fail "expected a wait");
  (match Frame.poll f ~now_ms:17. ~vsync:false with
   | Frame.Present -> ()
   | _ -> Alcotest.fail "past deadline presents");
  (match Frame.poll f ~now_ms:1. ~vsync:true with
   | Frame.Present -> ()
   | _ -> Alcotest.fail "vsync presents when dirty")

(* The monitor's refresh rate drives the period — 120 Hz and 144 Hz
   shorten it. *)
let test_frame_refresh_rate () =
  let f = Frame.create () in
  Frame.set_refresh_hz f 120.;
  Frame.presented f ~now_ms:0.;
  Frame.request_frame f;
  (match Frame.poll f ~now_ms:4. ~vsync:false with
   | Frame.Wait_ms ms ->
     Alcotest.(check bool) "120Hz period" true (ms > 3. && ms < 6.)
   | _ -> Alcotest.fail "expected a wait");
  (match Frame.poll f ~now_ms:9. ~vsync:false with
   | Frame.Present -> ()
   | _ -> Alcotest.fail "120Hz deadline");
  Frame.set_refresh_hz f 144.;
  Frame.presented f ~now_ms:10.;
  Frame.request_frame f;
  (match Frame.poll f ~now_ms:15. ~vsync:false with
   | Frame.Wait_ms ms ->
     Alcotest.(check bool) "144Hz period" true (ms > 1. && ms < 3.)
   | _ -> Alcotest.fail "expected a wait");
  (* invalid rates keep the previous value *)
  Frame.set_refresh_hz f 0.;
  Alcotest.(check (float 0.01)) "kept" 144. (Frame.refresh_hz f)

(* Visibility: hidden and minimized surfaces throttle presents to the
   background cadence; restoring marks the surface dirty so it
   presents fresh content right away. *)
let test_frame_visibility () =
  let f = Frame.create () in
  Frame.set_refresh_hz f 60.;
  Frame.presented f ~now_ms:0.;
  Frame.set_visibility f Frame.Hidden;
  Frame.request_frame f;
  (* inside the 250 ms background period the surface waits even
     though a refresh interval already passed *)
  (match Frame.poll f ~now_ms:20. ~vsync:false with
   | Frame.Wait_ms ms ->
     Alcotest.(check bool) "bg cadence" true (ms > 200.)
   | _ -> Alcotest.fail "expected a wait");
  (match Frame.poll f ~now_ms:260. ~vsync:false with
   | Frame.Present -> ()
   | _ -> Alcotest.fail "throttled present");
  Frame.presented f ~now_ms:260.;
  Frame.set_visibility f Frame.Minimized;
  Frame.request_frame f;
  (match Frame.poll f ~now_ms:300. ~vsync:false with
   | Frame.Wait_ms _ -> ()
   | _ -> Alcotest.fail "minimized throttles too");
  (* back on screen: dirty again, and past the refresh deadline the
     restored surface presents promptly *)
  Frame.set_visibility f Frame.Shown;
  Alcotest.(check bool) "restore is dirty" true (Frame.dirty f);
  (match Frame.poll f ~now_ms:300. ~vsync:false with
   | Frame.Present -> ()
   | _ -> Alcotest.fail "restore presents promptly")

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

let detail_click_app () =
  let store = Lui_store.create () in
  let received = ref [] and behind = ref 0 in
  let open Lui_elements in
  let view _ _ _ = column
    [ column ~style_class:"behind" ~on_press_detail:(fun _ -> incr behind) [];
      column ~style_class:"owner" ~on_press_detail:(fun ev ->
        match ev with
        | PressDetail (_, detail) -> received := detail :: !received
        | _ -> ())
        [ text ~style_class:"page-title" ~value:"page" [];
          button ~style_class:"sidebar-page-actions" ~text:"dots" [] ] ]
  in
  let app = Lui_app.create (demo_backend store) () (fun () () -> ()) view in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  let find kind cls = require_id (find_prop_id store kind "style-class" cls) in
  let owner = find "column" "owner" in
  let title = find "text" "page-title" and dots = find "button" "sidebar-page-actions" in
  let rects = Rects.create () in
  List.iter (fun id -> Hashtbl.replace rects id (rect 0. 0. 100. 40.))
    (Lui_store.preorder store);
  Hashtbl.replace rects title (rect 0. 0. 50. 40.);
  Hashtbl.replace rects dots (rect 50. 0. 50. 40.);
  let ui = Ui.create () in
  let input event =
    List.iter (function
      | Dispatch event -> ignore (Lui_app.dispatch_event app event)
      | _ -> ()) (Ui.handle ui store rects event);
    ignore (Lui_app.flush app)
  in
  app, store, ui, owner, received, behind, input

let test_detail_click_bubbles_to_owner () =
  let _, _, _, _, received, behind, input = detail_click_app () in
  let mods = { Input.mods_none with shift = true } in
  input (Input.Button_down (10., 10., Input.Left, 1, mods));
  input (Input.Button_up (10., 10., Input.Left, mods));
  Alcotest.(check int) "wrapper activated once" 1 (List.length !received);
  let detail = List.hd !received in
  Alcotest.(check string) "deepest hit class preserved" "page-title" detail.target_class;
  Alcotest.(check int) "shift preserved" 2 detail.modifiers;
  Alcotest.(check int) "unrelated underlay receives no click" 0 !behind

let test_detail_click_capture_and_dots () =
  let _, store, _, owner, received, _, input = detail_click_app () in
  input (Input.Button_down (10., 10., Input.Left, 1, Input.mods_none));
  input (Input.Button_up (70., 10., Input.Left, Input.mods_none));
  Alcotest.(check int) "same owner captures release over sibling" 1 (List.length !received);
  Alcotest.(check string) "dots hit class reaches owner" "sidebar-page-actions"
    (List.hd !received).target_class;
  input (Input.Button_down (10., 10., Input.Left, 1, Input.mods_none));
  input (Input.Button_up (150., 10., Input.Left, Input.mods_none));
  Alcotest.(check int) "release outside cancels click" 1 (List.length !received);
  Lui_store.apply_op store (SetProp (owner, Enabled, BoolValue false));
  input (Input.Button_down (10., 10., Input.Left, 1, Input.mods_none));
  input (Input.Button_up (10., 10., Input.Left, Input.mods_none));
  Alcotest.(check int) "disabled owner does not activate" 1 (List.length !received)

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
  (* This scene includes border insets and clipped select labels. *)
  Alcotest.(check string) "golden"
    "headless done: frames=6 checksum=1a3748927bb9c905" c1

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

(* ---------- shared-model multi-window ---------- *)

(* A Lui_multi_window application over two real hosts: each window
   keeps the full per-surface pipeline the SDL driver builds (own
   host/store, Ui, rect mirror) while the model, scheduler and
   reducer live once on the application — the wiring a driver adopts
   for a shared-document app, minus the OS handles. *)

module Mw = Lui_multi_window

type sm_doc = {
  sm_title : string;
  sm_count : int;
}

type sm_action =
  | Sm_title of string
  | Sm_bump

let sm_reducer m = function
  | Sm_title sm_title -> { m with sm_title }
  | Sm_bump -> { m with sm_count = m.sm_count + 1 }

let sm_view _surface _context model_source send =
  Lui_elements.column
    [
      Lui_elements.dyn
        ~equal:(fun (a : sm_doc) b -> a.sm_title = b.sm_title)
        (fun d ->
           Lui_elements.text_field ~text:d.sm_title
             ~on_input:
               (Lui_elements.on_input send (fun s -> Sm_title s))
             [])
        model_source;
      Lui_elements.dyn
        ~equal:(fun (a : sm_doc) b -> a.sm_count = b.sm_count)
        (fun d ->
           Lui_elements.text
             ~value:("edits=" ^ string_of_int d.sm_count)
             [])
        model_source;
      Lui_elements.scroll [ Lui_elements.text ~value:"scrollable" [] ];
      Lui_elements.button ~text:"Bump"
        ~on_press:(Lui_elements.press send Sm_bump) [];
    ]

(* One window's driver-side payload: real host (store + paint
   pipeline) as the surface backend, plus the Ui/rects pair the
   driver's registry would hold for it. *)
let sm_surface app =
  let host = host_stub () in
  let surface =
    Mw.open_window app
      (Lui_host.backend host (Lui_protocol.generic_profile ()))
  in
  (host, surface, Ui.create (), Rects.create ())

let sm_layout host rects =
  Layout.refresh (Lui_host.store host) rects ~width:200 ~height:200
    ~scale:1. ~measure:Layout.default_measure

(* The [Dispatch] arm of the driver's apply_actions: Ui actions route
   into that window's runtime surface — and nowhere else. *)
let sm_apply surface acts =
  List.iter
    (function
      | Dispatch ev -> ignore (Mw.dispatch surface ev)
      | _ -> ())
    acts

let sm_find store kind =
  List.find_opt
    (fun id -> Lui_store.kind store id = kind)
    (Lui_store.preorder store)

(* Editing through one window's Ui → dispatch → reducer → shared model
   re-renders every window's store; focus, caret and scroll stay
   inside the window that produced them. *)
let test_shared_model_pipeline () =
  let app =
    Mw.create ~shared:() { sm_title = "doc"; sm_count = 0 } sm_reducer
      sm_view
  in
  let h1, s1, ui1, r1 = sm_surface app in
  let h2, s2, ui2, r2 = sm_surface app in
  ignore (Mw.flush app);
  sm_layout h1 r1;
  sm_layout h2 r2;
  let store1 = Lui_host.store h1 and store2 = Lui_host.store h2 in
  let field1 =
    match sm_find store1 "text-field" with
    | Some id -> id
    | None -> Alcotest.fail "no text-field in window 1"
  and field2 =
    match sm_find store2 "text-field" with
    | Some id -> id
    | None -> Alcotest.fail "no text-field in window 2"
  in
  (* both windows mounted the same page from the shared model *)
  Alcotest.(check int) "same tree size"
    (Lui_store.node_count store1)
    (Lui_store.node_count store2);
  (* click the field in window 1: focus lands there only *)
  let fr = Rects.get r1 field1 in
  sm_apply s1
    (Ui.handle ui1 store1 r1
       (Input.Button_down
          ( fr.x +. (fr.w /. 2.),
            fr.y +. (fr.h /. 2.),
            Input.Left,
            1,
            Input.mods_none )));
  Alcotest.(check int) "w1 field focused" field1 (Ui.focused ui1);
  Alcotest.(check int) "w2 untouched" 0 (Ui.focused ui2);
  (* type into the focused field of window 1 *)
  sm_apply s1
    (Ui.handle ui1 store1 r1 (Input.Text_input "hi"));
  Alcotest.(check string) "w1 shadow" "dochi" (Ui.shadow ui1);
  Alcotest.(check string) "w2 shadow empty" "" (Ui.shadow ui2);
  Alcotest.(check int) "w1 caret at end" 5 (Ui.caret ui1);
  Alcotest.(check int) "w2 caret empty" 0 (Ui.caret ui2);
  ignore (Mw.flush app);
  Alcotest.(check string) "model updated" "dochi"
    (Mw.model app).sm_title;
  (* the edit reached BOTH windows' stores — one model, two views *)
  Alcotest.(check (option string)) "w1 store text" (Some "dochi")
    (Lui_store.string_prop store1 field1 "text");
  Alcotest.(check (option string)) "w2 store text" (Some "dochi")
    (Lui_store.string_prop store2 field2 "text");
  (* scroll one window's scroll container; the other's offset stays *)
  let scroll1 =
    match sm_find store1 "scroll" with
    | Some id -> id
    | None -> Alcotest.fail "no scroll container in window 1"
  in
  Ui.set_scroll_cap ui1 scroll1 300.;
  ignore (Ui.scroll_by ui1 store1 scroll1 50.);
  Alcotest.(check bool) "w1 scrolled" true
    (Ui.scroll_offset ui1 scroll1 = 50.);
  Alcotest.(check bool) "w2 scroll zero" true
    (Ui.scroll_offset ui2 scroll1 = 0.);
  (* a press routed through window 2 reduces the same shared model *)
  let button2 =
    match sm_find store2 "button" with
    | Some id -> id
    | None -> Alcotest.fail "no button in window 2"
  in
  sm_apply s2 [ Dispatch (Press button2) ];
  ignore (Mw.flush app);
  Alcotest.(check int) "shared count" 1 (Mw.model app).sm_count;
  Alcotest.(check bool) "w1 shows count" true
    (List.exists
       (fun id -> Lui_store.string_prop store1 id "text" = Some "edits=1")
       (Lui_store.preorder store1));
  Alcotest.(check bool) "w2 shows count" true
    (List.exists
       (fun id -> Lui_store.string_prop store2 id "text" = Some "edits=1")
       (Lui_store.preorder store2));
  ignore (Mw.dispose app)

(* Closing a window drops only that surface's store tree; the sibling
   keeps its own Ui/host and keeps tracking the shared model. *)
let test_shared_model_window_close () =
  let app =
    Mw.create ~shared:() { sm_title = "doc"; sm_count = 0 } sm_reducer
      sm_view
  in
  let h1, s1, _ui1, _r1 = sm_surface app in
  let h2, s2, _ui2, _r2 = sm_surface app in
  ignore (Mw.flush app);
  let store1 = Lui_host.store h1 and store2 = Lui_host.store h2 in
  Alcotest.(check bool) "close w1" true (Mw.close_window s1);
  Alcotest.(check int) "w1 store emptied" 0
    (Lui_store.node_count store1);
  Alcotest.(check bool) "w2 untouched" true
    (Lui_store.node_count store2 > 0);
  ignore (Mw.send app (Sm_title "still-live"));
  ignore (Mw.flush app);
  let field2 =
    match sm_find store2 "text-field" with
    | Some id -> id
    | None -> Alcotest.fail "no text-field in window 2"
  in
  Alcotest.(check (option string)) "w2 saw the edit"
    (Some "still-live")
    (Lui_store.string_prop store2 field2 "text");
  Alcotest.(check bool) "dispatch on closed" false
    (Mw.dispatch s1 (Press 1));
  ignore s2;
  ignore (Mw.dispose app)

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
     Alcotest.(check string) "win0 golden" "1a3748927bb9c905"
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

(* Virtual lists take the scroll-request triple over data-attrs and
   resolve the key through the extent model — the target row does not
   need a mounted rect, the driver's synthesized content_rect stands
   in. *)
let test_vlist_scroll_request () =
  let ops =
    [ CreateNode (1, Root); CreateNode (2, VirtualList);
      InsertChild (1, 2, 0);
      SetProp
        (2, DataAttrs,
          StringValue
            (Lui_protocol.data_attrs_encode
               [ ("data-scroll-target", "item-9");
                 ("data-scroll-token", "1");
                 ("data-track-visible-range", "true") ])) ]
    @ List.flatten
        (List.init 10 (fun i ->
             [ CreateNode (10 + i, ListItem);
               SetProp
                 (10 + i, KeyValue,
                   StringValue (Printf.sprintf "item-%d" i));
               InsertChild (2, 10 + i, i) ]))
  in
  let s = store_of ops in
  let ui = Ui.create () in
  (* The driver's content_rect hook: the container's box, and the
     model rect for rows whether mounted or not. *)
  Ui.set_content_rect ui
    (fun id ->
       if id = 2 then rect 0. 0. 100. 60.
       else rect 0. (float (id - 10) *. 20.) 100. 20.);
  Ui.set_vlist_hook ui
    (Some
       Ui.
         { vh_count = (fun id -> if id = 2 then Some 10 else None);
           vh_item =
             (fun _ ~index ->
                Some (rect 0. (float index *. 20.) 100. 20.));
           vh_index_of_key =
             (fun _ k ->
                if String.length k > 5 && String.sub k 0 5 = "item-"
                then int_of_string_opt (String.sub k 5 (String.length k - 5))
                else None);
           vh_view = (fun _ -> Some (0., 60.)) });
  Ui.set_scroll_cap ui 2 200.;
  let acts = Ui.store_changed ui s in
  (match press_actions acts with
   | [ VisibleRange (2, 0, 2); ScrollCompleted (2, 1, "succeeded") ]
   | [ ScrollCompleted (2, 1, "succeeded"); VisibleRange (2, 0, 2) ]
   | [ ScrollCompleted (2, 1, "succeeded") ] -> ()
   | a -> Alcotest.failf "expected ScrollCompleted, got %d actions" (List.length a));
  (* item-9 at y=180 in a 60px view: minimal reveal scrolls to 140 *)
  Alcotest.(check (float 0.001)) "scrolled" 140. (Ui.scroll_offset ui 2);
  (* a missing key reports missing-target *)
  Lui_store.apply_batch s
    { generation = 2;
      ops =
        [ SetProp
            (2, DataAttrs,
              StringValue
                (Lui_protocol.data_attrs_encode
                   [ ("data-scroll-target", "nope");
                     ("data-scroll-token", "2") ])) ] };
  (match press_actions (Ui.store_changed ui s) with
   | [ ScrollCompleted (2, 2, "missing-target") ]
   | [ VisibleRange _; ScrollCompleted (2, 2, "missing-target") ]
   | [ ScrollCompleted (2, 2, "missing-target"); VisibleRange _ ] ->
     ()
   | _ -> Alcotest.fail "expected missing-target")

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

(* ---------- shared host assembly (cross-platform parity) ---------- *)

(* A deterministic layout engine for [Assembly] tests: children stack
   vertically inside their parent, each taking its ["height"] prop
   (device px) and its parent's full width. Deliberately NOT the real
   [Lui_layout] — the wiring under test (caps, mirror, hooks) must be
   verified against controlled geometry, not a second opinion about
   flex math. *)
module Fake_layout = struct
  type t = (int, rect) Hashtbl.t

  let create () = Hashtbl.create 16

  let h_of store id =
    match Lui_store.prop store id "height" with
    | Some (IntValue n) -> float n
    | Some (FloatValue f) -> f
    | _ -> 0.

  let sync ?scale:_ ?measure:_ ?hidden:_ ?ctx_anchor:_ ?vport:_
      ~width ~height t store =
    Hashtbl.reset t;
    let rec place id ~x ~y ~w =
      Hashtbl.replace t id (rect x y w (h_of store id));
      ignore
        (List.fold_left
           (fun acc c ->
              place c ~x ~y:(y +. acc) ~w;
              acc +. h_of store c)
           0. (Lui_store.child_ids store id))
    in
    List.iter
      (fun id -> place id ~x:0. ~y:0. ~w:width)
      (Lui_store.root_ids store);
    ignore height

  let invalidate _ = ()

  let layout_hook t id =
    Lui_paint.placement_of_rect
      (Option.value ~default:Rects.zero (Hashtbl.find_opt t id))

  let rect t id = Hashtbl.find_opt t id

  (* No virtualization — the empty surface every non-virtualizing
     engine answers. *)
  let vlists _ = []
  let mounted_range _ _ = None
  let mounted_children _ _ = None
  let virtual_extent _ _ = None
  let virtual_item_rect _ _ ~index:_ = None
  let virtual_index_of_key _ _ _ _ = None
  let virtual_index_of_id _ _ _ _ = None
  let virtual_view _ _ = None
  let virtual_take_drift _ _ = 0.

  (* The stub re-places the whole tree every sync — every rect is
     potentially fresh. *)
  let take_rect_changes t =
    let m = Hashtbl.create (Hashtbl.length t) in
    Hashtbl.iter (fun id _ -> Hashtbl.replace m id ()) t;
    m
end

let assembly_text : Assembly.text =
  { measure = (fun _ s -> (float (String.length s) *. 8., 16.));
    text_ops = (fun _ _ _ _ -> []);
    hit_text =
      (fun _ s ~lx ~ly:_ ~lw:_ ~lh:_ ->
         Float.min (float (String.length s)) (lx /. 8.)
         |> int_of_float |> max 0);
    caret_ops =
      (fun _ s ~lw:_ ~lh ->
         let n = String.length s in
         Ui.
           { c_before = (fun i -> max 0 (i - 1));
             c_after = (fun i -> min n (i + 1));
             c_up = (fun _ -> 0);
             c_down = (fun _ -> n);
             c_rect = (fun i -> (float i *. 8., 0., lh)) }) }

let assembly_renderer =
  { Lui_host.name = "noop";
    render =
      (fun (s : Lui_scene.t) ->
         Bytes.create (s.Lui_scene.width * s.Lui_scene.height * 4)) }

let assembly_of store =
  let asm =
    Assembly.create ~layout:(module Fake_layout)
      ~scale_cell:(ref 1.) ~text:assembly_text
      ~renderer:assembly_renderer ~width:200 ~height:200 ()
  in
  Lui_store.apply_batch (Assembly.store asm) { generation = 1; ops = store };
  ignore (Assembly.repaint asm);
  asm

(* root 1 → scroll 2 (100px viewport) → items 3 (120px) + 4 (80px):
   200px of content in a 100px viewport — wheel reveals the second
   item as the first scrolls out under the clip. *)
let scroll_store_ops =
  [ CreateNode (1, Root); CreateNode (2, Scroll);
    CreateNode (3, ListItem); CreateNode (4, ListItem);
    InsertChild (1, 2, 0); InsertChild (2, 3, 0);
    InsertChild (2, 4, 1);
    SetProp (2, HeightValue, IntValue 100);
    SetProp (3, HeightValue, IntValue 120);
    SetProp (4, HeightValue, IntValue 80) ]

let test_assembly_scroll_caps () =
  (* The wiring the Linux/Windows drivers lacked: populate must fill
     each scrollable container's cap from the engine's content extent,
     or wheel input finds no target. *)
  let asm = assembly_of scroll_store_ops in
  let ui = Assembly.ui asm in
  Alcotest.(check (float 0.001)) "cap from content" 100.
    (Ui.scroll_cap ui 2);
  (* pointer inside the container, wheel down: the deepest scrollable
     ancestor on the hit path takes the delta *)
  ignore (Assembly.handle asm (Input.Move (10., 10.)));
  ignore (Assembly.handle asm (Input.Wheel (0., -1.)));
  Alcotest.(check (float 0.001)) "wheel scrolled" 44.
    (Ui.scroll_offset ui 2);
  (* the mirror reflects the shift after the next paint: item 3 moves
     44px up, item 4 slides into the freed span below. Mirror rects
     keep their full resolved box — the container clip is applied by
     the shared hit walk, not baked into the mirror. *)
  ignore (Assembly.repaint asm);
  let r3 = Rects.get (Assembly.rects asm) 3
  and r4 = Rects.get (Assembly.rects asm) 4 in
  Alcotest.(check (float 0.001)) "item3 shifted" (-44.) r3.y;
  Alcotest.(check (float 0.001)) "item3 full h" 120. r3.h;
  Alcotest.(check (float 0.001)) "item4 in view" 76. r4.y;
  Alcotest.(check (float 0.001)) "item4 full h" 80. r4.h;
  (* the clip still holds for hits: item 4's box extends to 156 but
     the part below the 100px viewport is clipped away *)
  Alcotest.(check bool) "clipped part misses item4" true
    (hit (Assembly.store asm) (Assembly.rects asm) ~x:10. ~y:130.
     <> Some 4);
  (* hit parity follows paint: the point that hit item 3 before the
     scroll now hits item 4 where it slid in *)
  Alcotest.(check (option int)) "scrolled hit" (Some 4)
    (hit (Assembly.store asm) (Assembly.rects asm) ~x:10. ~y:90.)

let test_assembly_menu_scroll () =
  List.iter
    (fun (kind, props) ->
      let asm =
        assembly_of
          [
            CreateNode (1, Root);
            CreateNode (2, kind);
            CreateNode (3, MenuItem);
            CreateNode (4, MenuItem);
            InsertChild (1, 2, 0);
            InsertChild (2, 3, 0);
            InsertChild (2, 4, 1);
            SetProp (2, HeightValue, IntValue 100);
            SetProp (3, HeightValue, IntValue 120);
            SetProp (4, HeightValue, IntValue 80);
          ]
      in
      Lui_store.apply_batch (Assembly.store asm) { generation = 2; ops = props };
      ignore (Assembly.store_changed asm);
      ignore (Assembly.repaint asm);
      let ui = Assembly.ui asm and store = Assembly.store asm in
      Alcotest.(check (float 0.001))
        "menus scroll without an overflow override" 100. (Ui.scroll_cap ui 2);
      Alcotest.(check bool)
        "offscreen menu option cannot be hit" true
        (hit store (Assembly.rects asm) ~x:10. ~y:150. <> Some 4);
      ignore (Assembly.handle asm (Input.Move (10., 10.)));
      ignore (Assembly.handle asm (Input.Wheel (0., -100.)));
      ignore (Assembly.repaint asm);
      Alcotest.(check (float 0.001))
        "wheel reaches the final option" 100. (Ui.scroll_offset ui 2);
      let final = Rects.get (Assembly.rects asm) 4 in
      Alcotest.(check (float 0.001))
        "final option is fully visible" 100. (final.y +. final.h);
      Alcotest.(check (option int))
        "final option receives hits" (Some 4)
        (hit store (Assembly.rects asm) ~x:10. ~y:60.);
      ignore
        (Ui.handle ui store (Assembly.rects asm)
           (Input.Button_down (10., 60., Input.Left, 1, Input.mods_none)));
      let events =
        press_actions
          (Ui.handle ui store (Assembly.rects asm)
             (Input.Button_up (10., 60., Input.Left, Input.mods_none)))
      in
      Alcotest.(check bool)
        "final option remains clickable" true
        (List.mem (Press 4) events))
    [
      (DropdownMenu, []);
      (ContextMenu, []);
      (Popover, [ SetProp (2, RoleValue, StringValue "menu") ]);
    ]

let test_assembly_menu_keyboard () =
  List.iter
    (fun (kind, props) ->
      let asm =
        assembly_of
          [
            CreateNode (1, Root);
            CreateNode (2, kind);
            CreateNode (3, TextField);
            InsertChild (1, 3, 0);
            InsertChild (1, 2, 1);
            SetProp (3, HeightValue, IntValue 30);
            SetProp (3, TextValue, StringValue "background");
            SetProp (2, HeightValue, IntValue 100);
          ]
      in
      let ui = Assembly.ui asm and store = Assembly.store asm in
      Lui_store.apply_batch store { generation = 2; ops = props };
      for index = 0 to 19 do
        let id = index + 4 in
        Lui_store.apply_batch store
          {
            generation = index + 3;
            ops =
              [
                CreateNode (id, MenuItem);
                InsertChild (2, id, index);
                SetProp (id, HeightValue, IntValue 32);
                SetProp
                  ( id,
                    TextValue,
                    StringValue (if id = 23 then "Last item" else "Option") );
                SetProp (id, Enabled, BoolValue (id <> 5));
              ];
          }
      done;
      ignore (Assembly.store_changed asm);
      ignore (Assembly.repaint asm);
      Ui.set_focused ui store 3;
      let input key =
        Assembly.handle asm (Input.Key_down (key, Input.mods_none, false))
      in
      List.iter
        (fun (key, expected) ->
          ignore (input key);
          Alcotest.(check int)
            "menu keys navigate enabled options before the background field"
            expected (Ui.hl_item ui))
        [
          (Input.Home, 4);
          (Input.Arrow_down, 6);
          (Input.Arrow_up, 4);
          (Input.Arrow_up, 23);
          (Input.Arrow_down, 4);
          (Input.End, 23);
        ];
      Alcotest.(check string)
        "menu navigation preserves the background field" "background"
        (Ui.shadow ui);
      Alcotest.(check bool)
        "keyboard highlight paints as hovered" true
        (Ui.state_of ui store 23).Lui_paint.hovered;
      ignore (Assembly.repaint asm);
      let panel = Rects.get (Assembly.rects asm) 2
      and last = Rects.get (Assembly.rects asm) 23 in
      Alcotest.(check bool)
        "End reveals the entire final option" true
        (Ui.scroll_offset ui 2 > 0.
        && last.y >= panel.y
        && last.y +. last.h <= panel.y +. panel.h);
      List.iter
        (fun key ->
          let events =
            press_actions
              (Ui.handle ui store (Assembly.rects asm)
                 (Input.Key_down (key, Input.mods_none, false)))
          in
          Alcotest.(check int)
            "keyboard activation dispatches Press exactly once" 1
            (List.length (List.filter (( = ) (Press 23)) events));
          Alcotest.(check bool)
            "detail-only menu actions receive keyboard activation" true
            (List.exists
               (function
                 | PressDetail (23, d) ->
                     d.x >= last.x
                     && d.x <= last.x +. last.w
                     && d.y >= last.y
                     && d.y <= last.y +. last.h
                 | _ -> false)
               events))
        [ Input.Return; Input.Space ];
      let previous = Rects.get (Assembly.rects asm) 22 in
      ignore
        (Assembly.handle asm
           (Input.Move
              ( previous.x +. (previous.w /. 2.),
                previous.y +. (previous.h /. 2.) )));
      Alcotest.(check int)
        "pointer and keyboard share one menu highlight" 22 (Ui.hl_item ui);
      Alcotest.(check bool)
        "moving the pointer clears the previous keyboard highlight" false
        (Ui.state_of ui store 23).Lui_paint.hovered;
      ignore (input Input.Home);
      ignore (input Input.End);
      Alcotest.(check bool)
        "keyboard navigation clears the previous pointer highlight" false
        (Ui.state_of ui store 22).Lui_paint.hovered;
      ignore (input Input.Home);
      ignore (Assembly.handle asm (Input.Text_input "La"));
      Alcotest.(check int)
        "typeahead finds a matching menu option" 23 (Ui.hl_item ui);
      Alcotest.(check string)
        "menu typeahead cannot edit the background field" "background"
        (Ui.shadow ui);
      Lui_store.apply_batch store { generation = 30; ops = [ DropNode 2 ] };
      ignore (Assembly.store_changed asm);
      ignore (Assembly.handle asm (Input.Text_input "x"));
      Alcotest.(check string)
        "typing resumes after the menu is disposed" "backgroundx" (Ui.shadow ui))
    [
      (DropdownMenu, []);
      (ContextMenu, []);
      (Popover, [ SetProp (2, RoleValue, StringValue "menu") ]);
    ]

let test_menu_open_selection () =
  List.iter
    (fun (selected, navigate_early) ->
      let asm =
        assembly_of
          [
            CreateNode (1, Root);
            CreateNode (2, TextField);
            SetProp (2, TextValue, StringValue "draft");
            InsertChild (1, 2, 0);
          ]
      in
      let ui = Assembly.ui asm and store = Assembly.store asm in
      Ui.set_focused ui store 2;
      let rows =
        List.init 20 (fun index ->
            let id = index + 4 in
            [
              CreateNode (id, MenuItem);
              InsertChild (3, id, index);
              SetProp
                (id, TextValue, StringValue (Printf.sprintf "Option %d" index));
              SetProp (id, HeightValue, IntValue 32);
              SetProp (id, Selected, BoolValue (id = selected));
              SetProp (id, Enabled, BoolValue (id <> 4));
              SetProp (id, Visible, BoolValue (id <> 5));
            ])
      in
      Lui_store.apply_batch store
        {
          generation = 2;
          ops =
            [
              CreateNode (3, DropdownMenu);
              InsertChild (1, 3, 1);
              SetProp (3, HeightValue, IntValue 100);
            ]
            @ List.concat rows;
        };
      ignore (Assembly.store_changed asm);
      let expected = if selected = 23 then 23 else 6 in
      Alcotest.(check int)
        "open highlights the enabled selected row or first enabled row" expected
        (Ui.hl_item ui);
      Alcotest.(check bool)
        "initial selection uses the menu highlight style" true
        (Ui.state_of ui store expected).Lui_paint.hovered;
      Alcotest.(check int)
        "opening a menu preserves the trigger's input focus" 2 (Ui.focused ui);
      let events = press_actions (Assembly.handle asm (key Input.Return)) in
      Alcotest.(check bool)
        "Enter activates the initial selection" true
        (List.mem (Press expected) events);
      if navigate_early then ignore (Assembly.handle asm (key Input.Home));
      ignore (Assembly.repaint asm);
      ignore (Assembly.store_changed asm);
      ignore (Assembly.repaint asm);
      if expected = 23 && not navigate_early then begin
        let panel = Rects.get (Assembly.rects asm) 3 in
        let row = Rects.get (Assembly.rects asm) expected in
        Alcotest.(check bool)
          "opening reveals the entire selected row after layout" true
          (Ui.scroll_offset ui 3 > 0.
           && row.y >= panel.y && row.y +. row.h <= panel.y +. panel.h)
      end;
      if navigate_early then
        Alcotest.(check (float 0.01))
          "navigation cancels the deferred initial reveal" 0.
          (Ui.scroll_offset ui 3);
      ignore (Assembly.handle asm (key Input.Arrow_down));
      let next = if expected = 23 && not navigate_early then 6 else 7 in
      Alcotest.(check int)
        "Down continues from the initial selection" next (Ui.hl_item ui);
      Lui_store.apply_batch store
        {
          generation = 3;
          ops = [ SetProp (3, BackgroundValue, StringValue "#fff") ];
        };
      ignore (Assembly.store_changed asm);
      Alcotest.(check int)
        "unrelated patches preserve keyboard navigation" next (Ui.hl_item ui);
      Lui_store.apply_batch store { generation = 4; ops = [ DropNode 3 ] };
      ignore (Assembly.store_changed asm);
      ignore (Assembly.handle asm (Input.Text_input "x"));
      Alcotest.(check string)
        "closing restores editing without losing its draft" "draftx"
        (Ui.shadow ui))
    [ (23, false); (23, true); (4, false); (5, false); (0, false) ]

let test_menu_keyboard_scope () =
  let store =
    store_of
      [
        CreateNode (1, Root);
        CreateNode (2, TextField);
        InsertChild (1, 2, 0);
        SetProp (2, TextValue, StringValue "background");
        CreateNode (3, DropdownMenu);
        InsertChild (1, 3, 1);
        CreateNode (4, MenuItem);
        InsertChild (3, 4, 0);
        CreateNode (5, Popover);
        InsertChild (4, 5, 0);
        SetProp (5, RoleValue, StringValue "menu");
        CreateNode (6, MenuItem);
        InsertChild (5, 6, 0);
        CreateNode (7, MenuItem);
        InsertChild (5, 7, 1);
        SetProp (6, Enabled, BoolValue false);
      ]
  in
  let ui = Ui.create () and rects = Rects.create () in
  ignore (Ui.store_changed ui store);
  Ui.set_focused ui store 2;
  ignore (Ui.handle ui store rects (key Input.End));
  Alcotest.(check int) "only the top nested menu navigates" 7 (Ui.hl_item ui);
  let events = press_actions (Ui.handle ui store rects (key Input.Return)) in
  Alcotest.(check bool)
    "nested activation cannot reach the parent action" true
    (List.mem (Press 7) events && not (List.mem (Press 4) events));
  Lui_store.apply_batch store
    { generation = 2; ops = [ SetProp (7, Enabled, BoolValue false) ] };
  let events = press_actions (Ui.handle ui store rects (key Input.Return)) in
  Alcotest.(check bool)
    "disabling the highlighted option prevents stale activation" true
    (not
       (List.exists
          (function Press _ | PressDetail _ -> true | _ -> false)
          events));
  let consumed = ref 0 in
  ignore
    (Ui.handle
       ~on_component_input:(fun () -> incr consumed)
       ui store rects
       (Input.Text_editing ("ni", 2, 0)));
  Alcotest.(check string)
    "menu composition cannot attach to the background editor" "" (Ui.marked ui);
  Alcotest.(check int)
    "menu composition suppresses duplicate document delivery" 1 !consumed;
  ignore (Ui.handle ui store rects (Input.Text_input "x"));
  Alcotest.(check string)
    "a disabled menu still owns text input" "background" (Ui.shadow ui);
  Lui_store.apply_batch store { generation = 3; ops = [ DropNode 5 ] };
  ignore (Ui.handle ui store rects (key Input.Home));
  Alcotest.(check int)
    "dismissing the submenu restores parent navigation" 4 (Ui.hl_item ui);
  Lui_store.apply_batch store
    {
      generation = 4;
      ops = [ CreateNode (8, TextField); InsertChild (3, 8, 1) ];
    };
  ignore (Ui.store_changed ui store);
  Ui.set_focused ui store 8;
  ignore (Ui.handle ui store rects (Input.Text_editing ("ni", 2, 0)));
  Alcotest.(check string)
    "an editor inside a menu retains composition" "ni" (Ui.marked ui);
  ignore (Ui.handle ui store rects (Input.Text_input "ni"));
  Alcotest.(check string)
    "an editor inside a menu retains text input" "ni" (Ui.shadow ui)

let test_menu_activation_text_commit () =
  List.iter
    (fun commit ->
      let store =
        store_of
          [
            CreateNode (1, Root);
            CreateNode (2, TextField);
            InsertChild (1, 2, 0);
            SetProp (2, TextValue, StringValue "background");
            CreateNode (3, DropdownMenu);
            InsertChild (1, 3, 1);
            CreateNode (4, MenuItem);
            InsertChild (3, 4, 0);
          ]
      in
      let ui = Ui.create () and rects = Rects.create () in
      ignore (Ui.store_changed ui store);
      Ui.set_focused ui store 2;
      ignore (Ui.handle ui store rects (key Input.Home));
      let activation = Ui.handle ui store rects (key Input.Space) in
      Alcotest.(check bool)
        "Space activates the menu item" true
        (List.mem (Press 4) (press_actions activation));
      Lui_store.apply_batch store { generation = 2; ops = [ DropNode 3 ] };
      ignore (Ui.store_changed ui store);
      if commit then begin
        let consumed = ref false in
        ignore
          (Ui.handle
             ~on_component_input:(fun () -> consumed := true)
             ui store rects (Input.Text_input " "));
        Alcotest.(check string)
          "activation cannot insert behind the closed menu" "background"
          (Ui.shadow ui);
        Alcotest.(check bool)
          "activation consumes its trailing text commit" true !consumed
      end;
      ignore (Ui.handle ui store rects (key Input.Space));
      ignore (Ui.handle ui store rects (Input.Text_input " "));
      Alcotest.(check string)
        "the next ordinary Space still edits the field" "background "
        (Ui.shadow ui))
    [ true; false ]

let test_assembly_scroll_shows_in_paint () =
  (* scroll_of feeds the scrollbar: a container with range reports
     metrics; one without reports none. *)
  let asm = assembly_of scroll_store_ops in
  let ui = Assembly.ui asm in
  ignore (Assembly.handle asm (Input.Move (10., 10.)));
  ignore (Assembly.handle asm (Input.Wheel (0., -1.)));
  ignore (Assembly.repaint asm);
  (* A scroll container with range paints a scrollbar thumb — the
     shared [scroll_of] hook feeds sm_offset/sm_extent. The same tree
     as a plain column paints strictly fewer ops (no clip, no thumb). *)
  let scrolled = Ui.scroll_offset ui 2 in
  Alcotest.(check bool) "offset moved" true (scrolled > 0.);
  let scroll_ops =
    List.length (Lui_host.scene (Assembly.host asm)).ops
  in
  let plain =
    assembly_of
      [ CreateNode (1, Root); CreateNode (2, Column);
        CreateNode (3, ListItem);
        InsertChild (1, 2, 0); InsertChild (2, 3, 0);
        SetProp (2, HeightValue, IntValue 100);
        SetProp (3, HeightValue, IntValue 400) ]
  in
  let plain_ops =
    List.length (Lui_host.scene (Assembly.host plain)).ops
  in
  Alcotest.(check bool) "scrollbar ops" true (scroll_ops > plain_ops)

let test_assembly_inset_scroll_caps () =
  let module Inset_layout = struct
    include Fake_layout
    let sync ?scale:_ ?measure:_ ?hidden:_ ?ctx_anchor:_ ?vport:_
        ~width:_ ~height:_ t _store =
      Hashtbl.reset t;
      List.iter (fun (id,r) -> Hashtbl.add t id r)
        [1,Lui_scene.rect 0. 0. 200. 200.;2,Lui_scene.rect 20. 30. 100. 100.;
         3,Lui_scene.rect 28. 38. 180. 200.]
  end in
  let asm=Assembly.create ~layout:(module Inset_layout)
    ~scale_cell:(ref 1.) ~text:assembly_text ~renderer:assembly_renderer
    ~width:200 ~height:200 () in
  Lui_store.apply_batch (Assembly.store asm) {generation=1;ops=
    [CreateNode (1,Root);CreateNode (2,Scroll);CreateNode (3,Box);
     InsertChild (1,2,0);InsertChild (2,3,0)]};
  ignore (Assembly.repaint asm);
  let ui=Assembly.ui asm in
  Alcotest.(check (float 0.001)) "vertical inset remains reachable" 108.
    (Ui.scroll_cap ui 2);
  Alcotest.(check (float 0.001)) "horizontal inset remains reachable" 88.
    (Ui.scroll_cap_x ui 2);
  ignore (Ui.scroll_to ui (Assembly.store asm) 2 1000.);
  ignore (Ui.scroll_to ~axis:X ui (Assembly.store asm) 2 1000.);
  ignore (Assembly.repaint asm);
  let last=Rects.get (Assembly.rects asm) 3 in
  Alcotest.(check (float 0.001)) "last content bottom is visible" 130. (last.y+.last.h);
  Alcotest.(check (float 0.001)) "last content right is visible" 120. (last.x+.last.w)

let test_assembly_autofocus () =
  let asm =
    assembly_of
      [ CreateNode (1, Root); CreateNode (2, TextField);
        InsertChild (1, 2, 0);
        SetProp (2, TextValue, StringValue "");
        SetProp (2, Autofocus, BoolValue true) ]
  in
  Alcotest.(check (option int)) "autofocus id" (Some 2)
    (Assembly.first_autofocus asm)

(* ---------- Win32 key parity ---------- *)

let test_win32_key_parity () =
  (* Every named VK must land on the same [Input.key] the SDL table
     produces — this is the table that used to feed raw VKs into
     [Other], leaving every letter shortcut unreachable. *)
  let named =
    [ (0x0D, Input.Return); (0x1B, Input.Escape); (0x08, Input.Backspace);
      (0x2E, Input.Delete); (0x09, Input.Tab); (0x20, Input.Space);
      (0x24, Input.Home); (0x21, Input.Page_up); (0x22, Input.Page_down);
      (0x23, Input.End); (0x25, Input.Arrow_left); (0x27, Input.Arrow_right);
      (0x26, Input.Arrow_up); (0x28, Input.Arrow_down) ]
  in
  List.iter
    (fun (vk, k) ->
       Alcotest.(check bool) (Printf.sprintf "VK %02X" vk) true
         (Input.key_of_win32_vk vk = k))
    named;
  (* letters and digits map to the SDL scancode numbering *)
  for vk = 0x41 to 0x5A do
    Alcotest.(check bool) (Printf.sprintf "VK %02X" vk) true
      (Input.key_of_win32_vk vk
       = Input.key_of_sdl_scancode (vk - 0x41 + 4))
  done;
  for vk = 0x31 to 0x39 do
    Alcotest.(check bool) (Printf.sprintf "VK %02X" vk) true
      (Input.key_of_win32_vk vk
       = Input.key_of_sdl_scancode (vk - 0x31 + 30))
  done;
  Alcotest.(check bool) "0" true
    (Input.key_of_win32_vk 0x30 = Input.key_of_sdl_scancode 39)

let test_win32_accelerators () =
  (* The functional half of the parity: a VK the Win32 adapter decodes
     must drive the same accelerator table Ctrl+<scancode> does on the
     SDL hosts — here Ctrl+A select-all, Ctrl+C copy, Ctrl+V paste. *)
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  Ui.set_focused ui s 4;
  Lui_store.apply_op s (SetProp (4, TextValue, StringValue "hello"));
  ignore (Ui.store_changed ui s);
  let ctrl = { Input.mods_none with ctrl = true } in
  let key vk = Input.Key_down (Input.key_of_win32_vk vk, ctrl, false) in
  (* Ctrl+A: select all — caret to end, anchor to 0 *)
  ignore (Ui.handle ui s rects (key 0x41));
  Alcotest.(check int) "select-all caret" 5 (Ui.caret ui);
  Alcotest.(check int) "select-all anchor" 0 (Ui.sel_anchor ui);
  (* Ctrl+C: copy the selection *)
  (match Ui.handle ui s rects (key 0x43) with
   | [ Clipboard_write "hello" ] -> ()
   | _ -> Alcotest.fail "expected Clipboard_write hello");
  (* Ctrl+V: paste accelerator — the action a raw VK (0x56) never
     produced because it failed the [Other 25] match *)
  (match Ui.handle ui s rects (key 0x56) with
   | [ Paste_request ] -> ()
   | _ -> Alcotest.fail "expected Paste_request");
  (* the pasted text splices in as an edit event, same as SDL's
     scancode-25 V *)
  (match
     press_actions (Ui.handle ui s rects (Input.Paste "world"))
   with
   | [ TextChanged (4, "world") ] -> ()
   | _ -> Alcotest.fail "expected TextChanged world");
  (* the model echoes the edit, then Ctrl+X cuts the whole value *)
  Lui_store.apply_op s (SetProp (4, TextValue, StringValue "world"));
  ignore (Ui.store_changed ui s);
  ignore (Ui.handle ui s rects (key 0x41));
  (match Ui.handle ui s rects (key 0x58) with
   | Clipboard_write "world" :: _ -> ()
   | _ -> Alcotest.fail "expected cut of selection")

let test_idle_sync_allocations () =
  let store, _ = ui_store_fresh () in
  let ui = Ui.create () in
  ignore (Ui.store_changed ui store);
  let before = Gc.allocated_bytes () in
  for _ = 1 to 10000 do ignore (Ui.store_changed ui store) done;
  let bytes = Gc.allocated_bytes () -. before in
  Alcotest.(check bool) "Idle interaction sync exceeds 16 bytes per poll" true (bytes < 160000.)

let test_idle_scrollbar_allocations () =
  let ui = Ui.create () in
  let before = Gc.allocated_bytes () in
  for _ = 1 to 10000 do Ui.tick_scrollbars ui ~now_ms:0. done;
  let bytes = Gc.allocated_bytes () -. before in
  Alcotest.(check bool) "Hidden scrollbar polling exceeds 16 bytes per poll" true (bytes < 160000.)

let split_fixture () =
  let store = store_of [CreateNode (1,Split);CreateNode (2,Column);CreateNode (3,Column);
    SetProp (1,ProgressValue,FloatValue 0.25);SetProp (1,Gap,IntValue 3);
    InsertChild (1,2,0);InsertChild (1,3,1)] in
  let rects = Rects.create () in
  List.iter (fun (id,rect) -> Hashtbl.add rects id rect)
    [1,rect 50. 40. 1000. 600.;2,rect 50. 40. 250. 600.;3,rect 306. 40. 744. 600.];
  let ui=Ui.create () in
  Ui.set_scale ui 2.;
  store,rects,ui

let split_fraction store id = Option.get (Lui_store.float_prop store id "value")
let resized id acts = List.find_map (function
    | Dispatch (ValueChanged (node,value)) when node=id -> Some value
    | _ -> None) acts

let test_split_pointer_resize () =
  let store,rects,ui=split_fixture () in
  let input event=Ui.handle ui store rects event in
  ignore (input (Input.Move (151.5,100.)));
  Alcotest.(check (float 0.00001)) "hover does not resize" 0.25 (split_fraction store 1);
  ignore (input (Input.Button_down (151.5,100.,Input.Left,1,Input.mods_none)));
  Alcotest.(check (float 0.00001)) "grabbing the divider does not jump" 0.25 (split_fraction store 1);
  let acts=input (Input.Move (201.5,100.)) in
  Alcotest.(check (option (float 0.00001))) "drag dispatches the new fraction" (Some 0.35) (resized 1 acts);
  Alcotest.(check (float 0.00001)) "drag mirrors geometry before application feedback" 0.35 (split_fraction store 1);
  ignore (input (Input.Move (-500.,-100.)));
  Alcotest.(check (float 0.00001)) "captured drag clamps at the first endpoint" 0. (split_fraction store 1);
  ignore (input (Input.Move (2000.,1000.)));
  Alcotest.(check (float 0.00001)) "captured drag clamps at the second endpoint" 1. (split_fraction store 1);
  let acts=input (Input.Button_up (226.5,100.,Input.Left,Input.mods_none)) in
  Alcotest.(check (option (float 0.00001))) "release uses its final pointer coordinate" (Some 0.4) (resized 1 acts);
  ignore (input (Input.Move (500.,100.)));
  Alcotest.(check (float 0.00001)) "release ends resize capture" 0.4 (split_fraction store 1)

let test_split_pointer_minimums () =
  List.iter
    (fun scale ->
      let store, rects, ui = split_fixture () in
      Ui.set_scale ui scale;
      let input event = Ui.handle ui store rects event in
      let x = 303. /. scale and y = 200. /. scale in
      List.iter (Lui_store.apply_op store)
        [
          SetProp (2, MinWidth, IntValue 100);
          SetProp (3, MinWidth, IntValue 150);
        ];
      ignore (input (Input.Button_down (x, y, Input.Left, 1, Input.mods_none)));
      ignore (input (Input.Move (-2000., y)));
      let available = 994. /. scale in
      Alcotest.(check (float 0.00001))
        "drag preserves the first pane minimum" (100. /. available)
        (split_fraction store 1);
      Alcotest.(check (option (float 0.00001)))
        "dragging beyond the same minimum emits no duplicate resize" None
        (resized 1 (input (Input.Move (-2100., y))));
      let acts =
        input (Input.Button_up (2000., y, Input.Left, Input.mods_none))
      in
      Alcotest.(check (option (float 0.00001)))
        "release preserves the second pane minimum"
        (Some (1. -. (150. /. available)))
        (resized 1 acts);
      List.iter (Lui_store.apply_op store)
        [
          SetProp (2, MinWidth, IntValue 600);
          SetProp (3, MinWidth, IntValue 900);
        ];
      ignore (input (Input.Button_down (x, y, Input.Left, 1, Input.mods_none)));
      ignore (input (Input.Move (-2000., y)));
      Alcotest.(check (float 0.00001))
        "infeasible minimums share the track proportionally" 0.4
        (split_fraction store 1);
      ignore (input (Input.Button_up (2000., y, Input.Left, Input.mods_none)));
      Alcotest.(check (float 0.00001))
        "infeasible minimums remain stable on release" 0.4
        (split_fraction store 1))
    [ 1.; 2. ]

let test_split_pointer_admission () =
  let store,rects,ui=split_fixture () in
  let input event=Ui.handle ui store rects event in
  let down button x=ignore (input (Input.Button_down (x,100.,button,1,Input.mods_none))) in
  let up button x=ignore (input (Input.Button_up (x,100.,button,Input.mods_none))) in
  List.iter (fun (button,x) -> down button x;ignore (input (Input.Move (201.5,100.)));up button 201.5)
    [Input.Right,151.5;Input.Middle,151.5;Input.Left,100.];
  Alcotest.(check (float 0.00001)) "other buttons and pane content do not resize" 0.25 (split_fraction store 1);
  Lui_store.apply_op store (SetProp (1,Enabled,BoolValue false));
  down Input.Left 151.5;ignore (input (Input.Move (201.5,100.)));up Input.Left 201.5;
  Alcotest.(check (float 0.00001)) "disabled split cannot capture a drag" 0.25 (split_fraction store 1);
  Lui_store.apply_op store (SetProp (1,Enabled,BoolValue true));
  Lui_store.apply_op store (CreateNode (9,Dialog));
  Hashtbl.add rects 9 (rect 250. 40. 200. 600.);
  down Input.Left 151.5;ignore (input (Input.Move (201.5,100.)));up Input.Left 201.5;
  Alcotest.(check (float 0.00001)) "modal overlay masks a divider behind it" 0.25 (split_fraction store 1);
  Lui_store.apply_op store (DropNode 9);
  down Input.Left 151.5;
  Lui_store.apply_op store (DropNode 1);
  Alcotest.(check (option (float 0.00001))) "removed split emits no captured resize" None
    (resized 1 (input (Input.Move (201.5,100.))));
  up Input.Left 201.5

let test_nested_split_pointer_resize () =
  let store,rects,ui=split_fixture () in
  List.iter (Lui_store.apply_op store)
    [DropNode 3;CreateNode (3,Split);SetProp (3,ProgressValue,FloatValue 0.5);
     CreateNode (5,Column);CreateNode (6,Column);InsertChild (1,3,1);
     InsertChild (3,5,0);InsertChild (3,6,1)];
  Hashtbl.replace rects 3 (rect 306. 40. 744. 600.);
  Hashtbl.add rects 5 (rect 306. 40. 400. 600.);
  Hashtbl.add rects 6 (rect 712. 40. 338. 600.);
  ignore (Ui.handle ui store rects (Input.Button_down (354.5,100.,Input.Left,1,Input.mods_none)));
  let acts=Ui.handle ui store rects (Input.Move (364.5,100.)) in
  Alcotest.(check (option (float 0.00001))) "innermost divider uses its own scaled track" (Some (0.5+.20./.744.))
    (resized 3 acts);
  Alcotest.(check (float 0.00001)) "nested resize leaves the outer split unchanged" 0.25 (split_fraction store 1)

let () =
  Alcotest.run "lui_window"
    [ ("config", [ Alcotest.test_case "parse_args" `Quick test_parse_args ]);
      ( "input",
        [ Alcotest.test_case "tables" `Quick test_input_tables ] );
      ( "admission",
        [ Alcotest.test_case "event_supported" `Quick test_event_supported ] );
      ( "layout",
        [ Alcotest.test_case "stack" `Quick test_layout;
          Alcotest.test_case "props" `Quick test_layout_props;
          Alcotest.test_case "padding edges" `Quick test_layout_padding_edges ] );
      ( "hit",
        [ Alcotest.test_case "path" `Quick test_hit;
          Alcotest.test_case "z-order" `Quick test_hit_z_order;
          Alcotest.test_case "popup escapes clip" `Quick
            test_hit_popup_escapes_clip;
          Alcotest.test_case "popup promoted" `Quick
            test_hit_popup_promoted ] );
      ( "events",
        [ Alcotest.test_case "idle allocations" `Quick test_idle_sync_allocations;
          Alcotest.test_case "idle scrollbar allocations" `Quick test_idle_scrollbar_allocations;
          Alcotest.test_case "live scroll readers" `Quick test_live_scroll_readers;
          Alcotest.test_case "click" `Quick test_click_press;
          Alcotest.test_case "release elsewhere" `Quick
            test_click_release_elsewhere;
          Alcotest.test_case "focus" `Quick test_click_focus;
          Alcotest.test_case "text+keys" `Quick test_text_input_and_keys;
          Alcotest.test_case "caret ops" `Quick test_caret_ops_wiring;
          Alcotest.test_case "text revisions" `Quick
            test_text_revisions;
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
      ( "frame scheduler",
        [ Alcotest.test_case "dirty cycle" `Quick test_frame_dirty_cycle;
          Alcotest.test_case "pacing" `Quick test_frame_pacing;
          Alcotest.test_case "refresh rate" `Quick
            test_frame_refresh_rate;
          Alcotest.test_case "visibility" `Quick test_frame_visibility ] );
      ( "presentation meter",
        [ Alcotest.test_case "displayed cadence" `Quick test_presentation_meter;
          Alcotest.test_case "monotonic counters" `Quick test_presentation_meter_rejects_regression ] );
      ( "checksum",
        [ Alcotest.test_case "ops" `Quick test_checksum ] );
      ( "scroll",
        [ Alcotest.test_case "wheel" `Quick test_scroll;
          Alcotest.test_case "wheel-x" `Quick test_wheel_x ] );
      ( "snapping",
        [ Alcotest.test_case "stub layout" `Quick test_snap_stub_layout;
          Alcotest.test_case "phantom scroll" `Quick
            test_snap_phantom_scroll;
          Alcotest.test_case "hit boundary" `Quick
            test_snap_hit_boundary;
          Alcotest.test_case "caret" `Quick test_snap_caret;
          Alcotest.test_case "resolve parity" `Quick
            test_snap_resolve_parity ] );
      ( "demo",
        [ Alcotest.test_case "dispatch flow" `Quick test_demo_dispatch;
          Alcotest.test_case "detail click owner" `Quick test_detail_click_bubbles_to_owner;
          Alcotest.test_case "detail click capture" `Quick test_detail_click_capture_and_dots ] );
      ( "selection",
        [ Alcotest.test_case "shift+all" `Quick test_sel_shift_and_all;
          Alcotest.test_case "static text" `Quick test_static_select;
          Alcotest.test_case "siblings" `Quick test_sel_siblings ] );
      ( "clipboard",
        [ Alcotest.test_case "cut/copy/paste" `Quick test_clipboard_cycle;
          Alcotest.test_case "undo/redo" `Quick test_undo_redo ] );
      ( "split resize",
        [ Alcotest.test_case "pointer feedback" `Quick test_split_pointer_resize;
          Alcotest.test_case "pane minimums" `Quick test_split_pointer_minimums;
          Alcotest.test_case "capture admission" `Quick test_split_pointer_admission;
          Alcotest.test_case "nested scaled track" `Quick test_nested_split_pointer_resize ] );
      ( "keys",
        [ Alcotest.test_case "tab activation" `Quick test_tab_activation;
          Alcotest.test_case "control keys" `Quick test_control_keys ] );
      ( "list",
        [ Alcotest.test_case "typeahead" `Quick test_list_typeahead;
          Alcotest.test_case "scroll request" `Quick test_scroll_request;
          Alcotest.test_case "vlist scroll request" `Quick
            test_vlist_scroll_request ] );
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
          Alcotest.test_case "windows flag" `Quick test_parse_windows;
          Alcotest.test_case "shared model" `Quick
            test_shared_model_pipeline;
          Alcotest.test_case "shared close" `Quick
            test_shared_model_window_close ] );
      ( "headless",
        [ Alcotest.test_case "checksum" `Quick test_headless_checksum;
          Alcotest.test_case "drop-file" `Quick test_headless_drop;
          Alcotest.test_case "two windows" `Quick test_headless_multi ] );
      ( "assembly",
        [ Alcotest.test_case "scroll caps" `Quick
            test_assembly_scroll_caps;
          Alcotest.test_case "inset scroll caps" `Quick test_assembly_inset_scroll_caps;
          Alcotest.test_case "intrinsic menu scroll" `Quick test_assembly_menu_scroll;
          Alcotest.test_case "intrinsic menu keyboard" `Quick test_assembly_menu_keyboard;
          Alcotest.test_case "menu initial selection" `Quick test_menu_open_selection;
          Alcotest.test_case "nested menu keyboard scope" `Quick test_menu_keyboard_scope;
          Alcotest.test_case "menu activation text commit" `Quick test_menu_activation_text_commit;
          Alcotest.test_case "scrollbar paint" `Quick
            test_assembly_scroll_shows_in_paint;
          Alcotest.test_case "autofocus" `Quick test_assembly_autofocus ] );
      ( "parity",
        [ Alcotest.test_case "CSS percentage colors" `Quick test_css_percentage_colors;
          Alcotest.test_case "win32 key table" `Quick
            test_win32_key_parity;
          Alcotest.test_case "win32 accelerators" `Quick
            test_win32_accelerators ] ) ]
