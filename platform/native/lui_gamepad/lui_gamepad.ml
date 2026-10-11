(* Gamepad input for the native backend.

   [Lui_gamepad] is the facade window hosts and plugins use.  It owns
   backend selection (SDL on macOS/Linux, XInput on Windows), a
   shared tracker that turns per-frame snapshots into events, and the
   translation of gamepad events into the shape [Lui_window.Input]
   dispatch already routes.

   Host wiring (non-invasive): a window host calls {!pump} once per
   frame, after its own input poll, and feeds the returned events to
   dispatch — either raw, or through {!input_of_event} for buttons
   that behave like navigation keys.  The SDL backend only reads
   controller *state* and never touches the SDL event queue, so it
   cannot starve the host's own event drain.  On Windows the XInput
   backend polls by user index, independent of the Win32 message
   loop. *)

include Lui_gamepad_core

(* Backend modules, exposed for tests and tooling; production code
   should stay on the facade API below. *)
module Sdl = Lui_gamepad_sdl
module Xinput = Lui_gamepad_xinput

(* A backend source: [init] prepares the host API, [refresh] runs
   once per frame and returns the events the tracker produced. *)
type source = {
  name : string;
  init : unit -> (unit, string) result;
  refresh : tracker -> event list;
}

let sdl_source =
  { name = "sdl"; init = Lui_gamepad_sdl.init;
    refresh = Lui_gamepad_sdl.refresh }

let xinput_source =
  { name = "xinput"; init = Lui_gamepad_xinput.init;
    refresh = Lui_gamepad_xinput.refresh }

(* Default backend per host OS; [use_source] overrides (tests inject
   a fake source through it). *)
let default_source () =
  match Sys.os_type with
  | "Win32" | "Cygwin" -> xinput_source
  | "Unix" -> sdl_source
  | _ ->
    { name = "unsupported";
      init = (fun () -> Error "lui_gamepad: unsupported platform");
      refresh = (fun _ -> []) }

type status =
  | Uninitialized
  | Ready of string (* backend name *)
  | Failed of string

let trk = create_tracker ()
let src = ref (None : source option)
let status = ref Uninitialized

let set_source s =
  src := Some s;
  status := Uninitialized;
  (* Drop any controllers the previous backend tracked — a source
     swap must not leak stale state. *)
  List.iter
    (fun c -> ignore (tracker_disconnected trk c.id))
    (tracker_controllers trk)

let init () =
  match !status with
  | Ready _ -> Ok ()
  | _ ->
    let s = match !src with Some s -> s | None -> default_source () in
    (match s.init () with
     | Ok () ->
       status := Ready s.name;
       src := Some s;
       Ok ()
     | Error e ->
       status := Failed e;
       Error e)

let backend_name () =
  match !status with Ready n -> n | Uninitialized -> "uninitialized"
  | Failed _ -> "failed"

let init_error () =
  match !status with Failed e -> Some e | _ -> None

let available () = init () = Ok ()

let pump () =
  match init () with
  | Error _ -> []
  | Ok () ->
    (match !src with
     | Some s -> s.refresh trk
     | None -> [])

let controllers () = tracker_controllers trk

let state id = tracker_state trk id

let add_mapping m =
  match parse_mapping_line m with
  | None -> Error "invalid mapping string"
  | Some parsed ->
    (* Route through SDL too when it is the live backend so its own
       standardization uses the new binding. *)
    (match !src with
     | Some s when s.name = "sdl" ->
       ignore (Lui_gamepad_sdl.add_mapping m)
     | _ -> ());
    Ok parsed

let add_mappings_from_file path =
  match !src with
  | Some s when s.name = "sdl" ->
    Lui_gamepad_sdl.add_mappings_from_file path
  | _ -> 0

(* ---------- dispatch translation ---------- *)

(* Buttons that navigate: translated to the same [Key_down] inputs
   the window dispatch routes to the focused node (Lui_window
   conventions — see Lui_window.Input).  Everything else stays a
   raw [event] for app-level handlers. *)
let input_of_event = function
  | Button (_, b, Pressed) ->
    let open Lui_window.Input in
    let m = mods_none in
    (match b with
     | Dpad_up -> Some (Key_down (Arrow_up, m, false))
     | Dpad_down -> Some (Key_down (Arrow_down, m, false))
     | Dpad_left -> Some (Key_down (Arrow_left, m, false))
     | Dpad_right -> Some (Key_down (Arrow_right, m, false))
     | A | Start -> Some (Key_down (Return, m, false))
     | B -> Some (Key_down (Escape, m, false))
     | _ -> None)
  | _ -> None

(* ---------- testing seams ---------- *)

module Private = struct
  let set_source = set_source
  let tracker = trk
end
