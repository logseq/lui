(* Typed resource loaders on top of {!Lui_resource}: one adapter per
   resource kind. Each wraps {!Lui_resource.request}/{!Lui_resource.reload}
   with a canonical key and a load function that produces the kind's
   value, so callers only pick a cache and a source.

   The caches these adapters fill are plain ['v Lui_resource.t]:
   {!Lui_resource.drain} / {!Lui_resource.drain_all} publish their
   completions on the foreground the same way. *)

open Lui_resource

(* Where encoded resource bytes come from. *)
type source =
  | Path of string
      (* local file: read to bytes, then decode *)
  | Bytes of bytes
      (* already-encoded data *)
  | Fetch of Lui_plugin_fetch.request
      (* HTTP(S) via the platform libcurl client; [Url] below is the
         plain-GET convenience *)

val url : string -> source
(* [url u] is [Fetch (Lui_plugin_fetch.request u)] — a GET that follows
   redirects, 30s timeout, public hosts only. *)

val key_of_source : kind:string -> source -> key
(* Stable cache keys: ["kind:file:path"], ["kind:bytes:sha"],
   ["kind:fetch:method url sha"]. *)

(* Read/fetch [src]'s bytes. Runs inside a resource task; honours
   cooperative cancellation between the read/fetch and the caller's
   decode step. *)
val bytes_of_source : task -> source -> (Bytes.t, string) result

module Image : sig
  (* A decoded image as a scene-IR bitmap — the value {!Lui_paint}'s
     [image_of] hook consumes. *)
  type value = Lui_scene.image

  val create :
    ?executor:executor -> ?retire:(value -> unit) -> unit -> value t

  val key_of : source -> key

  val request : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> source -> value entry
  val reload : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> source -> value entry
end

module Svg : sig
  (* A parsed SVG document; callers rasterize at the draw size with
     {!Lui_svg.rasterize} so one entry serves every slot. *)
  type value = Lui_svg.doc

  val create :
    ?executor:executor -> ?retire:(value -> unit) -> unit -> value t

  val key_of : source -> key

  val request : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> source -> value entry
  val reload : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> source -> value entry
end

module Fetch : sig
  (* Raw network resource: a [Lui_plugin_fetch] response. *)
  type value = Lui_plugin_fetch.response

  val create :
    ?executor:executor -> ?retire:(value -> unit) -> unit -> value t

  val key_of : Lui_plugin_fetch.request -> key

  val request : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> Lui_plugin_fetch.request -> value entry
  val reload : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> Lui_plugin_fetch.request -> value entry
end

module Media : sig
  (* A decoded audio buffer ({!Lui_media.decode}); platform-limited —
     where the decoder is missing the entry publishes [Failed]. *)
  type value = Lui_media.pcm

  val create :
    ?executor:executor -> ?retire:(value -> unit) -> unit -> value t

  val key_of : path:string -> key

  val request : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> path:string -> unit -> value entry
  val reload : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) -> path:string -> unit -> value entry
end

module Plugin : sig
  (* A plugin service call ({!Lui_plugin.call}); the value is the raw
     JSON response string. *)
  type value = string

  val create :
    ?executor:executor -> ?retire:(value -> unit) -> unit -> value t

  val key_of : service:string -> method_:string -> payload:string -> key

  val request : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) ->
    service:string -> method_:string -> payload:string -> unit -> value entry
  val reload : value t -> scope:Signal.scope ->
    ?on_state:(value entry -> unit) ->
    service:string -> method_:string -> payload:string -> unit -> value entry
end

module Fonts : sig
  (* Font lookup is engine-specific (CoreText / Pango / DWrite behind
     the same signature), so the adapter takes the engine's
     create-function as [load]; the cache key is canonical. *)
  type spec = {
    families : string list;
    weight : int;
    italic : bool;
    size : float;
  }

  val spec : ?families:string list -> ?weight:int -> ?italic:bool ->
    size:float -> unit -> spec

  val key_of : spec -> key

  val request : 'font t -> scope:Signal.scope ->
    ?on_state:('font entry -> unit) ->
    load:(spec -> 'font) -> spec -> 'font entry
  val reload : 'font t -> scope:Signal.scope ->
    ?on_state:('font entry -> unit) ->
    load:(spec -> 'font) -> spec -> 'font entry
end
