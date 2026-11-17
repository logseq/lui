(* XInput backend for lui_gamepad (Windows hosts).

   Wraps the stub externals that LoadLibrary xinput1_4.dll and call
   XInputGetState/GetCapabilities/BatteryInformation/GetKeystroke.
   State polling needs no message pump: each frame we XInputGetState
   the four user indices, detect connects via ERROR_DEVICE_NOT_
   CONNECTED and changes via dwPacketNumber, and translate the
   XINPUT_GAMEPAD bits through the shared deadzone code.  On
   non-Windows platforms every entry point raises Failure. *)

open Lui_gamepad_core

external c_probe : unit -> int = "lui_gp_xi_probe"
external c_get_state : int -> int array = "lui_gp_xi_get_state"
external c_get_caps : int -> int array = "lui_gp_xi_get_caps"
external c_get_battery : int -> int -> int array
  = "lui_gp_xi_get_battery"
external c_get_keystroke : int -> int array = "lui_gp_xi_get_keystroke"

let err_not_connected = 1167
let max_users = 4

(* XINPUT_GAMEPAD button bits -> standard buttons. *)
let xinput_buttons =
  [ (0x1000, A); (0x2000, B); (0x4000, X); (0x8000, Y);
    (0x0020, Back); (0x0010, Start);
    (0x0040, Left_stick); (0x0080, Right_stick);
    (0x0100, Left_shoulder); (0x0200, Right_shoulder);
    (0x0001, Dpad_up); (0x0002, Dpad_down);
    (0x0004, Dpad_left); (0x0008, Dpad_right) ]

(* XINPUT_CAPABILITIES SubType -> kind. *)
let kind_of_subtype = function
  | 2 -> Wheel
  | 3 -> Arcade_stick
  | 4 -> Flight_stick
  | 5 -> Dance_pad
  | 6 -> Guitar
  | 8 -> Drum_kit
  | 19 -> Arcade_pad
  | 1 -> Gamepad
  | _ -> Unknown

let available () =
  match c_probe () with 1 -> true | _ -> false
  | exception Failure _ -> false

let init () =
  match c_probe () with
  | 1 -> Ok ()
  | _ -> Error "xinput1_4.dll not available"
  | exception Failure e -> Error e

(* Deadzones per the XInput SDK defaults (normalized in
   lui_gamepad_core): left thumb 7849, right thumb 8689, triggers
   30/255 — XInput itself applies no deadzone, so we do it here. *)
let state_of_raw a =
  let buttons = a.(2) in
  let pressed =
    List.filter_map
      (fun (mask, b) -> if buttons land mask <> 0 then Some b else None)
      xinput_buttons
  in
  let axis a_kind v norm zone =
    (a_kind, apply_deadzone ~zone (norm v))
  in
  let axes =
    [ axis Left_x a.(5) normalize_i16 xinput_left_deadzone;
      axis Left_y a.(6) normalize_i16 xinput_left_deadzone;
      axis Right_x a.(7) normalize_i16 xinput_right_deadzone;
      axis Right_y a.(8) normalize_i16 xinput_right_deadzone;
      axis Left_trigger a.(3) normalize_u8 xinput_trigger_deadzone;
      axis Right_trigger a.(4) normalize_u8 xinput_trigger_deadzone ]
  in
  { pressed; axes }

(* Per-frame refresh: poll each user index, connect on first
   successful GetState, update when dwPacketNumber advanced,
   disconnect when the device reports not-connected. *)
let packets = Hashtbl.create max_users

let refresh trk =
  let evs = ref [] in
  for user = 0 to max_users - 1 do
    let a = c_get_state user in
    let err = a.(0) in
    if err = 0 then begin
      let packet = a.(1) in
      let st = state_of_raw a in
      if tracker_mem trk user then begin
        match Hashtbl.find_opt packets user with
        | Some p when p = packet -> ()
        | _ ->
          Hashtbl.replace packets user packet;
          evs := tracker_update trk user st @ !evs
      end
      else begin
        Hashtbl.replace packets user packet;
        let caps = c_get_caps user in
        let kind =
          if caps.(0) = 0 then kind_of_subtype caps.(2) else Gamepad
        in
        let c =
          { id = user;
            name = Printf.sprintf "XInput controller %d" (user + 1);
            kind }
        in
        evs := tracker_connected trk c st @ !evs
      end
    end
    else if err = err_not_connected then begin
      if tracker_mem trk user then begin
        Hashtbl.remove packets user;
        evs := tracker_disconnected trk user @ !evs
      end
    end
  done;
  List.rev !evs
