(* SDL backend for lui_gamepad.

   Thin OCaml wrappers over the C stubs plus the per-frame refresh
   loop.  The path is state-polling only: it pumps SDL for fresh
   hardware state, diffs the controller set and reads
   SDL_GameController state directly — it never consumes the SDL
   event queue, so it composes cleanly with window hosts that own
   SDL event delivery. *)

open Lui_gamepad_core

external c_probe : unit -> int = "lui_gp_sdl_probe"
external c_load_error : unit -> string = "lui_gp_sdl_load_error"
external c_init : unit -> int = "lui_gp_sdl_init"
external c_pump : unit -> unit = "lui_gp_sdl_pump"
external c_num_devices : unit -> int = "lui_gp_sdl_num_devices"
external c_is_controller : int -> bool = "lui_gp_sdl_is_controller"
external c_device_name : int -> string = "lui_gp_sdl_device_name"
external c_device_guid : int -> string = "lui_gp_sdl_device_guid"
external c_device_instance : int -> int = "lui_gp_sdl_device_instance"
external c_device_mapping : int -> string = "lui_gp_sdl_device_mapping"
external c_open : int -> int = "lui_gp_sdl_open"
external c_close : int -> unit = "lui_gp_sdl_close"
external c_attached : int -> bool = "lui_gp_sdl_attached"
external c_axis : int -> int -> int = "lui_gp_sdl_axis"
external c_button : int -> int -> bool = "lui_gp_sdl_button"
external c_add_mapping : string -> int = "lui_gp_sdl_add_mapping"
external c_add_mappings_file : string -> int
  = "lui_gp_sdl_add_mappings_file"
external c_attach_virtual : int -> int -> int -> int -> int
  = "lui_gp_sdl_attach_virtual"
external c_detach_virtual : int -> int = "lui_gp_sdl_detach_virtual"
external c_joystick_open : int -> int = "lui_gp_sdl_joystick_open"
external c_set_vaxis : int -> int -> int -> int = "lui_gp_sdl_set_vaxis"
external c_set_vbutton : int -> int -> bool -> int
  = "lui_gp_sdl_set_vbutton"

let num_axes = Array.length sdl_axis_order
let num_buttons = Array.length sdl_button_order

let available () =
  match c_probe () with
  | 1 -> true
  | _ -> false
  | exception Failure _ -> false

let load_error () =
  match c_load_error () with
  | "" -> None
  | s -> Some s
  | exception Failure e -> Some e

let init () =
  match c_init () with
  | 0 -> Ok ()
  | _ -> Error (Option.value ~default:"SDL init failed" (load_error ()))
  | exception Failure e -> Error e

(* Full standard snapshot for one opened controller: every
   SDL_CONTROLLER_AXIS_* normalized and deadzoned, every
   SDL_CONTROLLER_BUTTON_* that's down. *)
let read_state inst =
  let dz = function
    | Left_trigger | Right_trigger -> default_trigger_deadzone
    | _ -> default_stick_deadzone
  in
  let axes =
    List.filter_map
      (fun i ->
        let a = axis_of_sdl i in
        let v = apply_deadzone ~zone:(dz a) (normalize_i16 (c_axis inst i)) in
        Some (a, v))
      (List.init num_axes Fun.id)
  in
  let pressed =
    List.filter_map
      (fun i -> if c_button inst i then Some (button_of_sdl i) else None)
      (List.init num_buttons Fun.id)
  in
  { pressed; axes }

(* Per-frame refresh: enumerate SDL devices, open/close controllers
   so the tracker set matches hardware, then push every attached
   controller's snapshot through the diff. *)
let refresh trk =
  c_pump ();
  let seen = Hashtbl.create 8 in
  let evs = ref [] in
  let n = c_num_devices () in
  for i = 0 to n - 1 do
    if c_is_controller i then begin
      let inst = c_device_instance i in
      Hashtbl.replace seen inst ();
      if tracker_mem trk inst then begin
        if c_attached inst then
          evs := tracker_update trk inst (read_state inst) @ !evs
        else begin
          evs := tracker_disconnected trk inst @ !evs;
          c_close inst
        end
      end
      else begin
        let opened = c_open i in
        if opened >= 0 then begin
          let c =
            { id = opened; name = c_device_name i; kind = Gamepad }
          in
          evs := tracker_connected trk c (read_state opened) @ !evs
        end
      end
    end
  done;
  (* Anything still tracked under this backend but absent from the
     enumeration has gone away. *)
  List.iter
    (fun c ->
      if not (Hashtbl.mem seen c.id) then begin
        evs := tracker_disconnected trk c.id @ !evs;
        c_close c.id
      end)
    (tracker_controllers trk);
  List.rev !evs

let add_mapping s = c_add_mapping s

(* SDL_GameControllerAddMappingsFromFile; Linux hosts use this for
   the community mapping file, and it works on every SDL platform. *)
let add_mappings_from_file path = c_add_mappings_file path

(* ---- fake-event injection harness (virtual joysticks) ---- *)

(* Returns the device index or -1 when the build's SDL lacks
   SDL_JoystickAttachVirtual (SDL >= 2.14) or it failed. *)
let attach_virtual ~naxes ~nbuttons ~nhats =
  (* SDL_JOYSTICK_TYPE_GAMECONTROLLER *)
  c_attach_virtual 1 naxes nbuttons nhats

let joystick_open = c_joystick_open
let set_virtual_axis = c_set_vaxis
let set_virtual_button = c_set_vbutton
let detach_virtual = c_detach_virtual
let device_guid = c_device_guid
let device_mapping = c_device_mapping
