(* SDL window driver: creates a GL 3.3 core window, wires Lui_host
   with Lui_gl as the renderer (a no-op loop renderer when GL is
   unavailable — e.g. the dummy video driver), feeds SDL events
   through Lui_window.Ui into Lui_app.dispatch_event and presents
   frames via SDL_GL_SwapWindow.

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
      warn "%s\nusage: lui_window [--width N] [--height N] [--headless N]"
        msg;
      exit 2
  in
  let headless = Option.is_some cfg.headless_frames in
  if headless then Unix.putenv "SDL_VIDEODRIVER" "dummy";
  (* LUI_GPU=0|cpu forces the CPU path: no GL context, raster +
     software-texture present. Anything else prefers GL and falls
     back to a no-op loop renderer when no context exists. *)
  let use_cpu =
    let env = try Sys.getenv "LUI_GPU" with Not_found -> "" in
    env = "0" || env = "cpu"
  in
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
  (* The dummy video driver refuses an OpenGL window entirely, and
     the CPU path does not need one either. *)
  let flags =
    let base = Sdl.Window.(resizable + allow_highdpi + shown) in
    if headless || use_cpu then base else Sdl.Window.(base + opengl)
  in
  let win =
    sdl_ok (Sdl.create_window "lui_window" ~w:cfg.width ~h:cfg.height flags)
  in
  (* The dummy driver cannot create a GL context at all; a real
     window without one is useless, so only headless continues. *)
  let gctx =
    if use_cpu then None
    else match Sdl.gl_create_context win with
    | Ok c ->
      sdl_ok (Sdl.gl_make_current win c);
      Some c
    | Error (`Msg m) ->
      if headless then begin
        warn "gl_create_context failed (expected headless): %s" m;
        None
      end
      else failwith ("SDL: " ^ m)
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
    match Sdl.gl_get_drawable_size win with
    | 0, 0 -> (cfg.width, cfg.height)
    | d -> d
  in
  let dw, dh = drawable () in
  let scale = Float.max 0.01 (float dw /. float cfg.width) in
  let renderer, gl_live, blit =
    if use_cpu then begin
      (* CPU path: Lui_raster renders the scene; Lui_blit uploads the
         damaged rects (or the whole frame) to the window texture. *)
      match Lui_blit.create win ~w:dw ~h:dh with
      | Error m ->
        warn "lui_blit.create failed: %s" m;
        ( { Lui_host.name = "noop";
            render =
              (fun s ->
                 Bytes.create
                   (s.Lui_scene.width * s.Lui_scene.height * 4)) },
          false, None )
      | Ok b ->
        let rr = Lui_raster.Renderer.create () in
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
          false, Some b )
    end
    else match gctx with
    | None ->
      warn "no GL context; using no-op loop renderer";
      ( { Lui_host.name = "noop";
          render =
            (fun s ->
               Bytes.create
                 (s.Lui_scene.width * s.Lui_scene.height * 4)) },
        false, None )
    | Some _ ->
    match Lui_gl.init () with
    | Ok gl ->
      log "renderer: Lui_gl (GL context %s)"
        (match Sdl.gl_get_attribute Sdl.Gl.context_major_version with
         | Ok v -> Printf.sprintf "%d.x" v
         | Error _ -> "?");
      (* read_frame is a full glReadPixels round-trip — only for
         capture/checksum paths, never inside the paint loop. *)
      ( { Lui_host.name = "lui_gl";
          render =
            (fun s ->
               Lui_gl.render gl s;
               Bytes.empty) },
        true, None )
    | Error msg ->
      warn "lui_gl.init failed: %s" msg;
      warn "falling back to no-op loop renderer";
      ( { Lui_host.name = "noop";
          render =
            (fun s ->
               Bytes.create
                 (s.Lui_scene.width * s.Lui_scene.height * 4)) },
        false, None )
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
      (Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.GenericHost)
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
      scale_cell := float dw /. float (max 1 !win_w);
      Ui.set_scale ui !scale_cell;
      Lui_host.resize host ~width:dw ~height:dh ~scale:!scale_cell;
      refresh_layout ()
    | Focus_changed id ->
      if id = 0 then Sdl.stop_text_input ()
      else begin
        Sdl.start_text_input ();
        set_ime_rect (Rects.get rects id)
      end
    | Ime_rect r -> set_ime_rect r
    | Quit -> quit := true)
  in
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
  log "lui_window: %dx%d drawable (scale %.2f), renderer=%s%s"
    dw dh scale renderer.Lui_host.name
    (if headless then " [headless]" else "");
  while continue () do
    let t0 = perf_s () in
    drain_events ();
    (* Patches queued by dispatched events land in the store here;
       layout must see them before the next paint or hit test. *)
    if Lui_app.flush app then refresh_layout ();
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
      if gl_live then Sdl.gl_swap_window win;
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
  (match gctx with
   | Some c -> Sdl.gl_delete_context c
   | None -> ());
  Sdl.destroy_window win;
  Sdl.quit ()
