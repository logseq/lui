(* macOS-only: embeds a real WKWebView inside an SDL window and drives
   the documented behaviours end to end.

   Headless note: creating an NSWindow needs a WindowServer session.
   On machines without one (ssh, some CI) [Sdl.init] or window
   creation fails; the suite then reports itself skipped rather than
   failed.

   One SDL host window is shared by the whole suite: SDL on macOS is
   not reliably re-initialisable after [Sdl.quit], so tests create and
   destroy their own webviews inside this window instead of cycling
   windows. *)

module Sdl = Tsdl.Sdl

let window : Sdl.window option ref = ref None

let win () =
  match !window with
  | Some w -> w
  | None ->
    (match Sdl.init Sdl.Init.video with
     | Error (`Msg e) ->
       Printf.printf "SKIP: sdl init: %s\n%!" e;
       exit 0
     | Ok () ->
       (match
          Sdl.create_window ~w:640 ~h:480 "lui_webview test"
            Sdl.Window.windowed
        with
        | Error (`Msg e) ->
          Printf.printf "SKIP: sdl window: %s\n%!" e;
          Sdl.quit ();
          exit 0
        | Ok w ->
          window := Some w;
          at_exit (fun () -> Sdl.destroy_window w; Sdl.quit ());
          w))

(* Pump the platform run loop and SDL until [pred] holds or the
   deadline passes. Drained events accumulate in [evs]: the C queue is
   consumed by [drain], so every spin must append, never discard. *)
let spin ?(secs = 10.0) t evs pred =
  let deadline = Unix.gettimeofday () +. secs in
  let rec loop () =
    Lui_webview.pump ();
    Sdl.pump_events ();
    evs := !evs @ Lui_webview.drain t;
    if pred () then ()
    else if Unix.gettimeofday () > deadline then ()
    else begin Unix.sleepf 0.01; loop () end
  in
  loop ()

let has_finish evs =
  List.exists (function Lui_webview.Did_finish _ -> true | _ -> false)
    evs

let create_view src rect =
  let host = Lui_webview.host_of_sdl_window (Sdl.unsafe_ptr_of_window (win ())) in
  Lui_webview.create host rect (Lui_webview.opts src)

let html = "<html><body><h1>lui_webview</h1></body></html>"

let test_load_finish () =
  let t =
    create_view (Lui_webview.Html (html, ""))
      (Lui_webview.rect 10. 10. 300. 200.)
  in
  let evs = ref [] in
  spin ~secs:8.0 t evs (fun () -> has_finish !evs);
  Alcotest.(check bool) "did_finish" true (has_finish !evs);
  Alcotest.(check bool) "not loading" false (Lui_webview.is_loading t);
  Lui_webview.destroy t

let test_eval_roundtrip () =
  let t =
    create_view (Lui_webview.Html (html, ""))
      (Lui_webview.rect 10. 10. 300. 200.)
  in
  let got = ref None in
  let evs = ref [] in
  Lui_webview.call_async t "return 1 + 1" (fun s -> got := Some s);
  spin t evs (fun () -> !got <> None);
  Alcotest.(check (option string)) "1+1" (Some "2") !got;
  (* fire-and-forget eval must not crash *)
  Lui_webview.eval t "document.title = 'lui'";
  let got2 = ref None in
  Lui_webview.call_async t "return document.title"
    (fun s -> got2 := Some s);
  spin t evs (fun () -> !got2 <> None);
  (* Results come back bridged: strings raw, other values JSON. *)
  Alcotest.(check (option string)) "title" (Some "lui") !got2;
  Lui_webview.destroy t

let test_frame () =
  let t =
    create_view (Lui_webview.Html (html, ""))
      (Lui_webview.rect 10. 10. 300. 200.)
  in
  let f0 = Lui_webview.frame t in
  Alcotest.(check (float 0.5)) "x0" 10. f0.x;
  Alcotest.(check (float 0.5)) "y0" 10. f0.y;
  Alcotest.(check (float 0.5)) "w0" 300. f0.w;
  Alcotest.(check (float 0.5)) "h0" 200. f0.h;
  Lui_webview.layout_webview t (Lui_webview.rect 24. 36. 200. 150.);
  let f1 = Lui_webview.frame t in
  Alcotest.(check (float 0.5)) "x1" 24. f1.x;
  Alcotest.(check (float 0.5)) "y1" 36. f1.y;
  Alcotest.(check (float 0.5)) "w1" 200. f1.w;
  Alcotest.(check (float 0.5)) "h1" 150. f1.h;
  Lui_webview.destroy t

let test_capture () =
  let t =
    create_view (Lui_webview.Html (html, ""))
      (Lui_webview.rect 10. 10. 300. 200.)
  in
  let evs = ref [] in
  spin ~secs:8.0 t evs (fun () -> not (Lui_webview.is_loading t));
  match Lui_webview.capture_page t with
  | None -> Alcotest.fail "capture_page returned None"
  | Some png ->
    Alcotest.(check bool) "png signature" true
      (Bytes.length png > 8
       && Bytes.get png 0 = '\x89'
       && Bytes.sub_string png 1 3 = "PNG");
    Lui_webview.destroy t

let test_script_message () =
  let t =
    create_view (Lui_webview.Html (html, ""))
      (Lui_webview.rect 10. 10. 300. 200.)
  in
  Lui_webview.eval t "webkit.messageHandlers.lui_wv.postMessage('ping')";
  let evs = ref [] in
  spin ~secs:3.0 t evs (fun () ->
      List.exists
        (function Lui_webview.Script_message _ -> true | _ -> false)
        !evs);
  Alcotest.(check bool) "script message" true
    (List.exists
       (function Lui_webview.Script_message "\"ping\"" -> true
               | Lui_webview.Script_message "ping" -> true
               | _ -> false)
       !evs);
  Lui_webview.destroy t

let () =
  if Lui_webview.backend_name () <> "wkwebview" then
    Printf.printf "SKIP: not on macOS backend\n%!"
  else
    Alcotest.run "lui_webview_mac"
      [ ( "wkwebview",
          [ Alcotest.test_case "load -> did_finish" `Quick
              test_load_finish;
            Alcotest.test_case "eval round-trip" `Quick
              test_eval_roundtrip;
            Alcotest.test_case "set_frame readback" `Quick test_frame;
            Alcotest.test_case "capture png" `Quick test_capture;
            Alcotest.test_case "script message" `Quick
              test_script_message ] ) ]
