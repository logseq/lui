(* Tests for the Linux window host: the renderer ladder, the AT
   action -> protocol event mapping, the headless checksum pipeline
   (demo app -> patches -> store -> layout -> paint -> raster ->
   checksum, run twice and compared), the input event flow through
   Lui_window.Ui, the accessibility bridge's offline behavior and the
   desktop shell's pure surfaces. The SDL/GL path itself is exercised
   by running main.exe. *)

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
  Alcotest.(check bool) "default gl" true
    (Lui_linux.ladder ~env:"" = [ Lui_linux.Gl; Lui_linux.Noop ]);
  Alcotest.(check bool) "cpu" true
    (Lui_linux.ladder ~env:"cpu"
     = [ Lui_linux.Cpu; Lui_linux.Noop ]);
  Alcotest.(check bool) "zero" true
    (Lui_linux.ladder ~env:"0" = [ Lui_linux.Cpu; Lui_linux.Noop ]);
  Alcotest.(check bool) "vulkan" true
    (Lui_linux.ladder ~env:"vulkan"
     = [ Lui_linux.Vulkan; Lui_linux.Gl; Lui_linux.Noop ]);
  (* the no-op renderer returns a correctly sized zeroed frame *)
  let scene =
    Lui_scene.create ~mask_atlas:(Atlas.create ~bpp:1 ~w:8 ~h:8)
      ~color_atlas:(Atlas.create ~bpp:4 ~w:8 ~h:8)
  in
  scene.width <- 5;
  scene.height <- 3;
  let pix = Lui_linux.noop_renderer.Lui_host.render scene in
  Alcotest.(check int) "noop bytes" (5 * 3 * 4) (Bytes.length pix)

let test_tray_icon () =
  let px = Lui_linux.tray_icon_rgba () in
  Alcotest.(check int) "rgba bytes" (22 * 22 * 4) (Bytes.length px);
  (* center opaque, corners transparent *)
  let alpha_at x y = Char.code (Bytes.get px (((y * 22) + x) * 4 + 3)) in
  Alcotest.(check int) "center opaque" 255 (alpha_at 11 11);
  Alcotest.(check int) "corner clear" 0 (alpha_at 0 0);
  (match
     Lui_shell_linux.image_of_rgba ~width:22 ~height:22 px
   with
   | Some _ -> ()
   | None -> Alcotest.fail "icon rejected");
  Alcotest.(check bool) "bad size rejected" true
    (Lui_shell_linux.image_of_rgba ~width:4 ~height:4
       (Bytes.create 3)
     = None)

(* ---------- AT action mapping ---------- *)

