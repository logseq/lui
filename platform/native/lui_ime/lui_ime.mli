(* IME (input method editor) composition state machine for the native
   backend.

   Pure OCaml and display-free: the window driver feeds SDL text-input
   events in and performs the returned actions — dispatching committed
   text through the app's normal input path, rendering marked text, and
   moving the candidate window rect. The machine itself never touches
   Lui_app, SDL or the scene.

   Composition lifecycle:
   - [`Editing (text, start, len)] updates the marked (preedit) text.
     The first non-empty editing begins a composition; empty editing
     clears the displayed marked text but keeps the session open —
     the IME may still be composing and only it knows when it is done.
     Marked text is reported to the view only; it is never committed.
   - [`Commit text] ends the composition and emits [`Commit_text]: the
     driver splices it into the focused field through the same path
     plain keyboard input uses. Commits with no active composition
     pass straight through (uncomposed input such as plain ASCII).
     An empty commit while composing is treated as a cancellation.
   - [`Focus false] cancels any in-flight composition first; the
     driver clears marked text and stops SDL text input afterwards.
   - [`Caret r] records the focused field's caret rect (device px,
     computed by the caller from the node's layout rect plus the
     caret offset — the node rect itself is the default). While a
     composition is active, changes emit [`Move_candidate r] so the
     driver can call SDL_SetTextInputRect; while idle the rect is
     only remembered so a later composition starts positioned.

   Key events are not fed here: while {!composing} holds (marked text
   non-empty) the driver suppresses key-driven edits — they belong to
   the IME. SDL already filters most of them; the flag is a belt. *)

(** {2 State} *)

type state = {
  active : bool;      (** a composition session is open *)
  marked_text : string; (** current marked (preedit) text, UTF-8 *)
  cursor : int;       (** composition selection start, as reported *)
  sel_len : int;      (** composition selection length, as reported *)
  caret_rect : Lui_scene.rect option;
      (** last caret rect the caller supplied (device px) *)
}

val initial : state

(** True while marked text is non-empty — the flag the window driver
    consults to gate key-driven edits during a composition. *)
val composing : state -> bool

(** {2 Events and actions} *)

type input =
  [ `Editing of string * int * int
      (** composition text, selection start, selection length *)
  | `Commit of string  (** committed (final) text *)
  | `Focus of bool     (** keyboard focus gained/lost on the field *)
  | `Caret of Lui_scene.rect  (** caret rect, device px *) ]

type action =
  [ `Begin_composition  (** a composition opened *)
  | `Update_composition of string * int
      (** marked text changed: full string + cursor (selection start) *)
  | `Commit_text of string  (** commit through the normal text path *)
  | `Cancel               (** composition cancelled, clear marked text *)
  | `Move_candidate of Lui_scene.rect
      (** reposition the candidate window (device px) *) ]

val feed_event : state -> input -> state * action list
(** Consume one event; returns the next state and the ordered actions
    for the driver to perform. *)

val string_of_action : action -> string
(** Compact rendering for logs and test failures. *)
