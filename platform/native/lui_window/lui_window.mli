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
  drop_files : string list;
      (** [--drop-file PATH] repeat flag: synthetic OS file drops the
          headless driver injects on frame 1 (at the deepest target
          accepting the ["file:"] payload). *)
  windows : int;
      (** [--windows N] (1–8): number of top-level windows the driver
          opens; each is an independent surface. *)
}

val default_config : config

(** Parse driver arguments (already stripped of argv\[0\]).
    Recognises [--width N], [--height N], [--headless N],
    [--drop-file PATH], [--windows N]. *)
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
    | Other of int  (** SDL scancode for keys without special handling. *)

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
        (** dx dy — SDL convention: +y scrolls content up *)
    | Wheel_mods of float * float * mods
        (** wheel deltas with the modifier state at dispatch — Shift
            turns the vertical delta horizontal *)
    | Drop_file of string
        (** OS file drop (SDL_DROPFILE). Lands at the last pointer
            position — SDL drop events carry no coordinates. The
            payload offered to matching drop targets is
            ["file:" ^ path], so [data-drop-accept="file:"] selects
            it. *)
    | Drop_text of string
        (** OS text drop (SDL_DROPTEXT); payload ["text:" ^ s]. *)
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

  (** Win32 virtual-key codes → SDL scancode values. [Other] must
      mean the same thing on every platform — the accelerator table
      matches [Other] against SDL scancodes (A=4, C=6, V=25, X=27,
      Z=29) and typeahead goes through {!char_of_scancode} — so raw
      VK codes (A=0x41) would leave every letter shortcut unreachable
      on Windows. Positional (scancode-style) reading of VKs: the
      same mapping SDL's own Win32 backend applies. *)
  val sdl_scancode_of_win32_vk : int -> int

  (** Win32 virtual-key codes → keys, in the same space
      {!key_of_sdl_scancode} produces: the named keys map to their
      variant, the rest become [Other] of
      {!sdl_scancode_of_win32_vk}. *)
  val key_of_win32_vk : int -> key
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

(** Deterministic layout stub. Stacks children vertically inside
    their parent's padded content box (or horizontally for rows),
    honours [width]/[height]/[gap]/[padding]/[grow] props and uses
    intrinsic extents for leaf kinds. All output is device pixels and
    fully deterministic. Kept for the pure-Ui unit tests — the
    drivers' production path is the real engine wired through
    {!Assembly}. *)
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

  (** Static user-select=text selection, independent of focus:
      [(anchor_node, anchor_off, focus_node, focus_off)] byte offsets
      into each node's [text] prop. A drag or shift-click may extend
      the focus endpoint onto sibling text nodes of the anchor's
      container — the bound of cross-node selection. *)
  val sel_text : t -> (int * int * int * int) option

  (** Focus arrived via keyboard (Tab) rather than the pointer — the
      distinction behind focus-ring visibility. *)
  val focus_visible : t -> bool

  (** Highlighted list-item for arrow/typeahead navigation. *)
  val hl_item : t -> int

  (** Current typeahead prefix buffer. *)
  val typeahead : t -> string

  (** [(drop-target, payload, serial)] of the last completed drop,
      if any. Host-local: the wire has no drop event. The serial
      bumps on every completed drop so the driver notices a repeat
      drop of an identical payload. *)
  val last_drop : t -> (int * string * int) option

  (** A data-attrs drag session is in flight. *)
  val drag_active : t -> bool

  (** Topmost overlay-kind node currently tracked (0 = none). *)
  val overlay_top : t -> int

  val open_menu : t -> int
  (** The trigger-owned menu panel currently open, 0 when none. *)

  val pointer : t -> float * float
  (** Last pointer position in logical px — wire to
      {!Lui_host.set_ctx_anchor} so unanchored context menus open at
      the cursor. *)

  val hidden : t -> Lui_store.t -> int -> bool
  (** Host-owned transient visibility: true for menu panels declared
      under a [menu-trigger] that are not the open one. Wire to
      {!Lui_host.set_hidden} — the predicate reads live state. *)

  (** Driver hooks: glyph measurement for caret/selection math, and
      unshifted (content-space) rects for [scroll_show]/visible-range.
      Deterministic defaults keep tests text-engine free. *)
  val set_measure :
    t -> (Lui_store.t -> int -> string -> float * float) -> unit

  (** Optional layout-accurate text hit-testing: [f store id text
      ~lx ~ly ~lw ~lh] is the byte offset in [text] under the
      device-px point [(lx, ly)] measured from the node's rect origin,
      where [(lw, lh)] is the rect's size. The engine resolves the
      point against the same layout it painted; unset, a
      measure-based fallback keeps tests text-engine free. *)
  val set_hit_text :
    t ->
    (Lui_store.t -> int -> string -> lx:float -> ly:float ->
     lw:float -> lh:float -> int) ->
    unit

  (** The text engine's caret model for one editable string, built
      over the same laid-out text the painter and {!set_hit_text}
      resolve against. [c_before]/[c_after] step byte offsets across
      grapheme clusters (combining marks, emoji ZWJ chains,
      ligatures); [c_up]/[c_down] move across visual — soft-wrapped —
      lines; [c_rect i] is the caret's device-pixel (x, y, h) in node
      content coordinates, for the IME candidate anchor. *)
  type caret_ops = {
    c_before : int -> int;
    c_after : int -> int;
    c_up : int -> int;
    c_down : int -> int;
    c_rect : int -> float * float * float;
  }

  (** Optional layout-accurate caret model: [f store id text ~lw ~lh]
      builds the {!caret_ops} for [text] inside a node rect of size
      [(lw, lh)] device px. Keyboard and delete paths consult it so
      they move like the mouse does; unset, codepoint and paragraph
      fallbacks keep tests text-engine free. *)
  val set_caret_ops :
    t ->
    (Lui_store.t -> int -> string -> lw:float -> lh:float ->
     caret_ops) ->
    unit

  val set_content_rect : t -> (int -> Lui_scene.rect) -> unit

  (** Tell the Ui that layout rects were recomputed (the driver's
      populate/refresh pass). Bumps the internal layout epoch that
      visible-range memoization keys on — call it wherever the rects
      feeding [content_rect] are rebuilt. *)
  val notify_layout : t -> unit

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

  (** Scroll axes: [Y] is the vertical path, [X] the horizontal one
      (wheel-x / shift+wheel deltas, horizontal reveal). *)
  type axis = X | Y

  val scroll_offset : t -> int -> float
  (** Current vertical scroll offset of the container, device px
      (0 when it was never scrolled). *)

  val scroll_epoch : t -> int
  (** Monotonic counter bumped whenever any scroll offset changes —
      drivers can memoize ancestor-offset sums against it. *)

  val scroll_cap : t -> int -> float
  (** Maximum vertical scroll offset of the container, device px. *)

  val set_scroll_cap : t -> int -> float -> unit
  (** Update a container's vertical scrollable range; clamps the live
      offset when the range shrank under it. *)

  val scroll_offset_x : t -> int -> float
  (** Horizontal counterparts of {!scroll_offset}/{!scroll_cap}/
      {!set_scroll_cap}. *)

  val scroll_cap_x : t -> int -> float

  val set_scroll_cap_x : t -> int -> float -> unit

  (** Programmatic scroll APIs (clamped to the driver-filled caps);
      each returns the actions the move produced — currently
      [VisibleRange] dispatches for tracked containers (y-axis
      moves only). *)
  val scroll_to :
    ?axis:axis -> t -> Lui_store.t -> int -> float -> action list

  val scroll_by :
    ?axis:axis -> t -> Lui_store.t -> int -> float -> action list

  (** Whether the node's drop-target attrs accept [payload]
      (data-drop-target + comma-separated data-drop-accept prefixes).
      OS drops offer namespaced payloads: ["file:" ^ path] and
      ["text:" ^ s]. *)
  val drop_accepts : Lui_store.t -> int -> string -> bool

  (** Reveal a node inside its nearest scrollable ancestor (minimal
      reveal on both axes — only scrolls when the node is clipped). *)
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

(** Multi-window manager: a registry of independent surfaces.

    Each surface owns a full pipeline — {!Lui_host} (store, layout,
    scene, renderer), per-window interaction state ({!Ui.t}) and the
    hit-test mirror — so windows never share app state and every
    window can render an independent view. The driver payload ['d]
    keeps this layer backend-free: the SDL driver stores its OS
    window handle/context there, tests store [unit].

    Window-model decision: N independent surfaces, not one store
    rendered into several windows and not a wire-level window node.
    The wire protocol has no window kind (adding one would change
    shared modules); {!Lui_host} fuses store+layout+scene per
    surface, so independent hosts need zero core changes, give
    per-window checksums/a11y for free, and close cleanly one at a
    time. Cost: windows cannot show live views of one model — for a
    desktop backend each window owning its app instance is the
    intended semantic. *)
module Multi : sig
  type 'd surface = {
    mutable id : int;
        (** Registry key; the SDL driver uses [SDL_GetWindowID].
            Mutable because a backend demote recreates the OS window,
            which mints a fresh id — see [rekey]. *)
    host : Lui_host.t;
    ui : Ui.t;
    rects : Rects.t;
    driver : 'd;
    mutable logical_w : int;
        (** Window size in logical units, from resize events. *)
    mutable logical_h : int;
    mutable drawable_w : int;
        (** Backing pixels last applied. *)
    mutable drawable_h : int;
    scale_cell : float ref;
        (** Backing scale drawable/logical. Kept as a ref so the
            hooks and text engine created before the surface can
            share it. *)
    mutable display : int;
        (** Display index last seen (-1 unknown); the driver updates
            it to detect monitor crossings. *)
  }

  type 'd t
  (** Registry of surfaces, iterated in registration order. *)

  val create : unit -> 'd t

  val make_surface :
    id:int -> host:Lui_host.t -> driver:'d -> ui:Ui.t ->
    rects:Rects.t -> scale_cell:float ref -> w:int -> h:int ->
    'd surface
  (** [ui], [rects] and [scale_cell] come from the caller rather than
      being allocated here because a window's paint hooks and text
      engine must capture them before the host — and therefore the
      surface — exists. The initial drawable is [w, h] × [!scale_cell]. *)

  val register : 'd t -> 'd surface -> unit
  val unregister : 'd t -> int -> 'd surface option
  (** [unregister] also clears focus if the removed window had it. *)

  val rekey : 'd t -> int -> int -> bool
  (** [rekey t old_id new_id] moves a surface's registry key — used
      when the driver recreates the OS window under a new id
      (renderer demote). Keeps registration order and the focused
      window. Returns [false] when [old_id] is unknown. *)

  val find : 'd t -> int -> 'd surface option
  val count : 'd t -> int
  val iter : 'd t -> ('d surface -> unit) -> unit
  (** Deterministic registration-order iteration. *)

  val focused : 'd t -> int
  (** Window id last reported focused; 0 = none. *)

  val set_focused : 'd t -> int -> unit

  val clear_focus : 'd t -> unit

  val find_focused : 'd t -> 'd surface option
  (** The focused surface, or the first registered when focus is
      unset (e.g. headless, where no focus events arrive). *)

  val first : 'd t -> 'd surface option
  val last : 'd t -> 'd surface option
  (** First / last registered in registration order. *)

  val any : 'd t -> ('d surface -> bool) -> bool
  (** [any t p]: some registered surface satisfies [p]. *)

  val dispatch : 'd surface -> Input.t -> action list
  (** Feed an input event through one window's [Ui.handle]. Event
      routing by OS window id happens in the driver; this is the
      per-window half of it. *)

  val drawable_scale : int -> int -> float
  (** [drawable_scale dw w]: backing scale from drawable and logical
      widths, clamped to ≥ 0.01. *)

  val apply_logical_size : 'd surface -> w:int -> h:int -> unit
  (** Record a logical (window-pixel) resize reported by the window
      system. *)

  val apply_drawable : 'd surface -> dw:int -> dh:int -> bool
  (** Apply a new drawable size: recompute the backing scale, push it
      into [Ui] and resize the host (marks the surface dirty so the
      next frame re-lays out). Returns [true] when something actually
      changed — the driver uses this for display-hotplug and
      monitor-crossing re-queries, where most calls are no-ops. *)

  val scale : 'd surface -> float
