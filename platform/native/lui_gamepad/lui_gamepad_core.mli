(** Pure gamepad model: controller record, standard control
    vocabulary, GameControllerDB mapping parser, axis normalization
    and deadzones, and the per-frame snapshot → event diff.  Nothing
    here touches a host API; every function is testable headless. *)

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

val sdl_button_order : button array
val sdl_axis_order : axis array
val button_of_sdl : int -> button
val axis_of_sdl : int -> axis
val string_of_button : button -> string
val string_of_axis : axis -> string
val string_of_kind : kind -> string
val button_of_name : string -> button option
val axis_of_name : string -> axis option

val normalize_i16 : int -> float
(** Signed 16-bit axis → [-1.0, 1.0]. *)

val normalize_u8 : int -> float
(** Unsigned 8-bit trigger → [0.0, 1.0]. *)

val apply_deadzone : zone:float -> float -> float
(** Symmetric deadzone, renormalized so output stays smooth at the
    zone edge. *)

val xinput_left_deadzone : float
val xinput_right_deadzone : float
val xinput_trigger_deadzone : float
val default_stick_deadzone : float
val default_trigger_deadzone : float
val axis_eps : float
val axis_button_threshold : float

(** {2 Mapping table} *)

type hw_bind =
  | Hw_button of int
  | Hw_axis of int * bool (** index, inverted *)
  | Hw_axis_half of int * bool (** index, true = positive half *)
  | Hw_hat of int * int (** hat index, direction mask *)

type mapping = {
  guid : string;
  map_name : string;
  binds : (string * hw_bind) list;
}

val parse_hw_bind : string -> hw_bind option
val parse_mapping_line : string -> mapping option
val parse_mapping_db : string -> mapping list
val mapping_button_bind : mapping -> button -> hw_bind option
val mapping_axis_bind : mapping -> axis -> hw_bind option

(** {2 Snapshots and diffs} *)

type raw_state = {
  rbuttons : bool array;
  raxes : int array;
  rhats : int array;
}

val empty_raw : raw_state

type state = {
  pressed : button list;
  axes : (axis * float) list;
}

val empty_state : state

val eval_mapping :
  ?dz:(axis -> float) -> mapping -> raw_state -> state
(** Standard snapshot from a raw hardware snapshot through a mapping.
    [dz] picks the deadzone per axis (default 0). *)

val diff : int -> state -> state -> event list
(** [diff id old new_] is the press/release/axis events moving the
    snapshot [old_] to [new_]. *)

type tracker

val create_tracker : unit -> tracker
val tracker_mem : tracker -> int -> bool
val tracker_state : tracker -> int -> state option
val tracker_controller : tracker -> int -> controller option
val tracker_controllers : tracker -> controller list
val tracker_connected : tracker -> controller -> state -> event list
val tracker_disconnected : tracker -> int -> event list
val tracker_update : tracker -> int -> state -> event list
