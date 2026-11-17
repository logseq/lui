(* In-process backend fast path (plan P1-4).

   The patch protocol stays the architectural seam — every backend
   still consumes [Lui_protocol.patch_batch] — but how the batch
   reaches the consumer is a transport choice:

   - [In_process]: the batch is delivered as the value it already is.
     This is what a same-process native backend (the SDL host, a
     headless harness) should pay: no encode, no decode, just apply.
   - [Wire]: the batch round-trips through the wire format —
     [Lui_wire.encode_batch] then [Lui_wire.decode_batch] — exactly
     what a foreign or remote host pays across the bridge ABI. Keeping
     that path expressible in-process lets the same test suite run
     against both backends and keeps protocol parity checkable.

   The real wire backend for SwiftUI/Kotlin/Web/remote drivers is
   [Lui_native_bridge]; this module mirrors its transport for
   same-runtime consumers. *)

type transport = Lui_wire.transport =
  | In_process
  | Wire

val transport_name : transport -> string

type t
(** A backend sink: a transport plus the [patch_batch -> unit]
    delivery it transcodes into. *)

val create : transport -> (Lui_protocol.patch_batch -> unit) -> t
(** [create transport deliver] builds a backend whose {!apply_batch}
    runs [deliver] on the batch after the transport's transcoding —
    identity for [In_process], encode+decode for [Wire]. *)

val over_store : transport -> Lui_store.t -> t
(** [over_store transport store] delivers into
    [Lui_store.apply_batch store]. *)

val apply_batch : t -> Lui_protocol.patch_batch -> unit
(** The fast-path entry point: one call from flush to committed
    mirror, with only [Wire] paying the serialization round-trip. *)

val transport : t -> transport

val backend : t -> Lui_protocol.platform_profile -> Lui_protocol.backend
(** Adapt to the record [Lui_app.create] consumes: the same app code
    drives either transport unchanged. *)
