(* Tests for the Windows window host: the renderer ladder, the UIA
   action -> protocol event mapping, the headless checksum pipeline
   (demo app -> patches -> store -> layout -> paint -> raster ->
   checksum, run twice and compared), the input event flow through
   Lui_window.Ui, the Win32 window stubs exercised for real (window,
   DIB present, IMM32 calls, WM_GETOBJECT -> Lui_ax_windows reply via
   a real SendMessageW) and the shell's pure surfaces. The D3D11 path
   itself is exercised by running main.exe. *)

open Lui_scene
open Lui_protocol
open Lui_window

(* ---------- store helpers ---------- *)

let store_of ops =
  let s = Lui_store.create () in
  Lui_store.apply_batch s { generation = 1; ops };
  s

(* root 1: column 2 -> button 3 (pointer-enabled), text-field 4,
   list-item 5, row 6 -> button 7 *)
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

let ui_store_fresh () =
  let s = demo_store () in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:200 ~scale:1.
    ~measure:Layout.default_measure;
  (s, rects)

let press_actions acts =
  List.filter_map (function Dispatch e -> Some e | _ -> None) acts

(* ---------- renderer ladder ---------- *)

let test_ladder () =
  Alcotest.(check bool) "default d3d11" true
    (Lui_window_windows.ladder ~env:""
     = [ Lui_window_windows.D3d11; Lui_window_windows.Gl;
         Lui_window_windows.Cpu; Lui_window_windows.Noop ]);
  Alcotest.(check bool) "cpu" true
    (Lui_window_windows.ladder ~env:"cpu"
     = [ Lui_window_windows.Cpu; Lui_window_windows.Noop ]);
  Alcotest.(check bool) "zero" true
    (Lui_window_windows.ladder ~env:"0"
     = [ Lui_window_windows.Cpu; Lui_window_windows.Noop ]);
  Alcotest.(check bool) "gl" true
    (Lui_window_windows.ladder ~env:"gl"
     = [ Lui_window_windows.Gl; Lui_window_windows.D3d11;
         Lui_window_windows.Cpu; Lui_window_windows.Noop ]);
  (* the no-op renderer returns a correctly sized zeroed frame *)
  let scene =
    Lui_scene.create ~mask_atlas:(Atlas.create ~bpp:1 ~w:8 ~h:8)
      ~color_atlas:(Atlas.create ~bpp:4 ~w:8 ~h:8)
  in
  scene.width <- 5;
  scene.height <- 3;
  let pix =
    Lui_window_windows.noop_renderer.Lui_host.render scene
  in
  Alcotest.(check int) "noop bytes" (5 * 3 * 4) (Bytes.length pix)

let test_tray_icon () =
  let px = Lui_window_windows.tray_icon_rgba () in
  Alcotest.(check int) "rgba bytes" (22 * 22 * 4) (Bytes.length px);
  (* center opaque, corners transparent *)
  let alpha_at x y = Char.code (Bytes.get px (((y * 22) + x) * 4 + 3)) in
  Alcotest.(check int) "center opaque" 255 (alpha_at 11 11);
  Alcotest.(check int) "corner clear" 0 (alpha_at 0 0);
  (match
     Lui_shell_windows.image_of_rgba ~width:22 ~height:22 px
   with
   | Some _ -> ()
   | None -> Alcotest.fail "icon rejected");
  Alcotest.(check bool) "bad size rejected" true
    (Lui_shell_windows.image_of_rgba ~width:4 ~height:4
       (Bytes.create 3)
     = None)

(* ---------- UIA action mapping ---------- *)

