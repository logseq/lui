(* Manual placement demo: SDL window + embedded WKWebView moved across
   a few layout rects, then captured to PNG.

   Usage: wv_demo.exe [out.png] [url]
   Defaults: out.png = /tmp/lui_wv_demo.png, url = an inline page. *)

module Sdl = Tsdl.Sdl

(* Pump the run loop until the view finished its current load or the
   deadline passes. *)
let settle t secs =
  let deadline = Unix.gettimeofday () +. secs in
  let rec loop () =
    Lui_webview.pump ();
    Sdl.pump_events ();
    ignore (Lui_webview.drain t);
    if Unix.gettimeofday () < deadline then begin
      Unix.sleepf 0.02;
      loop ()
    end
  in
  loop ()

let () =
  let out =
    if Array.length Sys.argv > 1 then Sys.argv.(1)
    else "/tmp/lui_wv_demo.png"
  in
  let src =
    if Array.length Sys.argv > 2 then Lui_webview.Url Sys.argv.(2)
    else
      Lui_webview.Html
        ( "<html><body style='font:28px sans-serif;background:#225'>" ^
          "<h1 style='color:#fff;margin:30px'>lui_webview demo</h1>" ^
          "<p style='color:#9cf;margin:30px'>native subview placed by \
           layout rects</p></body></html>",
          "" )
  in
  match Sdl.init Sdl.Init.video with
  | Error (`Msg e) -> Printf.eprintf "sdl init: %s\n%!" e; exit 1
  | Ok () ->
    (match
       Sdl.create_window ~w:800 ~h:600 "lui_webview demo"
         Sdl.Window.windowed
     with
     | Error (`Msg e) -> Printf.eprintf "sdl window: %s\n%!" e; exit 1
     | Ok win ->
       let host =
         Lui_webview.host_of_sdl_window (Sdl.unsafe_ptr_of_window win)
       in
       let t =
         Lui_webview.create host (Lui_webview.rect 40. 40. 480. 320.)
           (Lui_webview.opts src)
       in
       settle t 3.0;
       let frames =
         [ Lui_webview.rect 40. 40. 480. 320.;
           Lui_webview.rect 120. 160. 400. 300.;
           Lui_webview.rect 60. 300. 640. 240.;
           Lui_webview.rect 40. 40. 720. 500. ]
       in
       List.iter
         (fun (r : Lui_webview.rect) ->
            Lui_webview.layout_webview t r;
            let f = Lui_webview.frame t in
            Printf.printf "frame -> %.0f %.0f %.0f %.0f\n%!" f.x f.y f.w
              f.h;
            settle t 0.8)
         frames;
       begin match Lui_webview.capture_page t with
       | Some png ->
         let oc = open_out_bin out in
         output_bytes oc png;
         close_out oc;
         Printf.printf "wrote %s (%d bytes)\n%!" out (Bytes.length png)
       | None -> Printf.printf "capture_page: None\n%!"
       end;
       Lui_webview.destroy t;
       Sdl.destroy_window win;
       Sdl.quit ())
