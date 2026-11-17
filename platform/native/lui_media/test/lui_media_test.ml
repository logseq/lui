(* Tests for lui_media: audio decode/playback, video frame decode and
   pacing, the scene Image adapter, and the "media" plugin service.
   Platform coverage is exercised through the availability probes, so
   every test group runs headless wherever the capability exists and
   degrades to flag checks elsewhere. *)

open Lui_media

let check' t name want got = Alcotest.check t name want got

let checkf ?(eps = 0.001) name want got =
  Alcotest.(check (float eps)) name want got

let failf fmt = Printf.ksprintf failwith fmt
let checkb name cond = if not cond then failf "check failed: %s" name

(* Synthesize a 16-bit mono WAV in memory: sine of [freq] Hz for [secs]
   at [rate]. *)
let wav_bytes ~freq ~secs ~rate =
  let n = int_of_float (Float.of_int rate *. secs) in
  let len = 44 + (n * 2) in
  let b = Bytes.create len in
  let set32 i v =
    Bytes.set b i (Char.chr (v land 0xff));
    Bytes.set b (i + 1) (Char.chr ((v lsr 8) land 0xff));
    Bytes.set b (i + 2) (Char.chr ((v lsr 16) land 0xff));
    Bytes.set b (i + 3) (Char.chr ((v lsr 24) land 0xff))
  in
  let set16 i v =
    Bytes.set b i (Char.chr (v land 0xff));
    Bytes.set b (i + 1) (Char.chr ((v lsr 8) land 0xff))
  in
  Bytes.blit_string "RIFF" 0 b 0 4;
  set32 4 (len - 8);
  Bytes.blit_string "WAVE" 0 b 8 4;
  Bytes.blit_string "fmt " 0 b 12 4;
  set32 16 16;
  set16 20 1;
  set16 22 1;
  set32 24 rate;
  set32 28 (rate * 2);
  set16 32 2;
  set16 34 16;
  Bytes.blit_string "data" 0 b 36 4;
  set32 40 (n * 2);
  let step = 2. *. Float.pi *. freq /. Float.of_int rate in
  for i = 0 to n - 1 do
    let s = sin (step *. Float.of_int i) *. 0.5 in
    set16 (44 + (2 * i)) (int_of_float (s *. 32767.))
  done;
  Bytes.unsafe_to_string b

let tmpfile ~ext data =
  let path = Filename.temp_file "lui_media_test" ext in
  let oc = open_out_bin path in
  output_string oc data;
  close_out oc;
  path

let unlink_quiet p = try Sys.remove p with Sys_error _ -> ()

let pcm_rms (p : pcm) =
  let n = Bytes.length p.pcm_data / 4 in
  if n = 0 then 0.
  else (
    let sum = ref 0. in
    for i = 0 to n - 1 do
      let v =
        Int32.float_of_bits (Bytes.get_int32_le p.pcm_data (4 * i))
      in
      sum := !sum +. (v *. v)
    done;
    sqrt (!sum /. Float.of_int n))

(* Expected test-clip bars, as premultiplied RGBA: 8 vertical bars in
   R,G,B,W,K,Y,C,M order (matching the writer in lui_media_stubs.m). *)
let bar_rgb_of_x ~w x =
  let bar = min 7 ((x * 8) / w) in
  [| (255, 0, 0); (0, 255, 0); (0, 0, 255); (255, 255, 255); (0, 0, 0);
     (255, 255, 0); (0, 255, 255); (255, 0, 255) |].(bar)

let pix_rgba (img : Lui_scene.image) x y =
  let i = (y * img.Lui_scene.iw * 4) + (x * 4) in
  ( Char.code (Bytes.get img.Lui_scene.ipix i),
    Char.code (Bytes.get img.Lui_scene.ipix (i + 1)),
    Char.code (Bytes.get img.Lui_scene.ipix (i + 2)),
    Char.code (Bytes.get img.Lui_scene.ipix (i + 3)) )

let check_bar_px ~w img x y =
  let r, g, b, a = pix_rgba img x y in
  let er, eg, eb = bar_rgb_of_x ~w x in
  Alcotest.(check int) (Printf.sprintf "alpha at %d,%d" x y) 255 a;
  List.iter2
    (fun (ch, got) want ->
      Alcotest.(check int)
        (Printf.sprintf "bar pixel %s at %d,%d: got %d want ~%d" ch x y
           got want)
        1
        (if abs (got - want) <= 24 then 1 else 0))
    [ ("r", r); ("g", g); ("b", b) ]
    [ er; eg; eb ]

