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
  Alcotest.(check bool) "default vulkan" true
    (Lui_linux.ladder ~env:""
     = [ Lui_linux.Vulkan; Lui_linux.Gl; Lui_linux.Cpu;
         Lui_linux.Noop ]);
  Alcotest.(check bool) "cpu" true
    (Lui_linux.ladder ~env:"cpu"
     = [ Lui_linux.Cpu; Lui_linux.Noop ]);
  Alcotest.(check bool) "zero" true
    (Lui_linux.ladder ~env:"0" = [ Lui_linux.Cpu; Lui_linux.Noop ]);
  Alcotest.(check bool) "vulkan" true
    (Lui_linux.ladder ~env:"vulkan"
     = [ Lui_linux.Vulkan; Lui_linux.Gl; Lui_linux.Cpu;
         Lui_linux.Noop ]);
  Alcotest.(check bool) "gl skips vulkan" true
    (Lui_linux.ladder ~env:"gl"
     = [ Lui_linux.Gl; Lui_linux.Cpu; Lui_linux.Noop ]);
  Alcotest.(check bool) "opengl skips vulkan" true
    (Lui_linux.ladder ~env:"opengl"
     = [ Lui_linux.Gl; Lui_linux.Cpu; Lui_linux.Noop ]);
  (* the no-op renderer returns a correctly sized zeroed frame *)
  let scene =
    Lui_scene.create ~mask_atlas:(Atlas.create ~bpp:1 ~w:8 ~h:8)
      ~color_atlas:(Atlas.create ~bpp:4 ~w:8 ~h:8)
  in
  scene.width <- 5;
  scene.height <- 3;
  let pix = Lui_linux.noop_renderer.Lui_host.render scene in
  Alcotest.(check int) "noop bytes" (5 * 3 * 4) (Bytes.length pix)

(* The real walk/demote path the driver uses: injected init failures
   step down the ladder at startup, and a mid-render device loss
   demotes inside the same render call — not a CPU->CPU comparison. *)
