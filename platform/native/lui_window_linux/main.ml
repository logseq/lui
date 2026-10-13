(* SDL window driver for Linux: creates a GL 3.3 core window when the
   GL rung is reachable, otherwise a plain window whose present path is
   Lui_blit — CPU-rasterized frames on LUI_GPU=0|cpu, or an offscreen
   Lui_vulkan render read back into the blit texture on LUI_GPU=vulkan.
   Wires Lui_host into Lui_app.dispatch_event, feeds SDL events through
   Lui_window.Ui, serves the Lui_a11y tree through Lui_ax_linux, hosts
   the desktop shell through Lui_shell_linux and presents frames by the
   renderer's own path.

   TODO multi-window: this driver is single-window. Port the macOS
   recipe (see platform/native/MULTIWINDOW.md): the pure
   Lui_window.Multi registry already works here — wrap window creation
   in open_window, route SDL events by windowID, re-query scale on
   Moved/display events, keep --windows N + the headless tests. Near-
   mechanical: only the renderer-ladder entries differ.

   Renderer ladder (env LUI_GPU): default -> Lui_vulkan offscreen +
   readback + Lui_blit, then Lui_gl on the window's GL context, then
   CPU; "gl"|"opengl" -> Lui_gl then CPU (Vulkan skipped);
   "0"|"cpu" -> Lui_raster + Lui_blit. Every failed rung falls to the
   next, ending at a no-op loop renderer — the process never crashes
   for want of a GPU or display.

   Flags: --width N --height N --headless N. *)

open Lui_window

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

(* One SDL event → at most one backend-neutral input. *)
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
    (* Same shape macOS feeds: wheel deltas carry the modifier state
       so Shift turns the vertical delta horizontal. *)
    Some
      (Wheel_mods
         ( float (Sdl.Event.get e Sdl.Event.mouse_wheel_x),
           float (Sdl.Event.get e Sdl.Event.mouse_wheel_y),
           mods_of_keymod (Sdl.get_mod_state ()) ))
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

