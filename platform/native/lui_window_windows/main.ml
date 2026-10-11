(* Win32 window driver: creates the host window through [Lui_win32]
   (a Win32 CreateWindowW path — this build has no SDL/tsdl, so the
   window, the decoded event queue, the IMM32 hooks and the DIB
   present all live in lui_window_windows_stubs.c), wires [Lui_host]
   with the renderer ladder below, feeds decoded events through
   [Lui_window.Ui] into [Lui_app.dispatch_event], serves the
   [Lui_a11y] tree through [Lui_ax_windows] (the window procedure
   forwards WM_GETOBJECT to the bridge — see the stubs) and hosts
   the desktop shell through [Lui_shell_windows].

   Renderer ladder (see [Lui_window_windows.ladder]): the default
   tries [Lui_d3d11] on the window's HWND (a real DXGI swapchain),
   then a [Lui_d3d11] offscreen target whose frames are read back
   and blitted through the DIB path; "gl" reports unavailable on
   this build (no GL bindings installed) and falls through; "0"|"cpu"
   renders with [Lui_raster] and presents damaged rects (or the whole
   frame) via StretchDIBits. Every failed rung falls to the next,
   ending at a no-op loop renderer — the process never crashes for
   want of a GPU or display.

   Flags: --width N --height N --headless N. *)

open Lui_window

let log fmt = Printf.printf (fmt ^^ "\n%!")
let warn fmt = Printf.eprintf (fmt ^^ "\n%!")

