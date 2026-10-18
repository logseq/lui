(** Composer: the accessible send/stop input capsule.

    Built on [Lui_element_combine.composer]. While [generating]
    publishes [true] a labelled stop control appears and send stays
    disabled. The draft [text] signal is borrowed host state — it
    survives streaming updates and supports controlled reset. *)

open Lui_elements

(** Optional platform file/photo/camera picker wiring. With [picker],
    the attach control drives an internal request token and the host
    receives the raw [Picked] event via [on_picked] — decode it with
    [Lui_picked_files.decode] and copy/import files before the library
    echoes the completion token. Without [picker], [on_attach] is a
    plain callback for host-supplied pickers. *)
type picker = {
  source : file_picker_source;
  types : string option;   (* UTI list, comma-separated *)
  accept : string option;  (* web accept filter *)
  multiple : bool;
}

val composer :
  ?key:string ->
  ?label:string ->
  ?placeholder:string ->
  ?submit_on_enter:bool ->
  ?autofocus:bool ->
  ?send_label:string ->
  ?stop_label:string ->
  ?attach_label:string ->
  draft:string Signal.signal ->
  generating:bool Signal.signal ->
  ?send_disabled:bool Signal.signal ->
  ?disabled_reason:string Signal.signal ->
  ?status:t ->
  ?attachments:t ->
  ?attachments_visible_signal:bool Signal.signal ->
  ?controls:t list ->
  ?trailing_controls:t list ->
  ?picker:picker ->
  ?on_picked:(Lui_protocol.event -> unit) ->
  ?on_picker_dismiss:(Lui_protocol.event -> unit) ->
  ?on_attach:(Lui_protocol.event -> unit) ->
  on_input:(Lui_protocol.event -> unit) ->
  on_send:(Lui_protocol.event -> unit) ->
  ?on_stop:(Lui_protocol.event -> unit) ->
  unit ->
  t
(** - [on_send] fires on the send button and (with [submit_on_enter])
      on Enter; [on_stop] renders a stop control only while
      [generating].
    - [send_disabled] is OR'd with [generating]; [disabled_reason]
      greys the field and explains why on the feedback line; [status]
      is a free slot for errors/notices.
    - [controls]/[trailing_controls] flank the action row around the
      library's attach/stop controls (account select, refresh, retry).
    - No attach control mounts unless [picker] or [on_attach] is given. *)
