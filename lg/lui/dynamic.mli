(* ns lui.dynamic *)

type ui_switch = { dispose_dynamic_switch : unit -> bool ; switch_node_ref : int option ref }

type ui_conditional = { dispose_dynamic_conditional : unit -> bool ; conditional_node_ref : int option ref }

type 'key ui_key_node = { ui_key : 'key ; ui_node : int }

type 'key ui_keyed = { dispose_dynamic_keyed : unit -> bool ; key_nodes : 'key ui_key_node Rrbvec.t ref ; key_compare : 'key -> 'key -> int }

val switch_bang : ui_context -> int -> 'key signal -> ('key -> 'key -> bool) -> (ui_context -> 'key -> int) -> ui_switch

val make_switch : (unit -> bool) -> int option ref -> ui_switch

val segment_disposer : application -> dynamic_segment -> (unit -> bool) -> (unit -> bool)

val switch_node : ui_switch -> int

val dispose_switch_bang : ui_switch -> bool

val make_conditional : (unit -> bool) -> int option ref -> ui_conditional

val conditional_bang : ui_context -> int -> bool signal -> (ui_context -> int) -> ui_conditional

val conditional_node : ui_conditional -> int

val dispose_conditional_bang : ui_conditional -> bool

val find_key_node : 'key ui_key_node Rrbvec.t -> 'key -> ('key -> 'key -> int) -> int option

val remove_key_node_bang : 'key ui_key_node Rrbvec.t ref -> 'key -> ('key -> 'key -> int) -> bool

val mount_keyed_item_bang : ui_context -> int -> dynamic_segment -> ('item -> 'key) -> ('key -> 'key -> int) -> (ui_context -> 'item signal -> int) -> 'key ui_key_node Rrbvec.t ref -> 'item signal -> scope

val keyed_bang : ui_context -> int -> 'item Rrbvec.t signal -> ('item -> 'key) -> ('key -> 'key -> int) -> (ui_context -> 'item signal -> int) -> 'key ui_keyed

val make_keyed : (unit -> bool) -> 'key ui_key_node Rrbvec.t ref -> ('key -> 'key -> int) -> 'key ui_keyed

val keyed_node : 'key ui_keyed -> 'key -> int

val dispose_keyed_bang : 'key ui_keyed -> bool