let perf_s = Lui_win32.perf_s

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
      warn "%s\nusage: lui_window_windows [--width N] [--height N] [--headless N]"
        msg;
      exit 2
  in
  let headless = Option.is_some cfg.headless_frames in
  let rungs =
    Lui_window_windows.ladder
      ~env:(try Sys.getenv "LUI_GPU" with Not_found -> "")
  in
  (* The window is created before renderer selection: the D3D11 rung
     wants the HWND for its swapchain, and a hidden window still owns
     a full Win32 message pump for headless runs. *)
  let hwnd =
    Lui_win32.create_window ~w:cfg.width ~h:cfg.height
      ~title:"lui_window_windows" ~hidden:headless
  in
  (* Client area in device pixels — under per-monitor-v2 awareness
     client coordinates are physical pixels, which is what the paint
     pass, the hit-test mirror and the DIB present all use. *)
  let drawable () =
    match Lui_win32.client_size hwnd with
    | 0, 0 -> (cfg.width, cfg.height)
    | d -> d
  in
  let dw, dh = drawable () in
  let scale = Float.max 0.01 (Lui_win32.dpi_scale hwnd) in
  (* Renderer selection. [d3d_state] keeps the live [Lui_d3d11.t] for
     release at shutdown; [present_last] remembers the last blitted
     frame so a WM_PAINT can be answered without a full repaint. *)
  let d3d_state = ref None in
  let present_last = ref None in
  (* The ladder walk returns the renderer plus the live [Lui_d3d11.t]
     (when a D3D11 rung won) so shutdown can release the device. *)
  let renderer, d3d_live =
    let rec walk = function
      | [] ->
        warn "all renderer rungs failed; using no-op loop renderer";
        (Lui_window_windows.noop_renderer, None)
      | rung :: rest -> (
        match rung with
        | Lui_window_windows.Cpu -> (
          (* CPU rung: Lui_raster renders the scene; StretchDIBits
             uploads the damaged rects (or the whole frame). *)
          match
            let rr = Lui_raster.Renderer.create () in
            { Lui_host.name = "lui_raster+dib";
              render =
                (fun s ->
                   let dirty = Lui_raster.Renderer.render rr s in
                   let img = Lui_raster.Renderer.image rr in
                   let pix = img.Lui_raster.Image.pix in
                   let stride = img.Lui_raster.Image.stride / 4 in
                   let w = img.Lui_raster.Image.w
                   and h = img.Lui_raster.Image.h in
                   if Lui_raster.Renderer.whole rr || dirty = [] then
                     ignore (Lui_win32.present_frame hwnd pix ~w ~h)
                   else
                     List.iter
                       (fun (r : Lui_scene.irect) ->
                          ignore
                            (Lui_win32.present_region hwnd ~x0:r.x0
                               ~y0:r.y0 ~x1:r.x1 ~y1:r.y1 ~pix ~stride))
                       dirty;
                   present_last := Some (pix, w, h);
                   pix) }
          with
          | r -> (r, None)
          | exception e ->
            warn "cpu rung init failed: %s" (Printexc.to_string e);
            walk rest)
        | Lui_window_windows.D3d11 -> (
          (* Default rung: first a swapchain on the window's HWND —
             real presentation with GPU rasterization — then an
             offscreen render target whose frames are read back and
             uploaded through the same DIB path as the CPU rung.
             [Lui_d3d11.render] auto-resizes its target to the scene
             size, so resizes need no extra plumbing. *)
          let try_hwnd () =
            match Lui_d3d11.init_hwnd hwnd ~w:dw ~h:dh with
            | Ok d ->
              Some
                ( { Lui_host.name = "lui_d3d11 (hwnd)";
                    render =
                      (fun s ->
                         Lui_d3d11.render d s;
                         Bytes.empty) },
                  Some d )
            | Error e ->
              warn "lui_d3d11.init_hwnd failed: %s" e;
              None
          in
          let try_offscreen () =
            match Lui_d3d11.init_offscreen ~w:dw ~h:dh with
            | Ok d ->
              Some
                ( { Lui_host.name = "lui_d3d11 (offscreen+blit)";
                    render =
                      (fun s ->
                         Lui_d3d11.render d s;
                         let px =
                           Lui_d3d11.read_frame d ~w:s.Lui_scene.width
                             ~h:s.Lui_scene.height
                         in
                         ignore
                           (Lui_win32.present_frame hwnd px
                              ~w:s.Lui_scene.width
                              ~h:s.Lui_scene.height);
                         present_last :=
                           Some (px, s.Lui_scene.width, s.Lui_scene.height);
                         px) },
                  Some d )
            | Error e ->
              warn "lui_d3d11.init_offscreen failed: %s" e;
              None
          in
          match try_hwnd () with
          | Some v -> v
          | None -> (
            match try_offscreen () with
            | Some v -> v
            | None -> walk rest))
        | Lui_window_windows.Gl ->
          (* This build carries no GL bindings (tsdl/tgls are not
             installed on the VM), so the rung can only report and
             yield — a build that links Lui_gl would create a WGL
             context on the HWND here. *)
          warn "lui_gl unavailable on this build (no GL bindings)";
          walk rest
        | Lui_window_windows.Noop ->
          (Lui_window_windows.noop_renderer, None))
    in
    walk rungs
  in
  d3d_state := d3d_live;

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
      (Lui_protocol.profile Lui_protocol.WindowsOS Lui_protocol.GenericHost)
  in
  let app = Demo_app.create backend in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  (* Priming layout: fills the hit-test mirror so autofocus and the
     a11y frames below see real rects. *)
  refresh_layout ();
  (* Ui driver hooks: real glyph measurement for caret/selection math,
     unshifted engine rects for scroll_show/visible-range. *)
  Ui.set_measure ui
    (fun _store id s -> Lui_window_text.measure_text text_engine id s);
  Ui.set_content_rect ui (fun id -> Rects.get rects id);
  (* The a11y forest mirrors the store: synced after every repaint,
     focused along with the Ui focus, served over UIA by
     [Lui_ax_windows]. [frame_of] answers in client pixels — the
     bridge maps them to screen coordinates with ClientToScreen; the
     window procedure forwards WM_GETOBJECT to the bridge inside
     lui_window_windows_stubs.c, so no subclassing is needed here. *)
  let a11y = Lui_a11y.of_store store in
  let ax =
    Lui_ax_windows.attach
      ~frame_of:(fun id ->
        let r = Rects.get rects id in
        if Lui_scene.rect_empty r then None
        else
          Some
            { Lui_ax_windows.x = r.Lui_scene.x;
              Lui_ax_windows.y = r.Lui_scene.y;
              Lui_ax_windows.w = r.Lui_scene.w;
              Lui_ax_windows.h = r.Lui_scene.h })
      a11y hwnd
  in
  let quit = ref false in
  (* Hand focus to the first autofocus field, if any — and open the
     IME context for it (IMM32 associate; headless is a no-op when
     the OS has no IME installed). *)
  (match
     List.find_opt
       (fun id -> bool_prop store id "autofocus")
       (Lui_store.preorder store)
   with
   | Some id ->
     Ui.set_focused ui store id;
     Lui_ax_windows.set_focused ax id;
     Lui_win32.set_ime_enabled hwnd true
   | None -> ());
  (* Shell integration — a tray status item with a real Win32 popup
     menu, plus the notify/clipboard calls the driver fires on model
     requests. Interactive only: none of it is wanted under headless
     and skipping it keeps the checksum deterministic. *)
  let pending : Demo_app.action Queue.t = Queue.create () in
  let status_item =
    if headless then None
    else begin
      let item = Lui_shell_windows.status_item_create ~tag:1 () in
      Lui_shell_windows.status_item_set_title item "lui_window_windows";
      (match
         Lui_shell_windows.image_of_rgba ~width:22 ~height:22
           (Lui_window_windows.tray_icon_rgba ())
       with
       | Some img ->
         Lui_shell_windows.status_item_set_image item (Some img)
       | None -> ());
      let spec label id =
        Lui_shell_windows.Item
          { Lui_shell_windows.label = label; Lui_shell_windows.id = id;
            enabled = true; checked = false }
      in
      Lui_shell_windows.status_item_set_menu item
        (Some
           (Lui_shell_windows.menu ~title:"lui_window_windows"
              [ spec "show toast" 1;
                spec "notify" 2;
                spec "copy stats" 3;
                spec "dump a11y" 4;
                Lui_shell_windows.Separator;
                spec "quit" 9 ]));
      Lui_shell_windows.set_menu_handler
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
        (Lui_app.send app (Demo_app.Badge renderer.Lui_host.name));
      Some item
    end
  in
  (* IMM32 wants the candidate-window anchor in client (device)
     pixels — the same space rects are kept in, so no scaling. *)
  let set_ime_rect (r : Lui_scene.rect) =
    Lui_win32.set_ime_rect hwnd
      ~x:(int_of_float r.Lui_scene.x)
      ~y:(int_of_float r.Lui_scene.y)
      ~w:(max 1 (int_of_float r.Lui_scene.w))
      ~h:(max 1 (int_of_float r.Lui_scene.h))
  in
  (* Caret rect of the focused field, device px: the node's layout
     rect shifted to the caret column — horizontal padding plus the
     width of t
he caret column — horizontal padding plus the
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
  let rec apply_actions acts = List.iter (function
    | Dispatch ev ->
      (try ignore (Lui_app.dispatch_event app ev)
       with Invalid_argument msg ->
         warn "dispatch rejected event: %s" msg)
    | Clipboard_write s ->
      if not headless then ignore (Lui_shell_windows.clipboard_write s)
    | Paste_request ->
      (* clipboard I/O is a driver concern: read + feed back as
         Input.Paste (interactive only — headless never types Ctrl-V) *)
      (match if headless then None else Lui_shell_windows.clipboard_read () with
       | Some s ->
         apply_actions (Ui.handle ui store rects (Input.Paste s))
       | None -> ())
    | Resize_host _ ->
      let dw, dh = drawable () in
      scale_cell := float dw /. float (max 1 !win_w);
      Ui.set_scale ui !scale_cell;
      Lui_host.resize host ~width:dw ~height:dh ~scale:!scale_cell;
      refresh_layout ();
      Lui_ax_windows.refresh_frames ax
    | Focus_changed id ->
      if id = 0 then Lui_ax_windows.clear_focused ax
      else Lui_ax_windows.set_focused ax id;
      if id = 0 then Lui_win32.set_ime_enabled hwnd false
      else begin
        Lui_win32.set_ime_enabled hwnd true;
        set_ime_rect (Rects.get rects id)
      end
    | Ime_rect r -> set_ime_rect r
    | Quit -> quit := true)
    acts
  in
  (* UIA actions from assistive tech route through the same dispatch
     path as pointer input. [drain_actions] is pumped once per frame. *)
  let apply_ax_actions () =
    List.iter
      (fun (id, action) ->
         match action with
         | Lui_ax_windows.Focus ->
           if Lui_store.mem store id && node_enabled store id then begin
             Ui.set_focused ui store id;
             apply_actions [ Focus_changed id ]
           end
         | _ -> (
           match Lui_window_windows.a11y_event_of_action store id action with
           | Some ev -> apply_actions [ Dispatch ev ]
           | None -> ()))
      (Lui_ax_windows.drain_actions ax)
  in
  (* Model actions the shell layer queues out-of-band (tray menu):
     the event drain sends them into the app on the next frame, same
     as pointer input. *)
  let drain_events () =
    Queue.iter (fun a -> ignore (Lui_app.send app a)) pending;
    Queue.clear pending;
    let go = ref true in
    while !go do
      let ev = Lui_win32.next_event () in
      if ev.Lui_win32.tag = 0 then go := false
      else if ev.Lui_win32.tag = 10 then
        (* WM_PAINT: Windows owns no back-buffer for this window, so a
           damaged region must be re-blitted from the last frame --
           cheaper than forcing a repaint when a blit path is live. *)
        (match !present_last with
         | Some (pix, w, h) ->
           ignore (Lui_win32.present_frame hwnd pix ~w ~h)
         | None -> ())
      else
        match Lui_window_windows.input_of_event ~scale:!scale_cell ev with
        | Some (Input.Resize (w, h)) ->
          win_w := w;
          win_h := h;
          apply_actions
            (Ui.handle ui store rects (Input.Resize (w, h)))
        | Some input ->
          apply_actions (Ui.handle ui store rects input)
        | None -> ()
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
          Lui_shell_windows.notify ~id:"demo" ~title:"lui_window_windows"
            ~body:"notification from the native demo" () in
        log "shell notify: posted=%b (%s)" posted detail
      end;
      if req_hit "clipboard" m.Demo_app.req_clipboard then begin
        let s =
          Printf.sprintf "lui_window_windows %dx%d renderer=%s frames=%d"
            dw dh renderer.Lui_host.name !frame in
        log "shell clipboard: wrote %d chars (ok=%b)"
          (String.length s) (Lui_shell_windows.clipboard_write s)
      end;
      if req_hit "a11y" m.Demo_app.req_a11y then begin
        let names =
          List.map
            (fun n -> Lui_a11y.role_name n.Lui_a11y.role)
            (Lui_a11y.flatten a11y) in
        log "a11y: %d nodes — %s" (Lui_a11y.node_count a11y)
          (String.concat ", " names)
      end;
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
  log "lui_window_windows: %dx%d drawable (scale %.2f), renderer=%s%s"
    dw dh scale renderer.Lui_host.name
    (if headless then " [headless]" else "");
  while continue () do
    let t0 = perf_s () in
    drain_events ();
    (* Patches queued by dispatched events land in the store here;
       layout must see them before the next paint or hit test. *)
    if Lui_app.flush app then refresh_layout ();
    (* Store-driven effects: Appear lifecycle events, scroll-target
       completions, visible-range reports, modal focus save/restore. *)
    apply_actions (Ui.store_changed ui store);
    (* Shell event pump: tray-menu selections and notification
       activations dispatch on this thread via the shell's hidden
       window. *)
    if not headless then ignore (Lui_shell_windows.pump_pending ());
    apply_ax_actions ();
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
      Ui.frame_done ui;
      incr frame;
      Checksum.add_scene checksum (Lui_host.scene host);
      if headless then
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
    (* The semantic tree tracks the store every iteration — cheap
       when nothing changed, and UIA needs it between paints too
       (focus moves without a repaint). *)
    ignore (Lui_ax_windows.sync ax);
    (* No vsync on this path: pace the loop explicitly. An idle
       iteration (no repaint) also sleeps briefly so the poll loop
       does not spin at 100% CPU. *)
    if not headless then begin
      if dirty then begin
        let remaining = 16.6 -. ((perf_s () -. t0) *. 1000.) in
        if remaining > 0.5 then
          Lui_win32.delay_ms (int_of_float remaining)
      end
      else Lui_win32.delay_ms 4
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
  Lui_ax_windows.detach ax;
  (match status_item with
   | Some item -> Lui_shell_windows.status_item_remove item
   | None -> ());
  (match !d3d_state with
   | Some d -> Lui_d3d11.release d
   | None -> ());
  Lui_win32.destroy_window hwnd
