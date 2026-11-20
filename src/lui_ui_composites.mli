(** Tier-1 semantic UI composites built from {!Lui_elements} and {!Lui_tokens}.

    Every constructor here returns a declarative {!Lui_elements.el} value —
    low-level imperative [int]-returning builders remain under {!Lui_ui}
    (aliased as {!Lui.Raw}). *)

module Tokens = Lui_tokens
type color = Tokens.color
type space = Tokens.space
type radius = Tokens.radius
type text_role = Tokens.text_role

type action = Lui_element_combine.action =
  | Press of
      { label : string
      ; icon : Lui_elements.icon
      ; text : string option
      ; on_press : unit -> unit
      }
  | Menu of
      { label : string
      ; icon : Lui_elements.icon
      ; text : string option
      ; menu : Lui_elements.dropdown_menu_item_el list
      ; on_dismiss : (unit -> unit) option
      }

val buttons : actions:action list -> Lui_elements.t

val composer :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?attachments:Lui_elements.t ->
  ?attachments_visible_signal:bool Signal.signal ->
  ?attachments_height:int ->
  ?feedback:Lui_elements.t ->
  ?actions:Lui_elements.t list ->
  placeholder:string ->
  ?label:string ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?autofocus:bool ->
  ?autofocus_signal:bool Signal.signal ->
  ?submit_on_enter:bool ->
  ?send_icon:Lui_elements.icon ->
  ?send_label:string ->
  ?send_disabled_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  ?on_input:(string -> unit) ->
  ?on_submit:(unit -> unit) ->
  ?on_send:(unit -> unit) ->
  ?on_press:(unit -> unit) ->
  unit ->
  Lui_elements.t

val composer_attachment :
  ?disabled:bool ->
  ?status:string ->
  key:string ->
  path:string ->
  title:string ->
  file_type:string ->
  on_remove:(unit -> unit) ->
  unit ->
  Lui_elements.t

val composer_collapsed :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?icon:Lui_elements.icon ->
  on_press:(unit -> unit) ->
  unit ->
  Lui_elements.t

val confirm_dialog :
  ?key:string ->
  ?accessibility_identifier:string ->
  title:string ->
  ?message:string ->
  ?cancel_label:string ->
  ?confirm_label:string ->
  ?destructive:bool ->
  ?on_dismiss:(unit -> unit) ->
  ?on_cancel:(unit -> unit) ->
  on_confirm:(unit -> unit) ->
  unit ->
  Lui_elements.t

val settings_row :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?icon:Lui_elements.icon ->
  ?on_press:(unit -> unit) ->
  unit ->
  Lui_elements.t

val labeled_row :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?value:string ->
  ?value_signal:string Signal.signal ->
  unit ->
  Lui_elements.t

val toggle_row :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  on_toggle:(bool -> unit) ->
  unit ->
  Lui_elements.t

val settings_section :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?title:string ->
  rows:Lui_elements.t list ->
  unit ->
  Lui_elements.t

val feedback_banner :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?kind:[ `error | `info ] ->
  ?message:string ->
  ?message_signal:string Signal.signal ->
  unit ->
  Lui_elements.t

val loading :
  ?key:string ->
  ?accessibility_identifier:string ->
  message:string ->
  ?centered:bool ->
  unit ->
  Lui_elements.t

val empty_state :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?icon:Lui_elements.icon ->
  title:string ->
  ?description:string ->
  ?actions:Lui_elements.t list ->
  unit ->
  Lui_elements.t

val section_heading :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?icon:Lui_elements.icon ->
  title:string ->
  unit ->
  Lui_elements.t

type toolbar_item = Lui_element_combine.toolbar_item

val toolbar_item :
  label:string ->
  ?icon:Lui_elements.icon ->
  ?disabled:bool Signal.signal ->
  ?selected:bool ->
  on_press:(unit -> unit) ->
  unit ->
  toolbar_item

val action_toolbar :
  ?key:string ->
  ?accessibility_identifier:string ->
  items:toolbar_item list ->
  unit ->
  Lui_elements.t

