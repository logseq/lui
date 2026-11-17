(* Pure gamepad model for the native backend.

   This module owns every platform-free piece of gamepad handling:
   the controller record, the standard control vocabulary, the
   SDL_GameControllerDB-style mapping parser, axis normalization and
   deadzones, and the per-frame state tracker that diffs snapshots
   into events.  Nothing here touches a host API, so the whole model
   is unit-testable headless. *)

type kind =
  | Gamepad
  | Joystick
  | Wheel
  | Flight_stick
  | Arcade_stick
  | Dance_pad
  | Guitar
  | Drum_kit
  | Arcade_pad
  | Unknown

type controller = {
  id : int;
  name : string;
  kind : kind;
}

(* Standard controls, in SDL_GameControllerButton order so the SDL
   backend can index this table directly. *)
type button =
  | A
  | B
  | X
  | Y
  | Back
  | Guide
  | Start
  | Left_stick
  | Right_stick
  | Left_shoulder
  | Right_shoulder
  | Dpad_up
  | Dpad_down
  | Dpad_left
  | Dpad_right
  | Misc1
  | Paddle1
  | Paddle2
  | Paddle3
  | Paddle4
  | Touchpad
  | Button_ext of int

type axis =
  | Left_x
  | Left_y
  | Right_x
  | Right_y
  | Left_trigger
  | Right_trigger
  | Axis_ext of int

type press =
  | Pressed
  | Released

type event =
  | Connected of controller
  | Disconnected of int
  | Button of int * button * press
  | Axis_move of int * axis * float

(* ---------- standard tables ---------- *)

(* Index in this array == SDL_CONTROLLER_BUTTON_* value. *)
let sdl_button_order =
  [| A; B; X; Y; Back; Guide; Start; Left_stick; Right_stick;
     Left_shoulder; Right_shoulder; Dpad_up; Dpad_down; Dpad_left;
     Dpad_right; Misc1; Paddle1; Paddle2; Paddle3; Paddle4; Touchpad |]

(* Index == SDL_CONTROLLER_AXIS_* value. *)
let sdl_axis_order =
  [| Left_x; Left_y; Right_x; Right_y; Left_trigger; Right_trigger |]

let button_of_sdl i =
  if i >= 0 && i < Array.length sdl_button_order then
    sdl_button_order.(i)
  else Button_ext i

let axis_of_sdl i =
  if i >= 0 && i < Array.length sdl_axis_order then sdl_axis_order.(i)
  else Axis_ext i

let string_of_button = function
  | A -> "a" | B -> "b" | X -> "x" | Y -> "y"
  | Back -> "back" | Guide -> "guide" | Start -> "start"
  | Left_stick -> "leftstick" | Right_stick -> "rightstick"
  | Left_shoulder -> "leftshoulder" | Right_shoulder -> "rightshoulder"
  | Dpad_up -> "dpup" | Dpad_down -> "dpdown"
  | Dpad_left -> "dpleft" | Dpad_right -> "dpright"
  | Misc1 -> "misc1"
  | Paddle1 -> "paddle1" | Paddle2 -> "paddle2"
  | Paddle3 -> "paddle3" | Paddle4 -> "paddle4"
  | Touchpad -> "touchpad"
  | Button_ext n -> Printf.sprintf "button%d" n

let string_of_axis = function
  | Left_x -> "leftx" | Left_y -> "lefty"
  | Right_x -> "rightx" | Right_y -> "righty"
  | Left_trigger -> "lefttrigger" | Right_trigger -> "righttrigger"
  | Axis_ext n -> Printf.sprintf "axis%d" n

let string_of_kind = function
  | Gamepad -> "gamepad" | Joystick -> "joystick" | Wheel -> "wheel"
  | Flight_stick -> "flight_stick" | Arcade_stick -> "arcade_stick"
  | Dance_pad -> "dance_pad" | Guitar -> "guitar"
  | Drum_kit -> "drum_kit" | Arcade_pad -> "arcade_pad"
  | Unknown -> "unknown"

let button_of_name = function
  | "a" -> Some A | "b" -> Some B | "x" -> Some X | "y" -> Some Y
  | "back" -> Some Back | "guide" -> Some Guide | "start" -> Some Start
  | "leftstick" -> Some Left_stick | "rightstick" -> Some Right_stick
  | "leftshoulder" -> Some Left_shoulder
  | "rightshoulder" -> Some Right_shoulder
  | "dpup" -> Some Dpad_up | "dpdown" -> Some Dpad_down
  | "dpleft" -> Some Dpad_left | "dpright" -> Some Dpad_right
  | "misc1" -> Some Misc1
  | "paddle1" -> Some Paddle1 | "paddle2" -> Some Paddle2
  | "paddle3" -> Some Paddle3 | "paddle4" -> Some Paddle4
  | "touchpad" -> Some Touchpad
  | _ -> None

let axis_of_name = function
  | "leftx" -> Some Left_x | "lefty" -> Some Left_y
  | "rightx" -> Some Right_x | "righty" -> Some Right_y
  | "lefttrigger" -> Some Left_trigger
  | "righttrigger" -> Some Right_trigger
  | _ -> None

