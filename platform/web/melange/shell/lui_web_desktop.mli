(** Optional services of the OCaml system-WebView desktop host. *)
val available : unit -> bool
val check_for_updates : unit -> bool Js.Promise.t
(** Open the software update window. Resolves [false] in an ordinary browser. *)
