(* SDL window driver for Linux: creates a GL 3.3 core window when the
   GL rung is reachable, otherwise a plain window whose present path is
   Lui_blit — CPU-rasterized frames on LUI_GPU=0|cpu, or an offscreen
   Lui_vulkan render read back into the blit texture on LUI_GPU=vulkan.
   Wires Lui_host into Lui_app.dispatch_event, feeds SDL events through
   Lui_window.Ui, serves the Lui_a11y tree through Lui_ax_linux, hosts
   the desktop shell through Lui_shell_linux and presents frames by the
   renderer's own path.

   Renderer ladder (env LUI_GPU): default -> Lui_gl on the window's GL
   context; "vulkan" -> Lui_vulkan offscreen + readback + Lui_blit;
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
    Some
      (Wheel
         ( float (Sdl.Event.get e Sdl.Event.mouse_wheel_x),
           float (Sdl.Event.get e Sdl.Event.mouse_wheel_y) ))
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
  (* Renderer selection on Linux: GL by default, Vulkan offscreen on
     request, CPU on LUI_GPU=0|cpu, then the no-op loop renderer. *)
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
     is recreated with the flag. *)
  let renderer, gl_live, blit, vk_state, gctx =
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
    let rec attempt = function
      | [] ->
        warn "all renderers unavailable; using no-op loop renderer";
        (Lui_linux.noop_renderer, false)
      | Lui_linux.Noop :: _ -> (Lui_linux.noop_renderer, false)
      | Lui_linux.Cpu :: rest ->
        (match mk_blit () with
         | None -> attempt rest
         | Some b ->
           let rr = Lui_raster.Renderer.create () in
           log "renderer: lui_raster+blit";
           ( { Lui_host.name = "lui_raster+blit";
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
                    img.Lui_raster.Image.pix) },
             false ))
      | Lui_linux.Vulkan :: rest ->
        let dw, dh =
          match Sdl.gl_get_drawable_size !win with
          | 0, 0 -> (cfg.width, cfg.height)
          | d -> d
        in
        (match Lui_vulkan.init ~w:dw ~h:dh with
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
           attempt rest
         | Ok v ->
           log "renderer: lui_vulkan (device %s, dual=%b)"
             (Lui_vulkan.driver v) (Lui_vulkan.dual v);
           vk_cell := Some v;
           let b = mk_blit () in
           ( { Lui_host.name = "lui_vulkan+blit";
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
                          (s.Lui_scene.width * s.Lui_scene.height * 4))) },
             false ))
      | Lui_linux.Gl :: rest ->
        if headless then begin
          (* The dummy driver has no GL to give. *)
          attempt rest
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
             attempt rest
           | Ok c ->
             sdl_ok (Sdl.gl_make_current !win c);
             (match Lui_gl.init () with
              | Ok gl ->
                gctx_cell := Some c;
                log "renderer: Lui_gl";
                ( { Lui_host.name = "lui_gl";
                    render =
                      (fun s ->
                         try
                           Lui_gl.render gl s;
                           Bytes.empty
                         with
                         | Lui_gl.Error m ->
                           warn "lui_gl.render: %s" m;
                           Bytes.create
                             (s.Lui_scene.width * s.Lui_scene.height * 4)) },
                  true )
              | Error m ->
                warn "lui_gl.init failed: %s" m;
                Sdl.gl_delete_context c;
                Sdl.destroy_window !win;
                win :=
                  sdl_ok
                    (Sdl.create_window "lui_window_linux" ~w:cfg.width
                       ~h:cfg.height (flags false));
                attempt rest))
    in
    let renderer, gl_live = attempt ladder in
    (renderer, gl_live, !blit_cell, vk_cell, !gctx_cell)
  in
  let vsync =
    match gctx with
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
               let underline =
                 Lui_scene.Fill
                   { frect =
                       Lui_scene.rect
                         (r.Lui_scene.x +. dx)
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
        shadow_of = (fun _ -> None) }
  in
  let host = Lui_host.create ~hooks ~renderer ~width:dw ~height:dh ~scale () in
  host_cell := Some host;
  let store = Lui_host.store host in
  let win_w = ref cfg.width and win_h = ref cfg.height in
  let refresh_layout () =
    Layout.refresh store rects ~width:!win_w ~height:!win_h
      ~scale:!scale_cell ~measure:Lui_window_text.measure
  in
  let backend =
    Lui_host.backend host
      (Lui_protocol.profile Lui_protocol.LinuxOS Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  refresh_layout ();
  (* Hand focus to the first autofocus field, if any. *)
  (match
     List.find_opt
       (fun id -> bool_prop store id "autofocus")
       (Lui_store.preorder store)
   with
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
      let pad =
        match Lui_store.prop store id "padding-horizontal" with
        | Some (Lui_protocol.IntValue n) -> float n *. s
        | Some (Lui_protocol.FloatValue f) -> f *. s
        | _ ->
          (match Lui_store.prop store id "padding" with
           | Some (Lui_protocol.IntValue n) -> float n *. s
           | Some (Lui_protocol.FloatValue f) -> f *. s
           | _ -> 0.)
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
  (* The accessibility bridge cell: created after the app tree exists,
     consulted by Focus_changed. *)
  let ax_cell = ref None in
  let apply_actions = List.iter (function
    | Dispatch ev ->
      (try ignore (Lui_app.dispatch_event app ev)
       with Invalid_argument msg ->
         warn "dispatch rejected event: %s" msg)
    | Resize_host _ ->
      let dw, dh = drawable () in
      (match blit with
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
      Lui_host.resize host ~width:dw ~height:dh ~scale:!scale_cell;
      refresh_layout ()
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
        match input_of_event e with
        | Some (Input.Resize (w, h)) ->
          win_w := w;
          win_h := h;
          apply_actions
            (Ui.handle ui store rects (Input.Resize (w, h)))
        | Some input ->
          apply_actions (Ui.handle ui store rects input)
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
    dw dh scale renderer.Lui_host.name
    (if headless then " [headless]" else "");
  while continue () do
    let t0 = perf_s () in
    drain_events ();
    (* Patches queued by dispatched events land in the store here;
       layout must see them before the next paint or hit test. *)
    if Lui_app.flush app then refresh_layout ();
    (* Shell event pump: menu selections, status activations,
       notification activations and opened URLs dispatch to their
       handlers on this thread. No-op offline. *)
    ignore (Lui_shell_linux.pump ());
    (* Accessibility: fold the frame's dirty store ids into the
       semantic tree and answer pending AT calls. The queued events
       are drained rather than flushed: the c_emit_* stubs behind
       [flush] take >5 arguments through a bytecode-shaped signature,
       which crashes when called from native code on a live transport.
       Draining keeps the queue bounded and incoming AT actions still
       work; offline the same path is a plain no-op. *)
    Lui_ax_linux.sync ax;
    ignore (Lui_ax_linux.dispatch ax);
    ignore (Lui_ax_linux.drain_events ax);
    (* Report the caret once per frame: while a composition is open
       the state machine emits Ime_rect on movement so the candidate
       window tracks the caret; idle, the rect is only remembered. *)
    if Ui.focused ui <> 0 then
      apply_actions
        (Ui.handle ui store rects (Input.Caret (caret_rect ())));
    (* Headless proves the loop: force a repaint every iteration so
       the frame counter and checksum actually run. *)
    let dirty = headless || Ui.want_frame ui host in
    if dirty then begin
      ignore (Lui_host.repaint host);
      if gl_live then Sdl.gl_swap_window !win;
      Ui.frame_done ui;
      incr frame;
      Checksum.add_scene checksum (Lui_host.scene host);
      if headless && not gl_live then
        log "frame=%d ops=%d" !frame
          (List.length (Lui_host.scene host).Lui_scene.ops);
      stats_update st ((perf_s () -. t0) *. 1000.);
      if !frame mod 60 = 0 then stats_report st renderer.Lui_host.name
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
  stats_report st renderer.Lui_host.name;
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
  (match gctx with
   | Some c -> Sdl.gl_delete_context c
   | None -> ());
  Sdl.destroy_window !win;
  Sdl.quit ()
