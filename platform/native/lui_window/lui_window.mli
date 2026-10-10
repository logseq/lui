(* SDL window host core: input mapping, hit testing, the deterministic
   layout stub and the per-frame UI state shared by the executable
   driver ([main.ml]) and the test suite.

   This module is pure OCaml: it never touches SDL, GL or the text
   engine, so every function here stays testable on any platform. *)

open Lui_scene

(** Command line configuration for the window driver. *)
type config = {
  width : int;
  height : int;
  headless_frames : int option;
      (** [Some n]: run [n] frames under the dummy video driver and
          exit; [None]: normal interactive loop. *)
}

val default_config : config

(** Parse driver arguments (already stripped of argv\[0\]).
    Recognises [--width N], [--height N], [--headless N]. *)
val parse_args : string list -> (config, string) result

(** Backend-neutral input events. [main.ml] translates SDL events into
    these; [Ui.handle] maps them to LUI protocol events. Coordinates
    are in logical (window) pixels. *)
module Input : sig
  type key =
    | Return
    | Escape
    | Backspace
    | Delete
    | Tab
    | Space
    | Arrow_left
    | Arrow_right
    | Arrow_up
    | Arrow_down
    | Home
    | End
    | Page_up
    | Page_down
    | Other of int  (** SDL keycode for keys without special handling. *)

  type mouse_button =
    | Left
    | Middle
    | Right
    | Other of int

  type mods = {
    ctrl : bool;
    shift : bool;
    alt : bool;
    meta : bool;
  }

  val mods_none : mods

  (** DOM button numbering: 0 primary, 1 middle, 2 secondary. *)
  val button_to_int : mouse_button -> int

  (** Web-compatible bitmask: 1 ctrl, 2 shift, 4 meta. The secondary
      button bit (8) is added by the event builder when applicable. *)
  val mods_to_int : mods -> int

  type t =
    | Move of float * float
    | Button_down of float * float * mouse_button * int * mods
        (** x y button click-count mods *)
    | Button_up of float * float * mouse_button * mods
    | Text_input of string  (** committed text from SDL_TEXTINPUT *)
    | Text_editing of string * int * int
        (** SDL_TEXTEDITING: composition text, selection start,
            selection length — feeds {!Lui_ime}, never dispatched *)
    | Caret of rect
        (** driver-fed caret rect (device px) for candidate-window
            tracking; emitted once per frame while focused *)
    | Key_down of key * mods * bool  (** key, mods, repeat *)
    | Paste of string
        (** clipboard text the driver feeds after a [Paste_request]
            action — clipboard I/O stays outside this pure module *)
    | Resize of int * int  (** new window size, logical pixels *)
    | Wheel of float * float
    | Quit_input

  (** SDL_Scancode integer values → keys (40 return, 41 escape, 42
      backspace, 76 delete, 43 tab, 44 space, 74 home, 75 page-up,
      77 end, 78 page-down, 79-82 arrows). Pure table so the driver
      stays thin and tests need no SDL. *)
  val key_of_sdl_scancode : int -> key

  (** SDL scancode → printable char for host-side typeahead and the
      accelerator table; [~shift] uppercases letters. *)
  val char_of_scancode : ?shift:bool -> int -> char option

  (** SDL_BUTTON_* integer values: 1 left, 2 middle, 3 right. *)
  val button_of_sdl : int -> mouse_button
end

(** Effects the driver performs for [Ui.handle]: dispatch goes to
    [Lui_app.dispatch_event], [Resize_host] triggers [Lui_host.resize]
    from the current drawable size, [Focus_changed] lets the driver
    start/stop SDL text input and place the candidate window,
    [Ime_rect] moves that candidate rect while composing, [Quit]
    ends the loop. *)
type action =
  | Dispatch of Lui_protocol.event
  | Resize_host of int * int
  | Focus_changed of int
  | Ime_rect of rect
      (** SDL_SetTextInputRect target, device px — only emitted while
          a composition is active and the caret moved *)
  | Clipboard_write of string
      (** copy/cut: driver performs SDL_SetClipboardText *)
  | Paste_request
      (** the accelerator for paste fired: driver should read the
          clipboard and feed {!Input.Paste} back into [Ui.handle] *)
  | Quit

