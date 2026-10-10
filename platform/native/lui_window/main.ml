(* SDL window driver: creates a GL 3.3 core window, wires Lui_host
   with Lui_gl as the renderer (a no-op loop renderer when GL is
   unavailable — e.g. the dummy video driver), feeds SDL events
   through Lui_window.Ui into Lui_app.dispatch_event and presents
   frames via SDL_GL_SwapWindow.

   Flags: --width N --height N --headless N. *)

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
  (* Renderer selection on macOS: Metal is preferred, GL on request
     (LUI_GPU=gl|opengl) or as fallback, CPU on LUI_GPU=0|cpu. *)
  let env = try Sys.getenv "LUI_GPU" with Not_found -> "" in
  let use_cpu = env = "0" || env = "cpu" in
  let prefer_metal =
    not headless && not use_cpu && env <> "gl" && env <> "opengl"
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
  (* The dummy video driver refuses an OpenGL window entirely, the
     CPU path does not need one, and Metal attaches its own layer to
     a plain window — the opengl flag is only set when a GL context
     will actually be created. *)
  let flags gl =
    let base = Sdl.Window.(resizable + allow_highdpi + shown) in
    if gl then Sdl.Window.(base + opengl) else base
  in
  let win =
    ref
      (sdl_ok
         (Sdl.create_window "lui_window" ~w:cfg.width ~h:cfg.height
            (flags (not headless && not use_cpu && not prefer_metal))))
  in
  (* Metal attempt — before any GL context. On failure the plain
     window is replaced by an opengl-flagged one and the GL path
     continues below. *)
  let metal =
    match prefer_metal with
    | false -> None
    | true -> (
      match Lui_metal.init_window (Sdl.unsafe_ptr_of_window !win) with
      | Ok m -> Some m
      | Error e ->
        warn "lui_metal.init_window failed (%s); falling back to GL" e;
        Sdl.destroy_window !win;
        win :=
          sdl_ok
            (Sdl.create_window "lui_window" ~w:cfg.width ~h:cfg.height
               (flags true));
        None)
  in
  (* The dummy driver cannot create a GL context at all; a real
     window without one is useless, so only headless continues. *)
  let gctx =
    if use_cpu || Option.is_some metal then None
    else match Sdl.gl_create_context !win with
    | Ok c ->
      sdl_ok (Sdl.gl_make_current !win c);
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
    match Sdl.gl_get_drawable_size !win with
    | 0, 0 -> (cfg.width, cfg.height)
    | d -> d
  in
  let dw, dh = drawable () in
  let scale = Float.max 0.01 (float dw /. float cfg.width) in
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
    if use_cpu then begin
      (* CPU path: Lui_raster renders the scene; Lui_blit uploads the
         damaged rects (or the whole frame) to the window texture. *)
      match Lui_blit.create !win ~w:dw ~h:dh with
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
    let rec sum aid acc =
      match Lui_store.parent (store_of ()) aid with
      | Some p -> sum p (acc +. Ui.scroll_offset ui p)
      | None -> acc
    in
    sum id 0.
  in
  let shifted_rect id =
    let r = engine_rect id in
    { r with Lui_scene.y = r.Lui_scene.y -. scroll_shift_of id }
  in
  let content_top_bottom id =
    List.fold_left
      (fun (top, bot) d ->
         if d = id then (top, bot)
         else
           let r = engine_rect d in
           (Float.min top r.Lui_scene.y,
            Float.max bot (r.Lui_scene.y +. r.Lui_scene.h)))
      (Float.max_float, Float.min_float)
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
               let top, bot = content_top_bottom id in
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
        shadow_of = Lui_paint.parse_shadow Theme.color_of }
  in
  let host =
    Lui_host.create ~hooks ~layout:(module Lui_layout)
      ~measure:(fun id text _w _h ->
        Some (Lui_window_text.measure_text text_engine id text))
      ~renderer ~width:dw ~height:dh ~scale ()
  in
  host_cell := Some host;
  let store = Lui_host.store host in
  let win_w = ref cfg.width and win_h = ref cfg.height in
  (* Populate the hit-test mirror from the layout engine: each node's
     shifted rect clipped to its scrollable ancestors' viewports (so
     scrolled-off content can't be hit), then each scroll container's
     range from its unshifted content extent. Runs after every repaint
     while the engine is fresh. *)
  let populate_rects () =
    Hashtbl.reset rects;
    List.iter
      (fun id ->
         let base = engine_rect id in
         let rec walk aid (shift, clip) =
           match Lui_store.parent store aid with
           | None -> (shift, clip)
           | Some p ->
             let clip =
               if Ui.scrollable store p then
                 match Hashtbl.find_opt rects p with
                 | Some pr when not (Lui_scene.rect_empty pr) ->
                   rect_intersect clip pr
                 | _ -> clip
               else clip
             in
             walk p (shift +. Ui.scroll_offset ui p, clip)
         in
         let shift, clip = walk id (0., base) in
         let r = { base with Lui_scene.y = base.Lui_scene.y -. shift } in
         Hashtbl.replace rects id (rect_intersect r clip))
      (Lui_store.preorder store);
    List.iter
      (fun id ->
         if Ui.scrollable store id then
           let cr = engine_rect id in
           let top, bot = content_top_bottom id in
           Ui.set_scroll_cap ui id
             (Float.max 0. (bot -. top -. cr.Lui_scene.h)))
      (Lui_store.preorder store)
  in
  let backend =
    Lui_host.backend host
      (Lui_protocol.profile Lui_protocol.MacOS Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  (* Priming paint: syncs the flex engine and renders once so the
     hit-test mirror and scroll caps below see real rects. *)
  ignore (Lui_host.repaint host);
  populate_rects ();
  (* The a11y forest mirrors the store: synced after every repaint,
     focused along with the Ui focus, dumped on request and at quit. *)
  let a11y = Lui_a11y.of_store store in
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
  (* Shell integration — a menu-bar status item with a real AppKit
     menu, plus the notify/clipboard calls the driver fires on model
     requests. Interactive only: none of it is safe or wanted under
     the dummy driver, and skipping it keeps the headless checksum
     deterministic. *)
  let pending : Demo_app.action Queue.t = Queue.create () in
  if not headless then begin
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
            | _ -> ()));
    (* The renderer badge: static here, updated with fps once a
       second further down. *)
    ignore
      (Lui_app.send app (Demo_app.Badge renderer.Lui_host.name))
  end;
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
      Lui_host.resize host ~width:dw ~height:dh ~scale:!scale_cell
    | Focus_changed id ->
      ignore
        (if id = 0 then Lui_a11y.clear_focused a11y
         else Lui_a11y.set_focused a11y id);
      if id = 0 then Sdl.stop_text_input ()
      else begin
        Sdl.start_text_input ();
        set_ime_rect (Rects.get rects id)
      end
    | Ime_rect r -> set_ime_rect r
    | Quit -> quit := true)
  in
  let e = Sdl.Event.create () in
  (* Model actions the macOS shell layer queues out-of-band (menu-bar
     icon menu): the event drain sends them into the app on the next
     frame, same as pointer input. *)
  let drain_events () =
    Queue.iter (fun a -> ignore (Lui_app.send app a)) pending;
    Queue.clear pending;
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
  (* Side effects the demo requests through the model: a counter bump
     means the driver runs the shell call once, outside the
     deterministic store. Interactive only — headless frames never
     produce requests, keeping the checksum stable. *)
  let reqs_seen = Hashtbl.create 8 in
  let req_hit name n =
    let seen = Option.value ~default:0 (Hashtbl.find_opt reqs_seen name) in
    if n > seen then (Hashtbl.replace reqs_seen name n; true)
    else false
  in
  let toast_since = ref None in
  let poll_driver () =
    if not headless then begin
      let m = Lui_app.model app in
      if req_hit "notify" m.Demo_app.req_notify then begin
        let posted, detail =
          Lui_shell.notify ~id:"demo" ~title:"lui_window"
            ~body:"notification from the native demo" () in
        log "shell notify: posted=%b (%s)" posted detail
      end;
      if req_hit "clipboard" m.Demo_app.req_clipboard then begin
        let s =
          Printf.sprintf "lui_window %dx%d renderer=%s frames=%d"
            dw dh renderer.Lui_host.name !frame in
        log "shell clipboard: wrote %d chars (ok=%b)"
          (String.length s) (Lui_shell.clipboard_write s)
      end;
      if req_hit "a11y" m.Demo_app.req_a11y then begin
        let names =
          List.map
            (fun n -> Lui_a11y.role_name n.Lui_a11y.role)
            (Lui_a11y.flatten a11y) in
        log "a11y: %d nodes — %s" (Lui_a11y.node_count a11y)
          (String.concat ", " names)
      end;
      Lui_shell.set_dock_badge
        (match m.Demo_app.items with
         | [] -> None
         | l -> Some (string_of_int (List.length l)));
      (* The toast's [duration] prop is informational on this backend;
         the driver owns the clock and dismisses after 2.5 s. *)
      (match m.Demo_app.toast_open, !toast_since with
       | true, None -> toast_since := Some (perf_s ())
       | true, Some t0 when perf_s () -. t0 > 2.5 ->
         ignore (Lui_app.send app (Demo_app.Close Demo_app.P_toast));
         toast_since := None
       | false, _ -> toast_since := None
       | _ -> ())
    end
  in
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
       the repaint below picks them up through the layout sync. *)
    ignore (Lui_app.flush app);
    poll_driver ();
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
      populate_rects ();
      ignore (Lui_a11y.sync a11y);
      if gl_live then Sdl.gl_swap_window !win;
      Ui.frame_done ui;
      incr frame;
      Checksum.add_scene checksum (Lui_host.scene host);
      if headless && not gl_live then
        log "frame=%d ops=%d" !frame
          (List.length (Lui_host.scene host).Lui_scene.ops);
      stats_update st ((perf_s () -. t0) *. 1000.);
      if !frame mod 60 = 0 then begin
        (* FPS for the badge rides the same ~1 s window as the stats
           log; headless never sends it, keeping the initial badge
           (empty) deterministic for the checksum. *)
        let fps =
          if st.frames > 0 && st.acc_ms > 0. then
            1000. /. (st.acc_ms /. float st.frames)
          else 0. in
        stats_report st renderer.Lui_host.name;
        if not headless then
          ignore
            (Lui_app.send app
               (Demo_app.Badge
                  (Printf.sprintf "%s — %.0f fps"
                     renderer.Lui_host.name fps)))
      end
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
  log "a11y: %d nodes" (Lui_a11y.node_count a11y);
  (match frames_target with
   | Some _ ->
     log "headless done: frames=%d checksum=%016Lx" !frame
       (Checksum.value checksum)
   | None -> ());
  ignore (Lui_app.dispose app);
  (match gctx with
   | Some c -> Sdl.gl_delete_context c
   | None -> ());
  Sdl.destroy_window !win;
  Sdl.quit ()
