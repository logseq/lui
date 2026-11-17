(* PTY handle: real forkpty on Unix, ConPTY on Windows, Failure on
   other platforms. *)

type t

val spawn : argv:string array -> env:string array -> cwd:string ->
  cols:int -> rows:int -> t
(** [spawn ~argv ~env ~cwd ~cols ~rows] runs [argv.(0)] on a fresh
    terminal.  [env] items are "K=V".  Raises [Failure] where PTYs are
    unsupported. *)

val read : t -> bytes -> int -> int -> int
(** [read t buf off len] fills [buf] at [off] with up to [len] bytes:
    returns the count, 0 when no data is ready, -1 at EOF. *)

val write : t -> bytes -> int -> int -> int
(** Returns the byte count written, 0 on back-pressure, -1 on error. *)

val write_string : t -> string -> int

val resize : t -> cols:int -> rows:int -> unit

val poll : t -> int option
(** [Some code] when the child has exited (128+signal for kills). *)

val alive : t -> bool
val kill : t -> unit
val close : t -> unit
