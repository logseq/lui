(** Explicit native command registration. Handlers run on bounded worker threads. *)
type binding
val handle : ('a, 'b) Lui_command.t -> ('a -> ('b, Lui_command.error) result) -> binding

type t
val create : ?max_in_flight:int -> binding list -> (t, string) result
val dispatch : t -> name:string -> payload:string -> reply:(string -> unit) -> unit
(** Replies exactly once with a JSON result/error envelope. Unknown commands,
    malformed arguments and overload never call the application handler. *)
val close : t -> unit
