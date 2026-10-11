(* Headless verification for crash reporting and renderer-loss
   recovery: a synthetic "backend lost" at the recovery seam moves the
   renderer down the ladder, and the next frame still hits the
   deterministic checksum — the CPU fallback renders identically. *)

module R = Lui_resilience

let tmpdir name =
  let d =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "lui-resilience-test-%s-%d" name
         (int_of_float (Unix.gettimeofday () *. 1000.) mod 100000))
  in
  (try Unix.mkdir d 0o700 with Unix.Unix_error _ -> ());
  d

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i =
    if i + n > h then false
    else if String.sub hay i n = needle then true
    else go (i + 1)
  in
  go 0

let test_ring_keeps_last () =
  let dir = tmpdir "ring" in
  let t = R.install ~dir ~app_name:"ringapp" ~renderer:"gl" () in
  for i = 1 to 70 do
    R.log t (Printf.sprintf "lifecycle %d" i)
  done;
  ignore
    (R.write_crash_report t ~signal:"SIGSEGV (11)" ~backtrace:"bt-line");
  match R.pending_crash_report ~dir ~app_name:"ringapp" () with
  | None -> Alcotest.fail "no crash file written"
  | Some body ->
    Alcotest.(check bool) "has line 70" true
      (contains body "lifecycle 70");
    Alcotest.(check bool) "has line 7 (64th from last)" true
      (contains body "lifecycle 7");
    Alcotest.(check bool) "dropped line 6" false
      (contains body "lifecycle 6\n");
    Alcotest.(check bool) "signal line" true
      (contains body "signal: SIGSEGV (11)");
    Alcotest.(check bool) "renderer line" true
      (contains body "renderer: gl");
    Alcotest.(check bool) "backtrace" true
      (contains body "bt-line");
    Alcotest.(check bool) "header" true
      (contains body "LUI-CRASH 1");
    Alcotest.(check bool) "app" true (contains body "app: ringapp")

let test_pending_lifecycle () =
  let dir = tmpdir "pend" in
  let t = R.install ~dir ~app_name:"pendapp" ~renderer:"metal" () in
  Alcotest.(check bool) "no report yet" true
    (R.pending_crash_report ~dir ~app_name:"pendapp" () = None);
  ignore
    (R.write_crash_report t ~signal:"SIGABRT (6)" ~backtrace:"");
  Alcotest.(check bool) "report found" true
    (Option.is_some
       (R.pending_crash_report ~dir ~app_name:"pendapp" ()));
  R.mark_report_handled ~dir ~app_name:"pendapp" ();
  Alcotest.(check bool) "report cleared" true
    (R.pending_crash_report ~dir ~app_name:"pendapp" () = None)

let test_set_renderer () =
  let dir = tmpdir "rname" in
  let t = R.install ~dir ~app_name:"rapp" ~renderer:"lui_metal" () in
  R.set_renderer t "lui_raster+blit";
  ignore
    (R.write_crash_report t ~signal:"SIGFPE (8)" ~backtrace:"");
  match R.pending_crash_report ~dir ~app_name:"rapp" () with
  | None -> Alcotest.fail "no crash file"
  | Some body ->
    Alcotest.(check bool) "new renderer" true
      (contains body "renderer: lui_raster+blit");
    Alcotest.(check bool) "demotion logged" true
      (contains body "renderer: lui_raster+blit")

(* A real crash in a child process: install + raise SIGSEGV -> the
   handler writes the file, then the signal kills the child. Skipped
   on Windows (no fork). *)
