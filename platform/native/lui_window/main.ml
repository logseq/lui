(* SDL window driver: creates the renderer ladder (Metal > GL 3.3
   core > CPU blit > no-op loop renderer), wires each window into its
   own Lui_host + Lui_app surface, routes SDL events to the right
   window by SDL windowID, and presents frames per window.

   Multi-window model (see Lui_window.Multi for the rationale): each
   top-level window is an independent surface — its own host, app,
   interaction state, renderer and a11y tree. The registry below maps
   SDL windowID -> surface; events that carry a windowID dispatch
   there, global events (quit, display hotplug) apply process-wide.
   A window crossing monitors or a display change re-queries that
   window's drawable size, recomputes the backing scale and marks the
   surface dirty so the next frame re-lays out.

   Flags: --width N --height N --headless N --windows N
   --drop-file PATH. *)

open Lui_window
open Lui_window_demo

module Sdl = Tsdl.Sdl

let log fmt = Printf.printf (fmt ^^ "\n%!")
let warn fmt = Printf.eprintf (fmt ^^ "\n%!")

let sdl_ok = function
  | Ok v -> v
  | Error (`Msg m) -> failwith ("SDL: " ^ m)

let perf_s () =
  Int64.to_float (Sdl.get_performance_counter ())
  /. Int64.to_float (Sdl.get_performance_frequency ())

let mods_of_keymod km =
  Input.
    { ctrl = km land Sdl.Kmod.ctrl <> 0;
      shift = km land Sdl.Kmod.shift <> 0;
      alt = km land Sdl.Kmod.alt <> 0;
      meta = km land Sdl.Kmod.gui <> 0 }

(* One SDL event → at most one backend-neutral input. Window and
   display events are handled (and routed) in [handle_window_event] /
   [drain_events] before this is called, so the Window_event arm here
   only sees events that survived routing. *)
let input_of_event e =
  let open Input in
  match Sdl.Event.enum (Sdl.Event.get e Sdl.Event.typ) with
  | `Quit -> Some Quit_input
  | `Window_event ->
    (match
       Sdl.Event.window_event_enum
         (Sdl.Event.get e Sdl.Event.window_event_id)
     with
     | `Resized | `Size_changed ->
       Some
         (Resize
            ( Int32.to_int (Sdl.Event.get e Sdl.Event.window_data1),
              Int32.to_int (Sdl.Event.get e Sdl.Event.window_data2) ))
     | `Close -> Some Quit_input
     | _ -> None)
  | `Key_down ->
    Some
      (Key_down
         ( Input.key_of_sdl_scancode
             (Sdl.Event.get e Sdl.Event.keyboard_scancode),
           mods_of_keymod (Sdl.Event.get e Sdl.Event.keyboard_keymod),
           Sdl.Event.get e Sdl.Event.keyboard_repeat <> 0 ))
  | `Text_input ->
    Some (Text_input (Sdl.Event.get e Sdl.Event.text_input_text))
  | `Text_editing ->
    Some
      (Text_editing
         ( Sdl.Event.get e Sdl.Event.text_editing_text,
           Sdl.Event.get e Sdl.Event.text_editing_start,
           Sdl.Event.get e Sdl.Event.text_editing_length ))
  | `Mouse_motion ->
    Some
      (Move
         ( float (Sdl.Event.get e Sdl.Event.mouse_motion_x),
           float (Sdl.Event.get e Sdl.Event.mouse_motion_y) ))
  | `Mouse_button_down ->
    Some
      (Button_down
         ( float (Sdl.Event.get e Sdl.Event.mouse_button_x),
           float (Sdl.Event.get e Sdl.Event.mouse_button_y),
           Input.button_of_sdl
             (Sdl.Event.get e Sdl.Event.mouse_button_button),
           Sdl.Event.get e Sdl.Event.mouse_button_clicks,
           mods_of_keymod (Sdl.get_mod_state ()) ))
  | `Mouse_button_up ->
    Some
      (Button_up
         ( float (Sdl.Event.get e Sdl.Event.mouse_button_x),
           float (Sdl.Event.get e Sdl.Event.mouse_button_y),
           Input.button_of_sdl
             (Sdl.Event.get e Sdl.Event.mouse_button_button),
           mods_of_keymod (Sdl.get_mod_state ()) ))
  | `Mouse_wheel ->
    Some
      (Wheel_mods
         ( float (Sdl.Event.get e Sdl.Event.mouse_wheel_x),
           float (Sdl.Event.get e Sdl.Event.mouse_wheel_y),
           mods_of_keymod (Sdl.get_mod_state ()) ))
  | `Drop_file ->
    (* SDL_DROPFILE: the payload string must be freed once read *)
    let s = Sdl.Event.drop_file_file e in
    Sdl.Event.drop_file_free e;
    (match s with Some f -> Some (Drop_file f) | None -> None)
  | `Drop_text ->
    (* SDL_DROPTEXT: the dragged text rides the same field *)
    let s = Sdl.Event.drop_file_file e in
    Sdl.Event.drop_file_free e;
    (match s with Some t -> Some (Drop_text t) | None -> None)
  | `Drop_begin | `Drop_complete -> None
  | _ -> None

type stats = {
  mutable frames : int;
  mutable acc_ms : float;
  mutable min_ms : float;
  mutable max_ms : float;
}

let stats_update st ms =
  st.frames <- st.frames + 1;
  st.acc_ms <- st.acc_ms +. ms;
  st.min_ms <- Float.min st.min_ms ms;
  st.max_ms <- Float.max st.max_ms ms

let stats_report st renderer_name =
  if st.frames > 0 then begin
    let avg = st.acc_ms /. float st.frames in
    log "stats: frames=%d fps=%.0f frame_ms=%.2f (min %.2f max %.2f) renderer=%s"
      st.frames (1000. /. Float.max avg 0.001) avg st.min_ms st.max_ms
      renderer_name;
    st.frames <- 0;
    st.acc_ms <- 0.;
    st.min_ms <- 1e9;
    st.max_ms <- 0.
  end

(* ---------- driver state per window ---------- *)

(* Everything the loop needs per window beyond the pure state kept in
   [Multi.surface]: the OS window/context/renderer handles and the
   closures the pipeline built during setup (populate / caret_rect
   capture the pre-host cells, so they live here). The backend pieces
   are cells because a renderer demote swaps them live: it drops the
   GL context, recreates the window (which also re-keys the surface —
   [Multi.rekey]) and installs the next rung's renderer. *)
type drv = {
  mutable sdl : Sdl.window;
  gctx_cell : Sdl.gl_context option ref;
  gl_live_cell : bool ref;
  vsync : bool;
  blit_cell : Lui_blit.t option ref;
  metal : Lui_metal.t option;
  renderer_cell : Lui_host.renderer ref;
  app : (Demo_app.model, Demo_app.action) Lui_app.reducer_app;
  a11y : Lui_a11y.t;
  mutable drop_seen : int;
  mutable toast_since : float option;
  reqs_seen : (string, int) Hashtbl.t;
  checksum : Checksum.t;
  mutable frame : int;
  stats : stats;
  idx : int;                   (* registry/log index, 0-based *)
  populate : unit -> unit;     (* hit-test mirror refresh *)
  caret_rect : unit -> Lui_scene.rect;
}

type surf = drv Multi.surface

(* Process-wide driver state: the window registry, the quit flag and
   the parsed config/loop targets (set once in main before any window
   is created). *)
let windows : drv Multi.t = Multi.create ()
let quit = ref false
let cfg = ref default_config
let headless = ref false
let use_cpu = ref false
let prefer_metal = ref false
let frames_target : int option ref = ref None
let iter_no = ref 0
(* Model actions the macOS shell layer queues out-of-band (menu-bar
   icon menu): the event drain sends them into the focused window's
   app on the next frame, same as pointer input. *)
let pending : Demo_app.action Queue.t = Queue.create ()

(* ---------- per-window helpers ---------- *)

let drawable (s : surf) =
  (* Under the dummy driver this may report 0x0; fall back to the
     logical size so layout still gets a sane extent. *)
  match Sdl.gl_get_drawable_size s.driver.sdl with
  | 0, 0 -> (s.Multi.logical_w, s.Multi.logical_h)
  | d -> d

(* SDL_SetTextInputRect works in window (logical) pixels; the surface's
   backing scale converts the device-px rect. *)
let set_ime_rect (s : surf) (r : Lui_scene.rect) =
  let sc = Multi.scale s in
  Sdl.set_text_input_rect
    (Some
       (Sdl.Rect.create
          ~x:(int_of_float (r.Lui_scene.x /. sc))
          ~y:(int_of_float (r.Lui_scene.y /. sc))
          ~w:(max 1 (int_of_float (r.Lui_scene.w /. sc)))
          ~h:(max 1 (int_of_float (r.Lui_scene.h /. sc)))))

(* Re-read a window's drawable size and backing scale: on [Moved] the
   window may have crossed onto a monitor with a different scale, on
   display events anything may have changed. Cheap and idempotent —
   [apply_drawable] only acts when the values differ. *)
let refresh_scale (s : surf) =
  (match Sdl.get_window_display_index s.driver.sdl with
   | Ok di when di <> s.Multi.display -> s.Multi.display <- di
   | _ -> ());
  let dw, dh = drawable s in
  if Multi.apply_drawable s ~dw ~dh then
    log "win=%d: drawable %dx%d scale %.2f (display %d)" s.driver.idx
      dw dh (Multi.scale s) s.Multi.display

(* The window holding a text field's focus, for the process-global
   IME candidate window; prefers the OS-focused window. *)
let focused_field () =
  match Multi.find_focused windows with
  | Some w when Ui.focused w.Multi.ui <> 0 -> Some w
  | _ ->
    let hit = ref None in
    Multi.iter windows (fun w ->
        if !hit = None && Ui.focused w.Multi.ui <> 0 then hit := Some w);
    !hit

let rec apply_actions (s : surf) acts =
  let d = s.driver in
  List.iter
    (function
      | Dispatch ev ->
        (try ignore (Lui_app.dispatch_event d.app ev)
         with Invalid_argument msg ->
           warn "dispatch rejected event: %s" msg)
      | Clipboard_write text ->
        if not !headless then ignore (Lui_shell.clipboard_write text)
      | Paste_request ->
        (* clipboard I/O is a driver concern: read + feed back as
           Input.Paste into the same window (interactive only —
           headless never types Cmd-V) *)
        (match if !headless then None else Lui_shell.clipboard_read () with
         | Some text ->
           apply_actions s (Multi.dispatch s (Input.Paste text))
         | None -> ())
      | Resize_host _ ->
        let dw, dh = drawable s in
        (match !(d.blit_cell) with
         | Some b ->
           (match Lui_blit.resize b ~w:dw ~h:dh with
            | Ok () -> ()
            | Error m -> warn "blit resize: %s" m)
         | None -> ());
        ignore (Multi.apply_drawable s ~dw ~dh)
      | Focus_changed id ->
        ignore
          (if id = 0 then Lui_a11y.clear_focused d.a11y
           else Lui_a11y.set_focused d.a11y id);
        (* IME is process-global: input stays on while ANY window
           holds a field; the candidate window anchors on that
           window's rect. *)
        (match focused_field () with
         | Some w ->
           Sdl.start_text_input ();
           set_ime_rect w (Rects.get w.Multi.rects (Ui.focused w.Multi.ui))
         | None -> Sdl.stop_text_input ())
      | Ime_rect r -> set_ime_rect s r
      | Quit -> quit := true)
    acts

(* Public window ops: open/close/focus — the [open_window] path lives
   further down since it needs the full pipeline setup. *)
let close_window id =
  match Multi.unregister windows id with
  | None -> ()
  | Some s ->
    ignore (Lui_app.dispose s.driver.app);
    (match !(s.driver.gctx_cell) with
     | Some c -> Sdl.gl_delete_context c
     | None -> ());
    (match s.driver.metal with
     | Some m -> Lui_metal.release m
     | None -> ());
    Sdl.destroy_window s.driver.sdl;
    log "win=%d closed (%d left)" s.driver.idx (Multi.count windows);
    if Multi.count windows = 0 then quit := true

let focus_window id =
  match Multi.find windows id with
  | Some s ->
    Sdl.raise_window s.driver.sdl;
    Multi.set_focused windows id
  | None -> ()

(* Scale query for a window id: [Option.map Multi.scale
   (Multi.find windows id)] — the surface-level accessor is
   {!Multi.scale}. *)

(* Synthetic OS drops (--drop-file): on frame 1 each path lands on
   the deepest target accepting its namespaced payload — found by
   scanning the store rather than hard-coding a hit point, so the
   injection follows wherever the demo puts its drop well. *)
let inject_drops (s : surf) =
  let store = Lui_host.store s.host in
  List.iter
    (fun path ->
       let payload = "file:" ^ path in
       match
         List.find_opt
           (fun id -> Ui.drop_accepts store id payload)
           (Lui_store.preorder store)
       with
       | Some id ->
         let r = Rects.get s.Multi.rects id in
         let sc = Multi.scale s in
         let cx = (r.Lui_scene.x +. r.Lui_scene.w /. 2.) /. sc
         and cy = (r.Lui_scene.y +. r.Lui_scene.h /. 2.) /. sc in
         apply_actions s
           (Multi.dispatch s (Input.Move (cx, cy)));
         apply_actions s
           (Multi.dispatch s (Input.Drop_file path))
       | None -> log "drop: no target accepts %s" payload)
    (List.rev !cfg.drop_files)

(* Drops are host-local: the app learns of them through this poll,
   which forwards each new (target, payload, serial) triple into the
   demo model once. *)
let poll_drop (s : surf) =
  match Ui.last_drop s.Multi.ui with
  | Some (_, payload, seq) when seq <> s.driver.drop_seen ->
    s.driver.drop_seen <- seq;
    log "drop: payload=%s" payload;
    ignore (Lui_app.send s.driver.app (Demo_app.Dropped payload))
  | _ -> ()

(* Side effects the demo requests through the model: a counter bump
   means the driver runs the shell call once, outside the
   deterministic store. Interactive only — headless frames never
   produce requests, keeping the checksum stable. *)
let poll_driver (s : surf) =
  let d = s.driver in
  if not !headless then begin
    let m = Lui_app.model d.app in
    let req_hit name n =
      let seen =
        Option.value ~default:0 (Hashtbl.find_opt d.reqs_seen name)
      in
      if n > seen then begin Hashtbl.replace d.reqs_seen name n; true end
      else false
    in
    if req_hit "notify" m.Demo_app.req_notify then begin
      let posted, detail =
        Lui_shell.notify ~id:"demo" ~title:"lui_window"
          ~body:"notification from the native demo" () in
      log "shell notify: posted=%b (%s)" posted detail
    end;
    if req_hit "clipboard" m.Demo_app.req_clipboard then begin
      let text =
        Printf.sprintf "lui_window %dx%d renderer=%s frames=%d"
          s.Multi.drawable_w s.Multi.drawable_h
          (!(d.renderer_cell)).Lui_host.name
          d.frame in
      log "shell clipboard: wrote %d chars (ok=%b)" (String.length text)
        (Lui_shell.clipboard_write text)
    end;
    if req_hit "a11y" m.Demo_app.req_a11y then begin
      let names =
        List.map
          (fun n -> Lui_a11y.role_name n.Lui_a11y.role)
          (Lui_a11y.flatten d.a11y) in
      log "a11y: %d nodes — %s" (Lui_a11y.node_count d.a11y)
        (String.concat ", " names)
    end;
    Lui_shell.set_dock_badge
      (match m.Demo_app.items with
       | [] -> None
       | l -> Some (string_of_int (List.length l)));
    (* The toast's [duration] prop is informational on this backend;
       the driver owns the clock and dismisses after 2.5 s. *)
    (match m.Demo_app.toast_open, d.toast_since with
     | true, None -> d.toast_since <- Some (perf_s ())
     | true, Some t0 when perf_s () -. t0 > 2.5 ->
       ignore (Lui_app.send d.app (Demo_app.Close Demo_app.P_toast));
       d.toast_since <- None
     | false, _ -> d.toast_since <- None
     | _ -> ())
  end

(* One frame for one window: flush queued patches, run store-driven
   effects, poll model-driven side effects, refresh the IME anchor,
   repaint when dirty. Returns whether a repaint happened. *)
let tick (s : surf) ~t0 =
  let d = s.driver in
  let store = Lui_host.store s.host in
  ignore (Lui_app.flush d.app);
  apply_actions s (Ui.store_changed s.ui store);
  poll_driver s;
  poll_drop s;
  (* Report the caret once per frame: while a composition is open
     the state machine emits Ime_rect on movement so the candidate
     window tracks the caret; idle, the rect is only remembered. *)
  if Ui.focused s.Multi.ui <> 0 then
    apply_actions s (Multi.dispatch s (Input.Caret (d.caret_rect ())));
  (* Headless proves the loop: force a repaint every iteration so
     the frame counter and checksum actually run. *)
  let dirty = !headless || Ui.want_frame s.ui s.host in
  if dirty then begin
    ignore (Lui_host.repaint s.host);
    d.populate ();
    ignore (Lui_a11y.sync d.a11y);
    if !(d.gl_live_cell) then begin
      (match !(d.gctx_cell) with
       | Some c -> ignore (Sdl.gl_make_current d.sdl c)
       | None -> ());
      Sdl.gl_swap_window d.sdl
    end;
    Ui.frame_done s.ui;
    d.frame <- d.frame + 1;
    Checksum.add_scene d.checksum (Lui_host.scene s.host);
    if !headless && not !(d.gl_live_cell) then
      log "win=%d frame=%d ops=%d" d.idx d.frame
        (List.length (Lui_host.scene s.host).Lui_scene.ops);
    stats_update d.stats ((perf_s () -. t0) *. 1000.);
    if d.frame mod 60 = 0 then begin
      (* FPS for the badge rides the same ~1 s window as the stats
         log; headless never sends it, keeping the initial badge
         (empty) deterministic for the checksum. *)
      let fps =
        if d.stats.frames > 0 && d.stats.acc_ms > 0. then
          1000. /. (d.stats.acc_ms /. float d.stats.frames)
        else 0. in
      stats_report d.stats (!(d.renderer_cell)).Lui_host.name;
      if not !headless then
        ignore
          (Lui_app.send d.app
             (Demo_app.Badge
                (Printf.sprintf "%s — %.0f fps"
                   (!(d.renderer_cell)).Lui_host.name fps)))
    end
  end;
  dirty


(* ---------- window creation ---------- *)

let flags_for gl =
  let base = Sdl.Window.(resizable + allow_highdpi + shown) in
  if gl then Sdl.Window.(base + opengl) else base

(* ---------- runtime backend-loss recovery ---------- *)

(* A rung that reports frames without touching a GPU; the demote walk
   ends here so recovery always terminates. *)
let noop_renderer =
  { Lui_host.name = "noop";
    render =
      (fun s ->
         Bytes.create (s.Lui_scene.width * s.Lui_scene.height * 4)) }

let gl_renderer gl =
  { Lui_host.name = "lui_gl";
    render = (fun s -> Lui_gl.render gl s; Bytes.empty) }

(* CPU rung: Lui_raster renders the scene, Lui_blit uploads the damaged
   rects (or the whole frame) to the window texture. *)
let cpu_renderer b =
  let rr = Lui_raster.Renderer.create () in
  { Lui_host.name = "lui_raster+blit";
    render =
      (fun s ->
         let dirty = Lui_raster.Renderer.render rr s in
         let img = Lui_raster.Renderer.image rr in
         let stride = img.Lui_raster.Image.stride / 4 in
         if Lui_raster.Renderer.whole rr || dirty = [] then
           ignore
             (Lui_blit.update b ~pix:img.Lui_raster.Image.pix ~stride)
         else
           List.iter
             (fun (r : Lui_scene.irect) ->
                ignore
                  (Lui_blit.update_region b ~x0:r.x0 ~y0:r.y0 ~x1:r.x1
                     ~y1:r.y1 ~pix:img.Lui_raster.Image.pix ~stride))
             dirty;
         Lui_blit.present b;
         img.Lui_raster.Image.pix) }

(* Creation walks the Metal>GL>CPU ladder once; an SDL render-target/
   device reset event (0x2000/0x2001) or a render exception demotes the
   surface's active rung at runtime. The scene store is untouched, so
   the next repaint re-uploads a full scene to the new backend. A rung
   change may need a differently-flagged window (CPU blits cannot
   target an opengl window): the old window is destroyed and the new
   one mints a fresh windowID, so the surface is re-keyed in the
   registry — focus, iteration order and event routing all follow. *)
let rec demote (s : surf) reason =
  let d = s.driver in
  let dead = !(d.renderer_cell).Lui_host.name in
  (* The cell moves to noop first so a failing next rung still
     terminates the walk. *)
  warn "win=%d: renderer %s lost (%s); stepping down the ladder" d.idx
    dead reason;
  d.renderer_cell := noop_renderer;
  (match !(d.gctx_cell) with
   | Some c ->
     Sdl.gl_delete_context c;
     d.gctx_cell := None
   | None -> ());
  let next_gl = dead = "lui_metal" in
  if dead <> "noop" then begin
    Sdl.destroy_window d.sdl;
    d.sdl <-
      sdl_ok
        (Sdl.create_window "lui_window" ~w:!cfg.width ~h:!cfg.height
           (flags_for next_gl));
    ignore (Multi.rekey windows s.Multi.id (Sdl.get_window_id d.sdl))
  end;
  if next_gl then
    match Sdl.gl_create_context d.sdl with
    | Ok c -> (
      sdl_ok (Sdl.gl_make_current d.sdl c);
      match Lui_gl.init () with
      | Ok gl ->
        d.gctx_cell := Some c;
        d.gl_live_cell := true;
        d.renderer_cell := gl_renderer gl;
        log "win=%d: renderer lui_gl (recovered)" d.idx
      | Error msg ->
        warn "lui_gl.init failed: %s" msg;
        demote s "gl init failed")
    | Error (`Msg m) ->
      warn "gl_create_context failed: %s" m;
      demote s "gl context failed"
  else if dead = "lui_gl" || dead = "lui_raster+blit" then begin
    d.gl_live_cell := false;
    let dw, dh = drawable s in
    match Lui_blit.create d.sdl ~w:dw ~h:dh with
    | Ok b ->
      d.blit_cell := Some b;
      d.renderer_cell := cpu_renderer b;
      log "win=%d: renderer lui_raster+blit (recovered)" d.idx
    | Error m ->
      warn "lui_blit.create failed: %s" m;
      demote s "blit create failed"
  end

