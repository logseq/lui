type t
(** Retained-row reading position for a prepended virtual list. *)

type snapshot

val create :
  Webapi.Dom.Element.t ->
  (int, Webapi.Dom.Element.t) Hashtbl.t ->
  (int, int) Hashtbl.t ->
  Lui_web_virtualizer.t ->
  t

val capture : t -> snapshot option
val preserve : t -> snapshot option -> unit
val cancel : t -> unit
val restore : t -> scrolled:(float -> unit) -> unit