(* ---------- axes: normalization and deadzones ---------- *)

(* Signed 16-bit axis (SDL, XInput thumbs) -> [-1.0, 1.0]. *)
let normalize_i16 v =
  if v < 0 then Float.max (-1.) (float v /. 32768.)
  else Float.min 1. (float v /. 32767.)

(* Unsigned 8-bit trigger (XInput triggers) -> [0.0, 1.0]. *)
let normalize_u8 v = Float.min 1. (Float.max 0. (float v /. 255.))

(* Symmetric deadzone with renormalized output: values inside the
   zone collapse to 0 and the surviving range is stretched back over
   [-1, 1] (or [0, 1] for unipolar callers), so motion stays smooth
   instead of jumping at the zone edge. *)
let apply_deadzone ~zone v =
  let zone = Float.abs zone in
  let a = Float.abs v in
  if a <= zone || zone >= 1. then 0.
  else Float.copy_sign ((a -. zone) /. (1. -. zone)) v

(* Deadzone defaults. The XInput constants are the SDK's
   XINPUT_GAMEPAD_*_DEADZONE / _TRIGGER_THRESHOLD values expressed in
   normalized units; the generic stick default matches SDL's commonly
   used 8000-count zone. *)
let xinput_left_deadzone = 7849. /. 32767.
let xinput_right_deadzone = 8689. /. 32767.
let xinput_trigger_deadzone = 30. /. 255.
let default_stick_deadzone = 8000. /. 32767.
let default_trigger_deadzone = xinput_trigger_deadzone

