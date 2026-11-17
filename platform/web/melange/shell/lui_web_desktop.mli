(** Optional services of the OCaml system-WebView desktop host. *)
val available : unit -> bool
val check_for_updates : unit -> bool Js.Promise.t
(** Open the software update window. Resolves [false] in an ordinary browser. *)

val invoke :
  ('a, 'b) Lui_command.t -> 'a -> ('b, Lui_command.error) result Js.Promise.t
(** Call an explicitly registered native application command. Errors resolve
    as [Error], including absence of the desktop host and malformed responses. *)
