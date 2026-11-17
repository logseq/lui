(* Unit tests for lui_gamepad.

   The pure model (mapping parse, deadzones, snapshot diffs,
   connect/disconnect tracking, dispatch translation) is exercised
   headless.  The SDL path gets a real smoke test: the joystick
   subsystem needs no video device, so init + pump run headless
   anywhere SDL2 is installed; where SDL_JoystickAttachVirtual exists
   (SDL >= 2.14) a virtual controller drives the live
   connect → axis → button → disconnect pipeline end to end.  XInput
   stubs only exist on Windows; elsewhere they raise Failure, which
   is asserted directly. *)

open Lui_gamepad
module Sdl = Lui_gamepad.Sdl
module Xinput = Lui_gamepad.Xinput

let sf = Printf.sprintf

(* ---------- mapping parse ---------- *)

(* A real SDL_GameControllerDB entry (X360 wired, macOS row). *)
let x360_line =
  "030000005e0400008e02000010010000,X360 Controller,\
   a:b0,b:b1,x:b2,y:b3,back:b6,guide:b8,start:b7,leftstick:b9,\
   rightstick:b10,leftshoulder:b4,rightshoulder:b5,dpup:h0.1,\
   dpdown:h0.4,dpleft:h0.8,dpright:h0.2,leftx:a0,lefty:a1,rightx:a2,\
   righty:a3,lefttrigger:a4,righttrigger:a5,platform:Mac OS X,"

let test_parse_real_line () =
  match parse_mapping_line x360_line with
  | None -> Alcotest.fail "parse failed"
  | Some m ->
    Alcotest.(check string) "guid" "030000005e0400008e02000010010000"
      m.guid;
    Alcotest.(check string) "name" "X360 Controller" m.map_name;
    Alcotest.(check (option int))
      "a bind" (Some 0)
      (match mapping_button_bind m A with
       | Some (Hw_button i) -> Some i | _ -> None);
    Alcotest.(check (option int))
      "start bind" (Some 7)
      (match mapping_button_bind m Start with
       | Some (Hw_button i) -> Some i | _ -> None);
    Alcotest.(check (option int))
      "leftx axis" (Some 0)
      (match mapping_axis_bind m Left_x with
       | Some (Hw_axis (i, _)) -> Some i | _ -> None);
    Alcotest.(check (option int))
      "righttrigger axis" (Some 5)
      (match mapping_axis_bind m Right_trigger with
       | Some (Hw_axis (i, _)) -> Some i | _ -> None);
    Alcotest.(check (option (pair int int)))
      "dpup hat" (Some (0, 1))
      (match mapping_button_bind m Dpad_up with
       | Some (Hw_hat (h, mask)) -> Some (h, mask) | _ -> None);
    Alcotest.(check (option (pair int int)))
      "dpleft hat" (Some (0, 8))
      (match mapping_button_bind m Dpad_left with
       | Some (Hw_hat (h, mask)) -> Some (h, mask) | _ -> None)

let test_parse_variants () =
  let m =
    Option.get
      (parse_mapping_line
         "deadbeef,Weird Pad,lefttrigger:+a2,righttrigger:-a2,\
          lefty:a1~,a:b0,platform:Linux")
  in
  Alcotest.(check bool)
    "trigger +half" true
    (mapping_axis_bind m Left_trigger = Some (Hw_axis_half (2, true)));
  Alcotest.(check bool)
    "trigger -half" true
    (mapping_axis_bind m Right_trigger = Some (Hw_axis_half (2, false)));
  Alcotest.(check bool)
    "inverted axis" true
    (mapping_axis_bind m Left_y = Some (Hw_axis (1, true)));
  Alcotest.(check bool) "comment skipped" true
    (parse_mapping_line "# comment" = None);
  Alcotest.(check bool) "blank skipped" true
    (parse_mapping_line "   " = None);
  let db =
    parse_mapping_db
      ("# header\n" ^ x360_line
       ^ "\n\n03000000aaaa0000bbbb000000000000,Other Pad,a:b0,\
          platform:Linux,\n")
  in
  Alcotest.(check int) "db lines" 2 (List.length db)

(* ---------- normalization & deadzone ---------- *)

