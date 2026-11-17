(* Loader adapters: each resource kind flows through the shared
   lifecycle — request, foreground publish, generation, scope. *)

open Alcotest

module R = Lui_resource
module L = Lui_resource_loaders
module F = Lui_plugin_fetch

let check' = check
let scope () = Signal.scope "test"

(* ---------- fixtures ---------- *)

let png_4x3 () =
  let im = Image.create_rgb ~alpha:true ~max_val:255 4 3 in
  for y = 0 to 2 do
    for x = 0 to 3 do
      Image.write_rgba im x y 10 20 30 255
    done
  done;
  let buf = Buffer.create 256 in
  ImageLib.PNG.write (ImageUtil.chunk_writer_of_buffer buf) im;
  Buffer.to_bytes buf

let tmp_file suffix contents =
  let path = Filename.temp_file "lui_res_test" suffix in
  let oc = open_out_bin path in
  output_bytes oc contents;
  close_out oc;
  path

(* ---------- keys ---------- *)

let test_keys () =
  let b = Bytes.of_string "data" in
  check' string "same bytes same key"
    (L.key_of_source ~kind:"img" (L.Bytes b))
    (L.key_of_source ~kind:"img" (L.Bytes (Bytes.of_string "data")));
  check' bool "path vs bytes differ" true
    (L.key_of_source ~kind:"img" (L.Path "/x")
    <> L.key_of_source ~kind:"img" (L.Bytes b));
  check' bool "kinds differ" true
    (L.key_of_source ~kind:"img" (L.Path "/x")
    <> L.key_of_source ~kind:"svg" (L.Path "/x"))

(* ---------- image ---------- *)

let test_image_bytes () =
  let exec, pump = R.executor_queued () in
  let c = L.Image.create ~executor:exec () in
  let sc = scope () in
  let e = L.Image.request c ~scope:sc (L.Bytes (png_4x3 ())) in
  check' int "runs" 1 (pump ());
  ignore (R.drain c);
  match (R.state e) with
  | R.Ready img ->
      check' int "w" 4 img.Lui_scene.iw;
      check' int "h" 3 img.Lui_scene.ih
  | _ -> fail "expected ready"

let test_image_garbage () =
  let exec, pump = R.executor_queued () in
  let c = L.Image.create ~executor:exec () in
  let sc = scope () in
  let e = L.Image.request c ~scope:sc (L.Bytes (Bytes.of_string "not an image")) in
  ignore (pump ());
  ignore (R.drain c);
  check' bool "failed" true (match (R.state e) with R.Failed _ -> true | _ -> false)

let test_image_path () =
  let exec, pump = R.executor_queued () in
  let c = L.Image.create ~executor:exec () in
  let sc = scope () in
  let path = tmp_file ".png" (png_4x3 ()) in
  let e = L.Image.request c ~scope:sc (L.Path path) in
  ignore (pump ());
  ignore (R.drain c);
  Sys.remove path;
  check' bool "ready" true (match (R.state e) with R.Ready _ -> true | _ -> false)

let test_image_reload_new_source () =
  let exec, pump = R.executor_queued () in
  let c = L.Image.create ~executor:exec () in
  let sc = scope () in
  let e = L.Image.request c ~scope:sc (L.Bytes (png_4x3 ())) in
  ignore (pump ());
  ignore (R.drain c);
  let e2 = L.Image.reload c ~scope:sc (L.Bytes (png_4x3 ())) in
  check' bool "same entry" true (e == e2);
  check' int "gen 2" 2 (R.generation e2);
  ignore (pump ());
  ignore (R.drain c);
  check' bool "ready again" true
    (match (R.state e2) with R.Ready _ -> true | _ -> false)

(* ---------- svg ---------- *)

let svg_src =
  {|<svg viewBox="0 0 10 10"><rect width="10" height="10" fill="#f00"/></svg>|}

let test_svg () =
  let exec, pump = R.executor_queued () in
  let c = L.Svg.create ~executor:exec () in
  let sc = scope () in
  let e = L.Svg.request c ~scope:sc (L.Bytes (Bytes.of_string svg_src)) in
  ignore (pump ());
  ignore (R.drain c);
  match (R.state e) with
  | R.Ready doc ->
      (match Lui_svg.view_box doc with
       | Some (_, _, w, h) ->
           check' bool "viewbox" true (w = 10. && h = 10.)
       | None -> fail "no viewBox")
  | _ -> fail "expected ready"

let test_svg_bad () =
  let exec, pump = R.executor_queued () in
  let c = L.Svg.create ~executor:exec () in
  let sc = scope () in
  let e =
    L.Svg.request c ~scope:sc
      (L.Bytes (Bytes.of_string {|<svg><path d="M x y z"/></svg>|}))
  in
  ignore (pump ());
  ignore (R.drain c);
  check' bool "failed" true (match (R.state e) with R.Failed _ -> true | _ -> false)

(* ---------- fetch ---------- *)

let python_bin () =
  List.find_opt
    (fun name ->
      let ic =
        Unix.open_process_in ("command -v " ^ name ^ " 2>/dev/null")
      in
      let line = try input_line ic with End_of_file -> "" in
      ignore (Unix.close_process_in ic);
      line <> "")
    [ "python3"; "python" ]

let free_port () =
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
  let port =
    match Unix.getsockname sock with
    | Unix.ADDR_INET (_, p) -> p
    | _ -> assert false
  in
  Unix.close sock;
  port

let server_ready port =
  let s = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  match
    Unix.connect s (Unix.ADDR_INET (Unix.inet_addr_loopback, port))
  with
  | () -> Unix.close s; true
  | exception _ -> Unix.close s; false

