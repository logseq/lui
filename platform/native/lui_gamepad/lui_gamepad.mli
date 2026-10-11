(** Gamepad input for the native backend.

    Usage for window hosts: call {!pump} once per frame after the
    host's own input poll, then either feed the returned {!event}s to
    dispatch directly or pass them through {!input_of_event} for
    buttons that behave like navigation keys.  Backends are
    state-polling — SDL reads controller state without consuming the
    event queue, XInput polls by user index — so the host keeps
    owning event delivery and message handling. *)

include module type of Lui_gamepad_core

(** Backend internals, exposed for tests and tooling. *)
module Sdl : module type of Lui_gamepad_sdl
module Xinput : module type of Lui_gamepad_xinput

(** A pluggable backend: SDL on macOS/Linux, XInput on Windows.
    Tests substitute a fake source with {!Private.set_source}. *)
type source = {
  name : string;
  init : unit -> (unit, string) result;
  refresh : tracker -> event list;
}

val init : unit -> (unit, string) result
(** Select and initialize the platform backend.  Idempotent; called
    lazily by {!pump} on first use. *)

val pump : unit -> event list
(** Drain one frame of gamepad input into events: connect/disconnect,
    button press/release, and deadzoned axis moves.  Safe to call on
    any platform — returns [\[\]] when no backend is available. *)

val controllers : unit -> controller list
val state : int -> state option
val backend_name : unit -> string
val init_error : unit -> string option
val available : unit -> bool

val add_mapping : string -> (mapping, string) result
(** Parse a GameControllerDB-format string, register it, and forward
    it to SDL when that backend is live. *)

val add_mappings_from_file : string -> int
(** [SDL_GameControllerAddMappingsFromFile] — returns the number of
    mappings loaded, [0] on non-SDL backends, [-1] on failure. *)

val input_of_event : event -> Lui_window.Input.t option
(** Map navigation-style button presses (dpad, A, B, Start) onto the
    [Key_down] inputs window dispatch already routes to the focused
    node.  Returns [None] for everything else — app-level handlers
    consume the raw {!event} instead. *)

module Private : sig
  val set_source : source -> unit
  (** Swap the active backend (clears tracked controllers). *)

  val tracker : tracker
end