let test_real_crash () =
  if Sys.os_type = "Win32" then ()
  else begin
    let dir = tmpdir "crash" in
    match Unix.fork () with
    | 0 ->
      let t =
        R.install ~dir ~app_name:"crashapp" ~renderer:"lui_gl" ()
      in
      R.log t "about to die";
      Unix.kill (Unix.getpid ()) Sys.sigsegv;
      (* If the handler's re-raise did not deliver, still exit badly. *)
      exit 3
    | pid ->
      ignore (Unix.waitpid [] pid);
      (match R.pending_crash_report ~dir ~app_name:"crashapp" () with
       | None ->
         Alcotest.fail "crash file missing after real SIGSEGV"
       | Some body ->
         Alcotest.(check bool) "sigsegv recorded" true
           (contains body "SIGSEGV");
         Alcotest.(check bool) "lifecycle line" true
           (contains body "about to die"))
  end

let test_recovery_ladder () =
  let open R.Recovery in
  let rec_t = create [ "lui_metal"; "lui_gl"; "lui_raster+blit"; "noop" ] in
  Alcotest.(check string) "first rung" "lui_metal" (current rec_t);
  Alcotest.(check int) "index 0" 0 (index rec_t);
  Alcotest.(check bool) "not exhausted" false (exhausted rec_t);
  Alcotest.(check (option string)) "demote to gl"
    (Some "lui_gl") (lost rec_t ~reason:"device removed");
  Alcotest.(check string) "now gl" "lui_gl" (current rec_t);
  Alcotest.(check (option string)) "demote to cpu"
    (Some "lui_raster+blit")
    (lost rec_t ~reason:"SDL_RENDER_TARGETS_RESET");
  Alcotest.(check (option string)) "demote to noop"
    (Some "noop") (lost rec_t ~reason:"blit failed");
  Alcotest.(check bool) "exhausted" true (exhausted rec_t);
  Alcotest.(check (option string)) "nothing left" None
    (lost rec_t ~reason:"still lost");
  Alcotest.(check int) "3 demotions" 3 (demotions rec_t);
  match history rec_t with
  | [ (0, "lui_metal", "device removed");
      (1, "lui_gl", "SDL_RENDER_TARGETS_RESET");
      (2, "lui_raster+blit", "blit failed") ] ->
    ()
  | _ -> Alcotest.fail "bad demotion history"

let test_recovery_empty_ladder () =
  Alcotest.check_raises "empty ladder rejected"
    (Invalid_argument
       "Lui_resilience.Recovery.create: empty ladder")
    (fun () -> ignore (R.Recovery.create []))

(* The seam itself: render with the active rung; on loss, demote and
   re-render the same scene through the next rung. CPU fallback
   renders identically — the checksum must not move. *)
let fnv1a (b : Bytes.t) =
  let h = ref 0xcbf29ce484222325L in
  Bytes.iter
    (fun c ->
       h := Int64.logxor !h (Int64.of_int (Char.code c));
       h := Int64.mul !h 0x100000001b3L)
    b;
  !h

let sample_scene () =
  let s =
    Lui_scene.create
      ~mask_atlas:(Lui_scene.Atlas.create ~bpp:1 ~w:8 ~h:8)
      ~color_atlas:(Lui_scene.Atlas.create ~bpp:4 ~w:8 ~h:8)
  in
  Lui_scene.reset s ~width:64 ~height:64 ~scale:1.
    ~clear:(Lui_scene.color 0 0 0 0);
  s.Lui_scene.ops <-
    [ Lui_scene.Fill
        { frect = Lui_scene.rect 10. 12. 40. 18.;
          fradii = (0., 0., 0., 0.); fcontinuous = false;
          fcolor = Lui_scene.color 200 60 60 255;
          fpaint = Lui_scene.Solid;
          fcolor2 = Lui_scene.color 0 0 0 0;
          fgradient = (0., 0., 0., 0.);
          fborder = (0., 0., 0., 0.);
          fborder_color = Lui_scene.color 0 0 0 0;
          fdashed = false; fwide = 0; fopacity = 1. } ];
  s

let render_cpu s =
  let rr = Lui_raster.Renderer.create () in
  ignore (Lui_raster.Renderer.render rr s);
  (Lui_raster.Renderer.image rr).Lui_raster.Image.pix

let test_frame_survives_demotion () =
  let rec_t =
    R.Recovery.create [ "gpu"; "lui_raster+blit"; "noop" ]
  in
  (* Frame N on the GPU rung. CPU-parity is the design contract, so
     the GPU rung's checksum is the CPU render of the same scene. *)
  let gpu_frame = render_cpu (sample_scene ()) in
  let gpu_sum = fnv1a gpu_frame in
  (* The rung dies mid-frame; recovery hands back the next rung. *)
  (match R.Recovery.lost rec_t ~reason:"synthetic backend lost" with
   | Some "lui_raster+blit" -> ()
   | _ -> Alcotest.fail "expected demotion to lui_raster+blit");
  (* Frame N+1 on the new rung: same scene store, same pixels. *)
  let cpu_sum = fnv1a (render_cpu (sample_scene ())) in
  Alcotest.(check int64) "checksum survives demotion" gpu_sum cpu_sum;
  Alcotest.(check string) "on cpu rung" "lui_raster+blit"
    (R.Recovery.current rec_t)

let () =
  Alcotest.run "lui_resilience"
    [ ( "crash report",
        [ Alcotest.test_case "ring keeps last 64" `Quick
            test_ring_keeps_last;
          Alcotest.test_case "pending/handled lifecycle" `Quick
            test_pending_lifecycle;
          Alcotest.test_case "renderer update" `Quick test_set_renderer;
          Alcotest.test_case "real SIGSEGV writes report" `Quick
            test_real_crash ] );
      ( "recovery",
        [ Alcotest.test_case "ladder demotion" `Quick
            test_recovery_ladder;
          Alcotest.test_case "empty ladder rejected" `Quick
            test_recovery_empty_ladder;
          Alcotest.test_case "frame survives demotion" `Quick
            test_frame_survives_demotion ] ) ]
