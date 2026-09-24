(** Dynamic UI structure over signals: [switch] reconciles a new branch
    against the old one when its key signal changes (same-kind nodes keep
    their ids; only divergent nodes drop+create), [conditional] shows/hides
    a branch on a bool signal, and [keyed] keeps an identity-keyed
    collection of children in sync with an item-list signal
    (Insert/Remove/Move patches). *)

type ui_switch = {
  dispose_dynamic_switch : unit -> unit;
  switch_node_ref : int option ref;
}
type ui_conditional = {
  dispose_dynamic_conditional : unit -> unit;
  conditional_node_ref : int option ref;
}
type 'key ui_key_node = { ui_key : 'key; ui_node : int; }
type 'key ui_keyed = {
  dispose_dynamic_keyed : unit -> unit;
  key_nodes : 'key ui_key_node list ref;
  key_compare : 'key -> 'key -> int;
}
val segment_disposer :
  Lui_runtime.application ->
  Lui_runtime.dynamic_segment -> (unit -> unit) -> unit -> unit
val switch :
  Lui_ui.ui_context ->
  int ->
  'a Signal.signal ->
  ('a -> 'a -> bool) -> (Lui_ui.ui_context -> 'a -> int) -> ui_switch
val switch_node : ui_switch -> int
val dispose_switch : ui_switch -> unit
val conditional :
  Lui_ui.ui_context ->
  int -> bool Signal.signal -> (Lui_ui.ui_context -> int) -> ui_conditional
val conditional_node : ui_conditional -> int
val dispose_conditional : ui_conditional -> unit
val find_key_node :
  'a ui_key_node list -> 'b -> ('a -> 'b -> int) -> int option
val remove_key_node :
  'a ui_key_node list ref -> 'b -> ('a -> 'b -> int) -> unit
val mount_keyed_item :
  Lui_ui.ui_context ->
  int ->
  Lui_runtime.dynamic_segment ->
  ('a -> 'b) ->
  ('b -> 'b -> int) ->
  (Lui_ui.ui_context -> 'a Signal.signal -> int) ->
  'b ui_key_node list ref -> 'a Signal.signal -> Signal.scope
val keyed :
  Lui_ui.ui_context ->
  int ->
  'a list Signal.signal ->
  ('a -> 'b) ->
  ('b -> 'b -> int) ->
  (Lui_ui.ui_context -> 'a Signal.signal -> int) -> 'b ui_keyed
val keyed_node : 'a ui_keyed -> 'a -> int
val dispose_keyed : 'a ui_keyed -> unit
