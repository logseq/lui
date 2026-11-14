(** Explicit shared viewport lifetimes. Create the owner and semantic source
    handles in application state, before mounting the view. Returned signals
    are borrowed: consuming views must not dispose them. The SDK disposes
    binding signals with the owner, and receipt signals when the ticket ends.
    Unmounting a view invalidates its binding lease without disposing the
    application-owned handles.

    Each owner has one flat source. Retain cold rows before mounting:
    {[
      let owner = Lui_virtual.create_owner () in
      let root = Lui_virtual.root_source owner ~key:"outline" in
      let retained = Lui_virtual.retain root ~key:"editor-id" in
      let native_ticket = Lui_virtual.ticket retained in
      ignore native_ticket;
      match Signal.sample (Lui_virtual.receipt retained) with
      | Some proof when Lui_virtual.receipt_status proof = Lui_virtual.Focused ->
        ignore (Lui_virtual.request_release retained proof)
      | _ -> ()
    ]}
    Bind the owner to [Lui_elements.scroll ~virtual_owner:owner] and its source
    to [Lui_elements.virtual_list ~viewport:source], then use [virtual_rows]
    with stable semantic [scroll_key] values. Negotiate
    [~virtual_capabilities:[Shared_viewport_retention_v1]] on the application.
    Native controls must register their actual view before acknowledging a
    ticket. Release requests preserve cold keys until a validated native
    [Released] receipt; cancellation explicitly abandons that obligation. *)
type owner
type source
type retention
type receipt
type binding = { node : int; lease : int }
type release_error = Stale_receipt | Owner_retired | Unsupported
type capability = Shared_viewport_retention_v1
type receipt_status = Pinned | Focused | Released | Stale | Missing_target | Retired

val shared_viewport_version : int
val supports : Lui_protocol.host_kind -> capability -> bool
val create_owner : unit -> owner

(** Retire the owner and invalidate all bindings and unfinished tickets.
    Call when the application state owning these handles ends. Idempotent. *)
val dispose_owner : owner -> unit

(** Reuse the source for the same key; a distinct second key is rejected.
    Owners cannot nest, and virtual owners and sources cannot be nested
    inside virtual rows. *)
val root_source : owner -> key:string -> source
val binding : source -> binding option Signal.signal
val retain : source -> key:string -> retention

(** Positive owner-scoped native acknowledgement identifier. *)
val ticket : retention -> int

(** Borrowed signal, initially [None]. A successful release publishes its final
    [Released] value before ending the signal's subscription lifetime. *)
val receipt : retention -> receipt option Signal.signal
val receipt_status : receipt -> receipt_status
val request_release : retention -> receipt -> (unit, release_error) result

(** End the logical obligation without requiring physical pin acknowledgement.
    Use only when the application no longer needs to preserve this target. *)
val cancel_retention : retention -> unit

(** Runtime integration, below the DSL dependency layer. All unbind functions
    are lease-fenced. Obligation publishers run synchronously before
    reconciliation; source receipt refreshes are scheduled after transactions. *)
module Internal : sig
  val bind_owner : owner -> node:int -> publish:(int -> string -> string -> unit) -> schedule_receipts:(unit -> unit) -> binding
  val flush_receipts : owner -> unit
  val unbind_owner : owner -> binding -> bool
  val bind_source : source -> node:int -> owner_node:int -> binding
  val unbind_source : source -> binding -> bool
  val owner_binding : source -> binding option
  val retained_keys : source -> string list
  val on_change : source -> (unit -> unit) -> (unit -> unit)
  val commit_rows : source -> lease:int -> generation:int -> contains:(string -> bool) -> (string * int) list -> unit
  val accept_receipt : owner -> node:int -> ticket:int -> string -> unit
  val adopt_pins : source -> node:int -> (int list -> unit) -> (unit -> unit)
  val remap : owner -> (int -> int) -> unit
  val checkpoint : owner -> (unit -> unit)
  val replacing_owner : owner -> (unit -> unit)
  val replacing_source : source -> (unit -> unit)
end
