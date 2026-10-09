type t

val of_list : int list -> t
val to_list : t -> int list
val length : t -> int
val index : t -> int -> int option
val insert : t -> int -> int -> unit
val remove : t -> int -> unit
val move : t -> int -> int -> unit
val set_weight : t -> int -> int -> unit
val prefix_weight : t -> int -> int
