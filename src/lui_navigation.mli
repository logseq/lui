(** Controlled navigation whose root is outside the path. Business routes stay
    typed in OCaml; Apple hosts receive only entry IDs and revisions. *)

type 'route entry = private { id : string; route : 'route }
(** A distinct presentation of a route, even when another entry has the same
    route. IDs are process-local and allocated on the UI scheduler. *)

module Path : sig
  type +'route t

  val empty : 'route t
  (** Polymorphic empty path. *)

  val push : 'route -> 'route t -> 'route t
  (** Allocate a fresh entry and append it logically to the top, in O(1). *)

  val pop : 'route t -> 'route t
  (** Remove the top entry in O(1). An empty path stays empty. *)

  val pop_to_root : 'route t -> 'route t

  val entries : 'route t -> 'route entry list
  (** Root-to-top order, excluding root, in O(depth). *)
end

val register_into : Lui_extension.extension_registry -> unit
(** Add the Apple navigation schemas to an unfrozen application registry. The
    Swift host must also call [LUINavigation.register(in:)]. *)

val registry : unit -> Lui_extension.extension_registry
(** A fresh frozen registry containing the navigation schemas. *)

val navigation_stack :
  ?key:string ->
  path_signal:'route Path.t Signal.signal ->
  on_path_change:('route Path.t -> unit) ->
  destination:('route entry -> Lui_elements.t) ->
  root:Lui_elements.t ->
  unit ->
  Lui_elements.t
(** Mount once; subscribe root and destination content locally. Push/pop
    preserve root and covered entry nodes, render scopes and local state. Apple
    retains outgoing entries until the current revision settles. A committed
    native back action proposes a shorter path through [on_path_change]; the
    owner may accept, reject or synchronously replace it. Programmatic changes
    do not echo. Cancelling a native transition does not commit a path change.

    Other hosts render the current page with a Back button, retaining covered
    LUI nodes/scopes while detached. Their native widget and scroll retention is
    host-dependent. SwiftUI may recompute body or recreate native objects; this
    function does not promise those objects live forever. *)