let f_eq a b = Float.abs (a -. b) < 1e-6
let check_f tag a b = Alcotest.(check bool) tag true (f_eq a b)

let test_normalize () =
  check_f "i16 min" (-1.) (normalize_i16 (-32768));
  check_f "i16 zero" 0. (normalize_i16 0);
  check_f "i16 max" 1. (normalize_i16 32767);
  check_f "i16 mid" (16384. /. 32767.) (normalize_i16 16384);
  check_f "u8 max" 1. (normalize_u8 255);
  check_f "u8 mid" (128. /. 255.) (normalize_u8 128);
  check_f "u8 zero" 0. (normalize_u8 0)

let test_deadzone () =
  let dz = 0.2 in
  check_f "inside" 0. (apply_deadzone ~zone:dz 0.15);
  check_f "inside neg" 0. (apply_deadzone ~zone:dz (-0.15));
  check_f "edge" 0. (apply_deadzone ~zone:dz 0.2);
  check_f "past edge" 1. (apply_deadzone ~zone:dz 1.);
  (* 0.6 in -> (0.6-0.2)/0.8 = 0.5 renormalized *)
  check_f "renorm" 0.5 (apply_deadzone ~zone:dz 0.6);
  check_f "renorm neg" (-0.5) (apply_deadzone ~zone:dz (-0.6))

(* ---------- eval_mapping ---------- *)

let axis_value st a =
  match List.assoc_opt a st.axes with Some v -> v | None -> 0.

let test_eval_mapping () =
  let m = Option.get (parse_mapping_line x360_line) in
  let r =
    { rbuttons =
        (let a = Array.make 16 false in
         a.(0) <- true;   (* hw b0 -> A *)
         a.(5) <- true;   (* hw b5 -> Right_shoulder *)
         a);
      raxes =
        (let a = Array.make 6 0 in
         a.(0) <- 16384;    (* leftx = +0.5 *)
         a.(1) <- (-32768); (* lefty = -1 *)
         a.(4) <- 10000;    (* lefttrigger ~0.3 *)
         a);
      rhats = [| 1 |];      (* hat0 up -> Dpad_up *)
    }
  in
  let st = eval_mapping m r in
  Alcotest.(check bool) "A pressed" true (List.mem A st.pressed);
  Alcotest.(check bool) "RB pressed" true
    (List.mem Right_shoulder st.pressed);
  Alcotest.(check bool) "B not pressed" false (List.mem B st.pressed);
  Alcotest.(check bool) "dpup via hat" true (List.mem Dpad_up st.pressed);
  Alcotest.(check bool) "dpdown clear" false
    (List.mem Dpad_down st.pressed);
  check_f "leftx" (16384. /. 32767.) (axis_value st Left_x);
  check_f "lefty" (-1.) (axis_value st Left_y);
  check_f "lefttrigger" (10000. /. 32767.) (axis_value st Left_trigger)