(* Builds one surface end to end: SDL window, renderer ladder, host
   hooks/text engine, app, a11y — the same wiring the single-window
   driver did, now per window, then registers it by SDL windowID.
   [idx] is the log/demo index; window [idx] 0 is primary (autofocus,
   synthetic drops). *)
let open_window ~title ~idx =
  let gl_flag = not !headless && not !use_cpu && not !prefer_metal in
  let win =
    ref
      (sdl_ok
         (Sdl.create_window title ~w:!cfg.width ~h:!cfg.height
            (flags_for gl_flag)))
  in
  (* Metal attempt — before any GL context. On failure the plain
     window is replaced by an opengl-flagged one and the GL path
     continues below. *)
  let metal =
    match !prefer_metal with
    | false -> None
    | true -> (
      match Lui_metal.init_window (Sdl.unsafe_ptr_of_window !win) with
      | Ok m -> Some m
      | Error e ->
        warn "lui_metal.init_window failed (%s); falling back to GL" e;
        Sdl.destroy_window !win;
        win :=
          sdl_ok
            (Sdl.create_window title ~w:!cfg.width ~h:!cfg.height
               (flags_for true));
        None)
  in
  (* The dummy driver cannot create a GL context at all; a real
     window without one is useless, so only headless continues. *)
  let gctx =
    if !use_cpu || Option.is_some metal then None
    else match Sdl.gl_create_context !win with
    | Ok c ->
      sdl_ok (Sdl.gl_make_current !win c);
      Some c
    | Error (`Msg m) ->
      if !headless then begin
        warn "gl_create_context failed (expected headless): %s" m;
        None
      end
      else failwith ("SDL: " ^ m)
  in
  let vsync =
    match gctx with
    | Some _ -> (match Sdl.gl_set_swap_interval 1 with
        | Ok () -> not !headless
        | Error _ -> false)
    | None -> false
  in
  let drawable_of w =
    match Sdl.gl_get_drawable_size w with
    | 0, 0 -> (!cfg.width, !cfg.height)
    | d -> d
  in
  let dw, dh = drawable_of !win in
  let scale = Float.max 0.01 (float dw /. float !cfg.width) in
  let renderer, gl_live, blit =
    match metal with
    | Some m ->
      log "renderer: lui_metal";
      (* Lui_metal.render encodes; present commits and blits to the
         layer drawable — called from inside the render callback like
         the CPU path's Lui_blit.present. *)
      ( { Lui_host.name = "lui_metal";
          render =
            (fun s ->
               Lui_metal.render m s;
               Lui_metal.present m;
               Bytes.empty) },
        false, None )
    | None ->
    if !use_cpu then begin
      match Lui_blit.create !win ~w:dw ~h:dh with
      | Error m ->
        warn "lui_blit.create failed: %s" m;
        (noop_renderer, false, None)
      | Ok b -> (cpu_renderer b, false, Some b)
    end
    else match gctx with
    | None ->
      warn "no GL context; using no-op loop renderer";
      (noop_renderer, false, None)
    | Some _ ->
    match Lui_gl.init () with
    | Ok gl ->
      log "renderer: Lui_gl (GL context %s)"
        (match Sdl.gl_get_attribute Sdl.Gl.context_major_version with
         | Ok v -> Printf.sprintf "%d.x" v
         | Error _ -> "?");
      (gl_renderer gl, true, None)
    | Error msg ->
      warn "lui_gl.init failed: %s" msg;
      warn "falling back to no-op loop renderer";
      (noop_renderer, false, None)
  in
  (* The host owns a stable renderer record whose render delegates to
     the live rung cell, so a demote needs no host rebuild. A render
     exception is treated as backend loss: demote, then replay the
     frame once. [surf_cell] exists because the demote path needs the
     registered surface while [renderer_live] is built before it. *)
  let renderer_cell = ref renderer
  and gl_live_cell = ref gl_live
  and blit_cell = ref blit
  and gctx_cell = ref gctx in
  let surf_cell = ref (None : surf option) in
  let renderer_live =
    { Lui_host.name = "lui (resilient)";
      render =
        (fun scene ->
           try (!(renderer_cell)).Lui_host.render scene
           with exn ->
             (match !surf_cell with
              | Some s -> demote s (Printexc.to_string exn)
              | None -> raise exn);
             (!(renderer_cell)).Lui_host.render scene) }
  in
  (* Wiring: mutable cells so the paint hooks can reach the host,
     scene and scale that only exist after Lui_host.create. *)
  let host_cell = ref None in
  let rects = Rects.create () in
  let ui = Ui.create () in
  Ui.set_scale ui scale;
  let scale_cell = ref scale in
  let text_engine =
    Lui_window_text.create
      ~scene:(fun () -> Lui_host.scene (Option.get !host_cell))
      ~scale:(fun () -> !scale_cell)
      ~store:(fun () -> Lui_host.store (Option.get !host_cell))
  in
  (* Rect lookups for paint and hit tests, all in device px.
     [engine_rect] is the flex engine's placement; a node shifts up by
     the scroll offsets of its scrollable ancestors; a scroll
     container's extent is the unshifted span of its descendants. *)
  let store_of () = Lui_host.store (Option.get !host_cell) in
  let engine_rect id =
    match !host_cell with
    | Some h ->
      Option.value ~default:Rects.zero (Lui_host.layout_rect h id)
    | None -> Rects.zero
  in
  let scroll_shift_of id =
    let rec sum aid (sx, sy) =
      match Lui_store.parent (store_of ()) aid with
      | Some p ->
        sum p
          (sx +. Ui.scroll_offset_x ui p, sy +. Ui.scroll_offset ui p)
      | None -> (sx, sy)
    in
    sum id (0., 0.)
  in
  let shifted_rect id =
    let r = engine_rect id in
    let sx, sy = scroll_shift_of id in
    { r with
      Lui_scene.x = r.Lui_scene.x -. sx;
      Lui_scene.y = r.Lui_scene.y -. sy }
  in
  let content_box id =
    List.fold_left
      (fun (l, t, rgt, b) d ->
         if d = id then (l, t, rgt, b)
         else
           let r = engine_rect d in
           (Float.min l r.Lui_scene.x,
            Float.min t r.Lui_scene.y,
            Float.max rgt (r.Lui_scene.x +. r.Lui_scene.w),
            Float.max b (r.Lui_scene.y +. r.Lui_scene.h)))
      (Float.max_float, Float.max_float,
       Float.min_float, Float.min_float)
      (Lui_store.preorder ~root:id (store_of ()))
  in
  let rect_intersect a b =
    let x = Float.max a.Lui_scene.x b.Lui_scene.x
    and y = Float.max a.Lui_scene.y b.Lui_scene.y in
    Lui_scene.rect x y
      (Float.max 0.
         (Float.min (a.Lui_scene.x +. a.Lui_scene.w)
            (b.Lui_scene.x +. b.Lui_scene.w)
          -. x))
      (Float.max 0.
         (Float.min (a.Lui_scene.y +. a.Lui_scene.h)
            (b.Lui_scene.y +. b.Lui_scene.h)
          -. y))
  in
  let hooks =
    Lui_paint.
      { color_of = Theme.color_of;
        layout =
          (fun id -> Lui_paint.placement_of_rect (shifted_rect id));
        state_of =
          (fun id ->
             match !host_cell with
             | Some h -> Ui.state_of ui (Lui_host.store h) id
             | None -> Lui_paint.state_neutral);
        scroll_of =
          (fun id ->
             let cap = Ui.scroll_cap ui id in
             if cap <= 0.001 then None
             else
               let cr = engine_rect id in
               let _, top, _, bot = content_box id in
               let content = Float.max (bot -. top) 0.001 in
               Some
                 Lui_paint.
                   { sm_offset = Ui.scroll_offset ui id /. cap;
                     sm_extent =
                       Float.min 1. (cr.Lui_scene.h /. content) });
        text_ops =
          (fun id r fg s ->
             let ops = Lui_window_text.text_ops text_engine id r fg s in
             let marked = Ui.marked ui in
             if marked = "" || id <> Ui.focused ui then ops
             else begin
               (* Composition overlay: marked text drawn underlined at
                  the caret of the focused field. It is paint-only —
                  never dispatched — and cleared the moment the
                  composition commits or cancels. When the node's
                  text prop is empty [s] is the placeholder: drop its
                  glyphs so the marked string paints alone. *)
               let caret =
                 min (Ui.caret ui) (String.length (Ui.shadow ui))
               in
               let ops =
                 let has_text =
                   match !host_cell with
                   | Some h -> (
                     match
                       Lui_store.prop (Lui_host.store h) id "text"
                     with
                     | Some (Lui_protocol.StringValue v) -> v <> ""
                     | _ -> false)
                   | None -> false
                 in
                 if has_text then ops else []
               in
               let dx, _ =
                 Lui_window_text.measure_text text_engine id
                   (String.sub (Ui.shadow ui) 0 caret)
               in
               let mw, mh =
                 Lui_window_text.measure_text text_engine id marked
               in
               let pad =
                 match !host_cell with
                 | Some h ->
                   (Lui_paint.text_placement_of (Lui_host.store h) id)
                     .tp_pad_x
                   *. !scale_cell
                 | None -> 0.
               in
               let underline =
                 Lui_scene.Fill
                   { frect =
                       Lui_scene.rect
                         (r.Lui_scene.x +. pad +. dx)
                         (r.Lui_scene.y
                          +. (r.Lui_scene.h +. mh) /. 2. -. 2.)
                         mw 2.;
                     fradii = (0., 0., 0., 0.); fcontinuous = false;
                     fcolor = fg; fpaint = Lui_scene.Solid; fcolor2 = fg;
                     fgradient = (0., 0., 0., 0.);
                     fborder = (0., 0., 0., 0.);
                     fborder_color = Lui_scene.color 0 0 0 0;
                     fdashed = false; fwide = 0; fopacity = 1. }
               in
               let mr = { r with Lui_scene.x = r.Lui_scene.x +. dx } in
               ops @ [ underline ]
                 @ Lui_window_text.text_ops text_engine id mr fg marked
             end);
        image_of = (fun _ -> None);
        image_in = (fun _ _ -> None);
        shadow_of = Lui_paint.parse_shadows Theme.color_of }
  in
  let host =
    Lui_host.create ~hooks ~layout:(module Lui_layout)
      (* Measure the text the engine selected (label/title/text per
         kind) plus the placement padding it will paint around it —
         feeding the raw glyph metric collapses every labeled control
         to bare-text size (buttons, fields, kbd...). *)
      ~measure:(fun id text _w _h ->
        let w, h = Lui_window_text.measure_text text_engine id text in
        let tp = Lui_paint.text_placement_of (text_engine.store ()) id in
        let s = text_engine.scale () in
        Some
          (w +. (2. *. tp.tp_pad_x *. s), h +. (2. *. tp.tp_pad_y *. s)))
      ~renderer:renderer_live ~width:dw ~height:dh ~scale ()
  in
  host_cell := Some host;
  let store = Lui_host.store host in
  (* Trigger-owned menu panels stay hidden until opened; the predicate
     reads the interaction state's mutable open-menu slot each sync. *)
  Lui_host.set_hidden host (Some (fun id -> Ui.hidden ui store id));
  (* Unanchored context menus open at the pointer. The anchor feeds
     [refine_popups] only while a context-menu is open — reporting the
     live pointer position unconditionally would defeat the layout
     memo on every pointer-driven repaint, so the accessor returns
     [None] the rest of the time. *)
  Lui_host.set_ctx_anchor host
    (Some
       (fun () ->
          match Ui.open_menu ui with
          | 0 -> None
          | id when Lui_store.kind store id = "context-menu" ->
            Some (Ui.pointer ui)
          | _ -> None));
  (* Populate the hit-test mirror from the layout engine: each node's
     shifted rect clipped to its scrollable ancestors' viewports (so
     scrolled-off content can't be hit), then each scroll container's
     range on both axes from its unshifted content extent. Runs after
     every repaint while the engine is fresh. *)
  let populate () =
    Hashtbl.reset rects;
    List.iter
      (fun id ->
         let base = engine_rect id in
         let rec walk aid ((sx, sy), clip) =
           match Lui_store.parent store aid with
           | None -> ((sx, sy), clip)
           | Some p ->
             let clip =
               if Ui.scrollable store p then
                 match Hashtbl.find_opt rects p with
                 | Some pr when not (Lui_scene.rect_empty pr) ->
                   rect_intersect clip pr
                 | _ -> clip
               else clip
             in
             walk p
               ((sx +. Ui.scroll_offset_x ui p,
                 sy +. Ui.scroll_offset ui p), clip)
         in
         let (sx, sy), clip = walk id ((0., 0.), base) in
         let r =
           { base with
             Lui_scene.x = base.Lui_scene.x -. sx;
             Lui_scene.y = base.Lui_scene.y -. sy }
         in
         Hashtbl.replace rects id (rect_intersect r clip))
      (Lui_store.preorder store);
    List.iter
      (fun id ->
         if Ui.scrollable store id then
           let cr = engine_rect id in
           let l, t, rgt, b = content_box id in
           Ui.set_scroll_cap ui id
             (Float.max 0. (b -. t -. cr.Lui_scene.h));
           Ui.set_scroll_cap_x ui id
             (Float.max 0. (rgt -. l -. cr.Lui_scene.w)))
      (Lui_store.preorder store)
  in
  let backend =
    Lui_host.backend host
      (Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  (* A second window should not look like a clone: cycle each extra
     window onto a different demo tab (deterministic, so the headless
     checksum stays stable). *)
  if idx > 0 then
    ignore
      (Lui_app.send app
         (Demo_app.Tab
            (match idx mod 4 with
             | 0 -> Demo_app.Lists
             | 1 -> Demo_app.Overlays
             | 2 -> Demo_app.Deco
             | _ -> Demo_app.Controls)));
  (* Priming paint: syncs the flex engine and renders once so the
     hit-test mirror and scroll caps below see real rects. *)
  ignore (Lui_host.repaint host);
  populate ();
  (* Ui driver hooks: real glyph measurement for caret/selection math,
     unshifted engine rects for scroll_show/visible-range. *)
  Ui.set_measure ui
    (fun _store id s -> Lui_window_text.measure_text text_engine id s);
  Ui.set_hit_text ui
    (fun _store id text ~lx ~ly ~lw ~lh ->
       Lui_window_text.hit_text text_engine id text ~lx ~ly ~lw ~lh);
  Ui.set_content_rect ui engine_rect;
  (* The a11y forest mirrors the store: synced after every repaint,
     focused along with the Ui focus, dumped on request and at quit. *)
  let a11y = Lui_a11y.of_store store in
  (* Caret rect of the focused field, device px: the node's layout
     rect shifted to the caret column — horizontal padding plus the
     width of the text up to the caret. This is the candidate-window
     anchor while composing. *)
  let caret_rect () =
    let id = Ui.focused ui in
    let r = Rects.get rects id in
    if Lui_scene.rect_empty r then r
    else begin
      let s = !scale_cell in
      (* Same content inset the text engine applies, so the caret lands
         where the ink starts. *)
      let pad =
        (Lui_paint.text_placement_of store id).tp_pad_x *. s
      in
      let text = Ui.shadow ui in
      let prefix =
        String.sub text 0 (min (Ui.caret ui) (String.length text))
      in
      let dx, _ = Lui_window_text.measure_text text_engine id prefix in
      Lui_scene.rect (r.Lui_scene.x +. pad +. dx) r.Lui_scene.y 2.
        r.Lui_scene.h
    end
  in
  (* Hand focus to the first autofocus field — primary window only,
     secondary windows start unfocused. *)
  if idx = 0 then
    (match
       List.find_opt
         (fun id -> bool_prop store id "autofocus")
         (Lui_store.preorder store)
     with
     | Some id ->
       Ui.set_focused ui store id;
       Sdl.start_text_input ()
     | None -> ());
  let id = Sdl.get_window_id !win in
  let d =
    { sdl = !win; gctx_cell; gl_live_cell; vsync; blit_cell; metal;
      renderer_cell; app; a11y; drop_seen = 0; toast_since = None;
      reqs_seen = Hashtbl.create 8; checksum = Checksum.create ();
      frame = 0;
      stats = { frames = 0; acc_ms = 0.; min_ms = 1e9; max_ms = 0. };
      idx; populate; caret_rect }
  in
  let s =
    Multi.make_surface ~id ~host ~driver:d ~ui ~rects ~scale_cell
      ~w:!cfg.width ~h:!cfg.height
  in
  Multi.register windows s;
  surf_cell := Some s;
  (match Sdl.get_window_display_index !win with
   | Ok di -> s.Multi.display <- di
   | Error _ -> ());
  log "lui_window[%d]: %dx%d drawable (scale %.2f), renderer=%s%s"
    idx dw dh scale (!(renderer_cell)).Lui_host.name
    (if !headless then " [headless]" else "");
  (* The renderer badge: static here, updated with fps once a second
     in the loop. *)
  if not !headless then
    ignore
      (Lui_app.send app
         (Demo_app.Badge (!(renderer_cell)).Lui_host.name));
  s

(* ---------- event routing ---------- *)

(* The SDL windowID an event belongs to; None = process-global. *)
let window_id_of e =
  match Sdl.Event.enum (Sdl.Event.get e Sdl.Event.typ) with
  | `Key_down | `Key_up -> Some (Sdl.Event.get e Sdl.Event.keyboard_window_id)
  | `Text_input -> Some (Sdl.Event.get e Sdl.Event.text_input_window_id)
  | `Text_editing ->
    Some (Sdl.Event.get e Sdl.Event.text_editing_window_id)
  | `Mouse_motion ->
    Some (Sdl.Event.get e Sdl.Event.mouse_motion_window_id)
  | `Mouse_button_down | `Mouse_button_up ->
    Some (Sdl.Event.get e Sdl.Event.mouse_button_window_id)
  | `Mouse_wheel -> Some (Sdl.Event.get e Sdl.Event.mouse_wheel_window_id)
  | `Drop_file | `Drop_text | `Drop_begin | `Drop_complete ->
    Some (Sdl.Event.get e Sdl.Event.drop_window_id)
  | `Window_event -> Some (Sdl.Event.get e Sdl.Event.window_window_id)
  | _ -> None

(* Window lifecycle, routed by windowID: logical resize feeds the
   window's Ui (which emits Resize_host, applied against the real
   drawable), moves re-query the backing scale (monitor crossing),
   focus updates the registry's focused window, close destroys just
   that surface. *)
