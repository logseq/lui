(** Generic composite elements assembled purely from {!Lui_elements}
    primitives.

    Each composite fixes its own layout, padding, colour tokens and
    typography so hosts render it with the platform-native idiom — callers
    supply content and behaviour (labels, icons, callbacks, signals) but no
    fine-grained style parameters. *)

open Lui_elements

(** {1 Composer} *)

(** Message/capture input capsule: optional horizontal attachment strip,
    a growing [composer-input] textarea, and a controls row of caller
    actions followed by an optional send button. *)
val composer :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?attachments:t ->
  ?actions:t list ->
  placeholder:string ->
  ?text:string ->
  ?text_signal:string Signal.signal ->
  ?autofocus:bool ->
  ?submit_on_enter:bool ->
  ?send_disabled:bool Signal.signal ->
  ?on_input:(Lui_protocol.event -> unit) ->
  ?on_submit:(Lui_protocol.event -> unit) ->
  ?on_send:(Lui_protocol.event -> unit) ->
  unit -> t

(** Collapsed form of the composer: a capsule button the host expands back
    into the full {!composer}. *)
val composer_collapsed :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  icon:icon ->
  on_press:(Lui_protocol.event -> unit) ->
  unit -> t

(** {1 Dialogs and sheets} *)

(** Destructive-or-primary confirmation dialog: title, optional message
    (rendered as the native alert description), a Cancel button (default
    label "Cancel") and a confirm button (default label "Confirm";
    [~destructive] picks the destructive variant). Buttons are direct
    children so hosts render the native alert when supported. *)
val confirm_dialog :
  ?key:string ->
  ?accessibility_identifier:string ->
  title:string ->
  ?message:string ->
  ?cancel_label:string ->
  ?confirm_label:string ->
  ?destructive:bool ->
  ?on_dismiss:(Lui_protocol.event -> unit) ->
  ?on_cancel:(Lui_protocol.event -> unit) ->
  on_confirm:(Lui_protocol.event -> unit) ->
  unit -> t

(** Modal form sheet: a [navigation-form] sheet wrapping a [form] column
    of [content], plus a navigation-actions toolbar when [cancel] and/or
    [confirm] [(label, handler)] pairs are supplied. [confirm_disabled]
    greys out the confirm action. *)
val form_sheet :
  ?key:string ->
  ?accessibility_identifier:string ->
  title:string ->
  ?on_dismiss:(Lui_protocol.event -> unit) ->
  content:t list ->
  ?cancel:string * (Lui_protocol.event -> unit) ->
  ?confirm:string * (Lui_protocol.event -> unit) ->
  ?confirm_disabled:bool Signal.signal ->
  unit -> t

(** {1 Settings} *)

(** Tappable settings row. *)
val settings_row :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?icon:icon ->
  ?on_press:(Lui_protocol.event -> unit) ->
  unit -> t

(** Label + trailing value row (e.g. sync status). *)
val labeled_row :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?value:string ->
  ?value_signal:string Signal.signal ->
  unit -> t

(** Switch row bound to [checked]/[checked_signal]. *)
val toggle_row :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  on_toggle:(Lui_protocol.event -> unit) ->
  unit -> t

(** Rounded card grouping [rows] with separators between them and an
    optional muted heading above. *)
val settings_section :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?title:string ->
  rows:t list ->
  unit -> t

(** {1 Feedback} *)

(** Inline banner: alert surface with a leading icon and message text.
    [kind] is [`error] (destructive, warning glyph) or [`info]. *)
val feedback_banner :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?kind:[ `error | `info ] ->
  ?message:string ->
  ?message_signal:string Signal.signal ->
  unit -> t

(** Spinner + muted message; [centered] expands to a fill-centred column
    (full-page loading) instead of an inline row. *)
val loading :
  ?key:string ->
  ?accessibility_identifier:string ->
  message:string ->
  ?centered:bool ->
  unit -> t