end

(** Shared native host assembly: the wiring every window driver used
    to hand-roll — the layout engine synced per repaint, the paint
    hooks (theme colors, scroll metrics, IME marked-text overlay,
    shadows), trigger-menu visibility, the pointer-anchored context
    menu, the scroll-offset-shifted hit-test mirror, the scroll caps
    that let wheel input find a target, and the IME caret anchor.
    Platform drivers keep only OS event translation, window
    management and frame presentation; everything else lives here so
    every platform paints and hit-tests identically. *)
module Assembly : sig
  (** The platform text engine reduced to the three callbacks the
      shared wiring needs: glyph measure for layout/caret math,
      glyph-run emission for the paint hook, and layout-accurate
      point hit resolution for caret/selection. Each driver's
      [Lui_window_text] satisfies this directly. *)
  type text = {
    measure : int -> string -> float * float;
    text_ops : int -> rect -> color -> string -> op list;
    hit_text :
      int -> string -> lx:float -> ly:float -> lw:float -> lh:float ->
      int;
    caret_ops :
      int -> string -> lw:float -> lh:float -> Ui.caret_ops;
        (** Keyboard caret geometry over the same laid-out text
            (grapheme moves, visual lines, caret rect). *)
  }

  type t

  val create :
    ?layout:(module Lui_host.LAYOUT_ENGINE) ->
    scale_cell:float ref ->
    text:text ->
    renderer:Lui_host.renderer ->
    width:int -> height:int -> unit -> t
  (** [create ~scale_cell ~text ~renderer ~width ~height ()] builds
      one surface's shared pipeline: interaction {!Ui.t}, paint
      hooks, {!Lui_host} (store + scene + renderer), and the
      engine-driven hit-test mirror.

      Pass [~layout:(module Lui_layout)] — the production engine.
      The engine must be supplied as a module (not created inside)
      so the assembly stays decoupled from any concrete engine, the
      same contract {!Lui_host.create} declares.

      [~scale_cell] is a caller-owned ref: the text engine the driver
      builds must read the same cell, and the driver mutates it on
      drawable resizes (macOS via {!Multi.apply_drawable}); the hooks
      and [Ui] read it live. [width]/[height] are the initial
      drawable size in device px.

      Side effects wired at create: [Lui_host.set_hidden] (menu
      panels hidden until opened), [Lui_host.set_ctx_anchor]
      (unanchored context-menus open at the pointer), the [Ui]
      measure/hit-text/content-rect hooks, and the engine's text
      [measure] (glyph metric + painted padding — feeding raw
      extents collapses labeled controls to bare-text size). *)

  val host : t -> Lui_host.t
  val ui : t -> Ui.t
  val rects : t -> Rects.t
  (** The hit-test mirror {!Ui.handle} wants: resolved, scroll-
      shifted and ancestor-clipped rects, refreshed by {!repaint}. *)

  val scale_cell : t -> float ref
  val engine_rect : t -> int -> rect
  (** Unshifted engine rect — content-space input for
      [scroll_show]/visible-range reports. *)

  val store : t -> Lui_store.t
  val handle : t -> Input.t -> action list
  (** {!Ui.handle} over this surface's [ui], [store] and hit mirror —
      the single input entry point, identical on every platform. *)

  val store_changed : t -> action list
  (** {!Ui.store_changed} over this surface — run it after every
      [Lui_app.flush]. *)

  val populate : t -> unit
  (** Rebuild the hit mirror and the scroll caps from the last layout
      sync. {!repaint} already calls it; expose only for drivers that
      keep paint and hit-refresh on separate schedules. *)

  val repaint : t -> Bytes.t
  (** One frame's paint path: [Lui_host.repaint] (which re-syncs the
      engine) then {!populate} — always in this order, on every
      platform. *)

  val caret_rect : t -> rect
  (** Focused field's caret rect, device px — the IME candidate-window
      anchor; feed it back as {!Input.Caret} once per frame while
      focused. *)

  val backend : t -> Lui_protocol.platform_profile -> Lui_protocol.backend
  val first_autofocus : t -> int option
  (** First node carrying [autofocus] in preorder — the field the
      driver hands focus to at startup. *)
end