let with_server f () =
  match python_bin () with
  | None -> Printf.printf "python3 not found, skipping\n%!"
  | Some python ->
      let port = free_port () in
      let devnull = Unix.openfile "/dev/null" [ Unix.O_RDWR ] 0 in
      let pid =
        Unix.create_process python
          [| python; "fetch_test_server.py"; string_of_int port |]
          devnull devnull devnull
      in
      Unix.close devnull;
      let deadline = Unix.gettimeofday () +. 5.0 in
      while (not (server_ready port)) && Unix.gettimeofday () < deadline do
        Unix.sleepf 0.05
      done;
      if not (server_ready port) then fail "server did not start";
      Fun.protect
        ~finally:(fun () ->
          Unix.kill pid Sys.sigterm;
          ignore (Unix.waitpid [] pid))
        (fun () -> f (Printf.sprintf "http://127.0.0.1:%d" port))

let test_fetch base =
  let exec, pump = R.executor_queued () in
  let c = L.Fetch.create ~executor:exec () in
  let sc = scope () in
  let e = L.Fetch.request c ~scope:sc (F.request (base ^ "/get")) in
  ignore (pump ());
  ignore (R.drain c);
  match (R.state e) with
  | R.Ready resp ->
      check' int "status" 200 resp.F.status;
      check' string "body" "lui fetch test body\n" resp.F.body
  | R.Failed msg -> fail msg
  | _ -> fail "expected ready"

let test_fetch_status base =
  let exec, pump = R.executor_queued () in
  let c = L.Image.create ~executor:exec () in
  let sc = scope () in
  (* image loader over fetch: non-2xx is an error *)
  let e =
    L.Image.request c ~scope:sc (L.Fetch (F.request (base ^ "/status/404")))
  in
  ignore (pump ());
  ignore (R.drain c);
  match (R.state e) with
  | R.Failed msg -> check' bool "http status in error" true
                      (String.length msg >= 4)
  | _ -> fail "expected failed"

(* ---------- media ---------- *)

let test_media_missing () =
  let exec, pump = R.executor_queued () in
  let c = L.Media.create ~executor:exec () in
  let sc = scope () in
  let e = L.Media.request c ~scope:sc ~path:"/nonexistent/audio.mp3" () in
  ignore (pump ());
  ignore (R.drain c);
  check' bool "failed" true (match (R.state e) with R.Failed _ -> true | _ -> false)

(* ---------- plugin ---------- *)

let test_plugin () =
  ignore (Lui_plugin.reset ());
  let echo =
    Lui_plugin.v "res-test-echo" [ ("ping", fun payload -> Ok payload) ]
  in
  (match Lui_plugin.use [ echo ] with
   | Ok () -> ()
   | Error e -> fail e);
  let exec, pump = R.executor_queued () in
  let c = L.Plugin.create ~executor:exec () in
  let sc = scope () in
  let e =
    L.Plugin.request c ~scope:sc ~service:"plugin:res-test-echo"
      ~method_:"ping" ~payload:{|"hello"|} ()
  in
  ignore (pump ());
  ignore (R.drain c);
  ignore (Lui_plugin.reset ());
  check' (option string) "echo" (Some {|"hello"|})
    (match (R.state e) with R.Ready v -> Some v | _ -> None)

(* ---------- fonts ---------- *)

let test_fonts () =
  let exec, pump = R.executor_queued () in
  (* font type is engine-specific; a stand-in keeps the adapter test
     platform-free *)
  let c : string R.t = R.create ~executor:exec () in
  let sc = scope () in
  let fake_load (s : L.Fonts.spec) =
    Printf.sprintf "%s/%d/%g" (String.concat "," s.families) s.weight s.size
  in
  let spec = L.Fonts.spec ~families:[ "Inter"; "system-ui" ] ~size:14. () in
  let e = L.Fonts.request c ~scope:sc ~load:fake_load spec in
  ignore (pump ());
  ignore (R.drain c);
  check' (option string) "font" (Some "Inter,system-ui/400/14")
    (match (R.state e) with R.Ready v -> Some v | _ -> None);
  check' bool "same spec same key" true
    (L.Fonts.key_of spec = L.Fonts.key_of (L.Fonts.spec ~families:[ "Inter"; "system-ui" ] ~size:14. ()));
  check' bool "diff size diff key" true
    (L.Fonts.key_of spec <> L.Fonts.key_of (L.Fonts.spec ~families:[ "Inter"; "system-ui" ] ~size:15. ()))

(* ---------- run ---------- *)

let () =
  let offline =
    [
      ("keys", [ test_case "canonical" `Quick test_keys ]);
      ( "image",
        [
          test_case "bytes" `Quick test_image_bytes;
          test_case "garbage" `Quick test_image_garbage;
          test_case "path" `Quick test_image_path;
          test_case "reload new source" `Quick test_image_reload_new_source;
        ] );
      ( "svg",
        [
          test_case "parse" `Quick test_svg;
          test_case "bad" `Quick test_svg_bad;
        ] );
      ("media", [ test_case "missing path" `Quick test_media_missing ]);
      ("plugin", [ test_case "call" `Quick test_plugin ]);
      ("fonts", [ test_case "spec" `Quick test_fonts ]);
    ]
  in
  if F.available () then
    run "lui_resource_loaders"
      (offline
      @ [
          ( "fetch",
            [
              test_case "get" `Quick (with_server test_fetch);
              test_case "status" `Quick (with_server test_fetch_status);
            ] );
        ])
  else begin
    Printf.printf "libcurl unavailable, fetch cases skipped\n%!";
    run "lui_resource_loaders" offline
  end
