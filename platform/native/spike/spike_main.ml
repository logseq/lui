(* Throwaway validation app for the native backend substrate: opens an
   SDL2 window via tsdl, runs an event loop (quit / resize / keyboard),
   renders an animated CPU framebuffer each frame, uploads it to a
   streaming texture and presents. No GL is used on the pixel path.

   Controls: Esc/Q quits, Space pauses the animation, R resets it.
   Headless: SDL_VIDEODRIVER=dummy ./spike --headless renders a fixed
   number of frames on a virtual clock and prints a framebuffer checksum. *)

module Sdl = Tsdl.Sdl
module Ttf = Tsdl_ttf.Ttf

let log fmt = Printf.eprintf (fmt ^^ "\n%!")

let fail_of = function
  | Ok v -> v
  | Error _ -> failwith (Sdl.get_error ())

type config = {
  w : int;
  h : int;
  frames : int; (* -1 = run until quit *)
  headless : bool;
  no_ttf : bool;
}

let default_config =
  { w = 800; h = 500; frames = -1; headless = false; no_ttf = false }

let usage () =
  log "usage: spike [--headless] [--frames N] [--size WxH] [--no-ttf]";
  exit 2

let parse_argv () =
  let c = ref default_config in
  let i = ref 1 in
  let need_value () =
    incr i;
    if !i >= Array.length Sys.argv then usage ();
    Sys.argv.(!i)
  in
  while !i < Array.length Sys.argv do
    begin
      match Sys.argv.(!i) with
      | "--headless" ->
          c :=
            {
              !c with
              headless = true;
              frames = (if !c.frames < 0 then 120 else !c.frames);
            }
      | "--frames" ->
          let v = need_value () in
          c := { !c with frames = int_of_string v }
      | "--size" ->
          let v = need_value () in
          begin
            match String.split_on_char 'x' v with
            | [ w; h ] ->
                c := { !c with w = int_of_string w; h = int_of_string h }
            | _ -> usage ()
          end
      | "--no-ttf" -> c := { !c with no_ttf = true }
      | "--help" | "-h" -> usage ()
      | _ -> usage ()
    end;
    incr i
  done;
  !c

(* --- fonts ------------------------------------------------------------- *)

let font_candidates () =
  let env =
    match Sys.getenv_opt "SPIKE_FONT" with Some p -> [ p ] | None -> []
  in
  env
  @ [
      "/System/Library/Fonts/SFNSMono.ttf";
      "/System/Library/Fonts/Supplemental/Arial.ttf";
      "/System/Library/Fonts/Supplemental/Andale Mono.ttf";
      "/System/Library/Fonts/Geneva.ttf";
      "/System/Library/Fonts/Helvetica.ttc";
    ]

let open_font () =
  let rec try_paths = function
    | [] -> None
    | path :: rest -> (
        match Ttf.open_font path 26 with
        | Ok f ->
            log "ttf: using font %s" path;
            Some f
        | Error _ -> try_paths rest)
  in
  try_paths (font_candidates ())

(* Rasterize a string once into an ARGB8888 surface snapshot that the
   framebuffer can source-over blend every frame. *)
let render_label font text =
  match
    Ttf.render_utf8_blended font text
      (Sdl.Color.create ~r:235 ~g:238 ~b:245 ~a:255)
  with
  | Error _ -> None
  | Ok surf -> (
      match Sdl.convert_surface_format surf Sdl.Pixel.format_argb8888 with
      | Error _ ->
          Sdl.free_surface surf;
          None
      | Ok conv ->
          Sdl.free_surface surf;
          let lw, lh = Sdl.get_surface_size conv in
          Some
            {
              Spike_render.lw;
              lh;
              lpitch = Sdl.get_surface_pitch conv;
              lpix = Sdl.get_surface_pixels conv Bigarray.int8_unsigned;
            })

(* --- main loop ---------------------------------------------------------- *)

type state = {
  mutable quit : bool;
  mutable paused : bool;
  mutable t_anim : float;
  mutable prev_wall : float;
  mutable frame : int;
}

type stats = {
  mutable n : int;
  mutable acc_ms : float;
  mutable min_ms : float;
  mutable max_ms : float;
  mutable total_n : int;
  mutable total_ms : float;
  mutable report_at : float;
  mutable fps : int;
  mutable last_ms : float;
}

let perf_s () =
  Int64.to_float (Sdl.get_performance_counter ())
  /. Int64.to_float (Sdl.get_performance_frequency ())

