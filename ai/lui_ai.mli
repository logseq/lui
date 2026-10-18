(** Lui_ai — reusable AI/chat surface built on Lui_elements.

    The library owns the ordered item model, the keyed transcript with
    tail-follow autoscroll, collapsible tool-call rendering, attachment
    presentation and the accessible send/stop composer. The host owns
    transport, uploads, tool execution, account and permission UI
    through callbacks — no provider API, authorization, storage or
    credentials live here.

    Caller signals are borrowed for the mount's lifetime and never
    disposed by the library; text renders through text elements only so
    payloads can never inject markup. *)

module Model = Model
module Attachment = Attachment
module Transcript = Transcript
module Composer = Composer

val view :
  ?key:string ->
  ?viewport:Transcript.viewport ->
  ?content_width:int ->
  ?header:Lui_elements.t ->
  ?placeholder:string ->
  ?picker:Composer.picker ->
  ?render_item:(Model.item Signal.signal -> Lui_elements.t option) ->
  ?item_actions:(Model.item Signal.signal -> Lui_elements.t) ->
  ?on_retry:(Model.id -> unit) ->
  ?on_load_full:(Model.id -> unit) ->
  ?on_reach_top:(unit -> unit) ->
  ?on_remove_attachment:(Model.id -> unit) ->
  ?on_picked:(Lui_protocol.event -> unit) ->
  ?on_attach:(Lui_protocol.event -> unit) ->
  ?composer_controls:Lui_elements.t list ->
  ?composer_trailing_controls:Lui_elements.t list ->
  ?status:Lui_elements.t ->
  messages:Model.item list Signal.signal ->
  draft:string Signal.signal ->
  attachments:Model.attachment list Signal.signal ->
  generating:bool Signal.signal ->
  on_input:(Lui_protocol.event -> unit) ->
  on_send:(Lui_protocol.event -> unit) ->
  ?on_stop:(Lui_protocol.event -> unit) ->
  unit ->
  Lui_elements.t
(** Full chat surface: transcript (grow) over the composer capsule, with
    the staged-attachment strip rendered as removable chips. A
    convenience composition — hosts may mount {!Transcript.transcript}
    and {!Composer.composer} separately. *)