(** Centred empty-state: optional icon, title, optional muted description
    and optional action buttons. *)
val empty_state :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?icon:icon ->
  title:string ->
  ?description:string ->
  ?actions:t list ->
  unit -> t

(** {1 Headings and toolbars} *)

(** Muted caption heading row with optional leading icon, used to title a
    list section. *)
val section_heading :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?icon:icon ->
  title:string ->
  unit -> t

type toolbar_item

(** One entry of {!action_toolbar}: ghost icon-over-label button. *)
val toolbar_item :
  label:string ->
  ?icon:icon ->
  ?disabled:bool Signal.signal ->
  ?selected:bool ->
  on_press:(Lui_protocol.event -> unit) ->
  unit -> toolbar_item

(** Floating capsule bar of evenly-spaced icon buttons (selection or
    editing actions). *)
val action_toolbar :
  ?key:string ->
  ?accessibility_identifier:string ->
  items:toolbar_item list ->
  unit -> t

(** {1 Suggestion list} *)

(** Scrollable autocomplete-style list: a keyed column of full-width
    ghost buttons, bounded in height. [source] supplies the candidate
    items; [item_key] identifies them for reconciliation, [label] renders the
    caption, optional [icon] renders a reactive per-item glyph,
    [on_select] receives the selected item. *)
val suggestion_list :
  ?key:string ->
  ?accessibility_identifier:string ->
  source:'a list Signal.signal ->
  item_key:('a -> string) ->
  label:('a -> string) ->
  ?icon:('a -> icon) ->
  on_select:('a -> Lui_protocol.event -> unit) ->
  unit -> t

(** {1 Breadcrumbs} *)

(** Breadcrumb trail of ghost caption buttons from [(label, on_press)]
    pairs, first to last. *)
val breadcrumb_trail :
  ?key:string ->
  ?accessibility_identifier:string ->
  items:(string * (Lui_protocol.event -> unit)) list ->
  unit -> t

(** {1 Sidebar} *)

(** Navigation-semantic list row for a sidebar/page list. *)
val nav_item :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?accessibility_identifier_signal:string Signal.signal ->
  label:string ->
  ?label_signal:string Signal.signal ->
  ?icon:icon ->
  ?selected:bool ->
  ?selected_signal:bool Signal.signal ->
  on_press:(Lui_protocol.event -> unit) ->
  unit -> t

(** Menu entry that renders a checkmark while [checked]/[checked_signal]
    is true (selectable-option rows). *)
val check_menu_item :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?icon:icon ->
  ?checked:bool ->
  ?checked_signal:bool Signal.signal ->
  ?disabled:bool ->
  ?disabled_signal:bool Signal.signal ->
  on_press:(Lui_protocol.event -> unit) ->
  unit -> t

(** Label + trailing chevron button that opens [menu] (a list of
    {!menu_item}/{!check_menu_item}/{!submenu} children) as an anchored
    dropdown menu. The menu is a stack sibling gated by [open_], matching
    the wire contract (menus may not nest under [button]); drive [open_]
    from your model and clear it in [on_dismiss]. *)
val menu_button :
  ?key:string ->
  ?accessibility_identifier:string ->
  label:string ->
  ?icon:icon ->
  ?anchor:anchor ->
  open_:bool Signal.signal ->
  menu:t list ->
  ?on_dismiss:(Lui_protocol.event -> unit) ->
  ?on_press:(Lui_protocol.event -> unit) ->
  unit -> t

type sidebar_section

(** A titled group of sidebar rows rendered under a {!section_heading}. *)
val sidebar_section : title:string -> items:t list -> unit -> sidebar_section

(** Sidebar skeleton: optional [header] (e.g. a {!menu_button} switcher),
    flat navigation [items], then a scrollable stack of [sections]. *)
val sidebar :
  ?key:string ->
  ?accessibility_identifier:string ->
  ?header:t ->
  ?items:t list ->
  ?sections:sidebar_section list ->
  unit -> t