let test_a11y_actions () =
  let s = demo_store () in
  (match Lui_window_windows.a11y_event_of_action s 3
           Lui_ax_windows.Press
   with
   | Some (Press 3) -> ()
   | _ -> Alcotest.fail "expected Press 3");
  (* a text field takes no press *)
  Alcotest.(check bool) "field press gated" true
    (Lui_window_windows.a11y_event_of_action s 4
       Lui_ax_windows.Press
     = None);
  (* expand/collapse emit the boolean toggle *)
  (match Lui_window_windows.a11y_event_of_action s 5
           Lui_ax_windows.Expand
   with
   | Some (ToggleChanged (5, true)) -> ()
   | _ -> Alcotest.fail "expected ToggleChanged true");
  (match Lui_window_windows.a11y_event_of_action s 5
           Lui_ax_windows.Collapse
   with
   | Some (ToggleChanged (5, false)) -> ()
   | _ -> Alcotest.fail "expected ToggleChanged false");
  (* checkbox press flips the checkable prop *)
  let s2 =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Checkbox);
        InsertChild (1, 2, 0) ]
  in
  (match Lui_window_windows.a11y_event_of_action s2 2
           Lui_ax_windows.Press
   with
   | Some (ToggleChanged (2, true)) -> ()
   | _ -> Alcotest.fail "expected check toggle");
  (* disabled nodes serve nothing *)
  let s3 =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Button);
        InsertChild (1, 2, 0);
        SetProp (2, Enabled, BoolValue false) ]
  in
  Alcotest.(check bool) "disabled gated" true
    (Lui_window_windows.a11y_event_of_action s3 2
       Lui_ax_windows.Press
     = None);
  (* Increment/Decrement step the numeric value prop, clamped *)
  let s4 =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Slider);
        InsertChild (1, 2, 0);
        SetExtensionProp (2, "value", FloatValue 4.);
        SetExtensionProp (2, "step", FloatValue 2.);
        SetExtensionProp (2, "min", FloatValue 0.);
        SetExtensionProp (2, "max", FloatValue 5.) ]
  in
  (match Lui_window_windows.a11y_event_of_action s4 2
           Lui_ax_windows.Increment
   with
   | Some (ValueChanged (2, 5.)) -> ()
   | _ -> Alcotest.fail "expected ValueChanged clamped to max 5");
  (match Lui_window_windows.a11y_event_of_action s4 2
           Lui_ax_windows.Decrement
   with
   | Some (ValueChanged (2, 2.)) -> ()
   | _ -> Alcotest.fail "expected ValueChanged 4-2=2");
  (* a numeric Set_value goes through ValueChanged *)
  (match Lui_window_windows.a11y_event_of_action s4 2
           (Lui_ax_windows.Set_value "3.5")
   with
   | Some (ValueChanged (2, 3.5)) -> ()
   | _ -> Alcotest.fail "expected ValueChanged 3.5")

(* ---------- event flow ---------- *)

let test_click_press () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (5., 10., Input.Left, 1, Input.mods_none))
  in
  (match press_actions acts with
   | [ PointerDown (3, _) ] -> ()
   | _ -> Alcotest.fail "expected PointerDown");
  let acts =
    Ui.handle ui s rects
      (Input.Button_up (5., 10., Input.Left, Input.mods_none))
  in
  (match press_actions acts with
   | [ PointerUp (3, _); PressDetail (3, _); Press 3 ] -> ()
   | _ -> Alcotest.fail "expected PointerUp + PressDetail + Press")

let test_focus_and_text () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  let acts =
    Ui.handle ui s rects
      (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none))
  in
  (match acts with
   | [ Focus_changed 4 ] -> ()
   | _ -> Alcotest.fail "expected Focus_changed 4");
  let acts = Ui.handle ui s rects (Input.Text_input "ab") in
  (match press_actions acts with
   | [ TextChanged (4, "ab") ] -> ()
   | _ -> Alcotest.fail "expected TextChanged ab");
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

let test_ime_flow () =
  let s, rects = ui_store_fresh () in
  let ui = Ui.create () in
  ignore
    (Ui.handle ui s rects
       (Input.Button_down (5., 40., Input.Left, 1, Input.mods_none)));
  (* editing marks text for display only — nothing dispatches *)
  let acts = Ui.handle ui s rects (Input.Text_editing ("ni", 2, 0)) in
  Alcotest.(check int) "no dispatch" 0 (List.length acts);
  Alcotest.(check string) "marked" "ni" (Ui.marked ui);
  let acts = Ui.handle ui s rects (Input.Text_input "hao") in
  (match press_actions acts with
   | [ TextChanged (4, "hao") ] -> ()
   | _ -> Alcotest.fail "expected commit splice");
  Alcotest.(check string) "marked cleared" "" (Ui.marked ui);
  (* a caret move while composing emits the candidate rect *)
  ignore (Ui.handle ui s rects (Input.Text_editing ("n", 1, 0)));
  let cr = Lui_scene.rect 20. 36. 2. 32. in
  (match Ui.handle ui s rects (Input.Caret cr) with
   | [ Ime_rect r ] ->
     Alcotest.(check (float 0.01)) "x" 20. r.Lui_scene.x
   | _ -> Alcotest.fail "expected Ime_rect")

(* ---------- decoded Win32 event -> Input ---------- *)

