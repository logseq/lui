(* ns lui.host.ctypes *)

val c_string : string Ctypes.typ

val c_int : int Ctypes.typ

val c_void : unit Ctypes.typ

val open_library : string -> Dl.library

val bind_string_int : Dl.library -> string -> (string -> int)

val bind_int_int : Dl.library -> string -> (int -> int)

val bind_unit_unit : Dl.library -> string -> (unit -> unit)

val bind_event_setter : Dl.library -> string -> ((int -> (int -> (string -> unit))) -> unit)