let test_eval_deadzone_and_half () =
  let m =
    Option.get
      (parse_mapping_line "deadbeef,Pad,lefttrigger:+a0,leftx:a1,dpleft:h0.8")
  in
  let r =
    { rbuttons = [||];
      raxes = [| 4000; 2000 |];
      rhats = [| 8 |]; (* left *)
    }
  in
  let st = eval_mapping m r in
  check_f "half axis" (4000. /. 32767.) (axis_value st Left_trigger);
  let st' = eval_mapping ~dz:(fun _ -> default_stick_deadzone) m r in
  check_f "dz kills" 0. (axis_value st' Left_trigger);
  Alcotest.(check bool) "dpleft hat" true
    (List.mem Dpad_left st'.pressed)

(* ---------- diff ---------- *)

let st ?(p = []) ?(a = []) () = { pressed = p; axes = a }

let test_diff () =
  let id = 7 in
  let old_ = st ~p:[ A; Dpad_up ] ~a:[ (Left_x, 0.5) ] () in
  let new_ = st ~p:[ B; Dpad_up ] ~a:[ (Left_x, 0.9); (Left_y, 0.1) ] () in
  let evs = diff id old_ new_ in
  Alcotest.(check bool) "release A" true
    (List.mem (Button (id, A, Released)) evs);
  Alcotest.(check bool) "press B" true
    (List.mem (Button (id, B, Pressed)) evs);
  Alcotest.(check bool) "dpad steady" false
    (List.mem (Button (id, Dpad_up, Released)) evs
     || List.mem (Button (id, Dpad_up, Pressed)) evs);
  Alcotest.(check bool) "axis move" true
    (List.mem (Axis_move (id, Left_x, 0.9)) evs);
  Alcotest.(check bool) "new axis" true
    (List.mem (Axis_move (id, Left_y, 0.1)) evs);
  Alcotest.(check int) "count" 4 (List.length evs)

let test_diff_eps () =
  let id = 3 in
  let old_ = st ~a:[ (Left_x, 0.5) ] () in
  let evs = diff id old_ (st ~a:[ (Left_x, 0.504) ] ()) in
  Alcotest.(check int) "eps quiet" 0 (List.length evs);
  let evs = diff id old_ (st ~a:[ (Left_x, 0.51) ] ()) in
  Alcotest.(check int) "eps fire" 1 (List.length evs)

(* ---------- tracker ---------- *)

let test_tracker () =
  let trk = create_tracker () in
  let c = { id = 1; name = "Pad"; kind = Gamepad } in
  let evs = tracker_connected trk c (st ~p:[ A ] ()) in
  Alcotest.(check bool) "connected first" true
    (match evs with Connected c' :: _ -> c'.id = 1 | _ -> false);
  Alcotest.(check bool) "initial press" true
    (List.mem (Button (1, A, Pressed)) evs);
  Alcotest.(check int) "one controller" 1
    (List.length (tracker_controllers trk));
  let evs = tracker_update trk 1 (st ~p:[ B ] ()) in
  Alcotest.(check bool) "swap" true
    (List.mem (Button (1, A, Released)) evs
     && List.mem (Button (1, B, Pressed)) evs);
  let evs = tracker_disconnected trk 1 in
  Alcotest.(check (list int)) "disconnected" [ 1 ]
    (List.filter_map
       (function Disconnected id -> Some id | _ -> None)
       evs);
  Alcotest.(check int) "gone" 0
    (List.length (tracker_controllers trk));
  Alcotest.(check int) "unknown update" 0
    (List.length (tracker_update trk 99 (st ())));
  Alcotest.(check int) "unknown disco" 0
    (List.length (tracker_disconnected trk 99))

(* ---------- dispatch translation ---------- *)

let test_input_of_event () =
  let open Lui_window.Input in
  let conv b = Lui_gamepad.input_of_event (Button (0, b, Pressed)) in
  Alcotest.(check bool) "dpup -> arrow" true
    (conv Dpad_up = Some (Key_down (Arrow_up, mods_none, false)));
  Alcotest.(check bool) "dpleft -> arrow" true
    (conv Dpad_left = Some (Key_down (Arrow_left, mods_none, false)));
  Alcotest.(check bool) "A -> return" true
    (conv A = Some (Key_down (Return, mods_none, false)));
  Alcotest.(check bool) "B -> escape" true
    (conv B = Some (Key_down (Escape, mods_none, false)));
  Alcotest.(check bool) "start -> return" true
    (conv Start = Some (Key_down (Return, mods_none, false)));
  Alcotest.(check bool) "X unhandled" true (conv X = None);
  Alcotest.(check bool) "release unhandled" true
    (Lui_gamepad.input_of_event (Button (0, A, Released)) = None);
  Alcotest.(check bool) "axis unhandled" true
    (Lui_gamepad.input_of_event (Axis_move (0, Left_x, 1.)) = None)

(* ---------- XInput stub guards ---------- *)

let test_xinput_unsupported () =
  if Sys.os_type <> "Win32" && Sys.os_type <> "Cygwin" then begin
    let raises f =
      match f () with exception Failure _ -> true | _ -> false
    in
    Alcotest.(check bool) "state raises" true
      (raises (fun () -> ignore (Xinput.c_get_state 0)));
    Alcotest.(check bool) "probe raises" true
      (raises (fun () -> ignore (Xinput.c_probe ())))
  end

(* ---------- SDL smoke (live, tolerant) ---------- *)

(* Real end-to-end pass through SDL where the host provides it:
   attach a virtual joystick, teach SDL a mapping for it, then drive
   the actual pump() pipeline — enumerate, open, read standard
   state, diff — with synthetic hardware input.  Skipped piecemeal:
   each stage degrades to a note when the SDL build lacks the entry
   point, so older SDLs still get init/pump coverage. *)
let test_sdl_smoke () =
  let open Sdl in
  if not (available ()) then
    Printf.printf
      "lui_gamepad: SDL unavailable (%s), live smoke skipped\n%!"
      (Option.value ~default:"unknown" (load_error ()))
  else begin
    (match init () with
     | Ok () -> ()
     | Error e -> Alcotest.failf "sdl init: %s" e);
    let trk = create_tracker () in
    Alcotest.(check int) "no events before attach" 0
      (List.length (refresh trk));
    let idx = attach_virtual ~naxes:6 ~nbuttons:21 ~nhats:1 in
    if idx < 0 then
      Printf.printf
        "lui_gamepad: virtual joystick unsupported, attach skipped\n%!"
    else begin
      let guid = device_guid idx in
      let mapping =
        sf
          "%s,Virtual Test Pad,a:b0,b:b1,x:b2,y:b3,back:b4,start:b5,\
           leftshoulder:b6,rightshoulder:b7,leftx:a0,lefty:a1,rightx:a2,\
           righty:a3,lefttrigger:a4,righttrigger:a5,dpup:h0.1,dpdown:h0.4,\
           dpleft:h0.8,dpright:h0.2,"
          guid
      in
      let added = add_mapping mapping in
      if added < 0 then
        Printf.printf "lui_gamepad: AddMapping failed\n%!";
      let inst = joystick_open idx in
      if inst < 0 then
        Printf.printf "lui_gamepad: joystick open failed\n%!"
      else begin
        let evs = refresh trk in
        (match evs with
         | Connected c :: _ ->
           Alcotest.(check string) "name" "Virtual Test Pad" c.name
         | _ -> Alcotest.fail "expected Connected from virtual pad");
        (* move left stick +0.5 and press hw b0 -> standard A *)
        ignore (set_virtual_axis inst 0 16384);
        ignore (set_virtual_button inst 0 true);
        let evs = refresh trk in
        Alcotest.(check bool) "axis event" true
          (List.exists
             (function
               | Axis_move (_, Left_x, v) -> v > 0.2
               | _ -> false)
             evs);
        Alcotest.(check bool) "button event" true
          (List.exists
             (function
               | Button (_, A, Pressed) -> true
               | _ -> false)
             evs);
        (* steady state -> quiet *)
        let evs = refresh trk in
        Alcotest.(check int) "quiet frame" 0 (List.length evs);
        (* release -> Released *)
        ignore (set_virtual_button inst 0 false);
        let evs = refresh trk in
        Alcotest.(check bool) "release event" true
          (List.exists
             (function
               | Button (_, A, Released) -> true
               | _ -> false)
             evs);
        ignore (detach_virtual idx);
        let evs = refresh trk in
        Alcotest.(check bool) "disconnected" true
          (List.exists
             (function Disconnected _ -> true | _ -> false)
             evs)
      end
    end
  end

(* ---------- suite ---------- *)

let () =
  Alcotest.run "lui_gamepad"
    [ ( "mapping",
        [ Alcotest.test_case "real db line" `Quick test_parse_real_line;
          Alcotest.test_case "half/inverted/comments" `Quick
            test_parse_variants ] );
      ( "axes",
        [ Alcotest.test_case "normalize" `Quick test_normalize;
          Alcotest.test_case "deadzone" `Quick test_deadzone ] );
      ( "eval",
        [ Alcotest.test_case "x360 mapping" `Quick test_eval_mapping;
          Alcotest.test_case "deadzone+half" `Quick
            test_eval_deadzone_and_half ] );
      ( "diff",
        [ Alcotest.test_case "events" `Quick test_diff;
          Alcotest.test_case "axis eps" `Quick test_diff_eps ] );
      ( "tracker",
        [ Alcotest.test_case "lifecycle" `Quick test_tracker ] );
      ( "dispatch",
        [ Alcotest.test_case "input_of_event" `Quick test_input_of_event ] );
      ( "stubs",
        [ Alcotest.test_case "xinput guarded" `Quick
            test_xinput_unsupported;
          Alcotest.test_case "sdl smoke" `Quick test_sdl_smoke ] ) ]
