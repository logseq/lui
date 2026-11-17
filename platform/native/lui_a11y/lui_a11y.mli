(* Platform-agnostic accessibility semantic model for the native backend.

   Derives an a11y tree from the retained Lui_store node mirror so that
   platform bridges (macOS, AT-SPI, UIA, ...) bind one stable model
   instead of reinterpreting raw patch ops. Nodes keep their store ids;
   records are immutable snapshots recomputed on [update]. *)

(** Platform-neutral role classification; each bridge translates it to
    the native role. *)
type role =
  | Window
  | Group
  | Static_text
  | Heading
  | Text_field
  | Text_area
  | Search_field
  | Button
  | Toggle_button
  | Check_box
  | Radio_button
  | Radio_group
  | Switch
  | Slider
  | Spin_button
  | Progress_indicator
  | Link
  | Image
  | List
  | List_item
  | Outline
  | Outline_item
  | Tab_group
  | Tab
  | Menu
  | Menu_item
  | Combo_box
  | Dialog
  | Sheet
  | Tooltip
  | Table
  | Table_row
  | Table_cell
  | Separator
  | Toolbar
  | Status_bar
  | Navigation
  | Split_group
  | Extension

(** Tri-state for checkable controls. *)
type check_state =
  | Checked
  | Unchecked
  | Mixed

type state_flags = {
  focusable : bool;
  focused : bool;
  selected : bool;
  checked : check_state option;  (** [None] on non-checkable nodes *)
  disabled : bool;
  expanded : bool option;        (** [None] when not expandable *)
  required : bool;
  read_only : bool;
  password : bool;
}

(** Value payload for fields, sliders, steppers and progress nodes. *)
type a11y_value = {
  numeric : float option;
  minimum : float option;
  maximum : float option;
  text : string option;
}

type node_a11y = {
  id : int;
  kind : string;                 (** store kind name (wire name) *)
  role : role;
  name : string option;          (** computed accessible name *)
  description : string option;
  state : state_flags;
  value : a11y_value option;
  parent : int option;           (** a11y parent id *)
  children : int list;           (** a11y-visible child ids, in order *)
  ext_id : string option;        (** extension identifier, kept *)
}

(** A retained a11y forest bound to a store. *)
type t

(** {2 Kind mapping} *)

val kind_role_table : (string * role) list
(** Explicit kind-name -> role mapping covering every standard kind. *)

val role_of_kind : string -> role
(** [role_of_kind kind] maps a store kind name to an a11y role.
    ["extension:<id>"] maps to [Extension]; unknown kinds to [Group]. *)

val role_name : role -> string

(** {2 Deriving the tree} *)

val build : Lui_store.t -> node_a11y list
(** One-shot derivation: the a11y forest, roots in store order. Nodes
    hidden via [visible]=false or [display]="none" are excluded together
    with their subtrees. *)

val of_store : Lui_store.t -> t
(** Retained a11y forest bound to a store for incremental [update]. *)

val store : t -> Lui_store.t
val roots : t -> node_a11y list
val root_ids : t -> int list
val node_count : t -> int
val mem : t -> int -> bool
val find : t -> int -> node_a11y option
val flatten : t -> node_a11y list
(** Preorder over the forest. *)

(** {2 Incremental updates} *)

val update : t -> int list -> int list
(** [update t dirty_ids] recomputes the a11y records for a drained
    dirty-id set (see [Lui_store.drain_dirty]), reconciling structure,
    visibility and ancestor-derived fields (children lists, names
    accumulated from descendants). Returns the ids whose a11y record
    changed — added, modified or removed — sorted ascending; exactly the
    set a platform bridge turns into change notifications. *)

val sync : t -> int list
(** [sync t] drains the bound store's dirty set and applies [update]. *)

(** {2 Focus tracking} *)

val focused : t -> int option
val focused_node : t -> node_a11y option
val set_focused : t -> int -> int list
(** [set_focused t id] marks [id] focused, clearing any previous focus.
    Returns the ids whose records changed (old and new focus targets). *)

val clear_focused : t -> int list
