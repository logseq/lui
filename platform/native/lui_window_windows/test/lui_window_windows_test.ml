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
    { RL.renderer = Lui_window_windows.noop_renderer; state = `noop }
  in
  let try_rung rung ~rest:_ =
    tried := rung :: !tried;
    match rung with
    (* injected GPU init failures: no D3D11 device, no GL context *)
    | Lui_window_windows.D3d11 | Lui_window_windows.Gl -> None
    | Lui_window_windows.Cpu -> Some cpu
    | Lui_window_windows.Noop -> Some noop
  in
  let t =
    RL.create ~warn:(fun _ -> ())
      ~release:(fun a -> released := a.RL.state :: !released)
      ~noop ~try_rung
      [ Lui_window_windows.D3d11; Lui_window_windows.Gl;
        Lui_window_windows.Cpu; Lui_window_windows.Noop ]
  in
  (* the init walk tried D3d11 and Gl, then settled on Cpu with the
     Noop tail kept in reserve for a runtime demote *)
  Alcotest.(check bool) "walk order" true
    (List.rev !tried
     = [ Lui_window_windows.D3d11; Lui_window_windows.Gl;
         Lui_window_windows.Cpu ]);
  Alcotest.(check bool) "cpu active" true
    ((RL.active t).RL.state = `cpu);
  Alcotest.(check bool) "tail kept" true
    (RL.remaining t = [ Lui_window_windows.Noop ]);
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
    (List.exists (fun r -> r = Lui_window_windows.Noop) !tried)

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