let handle_window_event e =
  let id = Sdl.Event.get e Sdl.Event.window_window_id in
  match Multi.find windows id with
  | None -> ()
  | Some s ->
    (match
       Sdl.Event.window_event_enum
         (Sdl.Event.get e Sdl.Event.window_event_id)
     with
     | `Resized | `Size_changed ->
       let w = Int32.to_int (Sdl.Event.get e Sdl.Event.window_data1)
       and h = Int32.to_int (Sdl.Event.get e Sdl.Event.window_data2) in
       Multi.apply_logical_size s ~w ~h;
       apply_actions s (Multi.dispatch s (Input.Resize (w, h)))
     | `Moved -> refresh_scale s
     | `Close -> close_window id
     | `Focus_gained -> Multi.set_focused windows id
     | `Focus_lost ->
       if Multi.focused windows = id then Multi.clear_focus windows
     | `Take_focus -> focus_window id
     | _ -> ())

let drain_events e =
  (* Shell-queued model actions go to the focused window (falling back
     to the first, e.g. headless where no focus events arrive). *)
  (match Multi.find_focused windows with
   | Some s ->
     Queue.iter (fun a -> ignore (Lui_app.send s.driver.app a)) pending
   | None -> ());
  Queue.clear pending;
  let go = ref true in
  while !go do
    if Sdl.poll_event (Some e) then begin
      let typ = Sdl.Event.get e Sdl.Event.typ in
      (* SDL_RENDER_TARGETS_RESET / SDL_RENDER_DEVICE_RESET: the GPU
         device is shared across windows, so a reset demotes every
         surface down the ladder. *)
      if typ = 0x2000 || typ = 0x2001 then
        Multi.iter windows (fun s -> demote s "SDL render reset")
      else
      match Sdl.Event.enum typ with
      | `Quit -> quit := true
      | `Window_event -> handle_window_event e
      | `Display_event ->
        (* Hotplug / mode change: re-query every window's drawable —
           cheap, and only windows that actually changed respond. *)
        Multi.iter windows refresh_scale
      | _ ->
        let target =
          match window_id_of e with
          | Some id -> Multi.find windows id
          | None -> Multi.find_focused windows
        in
        (match target, input_of_event e with
         | Some s, Some input ->
           apply_actions s (Multi.dispatch s input)
         | _ -> ())
      end
    else go := false
  done

(* ---------- shell integration (interactive, process-wide) ---------- *)

let setup_shell () =
  Lui_shell.set_app_name "lui_window";
  ignore (Lui_shell.set_window_title "lui_window — native demo");
  let item = Lui_shell.status_item_create ~tag:1 () in
  Lui_shell.status_item_set_title item "LUI";
  let spec label id =
    Lui_shell.Item
      { Lui_shell.label = label; Lui_shell.id = id;
        enabled = true; checked = false } in
  Lui_shell.status_item_set_menu item
    (Some
       (Lui_shell.menu ~title:"lui_window"
          [ spec "show toast" 1;
            spec "notify" 2;
            spec "copy stats" 3;
            spec "dump a11y" 4;
            Lui_shell.Separator;
            spec "quit" 9 ]));
  Lui_shell.set_menu_handler
    (Some
       (fun id ->
          match id with
          | 1 -> Queue.add (Demo_app.Open Demo_app.P_toast) pending
          | 2 -> Queue.add Demo_app.Req_notify pending
          | 3 -> Queue.add Demo_app.Req_clipboard pending
          | 4 -> Queue.add Demo_app.Req_a11y pending
          | 9 -> quit := true
          | _ -> ()))

(* ---------- main ---------- *)

let () =
  match parse_args (List.tl (Array.to_list Sys.argv)) with
  | Error msg ->
    warn "%s\nusage: lui_window [--width N] [--height N] [--headless N] [--windows N] [--drop-file PATH]"
      msg;
    exit 2
  | Ok c ->
  cfg := c;
  headless := Option.is_some c.headless_frames;
  if !headless then Unix.putenv "SDL_VIDEODRIVER" "dummy";
  (* Renderer selection on macOS: Metal is preferred, GL on request
     (LUI_GPU=gl|opengl) or as fallback, CPU on LUI_GPU=0|cpu. *)
  let env = try Sys.getenv "LUI_GPU" with Not_found -> "" in
  use_cpu := env = "0" || env = "cpu";
  prefer_metal :=
    not !headless && not !use_cpu && env <> "gl" && env <> "opengl";
  sdl_ok (Sdl.init Sdl.Init.(video + events));
  (* GL context requirements from lui_gl.mli: OpenGL 3.3 core,
     double-buffered. Attributes are hints — SDL may refuse or
     substitute, in which case Lui_gl.init fails and the no-op
     renderer exercises the loop instead. *)
  sdl_ok (Sdl.gl_set_attribute Sdl.Gl.context_major_version 3);
  sdl_ok (Sdl.gl_set_attribute Sdl.Gl.context_minor_version 3);
  sdl_ok
    (Sdl.gl_set_attribute Sdl.Gl.context_profile_mask
       Sdl.Gl.context_profile_core);
  sdl_ok (Sdl.gl_set_attribute Sdl.Gl.doublebuffer 1);
  (* The dummy video driver refuses an OpenGL window entirely, the
     CPU path does not need one, and Metal attaches its own layer to
     a plain window — the opengl flag is only set when a GL context
     will actually be created. *)
  for i = 0 to c.windows - 1 do
    ignore
      (open_window
         ~title:(if i = 0 then "lui_window"
                 else Printf.sprintf "lui_window %d" (i + 1))
         ~idx:i)
  done;
  if not !headless then setup_shell ();
  frames_target := c.headless_frames;
  let e = Sdl.Event.create () in
  let continue () =
    (not !quit)
    && (match !frames_target with
        | Some n ->
          (* Run until the slowest window reached the target. *)
          let m = ref max_int in
          Multi.iter windows (fun s -> m := min !m s.driver.frame);
          !m < n
        | None -> Multi.count windows > 0)
  in
  while continue () do
    let t0 = perf_s () in
    drain_events e;
    (* Synthetic drop injection fires once rects exist (iteration 1
       populated them): the pointer is moved onto the well first,
       matching where a real SDL drop would land. Multi-window runs
       additionally route a Tab into the LAST window — a deterministic
       input that proves per-window routing and diverges its scene. *)
    if !headless && !iter_no = 1 then begin
      (match Multi.first windows with
       | Some s -> inject_drops s
       | None -> ());
      if c.windows > 1 then
        match Multi.last windows with
        | Some s ->
          apply_actions s
            (Multi.dispatch s
               (Input.Key_down (Input.Tab, Input.mods_none, false)))
        | None -> ()
    end;
    let dirty_any = ref false in
    Multi.iter windows (fun s -> if tick s ~t0 then dirty_any := true);
    incr iter_no;
    (* No vsync under the dummy driver and possibly none elsewhere:
       pace the loop explicitly. An idle iteration (no repaint) also
       sleeps briefly so the poll loop does not spin at 100% CPU. *)
    if not !headless then begin
      let any_vsync = Multi.any windows (fun s -> s.driver.vsync) in
      if !dirty_any && not any_vsync then begin
        let remaining = 16.6 -. ((perf_s () -. t0) *. 1000.) in
        if remaining > 0.5 then
          Sdl.delay (Int32.of_int (int_of_float remaining))
      end
      else if not !dirty_any then Sdl.delay 4l
    end
  done;
  Multi.iter windows (fun s ->
      stats_report s.driver.stats
        (!(s.driver.renderer_cell)).Lui_host.name;
      log "win=%d a11y: %d nodes" s.driver.idx
        (Lui_a11y.node_count s.driver.a11y));
  (match !frames_target with
   | Some _ ->
     if c.windows = 1 then
       (match Multi.first windows with
        | Some s ->
          log "headless done: frames=%d checksum=%016Lx" s.driver.frame
            (Checksum.value s.driver.checksum)
        | None -> ())
     else
       Multi.iter windows (fun s ->
           log "win=%d done: frames=%d checksum=%016Lx" s.driver.idx
             s.driver.frame (Checksum.value s.driver.checksum))
   | None -> ());
  (* Tear down every surface, then SDL. Collect the ids first since
     [close_window] mutates the registry while iterating. *)
  let ids = ref [] in
  Multi.iter windows (fun s -> ids := s.Multi.id :: !ids);
  List.iter close_window !ids;
  Sdl.quit ()