let test_ladder_demote () =
  let module RL = Renderer_ladder in
  let scene () =
    let s =
      Lui_scene.create ~mask_atlas:(Atlas.create ~bpp:1 ~w:8 ~h:8)
        ~color_atlas:(Atlas.create ~bpp:4 ~w:8 ~h:8)
    in
    s.Lui_scene.width <- 2;
    s.Lui_scene.height <- 1;
    s
  in
  let tried = ref [] and released = ref [] in
  let cpu_live = ref true in
  let cpu_pix = Bytes.make 8 '\xAB' in
  let cpu =
    { RL.renderer =
        { Lui_host.name = "mock-cpu";
          render =
            (fun _ ->
               if !cpu_live then cpu_pix else failwith "device lost") };
      state = `cpu }
  in
  let noop =
    { RL.renderer = Lui_linux.noop_renderer; state = `noop }
  in
  let try_rung rung ~rest:_ =
    tried := rung :: !tried;
    match rung with
    (* injected GPU init failures: no Vulkan device, no GL context *)
    | Lui_linux.Vulkan | Lui_linux.Gl -> None
    | Lui_linux.Cpu -> Some cpu
    | Lui_linux.Noop -> Some noop
  in
  let t =
    RL.create ~warn:(fun _ -> ())
      ~release:(fun a -> released := a.RL.state :: !released)
      ~noop ~try_rung
      [ Lui_linux.Vulkan; Lui_linux.Gl; Lui_linux.Cpu; Lui_linux.Noop ]
  in
  (* the init walk tried Vulkan and Gl, then settled on Cpu with the
     Noop tail kept in reserve for a runtime demote *)
  Alcotest.(check bool) "walk order" true
    (List.rev !tried
     = [ Lui_linux.Vulkan; Lui_linux.Gl; Lui_linux.Cpu ]);
  Alcotest.(check bool) "cpu active" true
    ((RL.active t).RL.state = `cpu);
  Alcotest.(check bool) "tail kept" true
    (RL.remaining t = [ Lui_linux.Noop ]);
  (* the CPU rung wins a frame before dying *)
  let live = RL.renderer_live t in
  Alcotest.(check bool) "cpu frame" true
    (live.Lui_host.render (scene ()) == cpu_pix);
  (* a mid-render device loss demotes to Noop inside the same call:
     the rung's release ran and the zeroed fallback frame comes back *)
  cpu_live := false;
  let pix = live.Lui_host.render (scene ()) in
  Alcotest.(check bool) "cpu released" true (!released = [ `cpu ]);
  Alcotest.(check bool) "noop active" true
    ((RL.active t).RL.state = `noop);
  Alcotest.(check int) "zeroed frame" (2 * 1 * 4) (Bytes.length pix);
  Alcotest.(check bool) "walked on" true
    (List.exists (fun r -> r = Lui_linux.Noop) !tried)

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

(* ---------- shared caret model (C7) ---------- *)

(* A Ui wired to the pango-backed caret ops, focused on a text field
   holding [text]: keyboard moves/deletes run on the same layouts
   the painter resolves. *)
let caret_ops_store text =
  let s =
    store_of
      [ CreateNode (1, Root); CreateNode (2, TextField);
        InsertChild (1, 2, 0);
        SetProp (2, TextValue, StringValue text) ]
  in
  let rects = Rects.create () in
  Layout.refresh s rects ~width:200 ~height:100 ~scale:1.
    ~measure:Layout.default_measure;
  let scene =
    Lui_scene.create ~mask_atlas:(Atlas.create ~bpp:1 ~w:8 ~h:8)
      ~color_atlas:(Atlas.create ~bpp:4 ~w:8 ~h:8)
  in
  let te =
    Lui_window_text.create ~scene:(fun () -> scene)
      ~scale:(fun () -> 1.) ~store:(fun () -> s)
  in
  let ui = Ui.create () in
  Ui.set_caret_ops ui
    (fun _store id text ~lw ~lh ->
       Lui_window_text.caret_ops te id text ~lw ~lh);
  Ui.set_focused ui s 2;
  (s, rects, ui)

let key k = Input.Key_down (k, Input.mods_none, false)

let test_caret_ops_zwj () =
  let fam = "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7" in
  let s, rects, ui = caret_ops_store ("a" ^ fam ^ "z") in
  (* caret starts at the end (20): one Left lands before "z"... *)
  ignore (Ui.handle ui s rects (key Input.Arrow_left));
  Alcotest.(check int) "before z" 19 (Ui.caret ui);
  (* ...the next Left crosses the whole ZWJ family — never inside *)
  ignore (Ui.handle ui s rects (key Input.Arrow_left));
  Alcotest.(check int) "skips family" 1 (Ui.caret ui);
  (* Backspace from 19 deletes the whole cluster, leaving "az" *)
  ignore (Ui.handle ui s rects (key Input.Arrow_right));
  Alcotest.(check int) "back before z" 19 (Ui.caret ui);
  (match
     press_actions (Ui.handle ui s rects (key Input.Backspace))
   with
   | [ TextChanged (2, "az") ] -> ()
   | a -> Alcotest.failf "expected cluster delete, got %d" (List.length a))

let test_caret_ops_combining () =
  let s, rects, ui = caret_ops_store "e\xCC\x81x" in
  ignore (Ui.handle ui s rects (key Input.Arrow_left));
  Alcotest.(check int) "before x" 3 (Ui.caret ui);
  ignore (Ui.handle ui s rects (key Input.Arrow_left));
  Alcotest.(check int) "skips combining" 0 (Ui.caret ui);
  (* Delete at 0 removes e+acute whole *)
  (match
     press_actions (Ui.handle ui s rects (key Input.Delete))
   with
   | [ TextChanged (2, "x") ] -> ()
   | _ -> Alcotest.fail "expected combining delete")

let test_caret_ops_vertical () =
  let s, rects, ui = caret_ops_store "ab\ncd" in
  (* caret at end of "cd" (5) -> Up keeps the column on "ab" *)
  ignore (Ui.handle ui s rects (key Input.Arrow_up));
  Alcotest.(check int) "up keeps x" 2 (Ui.caret ui);
  ignore (Ui.handle ui s rects (key Input.Arrow_down));
  Alcotest.(check int) "down keeps x" 5 (Ui.caret ui)

(* ---------- headless checksum pipeline ---------- *)

(* The demo app mounted on the shared assembly exactly as main.ml
   wires it — same hooks, same pango text engine, same real
   [Lui_layout] — but with the CPU renderer and no SDL. *)
let host_with_app () =
  let scale_cell = ref 1. in
  let host_cell = ref None in
  let text_engine =
    Lui_window_text.create
      ~scene:(fun () -> Lui_host.scene (Option.get !host_cell))
      ~scale:(fun () -> !scale_cell)
      ~store:(fun () -> Lui_host.store (Option.get !host_cell))
  in
  let rr = Lui_raster.Renderer.create () in
  let renderer =
    { Lui_host.name = "lui_raster";
      render =
        (fun s ->
           ignore (Lui_raster.Renderer.render rr s);
           (Lui_raster.Renderer.image rr).Lui_raster.Image.pix) }
  in
  let asm =
    Assembly.create ~layout:(module Lui_layout) ~scale_cell
      ~text:
        Assembly.
          { measure = Lui_window_text.measure_text text_engine;
            text_ops = Lui_window_text.text_ops text_engine;
            hit_text = Lui_window_text.hit_text text_engine;
            caret_ops = Lui_window_text.caret_ops text_engine }
      ~renderer ~width:480 ~height:320 ()
  in
  host_cell := Some (Assembly.host asm);
  let backend =
    Assembly.backend asm
      (Lui_protocol.profile Lui_protocol.LinuxOS
         Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  (asm, app)

(* One scripted frame's outcome: the actions [Ui.handle] produced and
   the scene checksum after the driver's flush/relayout/repaint. *)
type headless_run = {
  checksum : int64;
  ops : int;
  acted : action list list;
  ui : Ui.t;
  store : Lui_store.t;
}

(* Feed the host-level action list back into the app the way the
   driver's apply_actions does: only [Dispatch] events reach the
   model; the rest are driver-side concerns out of scope here. *)
let apply_to_app app acts =
  List.iter
    (function
      | Dispatch ev -> (
        try ignore (Lui_app.dispatch_event app ev)
        with Invalid_argument _ -> ())
      | _ -> ())
    acts

(* Drive [script] input events between frames like the SDL loop does,
   accumulating the scene checksum and keeping the action list each
   event produced so callers can assert on them. *)
let run_headless frames script =
  let asm, app = host_with_app () in
  let host = Assembly.host asm in
  let ui = Assembly.ui asm in
  let store = Assembly.store asm in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  (* prime the hit-test mirror before the first event — the driver
     lays out once before its loop, otherwise frame 1's click tests
     against empty rects *)
  ignore (Assembly.repaint asm);
  let cs = Checksum.create () in
  let ops_last = ref 0 in
  let acted = ref [] in
  let scripted = Array.of_list script in
  for f = 1 to frames do
    (* one scripted input per frame, then flush + repaint + populate —
       the same ordering the driver loop uses *)
    if f <= Array.length scripted then begin
      let acts = Assembly.handle asm scripted.(f - 1) in
      acted := acts :: !acted;
      apply_to_app app acts
    end;
    ignore (Lui_app.flush app);
    ignore (Assembly.repaint asm);
    Checksum.add_scene cs (Lui_host.scene host);
    ops_last := List.length (Lui_host.scene host).Lui_scene.ops
  done;
  { checksum = Checksum.value cs; ops = !ops_last;
    acted = List.rev !acted; ui; store }

let headless_script =
  [ Input.Button_down (60., 100., Input.Left, 1, Input.mods_none);
    Input.Button_up (60., 100., Input.Left, Input.mods_none);
    Input.Text_input "hello";
    Input.Key_down (Input.Return, Input.mods_none, false) ]

let test_headless_checksum () =
  let frames = 6 in
  let r1 = run_headless frames headless_script in
  let r2 = run_headless frames headless_script in
  Alcotest.(check bool) "scene painted" true (r1.ops > 0);
  Alcotest.(check int64) "deterministic" r1.checksum r2.checksum;
  Alcotest.(check int) "same ops" r1.ops r2.ops

(* The scripted frames are an interaction test, not just a render
   determinism check: every event must produce the actions the
   driver's apply_actions consumes, and the dispatches must land as
   store mutations. *)
let show_event = function
  | TextChanged (id, s) -> Printf.sprintf "TextChanged(%d,%S)" id s
  | Submit id -> Printf.sprintf "Submit %d" id
  | Press id -> Printf.sprintf "Press %d" id
  | PointerDown (id, _) -> Printf.sprintf "PointerDown %d" id
  | PointerUp (id, _) -> Printf.sprintf "PointerUp %d" id
  | PressDetail (id, _) -> Printf.sprintf "PressDetail %d" id
  | Appear id -> Printf.sprintf "Appear %d" id
  | ToggleChanged (id, b) -> Printf.sprintf "ToggleChanged(%d,%b)" id b
  | Change id -> Printf.sprintf "Change %d" id
  | Dismiss id -> Printf.sprintf "Dismiss %d" id
  | _ -> "event"

let show_acts acts =
  String.concat ", "
    (List.map
       (function
         | Focus_changed id -> Printf.sprintf "Focus_changed %d" id
         | Dispatch e -> "Dispatch " ^ show_event e
         | Quit -> "Quit"
         | Ime_rect _ -> "Ime_rect"
         | Resize_host _ -> "Resize_host"
         | Clipboard_write s -> Printf.sprintf "Clipboard_write %S" s
         | Paste_request -> "Paste_request")
       acts)

let test_headless_actions () =
  let r = run_headless 4 headless_script in
  let field =
    match
      List.find_opt
        (fun id ->
           Lui_store.string_prop r.store id "accessibility-label"
           = Some "New item")
        (Lui_store.preorder r.store)
    with
    | Some id -> id
    | None -> Alcotest.fail "demo text field not mounted"
  in
  (match r.acted with
   | [ down; up; input; submit ] ->
     (* the click claims the autofocus field — the Focus_changed the
        driver would use to start text input *)
     (match down with
      | [ Focus_changed f ] when f = field -> ()
      | _ ->
        Alcotest.failf "click did not focus the field: %s"
          (show_acts down));
     (match up with
      | [ Dispatch (Press p) ] when p <> 0 -> ()
      | _ -> Alcotest.failf "release not quiet: %s" (show_acts up));
     (match input with
      | [ Dispatch (TextChanged (f, "hello")) ] when f = field -> ()
      | _ ->
        Alcotest.failf "typing did not dispatch TextChanged: %s"
          (show_acts input));
     (match submit with
      | [ Dispatch (Submit f) ] when f = field -> ()
      | _ ->
        Alcotest.failf "Return did not dispatch Submit: %s"
          (show_acts submit))
   | frames ->
     Alcotest.failf "expected four action frames, got %d"
       (List.length frames));
  (* the dispatches reached the model: "hello" mounts as a new item
     and the field's draft is cleared *)
  let has_text_node v =
    List.exists
      (fun id -> Lui_store.string_prop r.store id "text" = Some v)
      (Lui_store.preorder r.store)
  in
  Alcotest.(check bool) "item added" true (has_text_node "hello");
  Alcotest.(check bool) "draft cleared" true
    (Lui_store.string_prop r.store field "text" = Some "");
  Alcotest.(check int) "focus kept" field (Ui.focused r.ui)

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
          Alcotest.test_case "demote path" `Quick test_ladder_demote;
          Alcotest.test_case "tray icon" `Quick test_tray_icon ] );
      ( "a11y",
        [ Alcotest.test_case "action mapping" `Quick test_a11y_actions;
          Alcotest.test_case "bridge offline" `Quick test_a11y_bridge ] );
      ( "events",
        [ Alcotest.test_case "click" `Quick test_click_press;
          Alcotest.test_case "focus+text" `Quick test_focus_and_text;
          Alcotest.test_case "ime" `Quick test_ime_flow ] );
      ( "caret",
        [ Alcotest.test_case "zwj cluster" `Quick test_caret_ops_zwj;
          Alcotest.test_case "combining" `Quick test_caret_ops_combining;
          Alcotest.test_case "vertical" `Quick test_caret_ops_vertical ] );
      ( "headless",
        [ Alcotest.test_case "checksum" `Quick test_headless_checksum;
          Alcotest.test_case "actions" `Quick test_headless_actions ] );
      ( "shell",
        [ Alcotest.test_case "menu model" `Quick test_shell_model;
          Alcotest.test_case "degraded" `Quick test_shell_degraded ] ) ]
