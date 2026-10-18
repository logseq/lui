(** Transcript: a keyed message list with tail-follow autoscroll.

    Rows keep identity across reordering, duplication and streaming
    updates of the same {!Model.item.id}. Items render strictly in the
    order the host supplies — the transcript never sorts. *)

open Lui_elements

(** Tail-follow contract. {!Anchored} (the default) mounts
    [virtual_list] — the virtualized message list — and drives the
    scroll contract ([scroll-target]/[scroll-anchor]/[scroll-token]
    plus [visible-range] tracking) implemented by virtualizing
    backends; {!Anchored_list} mounts [list] instead. {!Host_driven}
    mounts the chosen container and hands scrolling to the host —
    e.g. a web extension that tracks the scroll offset and calls
    [scrollIntoView] on the row carrying the key. *)
type viewport =
  | Anchored
  | Anchored_list
  | Host_driven of host_viewport

and host_viewport = {
  container : [ `list | `virtual_list ];
  at_bottom : bool Signal.signal;
      (** Borrowed: must publish [true] while the viewport's tail is
          within reach; the transcript latches its internal pin from it.
          The signal is never retained or disposed by the library. *)
  scroll_to : key:string -> animated:bool -> unit;
      (** Called on the signal push path when the transcript wants the
          row carrying [KeyValue key] brought into view. [animated]
          distinguishes user jumps from live follow. *)
}

val transcript :
  ?key:string ->
  ?viewport:viewport ->
  ?overscan:int ->
  ?item_extent:float ->
  ?content_width:int ->
  ?group_tools:bool ->
  ?render_item:(Model.item Signal.signal -> t option) ->
  ?render_attachment:(Model.attachment -> t) ->
  ?item_class:(Model.item -> string) ->
  ?item_data_attrs:(Model.item -> (string * string) list) ->
  ?container_class:string ->
  ?container_data_attrs:(string * string) list ->
  ?item_actions:(Model.item Signal.signal -> t) ->
  ?on_retry:(Model.id -> unit) ->
  ?retry_label:string ->
  ?on_load_full:(Model.id -> unit) ->
  ?load_full_label:(Model.item -> string) ->
  ?on_reach_top:(unit -> unit) ->
  ?scroll_animated:bool ->
  ?container_data_attrs_signal:(string * string) list Signal.signal ->
  messages:Model.item list Signal.signal ->
  unit ->
  t
(** Keyed message list plus tail-follow autoscroll and a "Jump to
    latest" affordance while unpinned.

    - Consecutive [Tool_call] items collapse into one "Working on N
      steps" / "Worked through N steps" section ([group_tools], default
      [true]); the section auto-expands while any call is active and
      stays user-toggleable, keyed by the first member's id.
    - [on_retry] adds a resend control on [`uncertain] items (labelled
      [retry_label], default ["Retry same message"]); [item_actions]
      mounts host actions per row (copy, etc.) and receives the borrowed
      item signal so callbacks read current content.
    - [on_load_full] is the lazy-payload action shown on items with
      [truncated] or a truncated tool output; [load_full_label] names it
      (default ["Load full item"]).
    - [on_reach_top] fires on the rising edge of the first row becoming
      visible (history paging).
    - [container_class]/[container_data_attrs] land on the scroll
      container itself (list or virtual_list) for host CSS/locators;
      [item_class]/[item_data_attrs] land on each row. *)

val item_row : Model.item -> t
(** A single message row mounted outside [transcript] (previews). *)