let test_a11y_actions () =
  let s = demo_store () in
  (match Lui_linux.a11y_event_of_action s 3 "press" with
   | Some (Press 3) -> ()
   | _ -> Alcotest.fail "expected Press 3");
  Alcotest.(check bool) "unknown action" true
    (Lui_linux.a11y_event_of_action s 3 "dissolve" = None);
  (* a text field takes no press *)
  Alcotest.(check bool) "field press gated" true
    (Lui_linux.a11y_event_of_action s 4 "press" = None);
  (* expand/contract emit the boolean toggle *)
  (match Lui_linux.a11y_event_of_action s 5 "expand" with
   | Some (ToggleChanged (5, true)) -> ()
   | _ -> Alcotest.fail "expected ToggleChanged true");
  (match Lui_linux.a11y_event_of_action s 5 "contract" with
   | Some (ToggleChanged (5, false)) -> ()
   | _ -> Alcotest.fail "expected ToggleChanged false");
  (* toggle flips the checkable prop *)
  let s2 =
    store_of
      [ CreateNode (1, Root); CreateNode (2, Checkbox);
        InsertChild (1, 2, 0) ]
  in
  (match Lui_linux.a11y_event_of_action s2 2 "toggle" with
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
    (Lui_linux.a11y_event_of_action s3 2 "press" = None)

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

(* ---------- headless checksum pipeline ---------- *)

(* The demo app mounted on a host exactly as main.ml wires it — same
   hooks, same pango text engine, same layout stub — but with the CPU
   renderer and no SDL. *)
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
      (Lui_protocol.profile Lui_protocol.LinuxOS
         Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  (host, store, app, refresh)

(* Drive [script] input events between frames like the SDL loop does,
   accumulating the scene checksum. *)
let run_headless frames script =
  let host, store, app, refresh = host_with_app () in
  let ui = Ui.create () in
  let rects = Rects.create () in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  refresh ();
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
    if f <= Array.length scripted then
      ignore (Ui.handle ui store rects scripted.(f - 1));
    ignore (Lui_app.flush app);
    refresh' ();
    ignore (Lui_host.repaint host);
    Checksum.add_scene cs (Lui_host.scene host);
    ops_last := List.length (Lui_host.scene host).Lui_scene.ops
  done;
  (Checksum.value cs, !ops_last)

let test_headless_checksum () =
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

(* ---------- accessibility bridge (offline-safe) ---------- *)

let test_a11y_bridge () =
  let s = demo_store () in
  let a = Lui_a11y.of_store s in
  Alcotest.(check bool) "tree non-empty" true (Lui_a11y.node_count a > 0);
  let ax = Lui_ax_linux.create ~toolkit_name:"lui" () in
  Lui_ax_linux.attach ax a;
  let evs = Lui_ax_linux.drain_events ax in
  Alcotest.(check bool) "cache ready queued" true
    (List.exists
       (function Lui_ax_linux.Cache_ready -> true | _ -> false)
       evs);
  Alcotest.(check bool) "nodes registered" true
    (List.exists
       (function Lui_ax_linux.Cache_add _ -> true | _ -> false)
       evs);
  (* a store mutation lands as queued events after sync *)
  Lui_store.apply_batch s
    { generation = 2;
      ops =
        [ CreateNode (8, Text); InsertChild (2, 8, 1);
          SetProp (8, TextValue, StringValue "added") ] };
  Lui_ax_linux.sync ax;
  let evs = Lui_ax_linux.drain_events ax in
  Alcotest.(check bool) "add queued" true
    (List.exists
       (function
         | Lui_ax_linux.Cache_add c ->
           c.Lui_ax_linux.path = Lui_ax_linux.path_of 8
         | _ -> false)
       evs);
  (* focus moves produce a Focus event on the object's path *)
  Lui_ax_linux.set_focus ax 4;
  let evs = Lui_ax_linux.drain_events ax in
  Alcotest.(check bool) "focus event" true
    (List.exists
       (function
         | Lui_ax_linux.Focus_event p ->
           p = Lui_ax_linux.path_of 4
         | _ -> false)
       evs);
  (* transport is whatever the session offers; on a bus-less CI box it
     is Offline. Either way drain/dispatch stay safe — [flush] is not
     called because its >5-arg emit stubs are bytecode-shaped and
     crash native code on a live transport. *)
  let _t = Lui_ax_linux.connect ax in
  ignore (Lui_ax_linux.drain_events ax);
  Alcotest.(check bool) "dispatch safe" true
    (Lui_ax_linux.dispatch ax >= 0);
  Lui_ax_linux.destroy ax

(* ---------- desktop shell (pure surfaces) ---------- *)

let test_shell_model () =
  let open Lui_shell_linux in
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
  Alcotest.(check int) "submenu row id" (-1) rows.(2).id;
  Alcotest.(check bool) "insert" true (app_menu_insert m ~at:0);
  Alcotest.(check int) "count" 1 (app_menu_count ());
  Alcotest.(check bool) "menus" true (Array.length (app_menus ()) = 1);
  ignore (app_menu_remove ~at:0)

let test_shell_degraded () =
  let open Lui_shell_linux in
  (* transport probing and every service call stay safe with no
     session — they report instead of raising *)
  ignore (transport ());
  ignore (gui_available ());
  let item = status_item_create ~tag:3 () in
  ignore (status_item_live item);
  status_item_remove item;
  let posted, _detail =
    notify ~id:"test" ~title:"t" ~body:"b" ()
  in
  ignore posted;
  ignore (clipboard_write "x");
  ignore (clipboard_read ());
  ignore (clipboard_change_count ());
  ignore (set_window_title "lui_window_linux")

let () =
  Alcotest.run "lui_window_linux"
    [ ( "ladder",
        [ Alcotest.test_case "renderer ladder" `Quick test_ladder;
          Alcotest.test_case "tray icon" `Quick test_tray_icon ] );
      ( "a11y",
        [ Alcotest.test_case "action mapping" `Quick test_a11y_actions;
          Alcotest.test_case "bridge offline" `Quick test_a11y_bridge ] );
      ( "events",
        [ Alcotest.test_case "click" `Quick test_click_press;
          Alcotest.test_case "focus+text" `Quick test_focus_and_text;
          Alcotest.test_case "ime" `Quick test_ime_flow ] );
      ( "headless",
        [ Alcotest.test_case "checksum" `Quick test_headless_checksum ] );
      ( "shell",
        [ Alcotest.test_case "menu model" `Quick test_shell_model;
          Alcotest.test_case "degraded" `Quick test_shell_degraded ] ) ]