(* The demo app mounted on the shared assembly exactly as main.ml
   wires it — same hooks, same DirectWrite text engine, same real
   [Lui_layout] — but with the CPU renderer and no window. *)
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
      (Lui_protocol.profile Lui_protocol.WindowsOS
         Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  (asm, app)

let dbg fmt = Printf.printf (fmt ^^ "
%!")

(* One scripted run's outcome: the actions [Ui.handle] produced and
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

(* Drive [script] input events between frames like the Win32 loop
   does, accumulating the scene checksum and keeping the action list
   each event produced so callers can assert on them. *)
let run_headless frames script =
  dbg "stage: host_with_app";
  let asm, app = host_with_app () in
  let host = Assembly.host asm in
  let ui = Assembly.ui asm in
  let store = Assembly.store asm in
  dbg "stage: app start";
  ignore (Lui_app.start app);
  dbg "stage: started";
  ignore (Lui_app.flush app);
  dbg "stage: flushed";
  (* prime the hit-test mirror before the first event — the driver
     lays out once before its loop, otherwise frame 1's click tests
     against empty rects *)
  ignore (Assembly.repaint asm);
  dbg "stage: repaint";
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
      apply_to_app app acts;
      dbg "f%d: handled" f
    end;
    ignore (Lui_app.flush app);
    dbg "f%d: flushed" f;
    ignore (Assembly.repaint asm);
    dbg "stage: repaint %d" f;
    Checksum.add_scene cs (Lui_host.scene host);
    ops_last := List.length (Lui_host.scene host).Lui_scene.ops
  done;
  { checksum = Checksum.value cs; ops = !ops_last;
    acted = List.rev !acted; ui; store }

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

let headless_script =
  [ Input.Button_down (60., 78., Input.Left, 1, Input.mods_none);
    Input.Button_up (60., 78., Input.Left, Input.mods_none);
    Input.Text_input "hello";
    Input.Key_down (Input.Return, Input.mods_none, false) ]

let test_headless_checksum () =
  dbg "entry";
  let frames = 6 in
  let r1 = run_headless frames headless_script in
  let r2 = run_headless frames headless_script in
  Alcotest.(check bool) "scene painted" true (r1.ops > 0);
  Alcotest.(check int64) "deterministic" r1.checksum r2.checksum;
  Alcotest.(check int) "same ops" r1.ops r2.ops;
  (* the scripted input is replayed identically: one action list per
     scripted event, the same focus and the same resulting store *)
  Alcotest.(check (list int)) "same actions per event"
    (List.map List.length r1.acted) (List.map List.length r2.acted);
  Alcotest.(check int) "one action list per event"
    (List.length headless_script) (List.length r1.acted);
  Alcotest.(check int) "same focus" (Ui.focused r1.ui) (Ui.focused r2.ui);
  let texts st =
    List.map (fun id -> Lui_store.string_prop st id "text")
      (Lui_store.preorder st)
  in
  Alcotest.(check (list (option string))) "same store text"
    (texts r1.store) (texts r2.store)

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

(* The scripted frames are an interaction test, not just a render
   determinism check: every event must produce the actions the
   driver's apply_actions consumes, and the dispatches must land as
   store mutations. The autofocused Name field is addressed by prop
   and by its laid-out rect rather than by guessed coordinates. *)
let test_headless_actions () =
  let asm, app = host_with_app () in
  let ui = Assembly.ui asm in
  let store = Assembly.store asm in
  let rects = Assembly.rects asm in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  ignore (Assembly.repaint asm);
  let field =
    match
      List.find_opt
        (fun id ->
           Lui_store.string_prop store id "accessibility-label"
           = Some "Name")
        (Lui_store.preorder store)
    with
    | Some id -> id
    | None -> Alcotest.fail "name field not mounted"
  in
  let handle = Assembly.handle asm in
  (* driver startup parity: the loop hands focus to the first
     autofocus field before pumping events *)
  Ui.set_focused ui store field;
  Alcotest.(check int) "autofocus claimed" field (Ui.focused ui);
  (* typing dispatches TextChanged for the focused field *)
  let input_acts = handle (Input.Text_input "hello") in
  (match press_actions input_acts with
   | [ TextChanged (f, "hello") ] when f = field -> ()
   | _ ->
     Alcotest.failf "typing did not dispatch TextChanged: %s"
       (show_acts input_acts));
  Alcotest.(check string) "shadow" "hello" (Ui.shadow ui);
  (* Enter submits *)
  let submit_acts =
    handle (Input.Key_down (Input.Return, Input.mods_none, false))
  in
  (match press_actions submit_acts with
   | [ Submit f ] when f = field -> ()
   | _ ->
     Alcotest.failf "Return did not dispatch Submit: %s"
       (show_acts submit_acts));
  (* the dispatches reach the model: the field's text prop carries
     "hello" and the status line reports the submit *)
  apply_to_app app input_acts;
  apply_to_app app submit_acts;
  ignore (Lui_app.flush app);
  let has_text_node v =
    List.exists
      (fun id -> Lui_store.string_prop store id "text" = Some v)
      (Lui_store.preorder store)
  in
  Alcotest.(check bool) "name stored" true
    (Lui_store.string_prop store field "text" = Some "hello");
  Alcotest.(check bool) "submit reported" true
    (has_text_node "name submitted");
  (* a click inside the field's laid-out rect keeps focus and lands
     the caret inside the typed text *)
  let fr = Rects.get rects field in
  let cx = fr.Lui_scene.x +. 6.
  and cy = fr.Lui_scene.y +. (fr.Lui_scene.h /. 2.) in
  let down =
    handle (Input.Button_down (cx, cy, Input.Left, 1, Input.mods_none))
  in
  Alcotest.(check bool) "no blur" true
    (not
       (List.exists (function Focus_changed 0 -> true | _ -> false)
          down));
  Alcotest.(check int) "focus kept" field (Ui.focused ui);
  Alcotest.(check bool) "caret in text" true
    (Ui.caret ui >= 0 && Ui.caret ui <= String.length "hello")

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
          Alcotest.test_case "demote path" `Quick test_ladder_demote;
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
          Alcotest.test_case "checksum" `Quick test_headless_checksum;
          Alcotest.test_case "actions" `Quick test_headless_actions ] );
      ( "shell",
        [ Alcotest.test_case "menu model" `Quick test_shell_model;
          Alcotest.test_case "guarded" `Quick test_shell_guarded ] ) ]