val suggestion_list :
  ?key:string ->
  ?accessibility_identifier:string ->
  source:'a list Signal.signal ->
  item_key:('a -> string) ->
  label:('a -> string) ->
  ?icon:('a -> Lui_elements.icon) ->
  on_select:('a -> unit -> unit) ->
  unit ->
  Lui_elements.t

val breadcrumb_trail :
  ?key:string ->
  ?accessibility_identifier:string ->
  items:(string * (unit -> unit)) list ->
  unit ->
  Lui_elements.t

val nav_item :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  label:string ->
  ?label_signal:string Signal.signal ->
  ?icon:Lui_elements.icon ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  on_press:(unit -> unit) ->
  unit ->
  Lui_elements.t

val check_menu_item :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?icon:Lui_elements.icon ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  on_press:(unit -> unit) ->
  unit ->
  Lui_elements.dropdown_menu_item_el

val menu_button :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?icon:Lui_elements.icon ->
  ?anchor:Lui_elements.anchor ->
  open_:bool Signal.signal ->
  menu:Lui_elements.dropdown_menu_item_el list ->
  ?on_dismiss:(unit -> unit) ->
  ?on_press:(unit -> unit) ->
  unit ->
  Lui_elements.t

type sidebar_section = Lui_element_combine.sidebar_section

val sidebar_section :
  title:string -> items:Lui_elements.t list -> unit -> sidebar_section

val sidebar :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?header:Lui_elements.t ->
  ?items:Lui_elements.t list ->
  ?sections:sidebar_section list ->
  unit ->
  Lui_elements.t

val hstack :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?background:color ->
  ?foreground:color ->
  ?border_color:color ->
  ?corner_radius:radius ->
  ?gap:space ->
  ?padding:space ->
  ?cross:Lui_elements.cross_alignment ->
  ?main:Lui_elements.main_alignment ->
  Lui_elements.t list ->
  Lui_elements.t

val vstack :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?background:color ->
  ?foreground:color ->
  ?border_color:color ->
  ?corner_radius:radius ->
  ?gap:space ->
  ?padding:space ->
  ?cross:Lui_elements.cross_alignment ->
  ?main:Lui_elements.main_alignment ->
  Lui_elements.t list ->
  Lui_elements.t

val nav_bar :
  ?key:string ->
  title:string ->
  ?leading:Lui_elements.toolbar_el list ->
  ?trailing:Lui_elements.toolbar_el list ->
  unit ->
  Lui_elements.t

val page :
  ?key:string ->
  ?background:color ->
  ?foreground:color ->
  ?gap:space ->
  ?padding:space ->
  title:string ->
  ?navigation:Lui_elements.t ->
  ?actions:Lui_elements.t list ->
  Lui_elements.t list ->
  Lui_elements.t

val section :
  ?key:string ->
  ?background:color ->
  ?foreground:color ->
  ?border_color:color ->
  ?corner_radius:radius ->
  ?gap:space ->
  ?padding:space ->
  ?title:string ->
  ?footer:string ->
  Lui_elements.t list ->
  Lui_elements.t

(** Wrap an arbitrary view as a native list-section row for {!form_section}
    and {!data_list}. Dynamic combinators ({!Lui_elements.if_},
    {!Lui_elements.keyed}, [reactive]) can wrap {!form_row} or
    {!Lui_elements.list_item} directly so removed rows unmount without leaving
    empty wrapper shells. *)
val form_row : ?key:string -> Lui_elements.t -> Lui_elements.list_section_item_el

val data_row : ?key:string -> Lui_elements.t -> Lui_elements.list_section_item_el

val form_section :
  ?key:string ->
  ?title:string ->
  ?footer:string ->
  Lui_elements.list_section_item_el list ->
  Lui_elements.t

val form_field :
  ?key:string ->
  label:string ->
  ?help:string ->
  ?help_signal:string option Signal.signal ->
  ?error:string ->
  ?error_signal:string option Signal.signal ->
  Lui_elements.t ->
  Lui_elements.t

val data_list :
  ?key:string ->
  label:string ->
  ?empty:Lui_elements.list_section_item_el ->
  Lui_elements.list_section_item_el list ->
  Lui_elements.t

val form_sheet :
  ?key:string ->
  ?accessibility_identifier:string ->
  title:string ->
  ?on_dismiss:(unit -> unit) ->
  ?cancel:string * (unit -> unit) ->
  ?confirm:string * (unit -> unit) ->
  ?confirm_disabled:bool ->
  ?confirm_disabled_signal:bool Signal.signal ->
  Lui_elements.t list ->
  Lui_elements.t

val confirmation :
  ?key:string ->
  ?accessibility_identifier:string ->
  title:string ->
  ?message:string ->
  ?cancel_label:string ->
  ?confirm_label:string ->
  ?destructive:bool ->
  ?on_dismiss:(unit -> unit) ->
  ?on_cancel:(unit -> unit) ->
  on_confirm:(unit -> unit) ->
  unit ->
  Lui_elements.t