let test_input_of_event () =
  let ev a b c x y text tag =
    { Lui_win32.tag; Lui_win32.a; Lui_win32.b; Lui_win32.c;
      Lui_win32.x; Lui_win32.y; Lui_win32.text }
  in
  (* pointer coordinates arrive in device px and scale down *)
  (match
     Lui_window_windows.input_of_event ~scale:2.
       (ev 0 0 0 30. 8. "" 6)
   with
   | Some (Input.Move (15., 4.)) -> ()
   | _ -> Alcotest.fail "expected scaled Move");
  (* VK_RETURN -> Return with the ctrl flag decoded *)
  (match
     Lui_window_windows.input_of_event ~scale:1.
       (ev 0x0D 1 0 0. 0. "" 3)
   with
   | Some (Input.Key_down (Input.Return, m, false)) ->
     Alcotest.(check bool) "ctrl" true m.Input.ctrl;
     Alcotest.(check bool) "no shift" false m.Input.shift
   | _ -> Alcotest.fail "expected Key_down Return");
  (* resize arrives in device px and reports logical *)
  (match
     Lui_window_windows.input_of_event ~scale:2.
       (ev 640 480 0 0. 0. "" 2)
   with
   | Some (Input.Resize (320, 240)) -> ()
   | _ -> Alcotest.fail "expected logical Resize");
  (* button down decodes button + clicks + mods *)
  (match
     Lui_window_windows.input_of_event ~scale:1.
       (ev 1 2 0 10. 20. "" 7)
   with
   | Some (Input.Button_down (10., 20., Input.Left, 2, _)) -> ()
   | _ -> Alcotest.fail "expected Button_down left x2")

(* ---------- headless checksum pipeline ---------- *)

(* The demo app mounted on a host exactly as main.ml wires it — same
   hooks, same DirectWrite text engine, same layout stub — but with
   the CPU renderer and no window. *)