let handle_events st e =
  while Sdl.poll_event (Some e) do
    match Sdl.Event.enum (Sdl.Event.get e Sdl.Event.typ) with
    | `Quit -> st.quit <- true
    | `Window_event -> (
        let wid = Sdl.Event.get e Sdl.Event.window_event_id in
        match Sdl.Event.window_event_enum wid with
        | `Resized | `Size_changed ->
            let w = Int32.to_int (Sdl.Event.get e Sdl.Event.window_data1) in
            let h = Int32.to_int (Sdl.Event.get e Sdl.Event.window_data2) in
            log "event: window resized to %dx%d" w h
        | `Close -> st.quit <- true
        | _ -> ())
    | `Key_down -> (
        match
          Sdl.Scancode.enum (Sdl.Event.get e Sdl.Event.keyboard_scancode)
        with
        | `Escape | `Q -> st.quit <- true
        | `Space -> st.paused <- not st.paused
        | `R -> st.t_anim <- 0.
        | _ -> ())
    | _ -> ()
  done

let make_renderer win =
  (* Prefer vsync so the loop is display-paced; fall back to SDL's default
     (software) renderer, which is the only one available under the dummy
     video driver. *)
  match
    Sdl.create_renderer ~flags:Sdl.Renderer.(accelerated + presentvsync) win
  with
  | Ok r -> (r, true)
  | Error _ -> (fail_of (Sdl.create_renderer win), false)

let init_font cfg =
  if cfg.no_ttf then (
    log "ttf: disabled by --no-ttf (shapes only)";
    None)
  else
    match Ttf.init () with
    | Error (`Msg m) ->
        log "ttf: Ttf.init failed: %s (shapes only)" m;
        None
    | Ok () -> (
        match open_font () with
        | None ->
            log "ttf: no usable font found (shapes only)";
            None
        | Some _ as f -> f)

let main () =
  let cfg = parse_argv () in
  try
    fail_of (Sdl.init Sdl.Init.(video + events));
    let font = init_font cfg in
    let win =
      fail_of
        (Sdl.create_window "lui native spike" ~w:cfg.w ~h:cfg.h
           Sdl.Window.(shown + resizable + allow_highdpi))
    in
    let rend, vsync = make_renderer win in
    let info = fail_of (Sdl.get_renderer_info rend) in
    log "renderer: %s (vsync flag %s)"
      info.Sdl.ri_name
      (if Sdl.Renderer.test info.Sdl.ri_flags Sdl.Renderer.presentvsync then
         "set"
       else "clear");
    let out_w, out_h = fail_of (Sdl.get_renderer_output_size rend) in
    log "window %dx%d, renderer output %dx%d, vsync=%b" cfg.w cfg.h out_w
      out_h vsync;
    let tex =
      fail_of
        (Sdl.create_texture rend Sdl.Pixel.format_argb8888
           Sdl.Texture.access_streaming ~w:cfg.w ~h:cfg.h)
    in
    let fb = Spike_render.create ~w:cfg.w ~h:cfg.h in
    let title_label =
      match font with
      | Some f -> render_label f "lui native spike - tsdl ok"
      | None -> None
    in
    let fps_label =
      ref
        (match (font, cfg.headless) with
        | Some f, true -> render_label f "headless run"
        | _ -> None)
    in
    let e = Sdl.Event.create () in
    let st =
      {
        quit = false;
        paused = false;
        t_anim = 0.;
        prev_wall = perf_s ();
        frame = 0;
      }
    in
    let stats =
      {
        n = 0;
        acc_ms = 0.;
        min_ms = infinity;
        max_ms = 0.;
        total_n = 0;
        total_ms = 0.;
        report_at = st.prev_wall +. 1.;
        fps = 0;
        last_ms = 0.;
      }
    in
    let last_label = ref 0. in
    while (not st.quit) && (cfg.frames < 0 || st.frame < cfg.frames) do
      handle_events st e;
      let t0 = perf_s () in
      let dt = if cfg.headless then 1. /. 60. else t0 -. st.prev_wall in
      st.prev_wall <- t0;
      if not st.paused then st.t_anim <- st.t_anim +. dt;
      Spike_render.render fb ~time:st.t_anim;
      (match title_label with
      | Some l -> Spike_render.blit_label fb ~x0:16 ~y0:12 l
      | None -> ());
      begin
        match font with
        | Some f when (not cfg.headless) && t0 -. !last_label > 0.25 ->
            let text =
              Printf.sprintf "fps %d   frame %.1f ms" stats.fps
                stats.last_ms
            in
            last_label := t0;
            fps_label := render_label f text
        | _ -> ()
      end;
      (match !fps_label with
      | Some l -> Spike_render.blit_label fb ~x0:16 ~y0:(cfg.h - l.lh - 12) l
      | None -> ());
      fail_of (Sdl.update_texture tex None fb.px fb.w);
      fail_of (Sdl.render_copy rend tex);
      Sdl.render_present rend;
      let ms = (perf_s () -. t0) *. 1000. in
      stats.last_ms <- ms;
      stats.n <- stats.n + 1;
      stats.acc_ms <- stats.acc_ms +. ms;
      stats.min_ms <- min stats.min_ms ms;
      stats.max_ms <- max stats.max_ms ms;
      stats.total_n <- stats.total_n + 1;
      stats.total_ms <- stats.total_ms +. ms;
      st.frame <- st.frame + 1;
      if t0 >= stats.report_at then begin
        stats.fps <- stats.n;
        Printf.printf "fps=%d avg_ms=%.2f min_ms=%.2f max_ms=%.2f t=%.2f\n%!"
          stats.n
          (stats.acc_ms /. float stats.n)
          stats.min_ms stats.max_ms st.t_anim;
        stats.n <- 0;
        stats.acc_ms <- 0.;
        stats.min_ms <- infinity;
        stats.max_ms <- 0.;
        stats.report_at <- t0 +. 1.
      end;
      if (not cfg.headless) && not vsync then begin
        let remaining = 16.6 -. ((perf_s () -. t0) *. 1000.) in
        if remaining > 1. then
          Sdl.delay (Int32.of_int (int_of_float remaining))
      end
    done;
    let checksum = Spike_render.fnv1a fb in
    Printf.printf
      "done: frames=%d avg_render_ms=%.2f checksum=0x%08Lx ttf=%s vsync=%b\n%!"
      stats.total_n
      (stats.total_ms /. float (max 1 stats.total_n))
      checksum
      (if Option.is_some font then "on" else "off")
      vsync;
    Sdl.destroy_texture tex;
    Sdl.destroy_renderer rend;
    Sdl.destroy_window win;
    (match font with Some f -> Ttf.close_font f | None -> ());
    if Option.is_some font then Ttf.quit ();
    Sdl.quit ();
    exit 0
  with
  | Failure m ->
      log "spike: %s" m;
      exit 1

(* invoked from spike.ml *)