(** Per-node device-pixel rectangles produced by [Layout.refresh] and
    consumed by the paint hooks and [hit_path]. *)
module Rects : sig
  type t = (int, rect) Hashtbl.t

  val create : unit -> t
  val get : t -> int -> rect
  val zero : rect
end

val kind_name : Lui_store.t -> int -> string
val kind_of : Lui_store.t -> int -> Lui_protocol.node_kind option

(** [enabled] prop: disabled only when explicitly false; disabled
    nodes emit no events (mirrors the web backend's enabled gate). *)
val node_enabled : Lui_store.t -> int -> bool

(** [pointer-enabled] prop; gates PointerDown/Up/Enter/Leave,
    PressDetail and ContextMenuPress. *)
val pointer_enabled : Lui_store.t -> int -> bool

val bool_prop : Lui_store.t -> int -> string -> bool
val string_prop : Lui_store.t -> int -> string -> string

(** Exact mirror of [Lui_runtime.dispatch]'s admission check: kind +
    the gate properties (press/pointer/change/toggle/appear-enabled,
    role=treeitem) decide whether an event may reach the node. *)
val event_supported :
  Lui_store.t -> int -> Lui_protocol.event -> bool

(** Deepest-first id path from the root to the topmost node whose
    layout rect contains [(x, y)] (device pixels). Skips invisible and
    zero-area nodes. [pointer-enabled] only gates pointer-detail
    events — plain clicks still reach Press-able nodes. *)
val hit_path :
  Lui_store.t -> Rects.t -> x:float -> y:float -> int list

val hit : Lui_store.t -> Rects.t -> x:float -> y:float -> int option

(** Deterministic layout stub. Until a real flex engine lands, this
    stacks children vertically inside their parent's padded content
    box (or horizontally for rows), honours [width]/[height]/[gap]/
    [padding]/[grow] props and uses intrinsic extents for leaf kinds.
    All output is device pixels and fully deterministic. *)
module Layout : sig
  (** Intrinsic content extent of a leaf node in device pixels —
      implemented by the driver over the real text engine. *)
  type measure = Lui_store.t -> int -> scale:float -> float * float

  val default_measure : measure

  (** Logical-pixel fallback extents per kind when no explicit size
      prop is set. *)
  val leaf_extent : Lui_store.t -> int -> scale:float -> float * float

  (** Recompute every rect from the store roots. *)
  val refresh :
    Lui_store.t ->
    Rects.t ->
    width:int ->
    height:int ->
    scale:float ->
    measure:measure ->
    unit
end

(** Per-frame interaction state: hover, press capture, focus and the
    text caret. [handle] is the single entry point that turns
    [Input.t] into [action]s, mirroring the web event wiring. *)
module Ui : sig
  type t

  val create : unit -> t
  val hovered : t -> int
  val pressed : t -> int
  val focused : t -> int
  val caret : t -> int

  (** Editable selection anchor (byte offset into {!shadow}); the
      selection is [min anchor caret .. max anchor caret). *)
  val sel_anchor : t -> int

  (** Static user-select=text selection: [(node, anchor, focus)] byte
      offsets into the node's [text] prop, independent of focus. *)
  val sel_text : t -> (int * int * int) option

  (** Focus arrived via keyboard (Tab) rather than the pointer — the
      distinction behind focus-ring visibility. *)
  val focus_visible : t -> bool

  (** Highlighted list-item for arrow/typeahead navigation. *)
  val hl_item : t -> int

  (** Current typeahead prefix buffer. *)
  val typeahead : t -> string

  (** [(drop-target, payload)] of the last completed drop, if any.
      Host-local: the wire has no drop event. *)
  val last_drop : t -> (int * string) option

  (** A data-attrs drag session is in flight. *)
  val drag_active : t -> bool

  (** Topmost overlay-kind node currently tracked (0 = none). *)
  val overlay_top : t -> int

  (** Driver hooks: glyph measurement for caret/selection math, and
      unshifted (content-space) rects for [scroll_show]/visible-range.
      Deterministic defaults keep tests text-engine free. *)
  val set_measure :
    t -> (Lui_store.t -> int -> string -> float * float) -> unit

  val set_content_rect : t -> (int -> Lui_scene.rect) -> unit

  (** Device-pixel scale; the driver updates it on resize/startup so
      logical input coordinates hit-test against device-pixel rects. *)
  val set_scale : t -> float -> unit

  (** Text as the app sees it: the store prop lags one frame behind
      dispatched edits, so the caret offset is defined against this
      shadow value. *)
  val shadow : t -> string

  (** The composition state machine [handle] feeds — IME editing and
      caret events land here; marked text lives inside it and is
      never dispatched to the app. *)
  val ime : t -> Lui_ime.state

  (** Current marked (preedit) text, ["]"] when not composing. The
      renderer draws it underlined at the caret of the focused node. *)
  val marked : t -> string

  (** [~kbd:true] marks keyboard-driven focus (affects
      {!focus_visible}); the default is pointer/programmatic focus. *)
  val set_focused : ?kbd:bool -> t -> Lui_store.t -> int -> unit

  (** Effects that react to store changes: dead-focus cleanup, modal
      overlay focus save/restore, Appear lifecycle events,
      scroll-target requests and track-visible-range reports. The
      driver runs it after every [Lui_app.flush]; [handle] runs it
      before each input too. *)
  val store_changed : t -> Lui_store.t -> action list

  (** Map one input event to ordered actions. *)
  val handle : t -> Lui_store.t -> Rects.t -> Input.t -> action list

  (** [state_of] hook for the paint pipeline: folds hover/press/focus
      from this Ui plus selected/disabled props. *)
  val state_of : t -> Lui_store.t -> int -> Lui_paint.state

  (** {1 Scroll state}

      Wheel input scrolls the deepest scrollable ancestor under the
      pointer; the driver fills [scroll_cap] from the layout engine's
      content extents each frame and reads [scroll_offset] to shift
      descendants' paint and hit rects. *)

  val scrollable : Lui_store.t -> int -> bool
  (** Whether the node is a scroll container (scroll/list kinds or a
      scrollable [overflow] prop) — the same rule the paint pass uses
      to clip and draw a scrollbar. *)

  val scroll_offset : t -> int -> float
  (** Current scroll offset of the container, device px (0 when it was
      never scrolled). *)

  val scroll_cap : t -> int -> float
  (** Maximum scroll offset of the container, device px. *)

  val set_scroll_cap : t -> int -> float -> unit
  (** Update a container's scrollable range; clamps the live offset
      when the range shrank under it. *)

  (** Programmatic scroll APIs (clamped to the driver-filled caps);
      each returns the actions the move produced — currently
      [VisibleRange] dispatches for tracked containers. *)
  val scroll_to : t -> Lui_store.t -> int -> float -> action list

  val scroll_by : t -> Lui_store.t -> int -> float -> action list

  (** Reveal a node inside its nearest scrollable ancestor (minimal
      reveal — only scrolls when the node is clipped). *)
  val scroll_show : t -> Lui_store.t -> int -> action list

  (** Repaint pacing: true when the store is dirty (wants_repaint) or
      hover/press/focus state changed since the last frame. *)
  val want_frame : t -> Lui_host.t -> bool

  (** Called by the driver after it repainted: resets the per-frame
      dirty flags collected in [handle]. *)
  val frame_done : t -> unit
end

(** Theme color resolution for the paint [color_of] hook. *)
module Theme : sig
  (** Built-in dark palette keyed by theme name. *)
  val palette : (string * color) list

  (** Resolve a theme name to a color. Checks [palette]. *)
  val color_of : string -> color option

  (** Parse ["#rgb"], ["#rrggbb"], ["#rrggbbaa"]. *)
  val color_of_hex : string -> color option
end

(** Deterministic FNV-1a checksum over the ops a frame produces, for
    the headless loop's correctness report. *)
module Checksum : sig
  type t

  val create : unit -> t
  val add_scene : t -> Lui_scene.t -> unit
  val value : t -> int64
end
