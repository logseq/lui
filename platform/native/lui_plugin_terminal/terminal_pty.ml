(* PTY: spawn a child on a master/slave pair, nonblocking I/O, size
   propagation and exit detection.  Unix uses forkpty; Windows a real
   ConPTY; elsewhere spawning raises [Failure]. *)

type t = { h : nativeint; mutable alive : bool }

external c_spawn : string array -> string array -> string -> int -> int
  -> nativeint = "lui_term_pty_spawn"
external c_read : nativeint -> bytes -> int -> int -> int
  = "lui_term_pty_read"
external c_write : nativeint -> bytes -> int -> int -> int
  = "lui_term_pty_write"
external c_resize : nativeint -> int -> int -> unit
  = "lui_term_pty_resize"
external c_poll : nativeint -> int = "lui_term_pty_poll"
external c_kill : nativeint -> unit = "lui_term_pty_kill"
external c_close : nativeint -> unit = "lui_term_pty_close"

let spawn ~argv ~env ~cwd ~cols ~rows =
  if Array.length argv = 0 then invalid_arg "Terminal_pty.spawn: empty argv";
  { h = c_spawn argv env cwd cols rows; alive = true }

(* Read up to [len] bytes.  Returns the byte count, 0 when no data is
   ready (nonblocking), or -1 at end of file / dead child. *)
let read t buf off len =
  if len <= 0 then 0 else c_read t.h buf off len

let write t buf off len =
  if len <= 0 then 0 else c_write t.h buf off len

let write_string t s = write t (Bytes.unsafe_of_string s) 0 (String.length s)

let resize t ~cols ~rows = c_resize t.h cols rows

(* [Some code] once the child has exited (sticky), [None] while it
   runs. *)
let poll t =
  if not t.alive then Some 137
  else
    let r = c_poll t.h in
    if r >= 0 then begin t.alive <- false; Some r end
    else None

let alive t = t.alive

let kill t =
  if t.alive then begin t.alive <- false; c_kill t.h end

let close t =
  if t.alive then kill t;
  c_close t.h
