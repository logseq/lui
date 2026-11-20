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

module Sdl = Lui_sdl3

let log fmt = Printf.printf (fmt ^^ "\n%!")
let warn fmt = Printf.eprintf (fmt ^^ "\n%!")

let sdl_ok = function
  | Ok v -> v
  | Error (`Msg m) -> failwith ("SDL: " ^ m)

let frame_stats = Sys.getenv_opt "LUI_FRAME_STATS" = Some "1"

let perf_s () =
  Int64.to_float (Sdl.get_performance_counter ())
  /. Int64.to_float (Sdl.get_performance_frequency ())

let profile_layout_ms = ref 0.
let profile_encode_ms = ref 0.
let profile_present_ms = ref 0.

module Profiled_layout = struct
  include Lui_layout
  let sync ?scale ?measure ?text_flow ?image_measure ?hidden ?ctx_anchor ?vport ?anchor_shift ~width ~height t store =
    if not frame_stats then
      Lui_layout.sync ?scale ?measure ?text_flow ?image_measure ?hidden ?ctx_anchor ?vport ?anchor_shift ~width ~height t store
    else begin
      let start = perf_s () in
      Lui_layout.sync ?scale ?measure ?text_flow ?image_measure ?hidden ?ctx_anchor ?vport ?anchor_shift ~width ~height t store;
      profile_layout_ms := !profile_layout_ms +. (perf_s () -. start) *. 1000.
    end
end

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
  match (Sdl.Event.value e).kind with
  | Sdl.Event.Quit -> Some Quit_input
  | Window (Resized, w, h) -> Some (Resize (w, h))
  | Window (Close_requested, _, _) -> Some Quit_input
  | Key_down key -> Some (Key_down (Input.key_of_sdl_scancode key.scancode,
                                   mods_of_keymod key.keymod, key.repeat))
  | Text_input text -> Some (Text_input text)
  | Text_editing (text, start, length) -> Some (Text_editing (text, start, length))
  | Mouse_motion motion -> Some (Move (motion.x, motion.y))
  | Mouse_button_down button ->
    Some (Button_down (button.x, button.y, Input.button_of_sdl button.button,
                       button.clicks, mods_of_keymod (Sdl.get_mod_state ())))
  | Mouse_button_up button ->
    Some (Button_up (button.x, button.y, Input.button_of_sdl button.button,
                     mods_of_keymod (Sdl.get_mod_state ())))
  | Mouse_wheel (x, y) -> Some (Wheel_mods (x, y, mods_of_keymod (Sdl.get_mod_state ())))
  | Drop_file file -> Some (Drop_file file)
  | Drop_text text -> Some (Drop_text text)
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
    log "stats: frames=%d frame_ms=%.2f (min %.2f max %.2f) renderer=%s"
      st.frames avg st.min_ms st.max_ms
      renderer_name;
    st.frames <- 0;
    st.acc_ms <- 0.;
    st.min_ms <- 1e9;
    st.max_ms <- 0.
  end

(* ---------- driver state per window ---------- *)

(* Everything the loop needs per window beyond the pure state kept in
   [Multi.surface]: the OS window/context/renderer handles, the shared
   host assembly and the IME anchor closure the pipeline built during
   setup. The backend pieces are cells because a renderer demote swaps
   them live: it drops the GL context, recreates the window (which
   also re-keys the surface — [Multi.rekey]) and installs the next
   rung's renderer. *)
type drv = {
  mutable sdl : Sdl.window;
  gctx_cell : Sdl.gl_context option ref;
  gl_live_cell : bool ref;
  vsync : bool;
  blit_cell : Lui_blit.t option ref;
  popups : Lui_blit.Popups.t;
  mutable metal : Lui_metal.t option;
  mutable display_link : bool;
  renderer_cell : Lui_host.renderer ref;
  app : (Demo_app.model, Demo_app.action) Lui_app.reducer_app;
  a11y : Lui_a11y.t;
  mutable drop_seen : int;
  reqs_seen : (string, int) Hashtbl.t;
  checksum : Checksum.t;
  mutable frame : int;
  stats : stats;
  presentations : Presentation_meter.t option;
  idx : int;                   (* registry/log index, 0-based *)
  sched : Frame.t;             (* frame scheduler: dirty → deadline → present *)
  asm : Assembly.t;            (* shared host assembly *)
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
  match Sdl.get_window_size_in_pixels s.driver.sdl with
  | 0, 0 -> (s.Multi.logical_w, s.Multi.logical_h)
  | d -> d

let set_ime_rect (s : surf) (r : Lui_scene.rect) =
  let sc = Multi.scale s in
  let field = Rects.get s.Multi.rects (Ui.focused s.Multi.ui) in
  let x = int_of_float (Float.min field.Lui_scene.x r.Lui_scene.x /. sc) in
  let cursor = int_of_float (r.Lui_scene.x /. sc) - x in
  Sdl.set_text_input_area s.driver.sdl
    (Some
       (Sdl.Rect.create
          ~x
          ~y:(int_of_float (r.Lui_scene.y /. sc))
          ~w:(max (cursor + 1) (int_of_float (field.Lui_scene.w /. sc)))
          ~h:(max 1 (int_of_float (r.Lui_scene.h /. sc)))))
    ~cursor

let start_ime window store id =
  let kind = kind_name store id in
  if Sdl.is_text_input_active window then Sdl.stop_text_input window;
  Sdl.start_text_input ~multiline:(kind = "textarea") ~secure:(kind = "secure-field") window

(* Re-read a window's drawable size and backing scale: on [Moved] the
   window may have crossed onto a monitor with a different scale, on
   display events anything may have changed. Cheap and idempotent —
   [apply_drawable] only acts when the values differ. *)
(* The monitor's reported refresh rate for the display a surface sits
   on; 0 when the OS declines to say (the scheduler keeps its previous
   rate then — [Frame.set_refresh_hz] ignores non-positive input). *)
let refresh_hz_of (s : surf) =
  if s.Multi.display <= 0 then 0.
  else
    match Sdl.display_refresh_rate s.Multi.display with
    | Ok hz -> hz
    | Error _ -> 0.

let update_display_link d =
  Option.iter (fun metal ->
    let hz = max 1 (int_of_float (Float.round (Frame.refresh_hz d.sched))) in
    d.display_link <-
      try Lui_metal.set_frame_rate metal hz; true
      with Failure _ -> false) d.metal

let refresh_scale (s : surf) =
  (match Sdl.get_window_display_id s.driver.sdl with
   | Ok di when di <> s.Multi.display -> s.Multi.display <- di
   | _ -> ());
  let sched = s.driver.sched in
  let previous = Frame.refresh_hz sched in
  Frame.set_refresh_hz sched (refresh_hz_of s);
  if Frame.refresh_hz sched <> previous then update_display_link s.driver;
  let dw, dh = drawable s in
  if Multi.apply_drawable s ~dw ~dh then
    log "win=%d: drawable %dx%d scale %.2f (display %d)" s.driver.idx
      dw dh (Multi.scale s) s.Multi.display

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
        (* SDL3 text input belongs to this window, independently of other
           windows' focused fields. *)
        if id = 0 then Sdl.stop_text_input d.sdl
        else begin
          start_ime d.sdl (Assembly.store d.asm) id;
          set_ime_rect s (d.caret_rect ())
        end
      | Ime_rect r -> set_ime_rect s r
      | Quit -> quit := true)
    acts

(* Public window ops: open/close/focus — the [open_window] path lives
   further down since it needs the full pipeline setup. *)
let close_window id =
  match Multi.unregister windows id with
  | None -> ()
  | Some s ->
    Lui_blit.Popups.clear s.driver.popups;
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
       | l -> Some (string_of_int (List.length l)))
  end

(* One frame-callback for one window: flush queued patches, run
   store-driven effects, poll model-driven side effects, refresh the
   IME anchor — then the scheduler decides whether the surface
   presents, waits for its pacing deadline or stays idle. Mutations
   only mark the frame dirty; nothing draws until [Frame.poll] says
   [Present]. Returns the scheduler's decision so the loop can sleep
   until the nearest deadline. *)
let tick ?(live_resize = false) (s : surf) ~t0 =
  let d = s.driver in
  let now_s = perf_s () in
  let now_ms = now_s *. 1000. in
  ignore (Lui_app.tick_clock d.app ~now:now_ms);
  Lui_host.tick s.host ~now:now_s;
  ignore (Lui_resource.drain_all ());
  (match d.metal, d.presentations with
   | Some metal, Some meter when not !headless ->
     let displayed_frames = Lui_metal.presented_frames metal in
     (match Presentation_meter.sample meter ~now_ms:(t0 *. 1000.) ~displayed_frames with
      | None -> ()
      | Some fps ->
        log "display_stats: time_s=%.6f displayed_frames=%d fps=%.2f"
          t0 displayed_frames fps;
        ignore (Lui_app.send d.app
          (Demo_app.Badge (Printf.sprintf "%s — %.0f fps"
            (!(d.renderer_cell)).Lui_host.name fps))))
   | _ -> ());
  profile_layout_ms := 0.;
  profile_encode_ms := 0.;
  profile_present_ms := 0.;
  let allocation_before = if frame_stats then
    Some (Gc.allocated_bytes (), (Gc.quick_stat ()).minor_collections) else None in
  let store = Lui_host.store s.host in
  Ui.tick_scrollbars s.ui ~now_ms;
  ignore (Lui_app.flush d.app);
  apply_actions s (Ui.store_changed s.ui store);
  (* Effects can dispatch back into the app — flush once more so the
     patches they produced land in this same frame instead of waiting
     for the next wake-up. *)
  ignore (Lui_app.flush d.app);
  poll_driver s;
  poll_drop s;
  ignore (Lui_app.flush d.app);
  (* Report the caret once per frame: while a composition is open
     the state machine emits Ime_rect on movement so the candidate
     window tracks the caret; idle, the rect is only remembered. *)
  if Ui.focused s.Multi.ui <> 0 then
    apply_actions s (Multi.dispatch s (Input.Caret (d.caret_rect ())));
  (* Headless proves the loop: force a repaint every iteration so
     the frame counter and checksum actually run. *)
  if !headless || Ui.want_frame s.ui s.host then
    Frame.request_frame d.sched;
  let decision =
    let now_ms = perf_s () *. 1000. in
    if !headless || live_resize then Frame.Present
    else match d.metal with
      | Some metal when d.display_link && Frame.visibility d.sched = Frame.Shown ->
        Frame.poll_display_link d.sched ~now_ms
          ~ready:(fun () -> Lui_metal.request_frame_tick metal)
      | _ -> Frame.poll d.sched ~now_ms ~vsync:d.vsync
  in
  (match decision with
   | Frame.Present ->
     (* Assembly.repaint repaints and refreshes the hit-test mirror *)
     (* populate's anchor-drift corrections surface as VisibleRange
        dispatches — apply them like any other Ui action *)
     let repaint_start = perf_s () in
     apply_actions s (snd (Assembly.repaint s.driver.asm));
     let repaint_ms = (perf_s () -. repaint_start) *. 1000. in
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
     let frame_ms = (perf_s () -. t0) *. 1000. in
     stats_update d.stats frame_ms;
     (match allocation_before with
      | None -> ()
      | Some (before, collections) ->
        let after = Gc.quick_stat () in
        log "frame_stats: frame=%d time_s=%.6f cpu_ms=%.3f repaint_ms=%.3f allocated_bytes=%.0f minor_gc=%d ops=%d layout_ms=%.3f encode_ms=%.3f present_ms=%.3f"
          d.frame (perf_s ()) frame_ms repaint_ms
          (Gc.allocated_bytes () -. before)
          (after.minor_collections - collections)
          (List.length (Lui_host.scene s.host).Lui_scene.ops)
          !profile_layout_ms !profile_encode_ms !profile_present_ms);
     Frame.presented d.sched ~now_ms:(perf_s () *. 1000.);
     if d.frame mod 60 = 0 then begin
       stats_report d.stats (!(d.renderer_cell)).Lui_host.name
     end
   | Frame.Wait_ms _ | Frame.Idle -> ());
  decision


(* ---------- window creation ---------- *)

let flags_for gl =
  let base = Sdl.Window.(resizable + high_pixel_density) in
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
  if next_gl then begin
    Option.iter Lui_metal.release d.metal;
    d.metal <- None;
    d.display_link <- false
  end;
  if dead <> "noop" then begin
    Lui_blit.Popups.clear d.popups;
    Lui_host.invalidate_paint s.host;
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
    match Sdl.get_window_size_in_pixels w with
    | 0, 0 -> (!cfg.width, !cfg.height)
    | d -> d
  in
  let dw, dh = drawable_of !win in
  let scale = Float.max 0.01 (float dw /. float !cfg.width) in
  let renderer, gl_live, blit =
    match metal with
    | Some m ->
      log "renderer: lui_metal";
      (* Window frames encode directly into a drawable on the renderer's
         queue. This synchronous driver waits at presentation; hosts
         handling input independently use present_async. *)
      ( { Lui_host.name = "lui_metal";
          render =
            (fun s ->
               if not frame_stats then begin
                 Lui_metal.render m s;
                 Lui_metal.present m
               end else begin
                 let start = perf_s () in
                 Lui_metal.render m s;
                 let present_start = perf_s () in
                 Lui_metal.present m;
                 profile_encode_ms := !profile_encode_ms +. (present_start -. start) *. 1000.;
                 profile_present_ms := !profile_present_ms +. (perf_s () -. present_start) *. 1000.
               end;
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
  (* Shared host assembly: hooks, the real layout engine, the
     scroll-shifted hit-test mirror and the scroll caps are all wired
     by [Lui_window.Assembly] — the same code Linux and Windows run,
     so every platform paints, scrolls and hit-tests identically.
     The text engine's scene/store accessors are cell-reads because it
     must exist before the assembly hands the host back. *)
  let scale_cell = ref scale in
  let host_cell = ref None in
  let text_engine =
    Lui_window_text.create
      ~scene:(fun () -> Lui_host.scene (Option.get !host_cell))
      ~scale:(fun () -> !scale_cell)
      ~store:(fun () -> Lui_host.store (Option.get !host_cell))
  in
  let asm =
    Assembly.create ~layout:(module Profiled_layout) ~scale_cell
      ~text:
        Assembly.
          { measure = Lui_window_text.measure_text text_engine;
            text_ops = Lui_window_text.text_ops text_engine;
            hit_text = Lui_window_text.hit_text text_engine;
            caret_ops = Lui_window_text.caret_ops text_engine }
      ~renderer:renderer_live ~width:dw ~height:dh ()
  in
  host_cell := Some (Assembly.host asm);
  let host = Assembly.host asm
  and ui = Assembly.ui asm
  and rects = Assembly.rects asm
  and store = Assembly.store asm in
  let backend =
    Assembly.backend asm
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
     hit-test mirror and scroll caps see real rects. *)
  ignore (Assembly.repaint asm);
  (* The a11y forest mirrors the store: synced after every repaint,
     focused along with the Ui focus, dumped on request and at quit. *)
  let a11y = Lui_a11y.of_store store in
  (* Caret rect of the focused field, device px — the candidate-window
     anchor while composing. *)
  let caret_rect () = Assembly.caret_rect asm in
  (* Hand focus to the first autofocus field — primary window only,
     secondary windows start unfocused. *)
  if idx = 0 then
    (match Assembly.first_autofocus asm with
     | Some id ->
       Ui.set_focused ui store id;
       start_ime !win store id
     | None -> ());
  let id = Sdl.get_window_id !win in
  let d =
    { sdl = !win; gctx_cell; gl_live_cell; vsync; blit_cell; metal;
      display_link = false;
      popups = Lui_blit.Popups.create ();
      renderer_cell; app; a11y; drop_seen = 0;
      reqs_seen = Hashtbl.create 8; checksum = Checksum.create ();
      frame = 0;
      stats = { frames = 0; acc_ms = 0.; min_ms = 1e9; max_ms = 0. };
      presentations = Option.map (fun m -> Presentation_meter.create
        ~now_ms:(perf_s () *. 1000.)
        ~displayed_frames:(Lui_metal.presented_frames m)) metal;
      idx; sched = Frame.create (); asm; caret_rect }
  in
  if not !headless then
    Lui_host.set_popup_presenter host (Some
      ((fun id kind (r : Lui_scene.rect) scene ->
        Lui_blit.Popups.present d.popups ~parent:d.sdl ~id
          ~tooltip:(kind = "tooltip") ~scale:!scale_cell
          ~rect:(r.x, r.y, r.w, r.h) (fun () ->
            let img = Lui_raster.render ~scene:(scene ()) () in
            img.pix, img.stride / 4)),
       (fun () -> Lui_blit.Popups.finish d.popups)));
  let s =
    Multi.make_surface ~id ~host ~driver:d ~ui ~rects ~scale_cell
      ~w:!cfg.width ~h:!cfg.height
  in
  Multi.register windows s;
  surf_cell := Some s;
  if Ui.focused ui <> 0 then set_ime_rect s (caret_rect ());
  (match Sdl.get_window_display_id !win with
   | Ok di -> s.Multi.display <- di
   | Error _ -> ());
  Frame.set_refresh_hz d.sched (refresh_hz_of s);
  update_display_link d;
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
  let id = (Sdl.Event.value e).window_id in
  if id = 0 then None else Some id

(* Window lifecycle, routed by windowID: logical resize feeds the
   window's Ui (which emits Resize_host, applied against the real
   drawable), moves re-query the backing scale (monitor crossing),
   focus updates the registry's focused window, close destroys just
   that surface. *)
let handle_window_event e =
  let event = Sdl.Event.value e in
  match Multi.find windows event.window_id, event.kind with
  | Some s, Sdl.Event.Window (change, w, h) ->
    let id = event.window_id in
    (match change with
     | Resized ->
       Multi.apply_logical_size s ~w ~h;
       apply_actions s (Multi.dispatch s (Input.Resize (w, h)))
     | Pixel_size_changed | Display_scale_changed | Display_changed | Moved -> refresh_scale s
     | Close_requested -> close_window id
     | Hidden -> Frame.set_visibility s.driver.sched Frame.Hidden
     | Minimized -> Frame.set_visibility s.driver.sched Frame.Minimized
     | Shown | Restored -> Frame.set_visibility s.driver.sched Frame.Shown
     | Exposed -> Frame.request_frame s.driver.sched
     | Focus_gained -> Multi.set_focused windows id
     | Focus_lost -> if Multi.focused windows = id then Multi.clear_focus windows
     | Other_window _ -> ())
  | _ -> ()

(* One SDL event, routed: process-global events apply everywhere,
   window-tagged events go to their surface. An event that woke a
   [Sdl.wait_event_timeout] sleep goes through here too — a wake is
   just a slower first poll. *)
let handle_sdl_event e =
  match (Sdl.Event.value e).kind with
  | Sdl.Event.Render_reset -> Multi.iter windows (fun s -> demote s "SDL render reset")
  | Quit -> quit := true
  | Window _ -> handle_window_event e
  | Display_changed -> Multi.iter windows refresh_scale
  | _ ->
    let target, e = match window_id_of e with
      | Some id -> (match Multi.find windows id with
          | Some s -> Some s, e
          | None ->
            let routed = ref (None, e) in
            Multi.iter windows (fun s ->
              Option.iter (fun e -> routed := Some s, e)
                (Lui_blit.Popups.route s.driver.popups e));
            !routed)
      | None -> Multi.find_focused windows, e in
    (match target, input_of_event e with
     | Some s, Some input ->
       Ui.tick_scrollbars s.ui ~now_ms:(perf_s () *. 1000.);
       apply_actions s (Multi.dispatch s input)
     | _ -> ())

let drain_events e =
  (* Shell-queued model actions go to the focused window (falling back
     to the first, e.g. headless where no focus events arrive). *)
  (match Multi.find_focused windows with
   | Some s ->
     Queue.iter (fun a -> ignore (Lui_app.send s.driver.app a)) pending
   | None -> ());
  Queue.clear pending;
  while Sdl.poll_event (Some e) do
    handle_sdl_event e
  done

let live_resize_error = ref None

let () =
  Callback.register "lui_native_live_resize_frame" (fun id ->
    match Multi.find windows id with
    | Some s when !live_resize_error = None ->
      (try
         let w, h = Sdl.get_window_size s.driver.sdl in
         let dw, dh = drawable s in
         if dw <> s.Multi.drawable_w || dh <> s.Multi.drawable_h then begin
           Multi.apply_logical_size s ~w ~h;
           apply_actions s (Multi.dispatch s (Input.Resize (w, h)));
           ignore (tick ~live_resize:true s ~t0:(perf_s ()))
         end
       with exn -> live_resize_error := Some exn)
    | _ -> ())

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
          let post action =
            Queue.add action pending;
            Option.iter (fun (s : surf) -> Sdl.push_expose_event s.driver.sdl)
              (Multi.find_focused windows)
          in
          match id with
          | 1 -> post (Demo_app.Open Demo_app.P_toast)
          | 2 -> post Demo_app.Req_notify
          | 3 -> post Demo_app.Req_clipboard
          | 4 -> post Demo_app.Req_a11y
          | 9 -> Sdl.push_quit_event ()
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
  Lui_resource.set_completion_wake (fun () ->
    try Sdl.run_on_main_thread ignore with _ -> ());
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
    (* Wake for input or the next frame or UI timer, not a periodic poll. *)
    let wait_ms = ref Float.infinity in
    Multi.iter windows (fun s ->
        (match tick s ~t0 with
         | Frame.Wait_ms ms -> wait_ms := Float.min !wait_ms ms
         | Frame.Present when Ui.want_frame s.ui s.host -> wait_ms := 0.
         | Frame.Present | Frame.Idle -> ());
        let now_ms = perf_s () *. 1000. in
        wait_ms :=
          Float.min !wait_ms
            (fold_wait_ms
               ~ui_deadline_ms:(Ui.next_input_deadline s.ui)
               ~clock_delay_ms:(Lui_clock.next_delay (Lui_app.clock s.driver.app))
               ~host_wants_frame:false
               ~now_ms));
    incr iter_no;
    if not !headless && continue () then begin
      Lui_metal.set_sdl_waiting true;
      let received =
        Fun.protect ~finally:(fun () -> Lui_metal.set_sdl_waiting false) (fun () ->
          if !wait_ms = Float.infinity then Sdl.wait_event (Some e)
          else Sdl.wait_event_timeout (Some e)
            (int_of_float (Float.ceil (Float.max 0. !wait_ms)))) in
      Option.iter raise !live_resize_error;
      if received
      then begin
        handle_sdl_event e;
        drain_events e
      end
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