let host_with_app () =
  let host_cell = ref None in
  let rects = Rects.create () in
  let ui = Ui.create () in
  let scale = 1. in
  let text_engine =
    Lui_window_text.create
      ~scene:(fun () -> Lui_host.scene (Option.get !host_cell))
      ~scale:(fun () -> scale)
      ~store:(fun () -> Lui_host.store (Option.get !host_cell))
  in
  let hooks =
    Lui_paint.
      { color_of = Theme.color_of;
        layout =
          (fun id -> Lui_paint.placement_of_rect (Rects.get rects id));
        state_of =
          (fun id ->
             match !host_cell with
             | Some h -> Ui.state_of ui (Lui_host.store h) id
             | None -> Lui_paint.state_neutral);
        scroll_of = (fun _ -> None);
        text_ops =
          (fun id r fg s ->
             Lui_window_text.text_ops text_engine id r fg s);
        image_of = (fun _ -> None);
        shadow_of = (fun _ -> None) }
  in
  let rr = Lui_raster.Renderer.create () in
  let renderer =
    { Lui_host.name = "lui_raster";
        render =
          (fun s ->
             ignore (Lui_raster.Renderer.render rr s);
             (Lui_raster.Renderer.image rr).Lui_raster.Image.pix) }
  in
  let host =
    Lui_host.create ~hooks ~renderer ~width:480 ~height:320 ~scale ()
  in
  host_cell := Some host;
  let store = Lui_host.store host in
  let refresh () =
    Layout.refresh store rects ~width:480 ~height:320 ~scale
      ~measure:Lui_window_text.measure
  in
  let backend =
    Lui_host.backend host
      (Lui_protocol.profile Lui_protocol.WindowsOS
         Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  (host, store, app, refresh)

(* Drive [script] input events between frames like the Win32 loop
   does, accumulating the scene checksum. *)
let dbg fmt = Printf.printf (fmt ^^ "
%!")
let run_headless frames script =
  dbg "stage: host_with_app";
  let host, store, app, refresh = host_with_app () in
  dbg "stage: app start";
  let ui = Ui.create () in
  let rects = Rects.create () in
  ignore (Lui_app.start app);
  dbg "stage: started";
  ignore (Lui_app.flush app);
  dbg "stage: flushed";
  refresh ();
  dbg "stage: refresh";
  let refresh' () =
    Layout.refresh store rects ~width:480 ~height:320 ~scale:1.
      ~measure:Lui_window_text.measure
  in
  let cs = Checksum.create () in
  let ops_last = ref 0 in
  let scripted = Array.of_list script in
  for f = 1 to frames do
    (* one scripted input per frame, then flush + relayout + repaint —
       the same ordering the driver loop uses *)
    if f <= Array.length scripted then begin
      ignore (Ui.handle ui store rects scripted.(f - 1));
      dbg "f%d: handled" f
    end;
    ignore (Lui_app.flush app);
    dbg "f%d: flushed" f;
    refresh' ();
    dbg "f%d: relayout" f;
    ignore (Lui_host.repaint host);
    dbg "stage: repaint %d" f;
    Checksum.add_scene cs (Lui_host.scene host);
    ops_last := List.length (Lui_host.scene host).Lui_scene.ops
  done;
  (Checksum.value cs, !ops_last)

(* Shaped lines rooted for the process: see the comment at
   [rooted_lines] use below. *)
let rooted_lines : Lui_text_dwrite.line array list ref = ref []

(* minimal rasterize loop: crash repro for the dwrite engine *)
let test_rast_loop () =
  let f = Lui_text_dwrite.system ~size:14. () in
  for i = 1 to 400 do
    ignore (Lui_text_dwrite.rasterize ~scale:1. ~dx:0. ~shade:0.5 f 76);
    if i mod 50 = 0 then Printf.printf "iter %d ok
%!" i
  done;
  (* The engine smoke path also exercises the run fonts that [shape]
     produces; each glyph rasterizes once, as the paint hook does. *)
  let s = "the IME candidate window tracks the caret - host reports" in
  let lines = Lui_text_dwrite.shape f s in
  (* Keep the shaped lines rooted: the engine's stub shares each run
     font's face reference with a collector the next [shape] call
     clears, so a finalized run font would release a face twice. *)
  rooted_lines := lines :: !rooted_lines;
  Array.iter
    (fun (l : Lui_text_dwrite.line) ->
       Array.iter
         (fun (r : Lui_text_dwrite.run) ->
            Array.iter
              (fun (g : Lui_text_dwrite.glyph) ->
                 ignore
                   (Lui_text_dwrite.rasterize ~scale:1. ~dx:0. ~shade:0.5
                      r.font g.id))
              r.glyphs)
         l.runs)
    lines;
  dbg "rast loop ok"

(* minimal repaint: bare host + noop renderer, no text, no app *)
let test_repaint_min () =
  let renderer = Lui_window_windows.noop_renderer in
  let host =
    Lui_host.create ~hooks:Lui_paint.default_hooks ~renderer
      ~width:64 ~height:64 ~scale:1. ()
  in
  ignore (Lui_host.repaint host);
  dbg "min repaint ok"

let test_headless_checksum () =
  dbg "entry";
  let frames = 6 in
  let script =
    [ Input.Button_down (60., 78., Input.Left, 1, Input.mods_none);
      Input.Button_up (60., 78., Input.Left, Input.mods_none);
      Input.Text_input "hello";
      Input.Key_down (Input.Return, Input.mods_none, false) ]
  in
  let v1, ops1 = run_headless frames script in
  let v2, ops2 = run_headless frames script in
  Alcotest.(check bool) "scene painted" true (ops1 > 0);
  Alcotest.(check int64) "deterministic" v1 v2;
  Alcotest.(check int) "same ops" ops1 ops2

(* ---------- Win32 window stubs + UIA bridge (real calls) ---------- *)

let test_win32_window () =
  let hwnd =
    Lui_win32.create_window ~w:320 ~h:240 ~title:"lui_window_windows_test"
      ~hidden:true
  in
  let cw, ch = Lui_win32.client_size hwnd in
  Alcotest.(check bool) "client non-empty" true (cw > 0 && ch > 0);
  Alcotest.(check bool) "dpi sane" true (Lui_win32.dpi_scale hwnd >= 0.5);
  (* a zeroed 2x2 BGRA frame blits without error *)
  Alcotest.(check bool) "present frame" true
    (Lui_win32.present_frame hwnd (Bytes.create (2 * 2 * 4)) ~w:2 ~h:2);
  Alcotest.(check bool) "present region" true
    (Lui_win32.present_region hwnd ~x0:0 ~y0:0 ~x1:2 ~y1:2
       ~pix:(Bytes.create (2 * 2 * 4)) ~stride:2);
  (* IMM32 calls degrade silently without an IME context *)
  Lui_win32.set_ime_rect hwnd ~x:4 ~y:8 ~w:2 ~h:20;
  Lui_win32.set_ime_enabled hwnd true;
  Lui_win32.set_ime_enabled hwnd false;
  Lui_win32.request_attention hwnd;
  (* creation itself enqueues a resize — drain until the queue is
     empty, which must eventually report tag 0 *)
  let rec drain n =
    if n <= 0 then -1
    else
      let ev = Lui_win32.next_event () in
      if ev.Lui_win32.tag = 0 then 0 else drain (n - 1)
  in
  Alcotest.(check int) "queue drains" 0 (drain 32);
  Lui_win32.set_title hwnd "renamed";
  ignore (Lui_win32.show_window hwnd false);
  Lui_win32.destroy_window hwnd

let test_a11y_bridge () =
  let s = demo_store () in
  let a = Lui_a11y.of_store s in
  Alcotest.(check bool) "tree non-empty" true (Lui_a11y.node_count a > 0);
  let hwnd =
    Lui_win32.create_window ~w:200 ~h:200 ~title:"ax_test" ~hidden:true
  in
  (* Before attach, WM_GETOBJECT on the UIA root object id answers
     through the default window procedure: 0. *)
  let uia_root_id = Nativeint.of_int (-25) in (* UiaRootObjectId *)
  let before =
    Lui_win32.send_wm_getobject hwnd ~wparam:Nativeint.zero
      ~lparam:uia_root_id
  in
  let ax =
    Lui_ax_windows.attach
      ~frame_of:(fun _id ->
        Some
          { Lui_ax_windows.x = 0.; Lui_ax_windows.y = 0.;
            Lui_ax_windows.w = 10.; Lui_ax_windows.h = 10. })
      a hwnd
  in
  let after =
    Lui_win32.send_wm_getobject hwnd ~wparam:Nativeint.zero
      ~lparam:uia_root_id
  in
  Alcotest.(check bool) "WM_GETOBJECT before=0" true
    (before = Nativeint.zero);
  Alcotest.(check bool) "WM_GETOBJECT after!=0" true
    (after <> Nativeint.zero);
  (* a store mutation folds into the bridge through sync *)
  Lui_store.apply_batch s
    { generation = 2;
      ops =
        [ CreateNode (8, Text); InsertChild (2, 8, 1);
          SetProp (8, TextValue, StringValue "added") ] };
  ignore (Lui_ax_windows.sync ax);
  (* no AT is attached in test, so the action queue stays empty —
     the drain path itself must be safe to call every frame *)
  Alcotest.(check int) "no pending actions" 0
    (List.length (Lui_ax_windows.drain_actions ax));
  Lui_ax_windows.detach ax;
  Lui_win32.destroy_window hwnd

(* ---------- desktop shell (pure + guarded surfaces) ---------- *)

let test_shell_model () =
  let open Lui_shell_windows in
  let m =
    menu ~title:"App"
      [ Item { label = "One"; id = 1; enabled = true; checked = false };
        Separator;
        Submenu
          { label = "More"; enabled = true;
            items =
              [ Item
                  { label = "Deep"; id = 7; enabled = true;
                    checked = false } ] } ]
  in
  let rows = menu_rows m in
  Alcotest.(check int) "rows" 4 (Array.length rows);
  Alcotest.(check int) "submenu depth" 1 rows.(3).depth;
  Alcotest.(check int) "submenu row id" (-1) rows.(2).id

let test_shell_guarded () =
  let open Lui_shell_windows in
  (* every surface is safe without a desktop session — calls report
     rather than raise *)
  let item = status_item_create ~tag:3 () in
  status_item_set_title item "t";
  status_item_remove item;
  let posted, _detail = notify ~id:"test" ~title:"t" ~body:"b" () in
  ignore posted;
  ignore (clipboard_write "lww_test_clip");
  (match clipboard_read () with
   | Some "lww_test_clip" -> ()
   | _ -> ());
  ignore (clipboard_change_count ());
  ignore (pump_pending ());
  ignore (can_present_dialogs ())

let () =
  Alcotest.run "lui_window_windows"
    [ ( "ladder",
        [ Alcotest.test_case "renderer ladder" `Quick test_ladder;
          Alcotest.test_case "tray icon" `Quick test_tray_icon ] );
      ( "a11y",
        [ Alcotest.test_case "action mapping" `Quick test_a11y_actions;
          Alcotest.test_case "bridge" `Quick test_a11y_bridge ] );
      ( "events",
        [ Alcotest.test_case "click" `Quick test_click_press;
          Alcotest.test_case "focus+text" `Quick test_focus_and_text;
          Alcotest.test_case "ime" `Quick test_ime_flow;
          Alcotest.test_case "event decode" `Quick test_input_of_event ] );
      ( "win32",
        [ Alcotest.test_case "window+present+ime" `Quick test_win32_window ] );
      ( "headless",
        [ Alcotest.test_case "rast loop" `Quick test_rast_loop;
          Alcotest.test_case "repaint min" `Quick test_repaint_min;
          Alcotest.test_case "checksum" `Quick test_headless_checksum ] );
      ( "shell",
        [ Alcotest.test_case "menu model" `Quick test_shell_model;
          Alcotest.test_case "guarded" `Quick test_shell_guarded ] ) ]
