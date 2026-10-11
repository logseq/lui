(* Lui_webapp_sdl — the real webview backend for {!Lui_webapp.boot}:
   one SDL window whose entire content area is a single
   {!Lui_webview} view (WKWebView on macOS, WebKitGTK on Linux,
   WebView2 on Windows).

   The shell owns the event loop: SDL window events drive
   close/resize, {!Lui_webview.pump} and {!Lui_webview.drain} make the
   platform engine progress and deliver page events to the spec-level
   message and ready hooks. *)

module Sdl = Tsdl.Sdl

let ( let* ) = Result.bind

type window = {
  width : int;
  height : int;
  resizable : bool;
  min_width : int;
  min_height : int;
}

let available () = Lui_webview.backend_name () <> "none"

(* SDL window events: close requests and resizes. Resizes re-place the
   view over the new client rect — the window's whole content is the
   web view, so the rect is always 0,0,w,h. *)
let pump_window_events t quit =
  let ev = Sdl.Event.create () in
  Sdl.pump_events ();
  while Sdl.poll_event (Some ev) do
    (match Sdl.Event.enum (Sdl.Event.get ev Sdl.Event.typ) with
     | `Quit -> quit := true
     | `Window_event ->
       (match
          Sdl.Event.window_event_enum
            (Sdl.Event.get ev Sdl.Event.window_event_id)
        with
        | `Close -> quit := true
        | `Resized | `Size_changed ->
          let w =
            Int32.to_int (Sdl.Event.get ev Sdl.Event.window_data1)
          in
          let h =
            Int32.to_int (Sdl.Event.get ev Sdl.Event.window_data2)
          in
          Lui_webview.layout_webview t
            (Lui_webview.rect 0. 0. (Float.of_int w) (Float.of_int h))
        | _ -> ())
     | _ -> ())
  done

let sdl_window (window : window) title =
  let* () =
    match Sdl.init Sdl.Init.video with
    | Error (`Msg e) -> Error ("Sdl.init: " ^ e)
    | Ok () -> Ok ()
  in
  let flags =
    if window.resizable then Sdl.Window.(shown + resizable)
    else Sdl.Window.shown
  in
  match
    Sdl.create_window ~w:window.width ~h:window.height title flags
  with
  | Error (`Msg e) ->
    Sdl.quit ();
    Error ("Sdl.create_window: " ^ e)
  | Ok win ->
    (if window.min_width > 0 && window.min_height > 0 then
       Sdl.set_window_minimum_size win ~w:window.min_width
         ~h:window.min_height);
    Ok win

let web_view win (window : window) source =
  try
    let host =
      Lui_webview.host_of_sdl_window (Sdl.unsafe_ptr_of_window win)
    in
    Ok
      (Lui_webview.create host
         (Lui_webview.rect 0. 0. (Float.of_int window.width)
            (Float.of_int window.height))
         (Lui_webview.opts source))
  with Failure e -> Error e

let run ~(window : window) ~title ~source ~on_message ~on_ready =
  match sdl_window window title with
  | Error e -> Error e
  | Ok win ->
    (match web_view win window source with
     | Error e ->
       Sdl.destroy_window win;
       Sdl.quit ();
       Error ("webview: " ^ e)
     | Ok t ->
       let quit = ref false in
       let ready = ref false in
       let fatal = ref None in
       Fun.protect
         ~finally:(fun () ->
           Lui_webview.destroy t;
           Sdl.destroy_window win;
           Sdl.quit ())
         (fun () ->
           while not !quit && Option.is_none !fatal do
             pump_window_events t quit;
             Lui_webview.pump ();
             List.iter
               (fun (e : Lui_webview.event) ->
                  match e with
                  | Did_finish _ ->
                    if not !ready then begin
                      ready := true;
                      on_ready ~eval:(fun js -> Lui_webview.eval t js)
                    end
                  | Script_message m -> on_message m
                  | Load_error (u, m) ->
                    (* A failed initial load leaves an unusable shell:
                       fatal. Later navigation errors are reported but
                       let the app recover. *)
                    if !ready then
                      Printf.eprintf
                        "lui_webapp: navigation error on %s: %s\n%!" u m
                    else
                      fatal :=
                        Some
                          (Printf.sprintf "%s failed to load: %s" u m)
                  | Did_navigate _ | Did_commit _ -> ())
               (Lui_webview.drain t);
             Unix.sleepf 0.01
           done);
       (match !fatal with Some e -> Error e | None -> Ok ()))