let scene_of_op op ~w ~h =
  let mask_atlas = Lui_scene.Atlas.create ~bpp:1 ~w:8 ~h:8 in
  let color_atlas = Lui_scene.Atlas.create ~bpp:4 ~w:8 ~h:8 in
  let s = Lui_scene.create ~mask_atlas ~color_atlas in
  Lui_scene.reset s ~width:w ~height:h ~scale:1.
    ~clear:(Lui_scene.color 0 0 0 0);
  s.Lui_scene.ops <- [ op ];
  s

let jmem name j =
  match Yojson.Safe.from_string j with
  | `Assoc kv -> ( try List.assoc name kv with Not_found -> `Null)
  | _ -> `Null

let jint j =
  match j with `Int i -> i | `Float f -> int_of_float f | _ -> -1

let state_t =
  let pp ppf = function
    | Stopped -> Format.fprintf ppf "stopped"
    | Playing -> Format.fprintf ppf "playing"
    | Paused -> Format.fprintf ppf "paused"
    | Ended -> Format.fprintf ppf "ended"
  in
  Alcotest.testable pp ( = )

let must_player () =
  match player_create () with
  | Ok p -> p
  | Error e -> failf "player_create: %s" e

let must_video path =
  match video_open path with
  | Ok v -> v
  | Error e -> failf "video_open: %s" e

let must_load p path =
  match load p path with
  | Ok () -> ()
  | Error e -> failf "load: %s" e

let with_wav f =
  let path = tmpfile ~ext:".wav" (wav_bytes ~freq:440. ~secs:0.1 ~rate:44100) in
  Fun.protect ~finally:(fun () -> unlink_quiet path) (fun () -> f path)

let with_clip ~w ~h ~secs f =
  if not (video_available ()) then ()
  else begin
    let path = Filename.temp_file "lui_media_test" ".mp4" in
    Fun.protect
      ~finally:(fun () -> unlink_quiet path)
      (fun () ->
        match Testing.write_test_video path ~w ~h ~secs with
        | Error e -> failf "clip: %s" e
        | Ok () -> f path)
  end

(* ---------- decode ---------- *)

let test_decode_bytes () =
  if decode_available () then begin
    let data = wav_bytes ~freq:220. ~secs:0.2 ~rate:22050 in
    match decode_bytes data with
    | Error e -> failf "decode_bytes: %s" e
    | Ok p ->
      check' Alcotest.int "channels" 1 p.pcm_channels;
      check' Alcotest.int "rate" 22050 p.pcm_rate;
      let expect = 4410 in
      checkb "frame count"
        (abs (p.pcm_frames - expect) <= max 16 (expect / 20));
      checkb "byte size"
        (Bytes.length p.pcm_data = p.pcm_frames * p.pcm_channels * 4);
      let rms = pcm_rms p in
      checkb "non-silent" (rms > 0.1 && rms < 0.9)
  end

let test_decode_file () =
  if decode_available () then
    with_wav (fun path ->
        match decode path with
        | Error e -> failf "decode: %s" e
        | Ok p ->
          check' Alcotest.int "channels" 1 p.pcm_channels;
          check' Alcotest.int "rate" 44100 p.pcm_rate;
          checkb "frames ~4410" (abs (p.pcm_frames - 4410) <= 220))

let test_decode_fail () =
  match decode_bytes "not audio at all" with
  | Error _ -> ()
  | Ok _ ->
    if decode_available () then
      failf "expected decode failure for garbage input"

(* ---------- player ---------- *)

let test_player_state_machine () =
  if audio_available () && decode_available () then
    with_wav (fun path ->
        let p = must_player () in
        must_load p path;
        checkb "duration >0" (duration p > 0.);
        check' state_t "initial state" Stopped (status p);
        play p;
        checkb "playing" (status p = Playing || status p = Ended);
        pause p;
        checkb "paused" (status p = Paused || status p = Ended);
        let pos = position p in
        checkb "position sane" (pos >= 0. && pos <= duration p);
        play p;
        seek p 0.05;
        checkf ~eps:0.5 "seek lands" 0.05 (position p);
        stop p;
        checkb "stopped" (status p = Stopped);
        checkf ~eps:0.5 "stop resets" 0. (position p);
        unload p)

let test_player_volume_loop () =
  if audio_available () && decode_available () then
    with_wav (fun path ->
        let p = must_player () in
        must_load p path;
        set_volume p 0.3;
        checkf ~eps:0.001 "volume" 0.3 (volume p);
        set_loop p true;
        check' Alcotest.bool "loop on" true (loops p);
        set_loop p false;
        check' Alcotest.bool "loop off" false (loops p);
        unload p)

let test_player_ended () =
  if audio_available () && decode_available () then
    with_wav (fun path ->
        let p = must_player () in
        must_load p path;
        let ended = ref false in
        on_ended p (fun _ -> ended := true);
        play p;
        (* seek near the end; the tail plays out and fires ended *)
        seek p (Float.max 0. (duration p -. 0.03));
        let deadline = Unix.gettimeofday () +. 3. in
        while not !ended && Unix.gettimeofday () < deadline do
          poll_events ();
          Unix.sleepf 0.05
        done;
        checkb "ended fired" !ended;
        unload p)

(* ---------- video ---------- *)

let test_video_decode () =
  with_clip ~w:96 ~h:64 ~secs:2.0 (fun path ->
      let v = must_video path in
      let vw, vh = video_natural_size v in
      check' Alcotest.int "video width" 96 vw;
      check' Alcotest.int "video height" 64 vh;
      checkb "duration ~2"
        (video_duration v > 1. && video_duration v < 3.);
      (* the paused first frame is committed eagerly *)
      (match current_frame v with
       | Some (Ok img) ->
         check' Alcotest.int "frame w" 96 img.Lui_scene.iw;
         check' Alcotest.int "frame h" 64 img.Lui_scene.ih;
         check_bar_px ~w:96 img 6 32;
         check_bar_px ~w:96 img 30 32;
         check_bar_px ~w:96 img 90 32
       | _ -> failf "no first frame");
      video_close v)

let test_video_frames_change () =
  with_clip ~w:96 ~h:64 ~secs:1.5 (fun path ->
      let v = must_video path in
      let st = state_create () in
      state_attach st v;
      video_play v;
      (* pull through real time; the moving block guarantees the pixels
         at a fixed probe change between frames *)
      let probe img = pix_rgba img 8 8 in
      let rec wait_frame tries =
        poll_events ();
        match current_frame v with
        | Some (Ok img) -> img
        | _ ->
          if tries <= 0 then failf "no frame after play";
          Unix.sleepf 0.05;
          wait_frame (tries - 1)
      in
      let img0 = wait_frame 40 in
      let p0 = probe img0 in
      let rec wait_change tries =
        poll_events ();
        Unix.sleepf 0.1;
        match current_frame v with
        | Some (Ok img) when probe img <> p0 -> img
        | _ ->
          if tries <= 0 then failf "frame never changed";
          wait_change (tries - 1)
      in
      ignore (wait_change 60);
      video_pause v;
      check' state_t "paused state" Paused (video_status v);
      video_close v)

let test_video_seek () =
  with_clip ~w:96 ~h:64 ~secs:2.0 (fun path ->
      let v = must_video path in
      video_seek v 1.0;
      checkf ~eps:0.4 "position after seek" 1.0 (video_position v);
      (match current_frame v with
       | Some (Ok img) ->
         (* bars still present at the seeked position *)
         check_bar_px ~w:96 img 6 32
       | _ -> failf "no frame after seek");
      checkb "pts >= 0.9 after seek" (video_frame_pts v >= 0.9);
      video_close v)

let test_video_ended () =
  with_clip ~w:64 ~h:48 ~secs:0.3 (fun path ->
      let v = must_video path in
      let st = state_create () in
      state_attach st v;
      let ended = ref false in
      video_on_ended v (fun _ -> ended := true);
      video_play v;
      let deadline = Unix.gettimeofday () +. 5. in
      while not !ended && Unix.gettimeofday () < deadline do
        poll_events ();
        Unix.sleepf 0.05
      done;
      checkb "video ended fired" !ended;
      check' state_t "ended state" Ended (video_status v);
      video_close v)

(* ---------- node adapter ---------- *)

let test_video_node () =
  with_clip ~w:96 ~h:64 ~secs:0.5 (fun path ->
      let v = must_video path in
      let st = state_create () in
      state_attach st v;
      poll_events ();
      let op = video_node v 48. 48. in
      (* the node wraps the video's stable image *)
      let s = scene_of_op op ~w:64 ~h:64 in
      let img = Lui_raster.render ~scene:s () in
      let px x y =
        let i = (y * img.Lui_raster.Image.stride) + (4 * x) in
        ( Char.code (Bytes.get img.Lui_raster.Image.pix (i + 2)),
          Char.code (Bytes.get img.Lui_raster.Image.pix (i + 1)),
          Char.code (Bytes.get img.Lui_raster.Image.pix i),
          Char.code (Bytes.get img.Lui_raster.Image.pix (i + 3)) )
      in
      (* default fit is Contain: a 96x64 frame in a 48x48 node is
         letterboxed to y in [8, 40); dst (2, 24) samples the red bar *)
      let r, g, b, _ = px 2 24 in
      checkb "rendered red bar" (r > 200 && g < 90 && b < 90);
      let _, _, _, a = px 2 2 in
      check' Alcotest.int "letterbox transparent" 0 a;
      video_close v)

let test_video_node_fit () =
  with_clip ~w:96 ~h:64 ~secs:0.3 (fun path ->
      let v = must_video path in
      let st = state_create () in
      state_attach st v;
      poll_events ();
      let op =
        video_node_at ~x:0. ~y:0. ~fit:Contain ~opacity:1. ~w:32. ~h:32.
          v
      in
      let s = scene_of_op op ~w:32 ~h:32 in
      let img = Lui_raster.render ~scene:s () in
      (* contain: 96x64 in a 32x32 box letterboxes vertically; pixels
         below the frame stay at the clear color *)
      let alpha_at x y =
        Char.code
          (Bytes.get img.Lui_raster.Image.pix
             ((y * img.Lui_raster.Image.stride) + (4 * x) + 3))
      in
      check' Alcotest.int "letterbox alpha" 0 (alpha_at 16 31);
      checkb "center opaque" (alpha_at 16 12 = 255);
      video_close v)

(* ---------- plugin ---------- *)

let plugin_call m body =
  Lui_plugin.call ~service:"plugin:media" ~method_:m body

let test_plugin_audio () =
  (match register_plugin () with
   | Ok () -> ()
   | Error e -> failf "register_plugin: %s" e);
  with_wav (fun path ->
      let body =
        Yojson.Safe.to_string (`Assoc [ ("path", `String path) ])
      in
      match plugin_call "audio.open" body with
      | Error e ->
        (* headless hosts have no output node: audio.open legitimately
           fails while decoding still works *)
        if audio_available () then failf "audio.open: %s" e
      | Ok r ->
        let id = jint (jmem "player" r) in
        checkb "player id" (id > 0);
        poll_events ();
        (match plugin_call "audio.play"
                 (Yojson.Safe.to_string
                    (`Assoc [ ("player", `Int id) ])) with
         | Ok _ -> ()
         | Error e ->
           if audio_available () then failf "audio.play: %s" e);
        (match plugin_call "audio.status"
                 (Yojson.Safe.to_string
                    (`Assoc [ ("player", `Int id) ])) with
         | Ok r -> ignore (jmem "state" r)
         | Error e -> failf "audio.status: %s" e);
        ignore
          (plugin_call "audio.close"
             (Yojson.Safe.to_string (`Assoc [ ("player", `Int id) ]))))

let test_plugin_video () =
  with_clip ~w:64 ~h:48 ~secs:0.5 (fun path ->
      match register_plugin () with
      | Error e -> failf "register_plugin: %s" e
      | Ok () -> (
        match plugin_call "video.open"
                (Yojson.Safe.to_string
                   (`Assoc [ ("path", `String path) ])) with
        | Error e -> failf "video.open: %s" e
        | Ok r ->
          let id = jint (jmem "video" r) in
          checkb "video id" (id > 0);
          poll_events ();
          (match plugin_call "video.frame"
                   (Yojson.Safe.to_string
                      (`Assoc [ ("video", `Int id) ])) with
           | Ok r -> checkb "frame width" (jint (jmem "width" r) = 64)
           | Error e -> failf "video.frame: %s" e);
          ignore
            (plugin_call "video.close"
               (Yojson.Safe.to_string (`Assoc [ ("video", `Int id) ])))))

(* ---------- headless gating ---------- *)

let test_gating () =
  (* availability flags are callable everywhere *)
  ignore (audio_available ());
  ignore (decode_available ());
  ignore (video_available ());
  (* bad paths fail gracefully, never crash *)
  (match decode "/nonexistent/file.wav" with
   | Error _ -> ()
   | Ok _ -> failf "decode of missing file should error");
  let st = state_create () in
  check' Alcotest.bool "no frame wanted" false (want_frame st);
  frame_done st

let () =
  Alcotest.run "lui_media"
    [ ( "decode",
        [ Alcotest.test_case "bytes" `Quick test_decode_bytes;
          Alcotest.test_case "file" `Quick test_decode_file;
          Alcotest.test_case "bad input" `Quick test_decode_fail ] );
      ( "player",
        [ Alcotest.test_case "state machine" `Quick
            test_player_state_machine;
          Alcotest.test_case "volume+loop" `Quick
            test_player_volume_loop;
          Alcotest.test_case "ended event" `Quick test_player_ended ] );
      ( "video",
        [ Alcotest.test_case "decode+pixels" `Slow test_video_decode;
          Alcotest.test_case "frames change" `Slow
            test_video_frames_change;
          Alcotest.test_case "seek" `Slow test_video_seek;
          Alcotest.test_case "ended" `Slow test_video_ended ] );
      ( "node",
        [ Alcotest.test_case "video_node render" `Slow test_video_node;
          Alcotest.test_case "contain letterbox" `Slow
            test_video_node_fit ] );
      ( "plugin",
        [ Alcotest.test_case "audio methods" `Quick test_plugin_audio;
          Alcotest.test_case "video methods" `Slow test_plugin_video ] );
      ( "gating", [ Alcotest.test_case "headless" `Quick test_gating ] ) ]