(* A stick/trigger value smaller than this in normalized units is
   noise, not a change — keeps [diff] from streaming axis events for
   jitter inside the ADC's last bits. *)
let axis_eps = 0.005

(* Analog value at which an axis-bound button (triggers on digital
   pads, half-axis bindings) reports pressed. *)
let axis_button_threshold = 0.3

(* ---------- SDL mapping strings (GameControllerDB format) ---------- *)

(* Hardware-side binding: the right of the ':' in "a:b0". *)
type hw_bind =
  | Hw_button of int
  | Hw_axis of int * bool (* index, inverted *)
  | Hw_axis_half of int * bool (* index, true = positive half *)
  | Hw_hat of int * int (* hat index, direction mask *)

type mapping = {
  guid : string;
  map_name : string;
  (* standard control name -> hardware binding, in file order *)
  binds : (string * hw_bind) list;
}

let parse_hw_bind s =
  let n = String.length s in
  if n < 2 then None
  else
    let inverted = s.[n - 1] = '~' in
    let body = if inverted then String.sub s 0 (n - 1) else s in
    let bn = String.length body in
    let int_suffix i =
      try Some (int_of_string (String.sub body i (bn - i)))
      with _ -> None
    in
    match body.[0] with
    | 'b' -> Option.map (fun i -> Hw_button i) (int_suffix 1)
    | 'h' ->
      (match String.index_opt body '.' with
       | Some dot ->
         let int_range i j =
           try Some (int_of_string (String.sub body i (j - i)))
           with _ -> None
         in
         (match int_range 1 dot, int_suffix (dot + 1) with
          | Some h, Some m -> Some (Hw_hat (h, m))
          | _ -> None)
       | None -> None)
    | '+' when bn > 1 && body.[1] = 'a' ->
      Option.map (fun i -> Hw_axis_half (i, true)) (int_suffix 2)
    | '-' when bn > 1 && body.[1] = 'a' ->
      Option.map (fun i -> Hw_axis_half (i, false)) (int_suffix 2)
    | 'a' -> Option.map (fun i -> Hw_axis (i, inverted)) (int_suffix 1)
    | _ -> None

let split_commas s =
  String.split_on_char ',' s
  |> List.filter (fun f -> String.length f > 0)

(* One GameControllerDB line:
   "<guid>,<name>,<field>:<bind>,..." — field entries without a colon
   (platform, crc, hints) are ignored, as are comment/blank lines. *)
let parse_mapping_line line =
  let line = String.trim line in
  if line = "" || line.[0] = '#' then None
  else
    match split_commas line with
    | guid :: name :: fields ->
      let binds =
        List.filter_map
          (fun f ->
            match String.index_opt f ':' with
            | None -> None
            | Some i ->
              let lhs = String.sub f 0 i in
              let rhs =
                String.sub f (i + 1) (String.length f - i - 1)
              in
              (match parse_hw_bind rhs with
               | Some b -> Some (lhs, b)
               | None -> None))
          fields
      in
      Some { guid; map_name = name; binds }
    | _ -> None

let parse_mapping_db text =
  String.split_on_char '\n' text |> List.filter_map parse_mapping_line

let mapping_button_bind m b =
  List.assoc_opt (string_of_button b) m.binds

let mapping_axis_bind m a =
  List.assoc_opt (string_of_axis a) m.binds

(* ---------- raw state -> standard state ---------- *)

type raw_state = {
  rbuttons : bool array;  (* hw button index -> down *)
  raxes : int array;      (* hw axis index -> signed 16-bit *)
  rhats : int array;      (* hw hat index -> SDL direction mask *)
}

let empty_raw =
  { rbuttons = [||]; raxes = [||]; rhats = [||] }

(* Standard per-frame snapshot. [pressed] holds every standard
   button currently down; [axes] holds every bound axis with its
   normalized, deadzoned value. *)
type state = {
  pressed : button list;
  axes : (axis * float) list;
}

let empty_state = { pressed = []; axes = [] }

let raw_button r i =
  i >= 0 && i < Array.length r.rbuttons && r.rbuttons.(i)

let raw_axis r i =
  if i >= 0 && i < Array.length r.raxes then normalize_i16 r.raxes.(i)
  else 0.

let raw_hat r i =
  if i >= 0 && i < Array.length r.rhats then r.rhats.(i) else 0

let bind_as_pressed r = function
  | Hw_button i -> raw_button r i
  | Hw_axis (i, inv) ->
    let v = raw_axis r i in
    Float.abs (if inv then -.v else v) > axis_button_threshold
  | Hw_axis_half (i, pos) ->
    let v = raw_axis r i in
    if pos then v > axis_button_threshold else v < -.axis_button_threshold
  | Hw_hat (i, m) -> raw_hat r i land m <> 0

let bind_as_axis r = function
  | Hw_axis (i, inv) ->
    let v = raw_axis r i in
    if inv then -.v else v
  | Hw_axis_half (i, pos) ->
    let v = raw_axis r i in
    if pos then Float.max 0. v else Float.max 0. (-.v)
  | Hw_button i -> if raw_button r i then 1. else 0.
  | Hw_hat (i, m) -> if raw_hat r i land m <> 0 then 1. else 0.

let standard_buttons =
  [ A; B; X; Y; Back; Guide; Start; Left_stick; Right_stick;
    Left_shoulder; Right_shoulder; Dpad_up; Dpad_down; Dpad_left;
    Dpad_right; Misc1; Paddle1; Paddle2; Paddle3; Paddle4; Touchpad ]

let standard_axes =
  [ Left_x; Left_y; Right_x; Right_y; Left_trigger; Right_trigger ]

(* Evaluate a mapping against a raw hardware snapshot. Axis values
   pass through [dz] (per-axis deadzone selector); pass [fun _ -> 0.]
   for raw readings. *)
let eval_mapping ?(dz = fun _ -> 0.) m r =
  let pressed =
    List.filter
      (fun b ->
        match mapping_button_bind m b with
        | Some bind -> bind_as_pressed r bind
        | None -> false)
      standard_buttons
  in
  let axes =
    List.filter_map
      (fun a ->
        match mapping_axis_bind m a with
        | Some bind -> Some (a, apply_deadzone ~zone:(dz a) (bind_as_axis r bind))
        | None -> None)
      standard_axes
  in
  { pressed; axes }

(* ---------- per-frame diff ---------- *)

let axis_value st a =
  match List.assoc_opt a st.axes with Some v -> v | None -> 0.

let diff id old_ new_ =
  let releases =
    List.filter_map
      (fun b ->
        if List.mem b new_.pressed then None
        else Some (Button (id, b, Released)))
      old_.pressed
  in
  let presses =
    List.filter_map
      (fun b ->
        if List.mem b old_.pressed then None
        else Some (Button (id, b, Pressed)))
      new_.pressed
  in
  let moves =
    List.filter_map
      (fun (a, v) ->
        if Float.abs (v -. axis_value old_ a) > axis_eps then
          Some (Axis_move (id, a, v))
        else None)
      new_.axes
  in
  releases @ presses @ moves

(* ---------- controller registry / frame tracker ---------- *)

type tracker = {
  tbl : (int, controller * state) Hashtbl.t;
}

let create_tracker () = { tbl = Hashtbl.create 8 }

let tracker_mem t id = Hashtbl.mem t.tbl id
let tracker_state t id =
  Option.map snd (Hashtbl.find_opt t.tbl id)
let tracker_controller t id =
  Option.map fst (Hashtbl.find_opt t.tbl id)
let tracker_controllers t =
  Hashtbl.fold (fun _ (c, _) acc -> c :: acc) t.tbl []
  |> List.sort (fun a b -> compare a.id b.id)

(* Attach with its first snapshot: emits [Connected] followed by any
   initial button presses (a controller held down while plugging in
   still reports its held buttons). *)
let tracker_connected t c st =
  if Hashtbl.mem t.tbl c.id then []
  else begin
    Hashtbl.replace t.tbl c.id (c, st);
    Connected c :: diff c.id empty_state st
  end

let tracker_disconnected t id =
  if Hashtbl.mem t.tbl id then begin
    Hashtbl.remove t.tbl id;
    [ Disconnected id ]
  end
  else []

let tracker_update t id st =
  match Hashtbl.find_opt t.tbl id with
  | None -> []
  | Some (c, old_) ->
    let evs = diff id old_ st in
    Hashtbl.replace t.tbl id (c, st);
    evs