let () =
  let cfg =
    match parse_args (List.tl (Array.to_list Sys.argv)) with
    | Ok c -> c
    | Error msg ->
      warn "%s\nusage: lui_window_linux [--width N] [--height N] [--headless N]"
        msg;
      exit 2
  in
  let headless = Option.is_some cfg.headless_frames in
  if headless then Unix.putenv "SDL_VIDEODRIVER" "dummy";
  (* Renderer selection on Linux: Vulkan offscreen+blit by default,
     then GL, then CPU on LUI_GPU=0|cpu (or after demotion), then the
     no-op loop renderer. LUI_GPU=gl|opengl skips Vulkan. *)
  let env = try Sys.getenv "LUI_GPU" with Not_found -> "" in
  let ladder =
    if headless && env = "" then [ Lui_linux.Noop ]
    else Lui_linux.ladder ~env
  in
  sdl_ok (Sdl.init Sdl.Init.(video + events));
  (* GL context requirements from lui_gl.mli: OpenGL 3.3 core,
     double-buffered. Attributes are hints — SDL may refuse or
     substitute, in which case Lui_gl.init fails and the ladder walks
     on. *)
  sdl_ok (Sdl.gl_set_attribute Sdl.Gl.context_major_version 3);
  sdl_ok (Sdl.gl_set_attribute Sdl.Gl.context_minor_version 3);
  sdl_ok
    (Sdl.gl_set_attribute Sdl.Gl.context_profile_mask
       Sdl.Gl.context_profile_core);
  sdl_ok (Sdl.gl_set_attribute Sdl.Gl.doublebuffer 1);
  (* The dummy video driver refuses an OpenGL window entirely, and
     neither the CPU blit path nor the Vulkan readback needs a GL
     context — the opengl flag is only set when the first ladder rung
     will actually use it. *)
  let flags gl =
    let base = Sdl.Window.(resizable + allow_highdpi + shown) in
    if gl then Sdl.Window.(base + opengl) else base
  in
  let first = match ladder with r :: _ -> r | [] -> Lui_linux.Noop in
  let win =
    ref
      (sdl_ok
         (Sdl.create_window "lui_window_linux" ~w:cfg.width ~h:cfg.height
            (flags (first = Lui_linux.Gl && not headless))))
  in
  (* Walk the ladder: each rung either yields a renderer or warns and
     the next rung gets its chance. GL needs the opengl-flagged
     window — when an earlier rung fails into the Gl rung the window
     is recreated with the flag. The walk/demote sequencing lives in
     [Lui_window.Renderer_ladder]; this supplies the per-rung init and
     the window re-fit the demote path needs. *)
  let blit_cell = ref None in
  let vk_cell = ref None in
  let gctx_cell = ref None in
  let mk_blit () =
    let dw, dh =
      match Sdl.gl_get_drawable_size !win with
      | 0, 0 -> (cfg.width, cfg.height)
      | d -> d
    in
    match Lui_blit.create !win ~w:dw ~h:dh with
    | Error m ->
      warn "lui_blit.create failed: %s" m;
      None
    | Ok b ->
      blit_cell := Some b;
      Some b
  in
  let try_rung rung ~rest =
    let attempt renderer state =
      Some { Renderer_ladder.renderer; state }
    in
    match rung with
    | Lui_linux.Noop -> attempt Lui_linux.noop_renderer false
    | Lui_linux.Cpu -> (
      match mk_blit () with
      | None -> None
      | Some b ->
        let rr = Lui_raster.Renderer.create () in
        log "renderer: lui_raster+blit";
        attempt
          { Lui_host.name = "lui_raster+blit";
            render =
              (fun s ->
                 let dirty = Lui_raster.Renderer.render rr s in
                 let img = Lui_raster.Renderer.image rr in
                 let stride = img.Lui_raster.Image.stride / 4 in
                 if Lui_raster.Renderer.whole rr || dirty = [] then
                   ignore
                     (Lui_blit.update b ~pix:img.Lui_raster.Image.pix
                        ~stride)
                 else
                   List.iter
                     (fun (r : Lui_scene.irect) ->
                        ignore
                          (Lui_blit.update_region b ~x0:r.x0 ~y0:r.y0
                             ~x1:r.x1 ~y1:r.y1
                             ~pix:img.Lui_raster.Image.pix ~stride))
                     dirty;
                 Lui_blit.present b;
                 img.Lui_raster.Image.pix) }
          false)
    | Lui_linux.Vulkan -> (
      let dw, dh =
        match Sdl.gl_get_drawable_size !win with
        | 0, 0 -> (cfg.width, cfg.height)
        | d -> d
      in
      match Lui_vulkan.init ~w:dw ~h:dh with
      | Error m ->
        warn "lui_vulkan.init failed: %s" m;
        if List.mem Lui_linux.Gl rest && not headless then begin
          (* The GL rung next needs an opengl-flagged window. *)
          Sdl.destroy_window !win;
          win :=
            sdl_ok
              (Sdl.create_window "lui_window_linux" ~w:cfg.width
                 ~h:cfg.height (flags true))
        end;
        None
      | Ok v ->
        log "renderer: lui_vulkan (device %s, dual=%b)"
          (Lui_vulkan.driver v) (Lui_vulkan.dual v);
        vk_cell := Some v;
        let b = mk_blit () in
        attempt
          { Lui_host.name = "lui_vulkan+blit";
            render =
              (fun s ->
                 (* The offscreen frame image is sized at init; a
                    resized scene forces a re-init. On failure the
                    rung degrades to a zeroed frame — no crash. *)
                 let v =
                   match !vk_cell with
                   | Some v -> Some v
                   | None -> (
                     match
                       Lui_vulkan.init ~w:s.Lui_scene.width
                         ~h:s.Lui_scene.height
                     with
                     | Ok v' -> vk_cell := Some v'; Some v'
                     | Error _ -> None)
                 in
                 match v with
                 | None ->
                   Bytes.create (s.Lui_scene.width * s.Lui_scene.height * 4)
                 | Some v -> (
                   try
                     Lui_vulkan.render v s;
                     let pix =
                       Lui_vulkan.read_frame v ~w:s.Lui_scene.width
                         ~h:s.Lui_scene.height
                     in
                     (match b with
                      | Some b ->
                        ignore
                          (Lui_blit.update b ~pix
                             ~stride:s.Lui_scene.width);
                        Lui_blit.present b
                      | None -> ());
                     pix
                   with
                   | Lui_vulkan.Error m ->
                     warn "lui_vulkan.render: %s" m;
                     Bytes.create
                       (s.Lui_scene.width * s.Lui_scene.height * 4))) }
          false)
    | Lui_linux.Gl ->
      if headless then begin
        (* The dummy driver has no GL to give. *)
        None
      end
      else
        (match Sdl.gl_create_context !win with
         | Error (`Msg m) ->
           warn "gl_create_context failed: %s" m;
           Sdl.destroy_window !win;
           win :=
             sdl_ok
               (Sdl.create_window "lui_window_linux" ~w:cfg.width
                  ~h:cfg.height (flags false));
           None
         | Ok c ->
           sdl_ok (Sdl.gl_make_current !win c);
           (match Lui_gl.init () with
            | Ok gl ->
              gctx_cell := Some c;
              log "renderer: Lui_gl";
              attempt
                { Lui_host.name = "lui_gl";
                  render =
                    (fun s ->
                       try
                         Lui_gl.render gl s;
                         Bytes.empty
                       with
                       | Lui_gl.Error m ->
                         warn "lui_gl.render: %s" m;
                         Bytes.create
                           (s.Lui_scene.width * s.Lui_scene.height * 4)) }
                true
            | Error m ->
              warn "lui_gl.init failed: %s" m;
              Sdl.gl_delete_context c;
              Sdl.destroy_window !win;
              win :=
                sdl_ok
                  (Sdl.create_window "lui_window_linux" ~w:cfg.width
                     ~h:cfg.height (flags false));
              None))
  in
  let vk_state = vk_cell in
  let ladder_t =
    Renderer_ladder.create
      ~warn:(fun m -> warn "%s" m)
      ~release:(fun _ ->
        (match !gctx_cell with
         | Some c -> Sdl.gl_delete_context c; gctx_cell := None
         | None -> ());
        (match !vk_cell with
         | Some v -> Lui_vulkan.release v; vk_cell := None
         | None -> ());
        blit_cell := None)
      ~before_walk:(fun rest ->
        (* Re-flag the window for the rung about to be tried. *)
        let next_gl =
          match rest with Lui_linux.Gl :: _ -> true | _ -> false
        in
        Sdl.destroy_window !win;
        win :=
          sdl_ok
            (Sdl.create_window "lui_window_linux" ~w:cfg.width
               ~h:cfg.height (flags (next_gl && not headless))))
      ~exhausted_msg:"all renderers unavailable; using no-op loop renderer"
      ~noop:{ Renderer_ladder.renderer = Lui_linux.noop_renderer;
              state = false }
      ~try_rung ladder
  in
  let gl_live () = (Renderer_ladder.active ladder_t).state in
  (* Runtime backend-loss recovery. An SDL render-target/device reset
     event (0x2000/0x2001) or a render exception demotes the active
     rung to the next ladder entry — the window is re-flagged for the
     new rung, stale GL/Vulkan/blit resources released first. The
     scene store is untouched, so the next repaint re-uploads a full
     scene — identical pixels on the CPU path by the parity
     contract. *)
  let demote reason = Renderer_ladder.demote ladder_t ~reason in
  (* The host owns a stable record whose render delegates to the live
     rung, so a demote needs no host rebuild. *)
  let renderer_live = Renderer_ladder.renderer_live ladder_t in
  let vsync =
    match !gctx_cell with
    | Some _ -> (match Sdl.gl_set_swap_interval 1 with
        | Ok () -> not headless
        | Error _ -> false)
    | None -> false
  in
  let drawable () =
    (* Under the dummy driver this may report 0x0; fall back to the
       window size so layout still gets a sane extent. *)
    match Sdl.gl_get_drawable_size !win with
    | 0, 0 -> (cfg.width, cfg.height)
    | d -> d
  in
  let dw, dh = drawable () in
  let scale = Float.max 0.01 (float dw /. float cfg.width) in
  (* Shared host assembly: hooks, the real layout engine, the
     scroll-shifted hit-test mirror and the scroll caps are all wired
     by [Lui_window.Assembly] — the same code macOS and Windows run,
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
    Assembly.create ~layout:(module Lui_layout) ~scale_cell
      ~text:
        Assembly.
          { measure = Lui_window_text.measure_text text_engine;
            text_ops = Lui_window_text.text_ops text_engine;
            hit_text = Lui_window_text.hit_text text_engine;
            caret_ops = Lui_window_text.caret_ops text_engine }
      ~renderer:renderer_live ~width:dw ~height:dh ()
  in
  host_cell := Some (Assembly.host asm);
  let host = Assembly.host asm in
  let ui = Assembly.ui asm in
  let rects = Assembly.rects asm in
  let store = Assembly.store asm in
  let win_w = ref cfg.width and win_h = ref cfg.height in
  let backend =
    Assembly.backend asm
      (Lui_protocol.profile Lui_protocol.LinuxOS Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  (* Priming paint: syncs the flex engine and renders once so the
     hit-test mirror and scroll caps see real rects. *)
  ignore (Assembly.repaint asm);
  (* Caret rect of the focused field, device px — the candidate-window
     anchor while composing. *)
  let caret_rect () = Assembly.caret_rect asm in
  (* Hand focus to the first autofocus field, if any. *)
  (match Assembly.first_autofocus asm with
   | Some id ->
     Ui.set_focused ui store id;
     Sdl.start_text_input ()
   | None -> ());
  let quit = ref false in
  (* SDL_SetTextInputRect works in window (logical) pixels. *)
  let set_ime_rect (r : Lui_scene.rect) =
    let s = !scale_cell in
    Sdl.set_text_input_rect
      (Some
         (Sdl.Rect.create
            ~x:(int_of_float (r.Lui_scene.x /. s))
            ~y:(int_of_float (r.Lui_scene.y /. s))
            ~w:(max 1 (int_of_float (r.Lui_scene.w /. s)))
            ~h:(max 1 (int_of_float (r.Lui_scene.h /. s)))))
  in
  (* The accessibility bridge cell: created after the app tree exists,
     consulted by Focus_changed. *)
  let ax_cell = ref None in
  let rec apply_actions acts = List.iter (function
    | Dispatch ev ->
      (try ignore (Lui_app.dispatch_event app ev)
       with Invalid_argument msg ->
         warn "dispatch rejected event: %s" msg)
    | Clipboard_write s ->
      if not headless then ignore (Lui_shell_linux.clipboard_write s)
    | Paste_request ->
      (* clipboard I/O is a driver concern: read + feed back as
         Input.Paste (interactive only — headless never types Ctrl-V) *)
      (match if headless then None else Lui_shell_linux.clipboard_read () with
       | Some s ->
         apply_actions (Assembly.handle asm (Input.Paste s))
       | None -> ())
    | Resize_host _ ->
      let dw, dh = drawable () in
      (match !blit_cell with
       | Some b ->
         if
           (match Lui_blit.resize b ~w:dw ~h:dh with
            | Ok () -> false
            | Error m -> warn "blit resize: %s" m; true)
         then ();
       | None -> ());
      (* The Vulkan rung's frame image is sized at init: drop it so
         the next render re-inits at the new extent. *)
      (match !vk_state with
       | Some v -> Lui_vulkan.release v; vk_state := None
       | None -> ());
      scale_cell := float dw /. float (max 1 !win_w);
      Ui.set_scale ui !scale_cell;
      Lui_host.resize host ~width:dw ~height:dh ~scale:!scale_cell
    | Focus_changed id ->
      (match !ax_cell with
       | Some ax ->
         if id = 0 then Lui_ax_linux.clear_focus ax
         else Lui_ax_linux.set_focus ax id
       | None -> ());
      if id = 0 then Sdl.stop_text_input ()
      else begin
        Sdl.start_text_input ();
        set_ime_rect (Rects.get rects id)
      end
    | Ime_rect r -> set_ime_rect r
    | Quit -> quit := true)
    acts
  in
  (* Accessibility: mirror the Lui_a11y semantic tree over the a11y
     bus. Everything is transport-guarded: offline, events queue and
     flush reports zero sent — the app is unaffected. *)
  let a11y = Lui_a11y.of_store store in
  let ax = Lui_ax_linux.create ~toolkit_name:"lui" () in
  Lui_ax_linux.attach ax a11y;
  let ax_transport = Lui_ax_linux.connect ax in
  ax_cell := Some ax;
  log "a11y: transport=%s nodes=%d"
    (match ax_transport with
     | Lui_ax_linux.Offline -> "offline"
     | Lui_ax_linux.Session_bus -> "session-bus"
     | Lui_ax_linux.A11y_bus -> "a11y-bus")
    (Lui_a11y.node_count a11y);
  (* AT invocations route through the same dispatch path as input. *)
  Lui_ax_linux.on_action ax (fun id name ->
    match Lui_linux.a11y_event_of_action store id name with
    | Some ev -> apply_actions [ Dispatch ev ]
    | None -> ());
  Lui_ax_linux.on_focus_request ax (fun id ->
    if Lui_store.mem store id && node_enabled store id then begin
      Ui.set_focused ui store id;
      apply_actions [ Focus_changed id ]
    end);
  Lui_ax_linux.on_caret_request ax (fun _id _offset -> false);
  Lui_ax_linux.on_value_request ax (fun id v ->
    match Lui_linux.a11y_event_of_value store id v with
    | Some ev -> (
      try Lui_app.dispatch_event app ev
      with Invalid_argument _ -> false)
    | None -> false);
  (* Desktop shell: app name, a status item with a generated icon and
     a two-item menu (Show raises the window, Quit ends the loop), and
     a notification handler — all inert without a session bus or the
     indicator service. *)
  Lui_shell_linux.set_app_name "lui_window_linux";
  ignore (Lui_shell_linux.set_activation_policy Regular);
  let status = Lui_shell_linux.status_item_create ~tag:1 () in
  Lui_shell_linux.status_item_set_title status "lui_window_linux";
  Lui_shell_linux.status_item_set_image status
    (Lui_shell_linux.image_of_rgba ~width:22 ~height:22
       (Lui_linux.tray_icon_rgba ()));
  let tray_menu =
    Lui_shell_linux.menu ~title:"lui_window_linux"
      [ Lui_shell_linux.Item
          { label = "Show"; id = 1; enabled = true; checked = false };
        Lui_shell_linux.Separator;
        Lui_shell_linux.Item
          { label = "Quit"; id = 2; enabled = true; checked = false } ]
  in
  Lui_shell_linux.status_item_set_menu status (Some tray_menu);
  Lui_shell_linux.set_menu_handler
    (Some
       (fun id ->
          match id with
          | 1 ->
            Sdl.show_window !win;
            Sdl.raise_window !win
          | 2 -> quit := true
          | _ -> ()));
  Lui_shell_linux.set_status_handler
    (Some
       (fun _tag ->
          Sdl.show_window !win;
          Sdl.raise_window !win));
  Lui_shell_linux.set_notification_handler
    (Some (fun id -> log "notification activated: %s" id));
  log "shell: transport=%s gui=%b"
    (match Lui_shell_linux.transport () with
     | Lui_shell_linux.Offline -> "offline"
     | Lui_shell_linux.Session_bus -> "session-bus"
     | Lui_shell_linux.Indicator -> "indicator")
    (Lui_shell_linux.gui_available ());
  let e = Sdl.Event.create () in
  let drain_events () =
    let go = ref true in
    while !go do
      if Sdl.poll_event (Some e) then
        let typ = Sdl.Event.get e Sdl.Event.typ in
        (* SDL_RENDER_TARGETS_RESET / SDL_RENDER_DEVICE_RESET: the
           backend lost its resources — recover down the ladder. *)
        if typ = 0x2000 || typ = 0x2001 then
          demote "SDL render-target/device reset"
        else
        match input_of_event e with
        | Some (Input.Resize (w, h)) ->
          win_w := w;
          win_h := h;
          apply_actions
            (Assembly.handle asm (Input.Resize (w, h)))
        | Some input ->
          apply_actions (Assembly.handle asm input)
        | None -> ()
      else go := false
    done
  in
  let frames_target = cfg.headless_frames in
  let checksum = Checksum.create () in
  let st = { frames = 0; acc_ms = 0.; min_ms = 1e9; max_ms = 0. } in
  let frame = ref 0 in
  let continue () =
    (not !quit)
    && (match frames_target with
        | Some n -> !frame < n
        | None -> true)
  in
  log "lui_window_linux: %dx%d drawable (scale %.2f), renderer=%s%s"
    dw dh scale (Renderer_ladder.active ladder_t).renderer.Lui_host.name
    (if headless then " [headless]" else "");
  while continue () do
    let t0 = perf_s () in
    drain_events ();
    (* Patches queued by dispatched events land in the store here;
       layout must see them before the next paint or hit test.
       Store-driven effects: Appear lifecycle events, scroll-target
       completions, visible-range reports, modal focus save/restore —
       the same post-flush pass macOS and Windows run. *)
    ignore (Lui_app.flush app);
    apply_actions (Assembly.store_changed asm);
    (* Shell event pump: menu selections, status activations,
       notification activations and opened URLs dispatch to their
       handlers on this thread. No-op offline. *)
    ignore (Lui_shell_linux.pump ());
    (* Accessibility: fold the frame's dirty store ids into the
       semantic tree and answer pending AT calls; offline both sides
       are plain no-ops. *)
    Lui_ax_linux.sync ax;
    ignore (Lui_ax_linux.dispatch ax);
    ignore (Lui_ax_linux.flush ax);
    (* Report the caret once per frame: while a composition is open
       the state machine emits Ime_rect on movement so the candidate
       window tracks the caret; idle, the rect is only remembered. *)
    if Ui.focused ui <> 0 then
      apply_actions
        (Assembly.handle asm (Input.Caret (caret_rect ())));
    (* Headless proves the loop: force a repaint every iteration so
       the frame counter and checksum actually run. *)
    let dirty = headless || Ui.want_frame ui host in
    if dirty then begin
      (* populate's anchor-drift corrections surface as VisibleRange
         dispatches — apply them like any other Ui action *)
      apply_actions (snd (Assembly.repaint asm));
      if gl_live () then Sdl.gl_swap_window !win;
      Ui.frame_done ui;
      incr frame;
      Checksum.add_scene checksum (Lui_host.scene host);
      if headless && not (gl_live ()) then
        log "frame=%d ops=%d" !frame
          (List.length (Lui_host.scene host).Lui_scene.ops);
      stats_update st ((perf_s () -. t0) *. 1000.);
      if !frame mod 60 = 0 then
        stats_report st (Renderer_ladder.active ladder_t).renderer.Lui_host.name
    end;
    (* No vsync under the dummy driver and possibly none elsewhere:
       pace the loop explicitly. An idle iteration (no repaint) also
       sleeps briefly so the poll loop does not spin at 100% CPU. *)
    if not headless then begin
      if dirty && not vsync then begin
        let remaining = 16.6 -. ((perf_s () -. t0) *. 1000.) in
        if remaining > 0.5 then
          Sdl.delay (Int32.of_int (int_of_float remaining))
      end
      else if not dirty then Sdl.delay 4l
    end
  done;
  stats_report st (Renderer_ladder.active ladder_t).renderer.Lui_host.name;
  (match frames_target with
   | Some _ ->
     log "headless done: frames=%d checksum=%016Lx" !frame
       (Checksum.value checksum)
   | None -> ());
  ignore (Lui_app.dispose app);
  Lui_ax_linux.destroy ax;
  Lui_shell_linux.status_item_remove status;
  (match !vk_state with
   | Some v -> Lui_vulkan.release v
   | None -> ());
  (match !gctx_cell with
   | Some c -> Sdl.gl_delete_context c
   | None -> ());
  Sdl.destroy_window !win;
  Sdl.quit ()
