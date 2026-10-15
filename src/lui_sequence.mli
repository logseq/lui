(** Persistent ordered sequences with constant-time length and logarithmic
    indexed access, insertion, and removal. Snapshots share unchanged nodes. *)
type 'a t
val empty : 'a t
val length : 'a t -> int
val insert : 'a t -> int -> 'a -> 'a t
val get : 'a t -> int -> 'a
val index : 'a t -> 'a -> int option
val remove : 'a t -> int -> 'a t
val to_list : 'a t -> 'a list
val of_list : 'a list -> 'a t
val map : ('a -> 'b) -> 'a t -> 'b t
val iter : ('a -> unit) -> 'a t -> unit
val iteri : (int -> 'a -> unit) -> 'a t -> unit
val fold_left : ('a -> 'b -> 'a) -> 'a -> 'b t -> 'a
val fold_right : ('a -> 'b -> 'b) -> 'a t -> 'b -> 'b
val exists : ('a -> bool) -> 'a t -> bool
val find_map : ('a -> 'b option) -> 'a t -> 'b option
val find_opt : ('a -> bool) -> 'a t -> 'a option
