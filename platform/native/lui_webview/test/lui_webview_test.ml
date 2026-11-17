(* Cross-platform API tests for Lui_webview: everything that must hold
   without a display or a platform backend. Platform coverage: the
   Linux and Windows code paths are compile-tested by building this
   library on those targets; their runtime behaviour is asserted only
   where a backend exists (see lui_webview_mac_test). *)

let test_backend_name () =
  let n = Lui_webview.backend_name () in
  Alcotest.(check bool) "non-empty" true (String.length n > 0);
  Alcotest.(check bool) "known backend" true
    (List.mem n [ "wkwebview"; "webkit2gtk"; "webview2"; "none" ])

let test_opts () =
  let o = Lui_webview.opts (Lui_webview.Url "https://example.com") in
  Alcotest.(check string) "ua default" "" o.user_agent;
  Alcotest.(check (float 0.001)) "zoom default" 1.0 o.zoom;
  Alcotest.(check bool) "not transparent" false o.transparent;
  let o2 = Lui_webview.opts ~user_agent:"UA" ~zoom:2.0 ~transparent:true
             (Lui_webview.Html ("<p>x</p>", "")) in
  Alcotest.(check string) "ua" "UA" o2.user_agent;
  Alcotest.(check (float 0.001)) "zoom" 2.0 o2.zoom

let test_rect () =
  let r = Lui_webview.rect 1.5 2.5 30. 40. in
  Alcotest.(check (float 0.001)) "x" 1.5 r.x;
  Alcotest.(check (float 0.001)) "y" 2.5 r.y;
  Alcotest.(check (float 0.001)) "w" 30. r.w;
  Alcotest.(check (float 0.001)) "h" 40. r.h

let test_bad_host () =
  (* A null SDL window pointer is rejected on every platform. *)
  try
    let host = Lui_webview.host_of_sdl_window 0n in
    ignore host;
    Alcotest.fail "expected host_of_sdl_window to raise"
  with Failure _ -> ()

let () =
  Alcotest.run "lui_webview"
    [ ( "api",
        [ Alcotest.test_case "backend_name" `Quick test_backend_name;
          Alcotest.test_case "opts" `Quick test_opts;
          Alcotest.test_case "rect" `Quick test_rect;
          Alcotest.test_case "bad sdl host" `Quick test_bad_host ] ) ]
