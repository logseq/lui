(* Software present path: full + region texture updates under the
   dummy video driver (a headless run produces a real SDL software
   renderer, so these exercise the actual upload calls). *)

module Sdl = Tsdl.Sdl

let init () =
  Unix.putenv "SDL_VIDEODRIVER" "dummy";
  match Sdl.init Sdl.Init.(video + events) with
  | Ok () -> ()
  | Error (`Msg m) -> Alcotest.failf "Sdl.init: %s" m

let with_window f =
  init ();
  match Sdl.create_window ~w:64 ~h:48 "blit" Sdl.Window.hidden with
  | Error (`Msg m) -> Alcotest.failf "window: %s" m
  | Ok win ->
    let v = f win in
    Sdl.destroy_window win;
    v

let frame w h fill =
  let pix = Bytes.create (w * h * 4) in
  Bytes.fill pix 0 (Bytes.length pix) fill;
  pix

let create_and_full_update () =
  with_window @@ fun win ->
  let b =
    match Lui_blit.create win ~w:64 ~h:48 with
    | Ok b -> b
    | Error m -> Alcotest.failf "create: %s" m
  in
  (match Lui_blit.update b ~pix:(frame 64 48 '\x7f') ~stride:64 with
   | Ok () -> ()
   | Error m -> Alcotest.failf "update: %s" m);
  Lui_blit.present b

let update_region_uploads_clipped () =
  with_window @@ fun win ->
  let b =
    match Lui_blit.create win ~w:64 ~h:48 with
    | Ok b -> b
    | Error m -> Alcotest.failf "create: %s" m
  in
  let pix = frame 64 48 '\xff' in
  (* in-bounds rect *)
  (match Lui_blit.update_region b ~x0:8 ~y0:8 ~x1:40 ~y1:24 ~pix ~stride:64 with
   | Ok () -> ()
   | Error m -> Alcotest.failf "region: %s" m);
  (* clipped rect — must not fail or read out of bounds *)
  (match Lui_blit.update_region b ~x0:50 ~y0:40 ~x1:80 ~y1:60 ~pix ~stride:64 with
   | Ok () -> ()
   | Error m -> Alcotest.failf "clipped: %s" m);
  (* empty rect *)
  (match Lui_blit.update_region b ~x0:5 ~y0:5 ~x1:5 ~y1:20 ~pix ~stride:64 with
   | Ok () -> ()
   | Error m -> Alcotest.failf "empty: %s" m);
  Lui_blit.present b

let resize_recreates_texture () =
  with_window @@ fun win ->
  let b =
    match Lui_blit.create win ~w:64 ~h:48 with
    | Ok b -> b
    | Error m -> Alcotest.failf "create: %s" m
  in
  (match Lui_blit.resize b ~w:128 ~h:96 with
   | Ok () -> ()
   | Error m -> Alcotest.failf "resize: %s" m);
  (match Lui_blit.update b ~pix:(frame 128 96 '\x01') ~stride:128 with
   | Ok () -> ()
   | Error m -> Alcotest.failf "update after resize: %s" m);
  Lui_blit.present b

let () =
  Alcotest.run "lui_blit" [
    ("present", [
      Alcotest.test_case "create + full update" `Quick create_and_full_update;
      Alcotest.test_case "region updates clip" `Quick update_region_uploads_clipped;
      Alcotest.test_case "resize" `Quick resize_recreates_texture;
    ]);
  ]
