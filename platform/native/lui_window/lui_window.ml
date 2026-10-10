(* Pure-OCaml core of the SDL window host: CLI parsing, backend-neutral
   input events, protocol event mapping with the same admission rules
   [Lui_runtime.dispatch] applies, rect hit testing, a deterministic
   layout stub, per-frame interaction state, the dark theme palette
   and the headless-loop checksum. SDL/GL/text-engine free so every
   piece is unit-testable. *)

open Lui_scene
open Lui_protocol

type config = {
  width : int;
  height : int;
  headless_frames : int option;
}

let default_config = { width = 960; height = 640; headless_frames = None }

let parse_args argv =
  let rec loop cfg = function
    | "--width" :: v :: tl ->
      (match int_of_string_opt v with
       | Some n when n > 0 -> loop { cfg with width = n } tl
       | _ -> Error ("invalid --width " ^ v))
    | "--height" :: v :: tl ->
      (match int_of_string_opt v with
       | Some n when n > 0 -> loop { cfg with height = n } tl
       | _ -> Error ("invalid --height " ^ v))
    | "--headless" :: v :: tl ->
      (match int_of_string_opt v with
       | Some n when n > 0 -> loop { cfg with headless_frames = Some n } tl
       | _ -> Error ("invalid --headless " ^ v))
    | ("--width" | "--height" | "--headless") :: [] ->
      Error "missing value for flag"
    | arg :: _ -> Error ("unknown argument " ^ arg)
    | [] -> Ok cfg
  in
  loop default_config argv

module Input = struct
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
    | Other of int

  type mouse_button =
    | Left
    | Middle
    | Right
    | Other of int

  let button_to_int = function
    | Left -> 0
    | Middle -> 1
    | Right -> 2
    | Other n -> n

  type mods = {
    ctrl : bool;
    shift : bool;
    alt : bool;
    meta : bool;
  }

  let mods_none = { ctrl = false; shift = false; alt = false; meta = false }

  (* Same bitmask the web backend emits: 1 ctrl, 2 shift, 4 meta. The
     secondary-button bit 8 is set by the detail builder on right
     clicks, matching press_detail's modifiers field. *)
  let mods_to_int m =
    (if m.ctrl then 1 else 0)
    lor (if m.shift then 2 else 0)
    lor (if m.meta then 4 else 0)

  type t =
    | Move of float * float
    | Button_down of float * float * mouse_button * int * mods
    | Button_up of float * float * mouse_button * mods
    | Text_input of string
    | Text_editing of string * int * int
    | Caret of rect
    | Key_down of key * mods * bool
    | Paste of string
        (** clipboard text the driver hands to [Ui.handle] after a
            [Paste_request] action — keeps clipboard I/O out of this
            pure module *)
    | Resize of int * int
    | Wheel of float * float
    | Quit_input

  (* SDL_Scancode integer constants, kept in this module (not the
     driver) so the table is unit-testable without SDL linked. *)
  let key_of_sdl_scancode = function
    | 40 | 88 -> Return (* return, keypad-enter *)
    | 41 -> Escape
    | 42 -> Backspace
    | 76 -> Delete
    | 43 -> Tab
    | 44 -> Space
    | 74 -> Home
    | 75 -> Page_up
    | 77 -> End
    | 78 -> Page_down
    | 80 -> Arrow_left
    | 79 -> Arrow_right
    | 81 -> Arrow_down
    | 82 -> Arrow_up
    | n -> Other n

  (* Inverse of the letter/digit half of the table above — used by
     host-side typeahead and the accelerator table, which match on
     characters rather than named keys. *)
  let char_of_scancode ?(shift = false) = function
    | n when n >= 4 && n <= 29 ->
      let c = Char.chr (Char.code 'a' + n - 4) in
      Some (if shift then Char.uppercase_ascii c else c)
    | n when n >= 30 && n <= 38 ->
      Some (Char.chr (Char.code '1' + n - 30))
    | 39 -> Some '0'
    | _ -> None

  (* SDL_BUTTON_* integer constants: 1 left, 2 middle, 3 right. *)
  let button_of_sdl = function
    | 1 -> Left
    | 2 -> Middle
    | 3 -> Right
    | n -> Other n
end

type action =
  | Dispatch of Lui_protocol.event
  | Resize_host of int * int
  | Focus_changed of int
  | Ime_rect of rect
  | Clipboard_write of string
  | Paste_request
  | Quit

module Rects = struct
  type t = (int, rect) Hashtbl.t

  let create () = Hashtbl.create 128
  let zero = rect 0. 0. 0. 0.
  let get t id = match Hashtbl.find_opt t id with Some r -> r | None -> zero
end

let kind_name store id = Lui_store.kind store id

let kind_table =
  let t = Hashtbl.create 97 in
  List.iter
    (fun k -> Hashtbl.replace t (Lui_wire_schema.node_kind_name k) k)
    Lui_wire_schema.all_node_kinds;
  t

let kind_of store id = Hashtbl.find_opt kind_table (Lui_store.kind store id)

(* Enabled unless the prop explicitly says otherwise — mirrors the
   paint pipeline's disabled fold (BoolValue false or "false"). *)
let node_enabled store id =
  match Lui_store.prop store id "enabled" with
  | Some (BoolValue false) -> false
  | Some (StringValue "false") -> false
  | _ -> true

let pointer_enabled store id = Lui_store.bool_prop store id "pointer-enabled"

let bool_prop store id name = Lui_store.bool_prop store id name

let string_prop store id name =
  match Lui_store.string_prop store id name with
  | Some s -> s
  | None -> ""

(* The only properties dispatch admission consults. *)
let gate_properties =
  [ AppearEnabled; PressEnabled; PointerEnabled; ChangeEnabled;
    ToggleEnabled; RoleValue ]

let event_supported store id event =
  match kind_of store id with
  | None -> false
  | Some kind ->
    let props =
      List.fold_left
        (fun acc p ->
           match Lui_store.prop store id (Lui_wire_schema.property_name p) with
           | Some v -> Property_map.add p v acc
           | None -> acc)
        Property_map.empty gate_properties
    in
    Lui_protocol.event_supported_for_properties kind props event

let hit_path store rects ~x ~y =
  let visible id =
    match Lui_store.prop store id "visible" with
    | Some (BoolValue false) -> false
    | _ -> true
  in
  let rec walk id path =
    if not (visible id) then path
    else
      let path =
        let r = Rects.get rects id in
        if not (rect_empty r) && rect_contains r x y then id :: path else path
      in
      (* Children paint after their parent, so prepending while walking
         leaves the node visited last — visually topmost — at the head. *)
      List.fold_left
        (fun acc c -> walk c acc)
        path (Lui_store.child_ids store id)
  in
  (* The head is the node visited last in paint order: visually
     topmost. *)
  List.fold_left
    (fun acc id -> walk id acc)
    [] (Lui_store.root_ids store)

let hit store rects ~x ~y =
  match hit_path store rects ~x ~y with
  | id :: _ -> Some id
  | [] -> None

module Layout = struct
  type measure = Lui_store.t -> int -> scale:float -> float * float

  let default_measure _store _id ~scale:_ = (0., 0.)

  (* Props arrive as IntValue for frame props (see apply_universal);
     accept FloatValue and "Npx"-style strings too. *)
  let parse_len s =
    let n = String.length s in
    let stop =
      let rec find i =
        if i >= n then n
        else
          match s.[i] with
          | '0' .. '9' | '.' | '-' | '+' -> find (i + 1)
          | _ -> i
      in
      find 0
    in
    if stop = 0 then None
    else
      try Some (float_of_string (String.sub s 0 stop))
      with _ -> None

  let len_prop store id name ~scale =
    match Lui_store.prop store id name with
    | Some (FloatValue f) -> Some (f *. scale)
    | Some (IntValue i) -> Some (float i *. scale)
    | Some (StringValue s) ->
      Option.map (fun v -> v *. scale) (parse_len s)
    | _ -> None

  type axis = Vertical | Horizontal

  let direction store id =
    match Lui_store.kind store id with
    | "row" -> Horizontal
    | _ -> Vertical

  let pad_axis store id ~scale axis =
    let uniform =
      Option.value ~default:0. (len_prop store id "padding" ~scale)
    in
    let name =
      match axis with
      | Vertical -> "padding-vertical"
      | Horizontal -> "padding-horizontal"
    in
    Option.value ~default:uniform (len_prop store id name ~scale)

  let gap_px store id ~scale =
    Option.value ~default:0. (len_prop store id "gap" ~scale)

  let grow_weight store id =
    match Lui_store.float_prop store id "grow" with
    | Some w when w > 0. -> w
    | _ ->
      (* A bare spacer always absorbs free space. *)
      if Lui_store.kind store id = "spacer" then 1. else 0.

  (* Logical-pixel default leaf heights; width defaults to "fill". *)
  let leaf_height = function
    | "button" | "toggle-button" | "text-field" | "secure-field"
    | "input" | "search-field" -> 32.
    | "textarea" -> 64.
    | "divider" -> 1.
    | "progress" -> 6.
    | "checkbox" | "switch" | "radio" -> 22.
    | "slider" | "number-stepper" -> 24.
    | "image" | "file-image" -> 64.
    | "spacer" -> 8.
    | "icon" -> 20.
    | _ -> 24.

  let leaf_extent store id ~scale =
    (0., leaf_height (Lui_store.kind store id) *. scale)

  let rec natural_main store measure scale dir id =
    let prop_name =
      match dir with Vertical -> "height" | Horizontal -> "width"
    in
    match len_prop store id prop_name ~scale with
    | Some v -> v
    | None ->
      (match Lui_store.child_ids store id with
       | [] ->
         (* Leaf: ask the text engine first, fall back to the table. *)
         let mw, mh = measure store id ~scale in
         let dw, dh = leaf_extent store id ~scale in
         (match dir with
          | Vertical -> if mh > 0. then mh else dh
          | Horizontal -> if mw > 0. then mw else max dw 24.)
       | children ->
         let pm = 2. *. pad_axis store id ~scale dir in
         let gap = gap_px store id ~scale in
         let n = List.length children in
         let sum =
           List.fold_left
             (fun acc c -> acc +. natural_main store measure scale dir c)
             0. children
         in
         pm +. sum +. gap *. float (max 0 (n - 1)))

  let cross_extent store id ~scale dir avail =
    let name =
      match dir with Vertical -> "width" | Horizontal -> "height"
    in
    match len_prop store id name ~scale with
    | Some v -> min v avail
    | None -> avail

  let rec layout_node store measure scale rects id (r : rect) =
    Hashtbl.replace rects id r;
    match Lui_store.child_ids store id with
    | [] -> ()
    | children ->
      let dir = direction store id in
      let gap = gap_px store id ~scale in
      let pm = pad_axis store id ~scale dir in
      let pc =
        pad_axis store id ~scale
          (match dir with Vertical -> Horizontal | Horizontal -> Vertical)
      in
      let cx, cy, cw, ch =
        match dir with
        | Vertical ->
          ( r.x +. pc, r.y +. pm,
            max 0. (r.w -. (2. *. pc)), max 0. (r.h -. (2. *. pm)) )
        | Horizontal ->
          ( r.x +. pm, r.y +. pc,
            max 0. (r.w -. (2. *. pm)), max 0. (r.h -. (2. *. pc)) )
      in
      let n = List.length children in
      let entries =
        List.map
          (fun c ->
             let w = grow_weight store c in
             ( c, w,
               if w > 0. then 0.
               else natural_main store measure scale dir c ))
          children
      in
      let fixed =
        List.fold_left (fun a (_, _, s) -> a +. s) 0. entries
      in
      let grow_total =
        List.fold_left (fun a (_, w, _) -> a +. w) 0. entries
      in
      let main = match dir with Vertical -> ch | Horizontal -> cw in
      let leftover =
        max 0. (main -. fixed -. (gap *. float (max 0 (n - 1))))
      in
      let start = match dir with Vertical -> cy | Horizontal -> cx in
      ignore
        (List.fold_left
           (fun pos (c, w, s) ->
              let m =
                if w > 0. && grow_total > 0. then
                  leftover *. w /. grow_total
                else s
              in
              let child_r =
                match dir with
                | Vertical ->
                  rect cx pos (cross_extent store c ~scale dir cw) m
                | Horizontal ->
                  rect pos cy m (cross_extent store c ~scale dir ch)
              in
              layout_node store measure scale rects c child_r;
              pos +. m +. gap)
           start entries)

  let refresh store rects ~width ~height ~scale ~measure =
    Hashtbl.reset rects;
    let w = float width *. scale and h = float height *. scale in
    List.iter
      (fun id -> layout_node store measure scale rects id (rect 0. 0. w h))
      (Lui_store.root_ids store)
end

module Ui = struct
  type t = {
    mutable scale : float;
    mutable hovered : int;
    mutable hover_detail : int;
    mutable pressed : int;
    mutable press_detail : int;
    mutable focused : int;
    mutable caret : int;
    (* Latest text value as the app sees it: the store prop lags one
       frame behind the events we dispatch, so rapid edits splice onto
       this shadow instead of the stale prop. *)
    mutable shadow : string;
    (* IME composition state machine: SDL text-editing/commit events
       feed it; marked text rides here (never dispatched) until the
       commit lands through the normal input path. *)
    mutable ime : Lui_ime.state;
    mutable dirty : bool;
    (* Scroll: offset and max offset (device px) per scroll container
       id. The driver computes caps from the layout engine's content
       extents each frame; wheel deltas scroll the deepest scrollable
       ancestor under the pointer. *)
    scroll_off : (int, float) Hashtbl.t;
    scroll_cap : (int, float) Hashtbl.t;
    (* Last pointer position in logical px — the wheel's implicit
       target since SDL mouse-wheel events carry no coordinates. *)
    mutable last_x : float;
    mutable last_y : float;
    (* Editable selection: byte offsets into [shadow]; [anchor = caret]
       is the collapsed caret. Static user-select=text nodes keep a
       node-local selection so they never steal field focus. *)
    mutable sel_anchor : int;
    mutable sel_text : (int * int * int) option;
    (* Keyboard-driven focus (Tab) vs pointer-driven — the ring state
       paints via the existing focus-shadow channel. *)
    mutable focus_visible : bool;
    (* Host-side undo/redo for shadow edits; reset on focus change.
       Entries are (shadow, caret, anchor) snapshots. *)
    mutable undo : (string * int * int) list;
    mutable redo : (string * int * int) list;
    (* List interaction: the scroll container that owns the highlight,
       the highlighted list-item, and the typeahead prefix buffer. *)
    mutable list_scope : int;
    mutable hl_item : int;
    mutable typeahead : string;
    (* Press point (logical px) for drag thresholds and the text node
       whose selection a drag gesture extends. *)
    mutable down_x : float;
    mutable down_y : float;
    mutable sel_drag : int;
    (* data-attrs drag/drop: grabbed source (threshold pending), live
       (source, payload) session, the accepting target under the
       pointer, and the last completed drop. The wire carries no drop
       event — this is host-local by design (gaps.md TODO). *)
    mutable drag_src : int;
    mutable drag : (int * string) option;
    mutable drop_target : int;
    mutable last_drop : (int * string) option;
    (* Overlay tracking: topmost overlay-kind id, its modality, and the
       focus a modal surface saved and restores on close. *)
    mutable overlay_id : int;
    mutable overlay_modal : bool;
    mutable saved_focus : int;
    (* autofocus is honored once, at mount, when nothing is focused. *)
    mutable autofocus_done : bool;
    (* appear-enabled ids already announced (mount lifecycle). *)
    seen : (int, unit) Hashtbl.t;
    (* Per-container scroll bookkeeping: handled scroll-target tokens
       and last emitted visible ranges. *)
    scroll_token : (int, int) Hashtbl.t;
    vrange : (int, int * int) Hashtbl.t;
    (* Driver hooks: glyph measurement for caret/selection math and
       unshifted (content-space) rects for scroll_show. Deterministic
       defaults keep the module testable without a text engine. *)
    mutable measure : Lui_store.t -> int -> string -> float * float;
    mutable content_rect : int -> rect;
  }

  let create () =
    { scale = 1.; hovered = 0; hover_detail = 0; pressed = 0;
      press_detail = 0; focused = 0; caret = 0; shadow = "";
      ime = Lui_ime.initial; dirty = true;
      scroll_off = Hashtbl.create 8; scroll_cap = Hashtbl.create 8;
      last_x = 0.; last_y = 0.;
      sel_anchor = 0; sel_text = None; focus_visible = false;
      undo = []; redo = [];
      list_scope = 0; hl_item = 0; typeahead = "";
      down_x = 0.; down_y = 0.; sel_drag = 0;
      drag_src = 0; drag = None; drop_target = 0; last_drop = None;
      overlay_id = 0; overlay_modal = false; saved_focus = 0;
      autofocus_done = false;
      seen = Hashtbl.create 64;
      scroll_token = Hashtbl.create 8; vrange = Hashtbl.create 8;
      measure =
        (fun _store _id s -> (8. *. float (String.length s), 16.));
      content_rect = (fun _ -> rect 0. 0. 0. 0.) }

  let set_scale t s = t.scale <- s
  let set_measure t f = t.measure <- f
  let set_content_rect t f = t.content_rect <- f
  let hovered t = t.hovered
  let pressed t = t.pressed
  let focused t = t.focused
  let caret t = t.caret
  let shadow t = t.shadow
  let ime t = t.ime
  let marked t = t.ime.Lui_ime.marked_text
  let sel_anchor t = t.sel_anchor
  let sel_text t = t.sel_text
  let focus_visible t = t.focus_visible
  let hl_item t = t.hl_item
  let typeahead t = t.typeahead
  let last_drop t = t.last_drop
  let drag_active t = Option.is_some t.drag
  let overlay_top t = t.overlay_id

  (* Same scrollable rule as the paint pass: a scroll-kind node, or
     anything opting in through its overflow prop. *)
  let scrollable store id =
    (match kind_name store id with
     | "scroll" | "list" | "virtual-list" -> true
     | _ -> false)
    || (match string_prop store id "overflow" with
        | "scroll" | "auto" -> true
        | _ -> false)

  let scroll_offset t id =
    Option.value ~default:0. (Hashtbl.find_opt t.scroll_off id)

  let scroll_cap t id =
    Option.value ~default:0. (Hashtbl.find_opt t.scroll_cap id)

  let set_scroll_cap t id cap =
    Hashtbl.replace t.scroll_cap id cap;
    (* A shrinking cap (content removed, window grown) clamps any
       offset it left dangling past the new range. *)
    let off = scroll_offset t id in
    if off > cap then begin
      Hashtbl.replace t.scroll_off id cap;
      t.dirty <- true
    end

  let text_of store id = string_prop store id "text"

  let set_focused ?(kbd = false) t store id =
    if id <> t.focused then begin
      (* Focus loss cancels any in-flight composition first — marked
         text was never dispatched, so clearing it locally is the
         whole rollback. *)
      let st, _ = Lui_ime.feed_event t.ime (`Focus false) in
      let st, _ = Lui_ime.feed_event st (`Focus (id <> 0)) in
      t.ime <- st;
      t.focused <- id;
      t.shadow <- (if id = 0 then "" else text_of store id);
      t.caret <- (if id = 0 then 0 else String.length t.shadow);
      (* The selection, undo chain and any static-text selection are
         owned by the focused node — they reset on every move. *)
      t.sel_anchor <- t.caret;
      t.sel_text <- None;
      t.undo <- [];
      t.redo <- [];
      t.focus_visible <- kbd;
      t.dirty <- true
    end

  (* First id in [path] (deepest-first) that is enabled and passes
     [accept]. Pointer events keep bubbling past disabled nodes. *)
  let pick store path accept =
    List.find_opt
      (fun id -> node_enabled store id && accept store id)
      path

  (* First path node satisfying [accept]; if it is disabled it swallows
     the activation — matches web: disabled controls neither activate
     nor let activation fall through to ancestors. *)
  let select_activation store path accept =
    match List.find_opt (fun id -> accept store id) path with
    | Some id -> if node_enabled store id then Some id else None
    | None -> None

  let detail_of store id x y mods button =
    { x; y;
      modifiers =
        Input.mods_to_int mods lor (if button = 2 then 8 else 0);
      button; target_class = string_prop store id "style-class" }

  (* A representative event per family for admission checks; only the
     constructor matters to the gate. *)
  let ev_text n : event = TextChanged (n, "")
  let ev_press n : event = Press n
  let ev_submit n : event = Submit n

  let dummy_detail =
    { x = 0.; y = 0.; modifiers = 0; button = 0; target_class = "" }

  let focus_target store path =
    select_activation store path
      (fun s id -> event_supported s id (ev_text id))

  let press_target store path =
    select_activation store path
      (fun s id -> event_supported s id (ev_press id))

  let detail_target store path make =
    pick store path (fun s id ->
        pointer_enabled s id && event_supported s id (make id))

  (* Click on a pressable node, mirroring the web click dispatch:
     toggle kinds flip their state instead of emitting Press. *)
  let primary_press store id =
    let dispatch e =
      if node_enabled store id && event_supported store id e
      then [ Dispatch e ] else []
    in
    match kind_name store id with
    | "toggle-button" | "toggle" ->
      dispatch (ToggleChanged (id, not (bool_prop store id "selected")))
    | "checkbox" | "switch" ->
      dispatch (ToggleChanged (id, not (bool_prop store id "checked")))
    | "radio" ->
      if event_supported store id (Change id) then [ Dispatch (Change id) ]
      else
        (match dispatch (ToggleChanged (id, true)) with
         | [] -> dispatch (Press id)
         | acts -> acts)
    | "list-item" ->
      let expand =
        if string_prop store id "role" = "treeitem"
           && event_supported store id (ToggleChanged (id, true))
        then
          dispatch (ToggleChanged (id, not (bool_prop store id "expanded")))
        else []
      in
      dispatch (Press id) @ expand
    | _ -> dispatch (Press id)

  (* ---- overlays (popover/dialog/menu/sheet/toast) ----------------- *)

  let overlay_class = function
    | "dialog" | "sheet" | "drawer" -> `modal
    | "popover" | "dropdown-menu" | "context-menu" | "toast" -> `light
    | _ -> `none

  let is_desc store id anc =
    let rec go cur =
      match Lui_store.parent store cur with
      | Some p -> p = anc || go p
      | None -> false
    in
    go id

  (* Topmost overlay = last overlay-kind node in paint (preorder)
     order; returns (id, modal, dismiss-admitted). *)
  let top_overlay store =
    List.fold_left
      (fun acc id ->
         match overlay_class (kind_name store id) with
         | `none -> acc
         | cls ->
           Some (id, cls = `modal,
                 event_supported store id (Dismiss id)))
      None (Lui_store.preorder store)

  let inside_ov store ov path =
    List.exists (fun i -> i = ov || is_desc store i ov) path

  (* ---- text selection math ---------------------------------------- *)

  let sel_lo t = min t.sel_anchor t.caret
  let sel_hi t = max t.sel_anchor t.caret
  let sel_range t = (sel_lo t, sel_hi t)

  let word_byte c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
    || (c >= '0' && c <= '9') || c = '_' || Char.code c >= 0x80

  (* [i] on a word byte expands to the word; on a non-word byte the
     contiguous same-class run is the unit. *)
  let word_bounds s i =
    let n = String.length s in
    if i < 0 || i >= n then (n, n)
    else begin
      let w = word_byte s.[i] in
      let rec l j = if j > 0 && word_byte s.[j - 1] = w then l (j - 1) else j in
      let rec r j = if j < n && word_byte s.[j] = w then r (j + 1) else j in
      (l i, r i)
    end

  (* Paragraph line: the run between newlines around [i]. *)
  let line_bounds s i =
    let n = String.length s in
    let i = min (max 0 i) n in
    let rec l j = if j > 0 && s.[j - 1] <> '\n' then l (j - 1) else j in
    let rec r j = if j < n && s.[j] <> '\n' then r (j + 1) else j in
    (l i, r i)

  let pad_axis store id ~scale name fallback =
    match Layout.len_prop store id name ~scale with
    | Some v -> v
    | None ->
      Option.value ~default:0. (Layout.len_prop store id fallback ~scale)

  (* UTF-8 byte boundaries of [s] ascending, 0 and len included. *)
  let utf8_bounds s =
    let n = String.length s in
    let rec go i acc =
      if i >= n then List.rev (n :: acc)
      else if Char.code s.[i] land 0xC0 = 0x80 then go (i + 1) acc
      else go (i + 1) (i :: acc)
    in
    go 0 []

  (* Nearest byte boundary in one [line] whose measured prefix width
     reaches [lx] device px. *)
  let boundary_at_x t store id line lx =
    if lx <= 0. then 0
    else
      let rec choose prev = function
        | b :: tl ->
          let w = fst (t.measure store id (String.sub line 0 b)) in
          if w >= lx then
            let wp = fst (t.measure store id (String.sub line 0 prev)) in
            if lx -. wp < w -. lx then prev else b
          else choose b tl
        | [] -> String.length line
      in
      choose 0 (utf8_bounds line)

  (* Byte offset in [text] under the device-px point [(x,y)] inside
     node [id]'s shifted rect, honoring padding and line breaks. *)
  let offset_at_point t store rects id ~x ~y text =
    let r = Rects.get rects id in
    let ph =
      pad_axis store id ~scale:t.scale "padding-horizontal" "padding" in
    let pv =
      pad_axis store id ~scale:t.scale "padding-vertical" "padding" in
    let lx = x -. r.Lui_scene.x -. ph
    and ly = y -. r.Lui_scene.y -. pv in
    let lh = Float.max 1. (snd (t.measure store id "Ag")) in
    let lines = String.split_on_char '\n' text in
    let li =
      if ly <= 0. then 0
      else min (int_of_float (ly /. lh)) (List.length lines - 1)
    in
    let rec base i acc = function
      | [] -> acc
      | l :: tl ->
        if i = li then acc else base (i + 1) (acc + String.length l + 1) tl
    in
    let line = List.nth lines li in
    base 0 0 lines + boundary_at_x t store id line lx

  (* ---- drag & drop (data-attrs) -------------------------------------- *)

  let data_attrs store id =
    match Lui_store.prop store id "data-attrs" with
    | Some (StringValue s) ->
      (try Lui_protocol.data_attrs_decode s with _ -> [])
    | _ -> []

  let data_attr store id name =
    List.assoc_opt name (data_attrs store id)

  (* A text node opts into host-side selection via the wire
     "user-select" prop, or — on vocabularies that lack it — the
     legal data-* channel: data-user-select="text". *)
  let selectable_text store id =
    string_prop store id "user-select" = "text"
    || data_attr store id "data-user-select" = Some "text"

  (* The focused node is editable only while it admits TextChanged. *)
  let editable t store =
    t.focused <> 0
    && event_supported store t.focused (ev_text t.focused)

  (* ---- selection / clipboard / undo -------------------------------- *)

  let push_undo t =
    (match t.undo with
     | (s, _, _) :: _ when s = t.shadow -> ()
     | _ ->
       t.undo <- (t.shadow, t.caret, t.sel_anchor) :: t.undo;
       (* bound the chain *)
       if List.length t.undo > 64 then
         t.undo <- List.rev (List.tl (List.rev t.undo)));
    t.redo <- []

  (* Splice [ins] over the current selection in [n]'s shadow and
     dispatch the resulting TextChanged (undo-recorded). *)
  let splice t _store n ins =
    let cur = t.shadow in
    let lo = min (sel_lo t) (String.length cur)
    and hi = min (sel_hi t) (String.length cur) in
    let next =
      String.sub cur 0 lo ^ ins
      ^ String.sub cur hi (String.length cur - hi)
    in
    let caret' = lo + String.length ins in
    if next = cur then begin
      t.caret <- caret'; t.sel_anchor <- caret'; []
    end else begin
      push_undo t;
      t.shadow <- next; t.caret <- caret'; t.sel_anchor <- caret';
      t.dirty <- true;
      [ Dispatch (TextChanged (n, next)) ]
    end

  let delete_between t store n lo hi =
    t.sel_anchor <- lo; t.caret <- hi;
    splice t store n ""

  (* Selected text the accelerators act on: a live static selection
     first, else the focused node's range. *)
  let active_sel_text t store =
    match t.sel_text with
    | Some (nid, a, b) ->
      let s = string_prop store nid "text" in
      let lo = min a b and hi = min (max a b) (String.length s) in
      if hi > lo then Some (String.sub s lo (hi - lo)) else None
    | None ->
      if editable t store then
        let lo, hi = sel_range t in
        if hi > lo then Some (String.sub t.shadow lo (hi - lo))
        else None
      else None

  (* ---- scroll APIs --------------------------------------------------- *)

  (* Recompute the visible list-item range of a tracked container and
     emit VisibleRange when it changed. *)
  let report_vrange t store id =
    (* VisibleRange is admissible on ListContainer ("list") only *)
    if kind_name store id = "list"
       && bool_prop store id "track-visible-range"
    then
      let cr = t.content_rect id in
      if rect_empty cr || cr.Lui_scene.h <= 0. then []
      else
        let off = scroll_offset t id in
        let y0 = cr.Lui_scene.y +. off
        and y1 = cr.Lui_scene.y +. off +. cr.Lui_scene.h in
        let items =
          List.filter
            (fun c -> kind_name store c = "list-item")
            (Lui_store.preorder ~root:id store)
        in
        let rec scan i f l = function
          | [] -> (f, l)
          | it :: tl ->
            let r = t.content_rect it in
            let vis =
              (not (rect_empty r))
              && r.Lui_scene.y +. r.Lui_scene.h > y0
              && r.Lui_scene.y < y1
            in
            scan (i + 1) (if vis && f < 0 then i else f)
              (if vis then i else l) tl
        in
        let f, l = scan 0 (-1) (-1) items in
        let f = max 0 f in
        (match Hashtbl.find_opt t.vrange id with
         | Some (f', l') when f' = f && l' = l -> []
         | _ ->
           Hashtbl.replace t.vrange id (f, l);
           [ Dispatch (VisibleRange (id, f, l)) ])
    else []

  let scroll_set t store id off =
    let cap = scroll_cap t id in
    let off' = Float.max 0. (Float.min cap off) in
    if Float.abs (off' -. scroll_offset t id) > 0.001 then begin
      Hashtbl.replace t.scroll_off id off';
      t.dirty <- true
    end;
    report_vrange t store id

  let scroll_to t store id off = scroll_set t store id off

  let scroll_by t store id d =
    scroll_set t store id (scroll_offset t id +. d)

  (* Nearest scrollable ancestor-or-self of [id]. *)
  let scroll_ancestor store id =
    let rec go cur =
      if scrollable store cur then Some cur
      else
        match Lui_store.parent store cur with
        | Some p -> go p
        | None -> None
    in
    go id

  (* Reveal [id] inside its nearest scrollable ancestor. *)
  let scroll_show t store id =
    match scroll_ancestor store id with
    | None -> []
    | Some a ->
      let ar = t.content_rect a and nr = t.content_rect id in
      if rect_empty ar || rect_empty nr then []
      else begin
        let top = nr.Lui_scene.y -. ar.Lui_scene.y in
        let bot = top +. nr.Lui_scene.h in
        let off = scroll_offset t a in
        let off' =
          if top < off then top
          else if bot > off +. ar.Lui_scene.h then bot -. ar.Lui_scene.h
          else off
        in
        scroll_set t store a off'
      end

  (* scroll-anchor aligned reveal for scroll-target requests. *)
  let scroll_align t store a it anchor =
    let ar = t.content_rect a and nr = t.content_rect it in
    if rect_empty ar || rect_empty nr then []
    else
      let top = nr.Lui_scene.y -. ar.Lui_scene.y in
      let off' =
        match anchor with
        | "center" -> top -. ((ar.Lui_scene.h -. nr.Lui_scene.h) /. 2.)
        | "bottom" -> top +. nr.Lui_scene.h -. ar.Lui_scene.h
        | _ ->
          (* "top" / unset: minimal reveal *)
          let off = scroll_offset t a in
          if top < off then top
          else if top +. nr.Lui_scene.h > off +. ar.Lui_scene.h then
            top +. nr.Lui_scene.h -. ar.Lui_scene.h
          else off
      in
      scroll_set t store a off'

  (* ---- lists: highlight + typeahead ---------------------------------- *)

  let list_items t store =
    if t.list_scope = 0 || not (Lui_store.mem store t.list_scope)
    then []
    else
      List.filter
        (fun id -> kind_name store id = "list-item")
        (Lui_store.preorder ~root:t.list_scope store)

  let index_of id items =
    let rec go i = function
      | a :: _ when a = id -> Some i
      | _ :: tl -> go (i + 1) tl
      | [] -> None
    in
    go 0 items

  (* Highlight [items.(i)] and scroll it into view. *)
  let hl_index t store items i =
    if items = [] then []
    else begin
      let i = min (max 0 i) (List.length items - 1) in
      t.hl_item <- List.nth items i;
      t.dirty <- true;
      scroll_show t store t.hl_item
    end

  let move_hl t store delta =
    let items = list_items t store in
    match index_of t.hl_item items with
    | Some i -> hl_index t store items (i + delta)
    | None -> hl_index t store items (if delta > 0 then 0 else List.length items - 1)

  (* First list-item in scope whose text starts with the typeahead
     buffer (case-insensitive). *)
  let typeahead_match t store =
    let buf = String.lowercase_ascii t.typeahead in
    List.find_opt
      (fun id ->
         let s = String.lowercase_ascii (string_prop store id "text") in
         String.length s >= String.length buf
         && String.sub s 0 (String.length buf) = buf)
      (list_items t store)

  (* ---- drag & drop (data-attrs) -------------------------------------- *)

  let draggable store id =
    data_attr store id "draggable" = Some "true"

  let drop_accepts store id payload =
    data_attr store id "data-drop-target" = Some "true"
    &&
    match data_attr store id "data-drop-accept" with
    | None | Some "*" | Some "" -> true
    | Some acc ->
      (* comma-separated payload prefixes *)
      List.exists
        (fun p ->
           let p = String.trim p in
           p <> ""
           && String.length payload >= String.length p
           && String.sub payload 0 (String.length p) = p)
        (String.split_on_char ',' acc)

  (* ---- focusables + keyboard activation -------------------------------- *)

  (* Activation-capable control kinds — the pointer does not focus
     them on this host (macOS-like), Tab/Shift-Tab do. *)
  let activatable store id =
    node_enabled store id
    &&
    match kind_name store id with
    | "button" | "toggle-button" | "toggle" | "checkbox" | "switch"
    | "radio" | "slider" | "number-stepper" | "select" | "menu-item" ->
      true
    | _ -> false

  let focusables store =
    let scope =
      match top_overlay store with
      | Some (ov, true, _) -> Some ov  (* modal focus trap *)
      | _ -> None
    in
    List.filter
      (fun id ->
         node_enabled store id
         && (event_supported store id (ev_text id) || activatable store id)
         &&
         match scope with
         | None -> true
         | Some ov -> id = ov || is_desc store id ov)
      (Lui_store.preorder store)

  let step_focusable store cur dir =
    let ids = focusables store in
    match ids with
    | [] -> 0
    | _ ->
      let n = List.length ids in
      let idx =
        match index_of cur ids with
        | Some i -> i
        | None -> if dir > 0 then -1 else n
      in
      List.nth ids (((idx + dir) mod n + n) mod n)

  (* UTF-8 aware caret stepping over byte offsets. *)
  let utf8_prev s i =
    let rec back j =
      if j <= 0 then 0
      else if Char.code s.[j] land 0xC0 = 0x80 then back (j - 1)
      else j
    in
    back (i - 1)

  let utf8_next s i =
    let n = String.length s in
    let rec fwd j =
      if j >= n then n
      else if Char.code s.[j] land 0xC0 = 0x80 then fwd (j + 1)
      else j
    in
    fwd (i + 1)

  let submit store id =
    if event_supported store id (ev_submit id) then [ Dispatch (Submit id) ]
    else []

  (* Translate one lui_ime action into window actions plus the Ui
     side effects they imply. `Commit_text splices through the exact
     path raw text input used before composition existed. *)
  let apply_ime t store actions =
    List.filter_map
      (fun a ->
         match a with
         | `Move_candidate r -> Some (Ime_rect r)
         | `Commit_text s ->
           t.dirty <- true;
           (match t.focused with
            | 0 -> None
            | n when node_enabled store n
                     && event_supported store n (ev_text n) ->
              (match splice t store n s with
               | [ a ] -> Some a
               | _ -> None)
            | _ -> None)
         | `Begin_composition | `Update_composition _ | `Cancel ->
           t.dirty <- true;
           None)
      actions

  (* Feed one IME event into the state machine and apply what it
     asks for. *)
  let feed_ime t store ev =
    let st, actions = Lui_ime.feed_event t.ime ev in
    t.ime <- st;
    apply_ime t store actions

  (* ---- store sync: effects that react to store changes -------------

     Runs at the top of [handle] and through [store_changed] after the
     app flushes a batch — dead-focus cleanup, modal overlay focus
     save/restore, Appear lifecycle events, scroll-target requests and
     track-visible-range reports. *)
  let sync t store =
    let acts = ref [] in
    let push a = acts := a :: !acts in
    if t.focused <> 0 && not (Lui_store.mem store t.focused) then begin
      set_focused t store 0;
      push (Focus_changed 0)
    end;
    if t.saved_focus <> 0 && not (Lui_store.mem store t.saved_focus)
    then t.saved_focus <- 0;
    let ov = top_overlay store in
    let ov_id, ov_modal =
      match ov with
      | Some (id, m, _) -> (id, m)
      | None -> (0, false)
    in
    if ov_id <> t.overlay_id then begin
      if ov_modal && t.focused <> 0 && t.focused <> ov_id
         && not (is_desc store t.focused ov_id)
      then t.saved_focus <- t.focused;
      if t.overlay_modal && not ov_modal && t.saved_focus <> 0
         && t.focused = 0 then begin
        set_focused t store t.saved_focus;
        push (Focus_changed t.saved_focus)
      end;
      t.overlay_id <- ov_id;
      t.overlay_modal <- ov_modal
    end;
    (* autofocus (wire `autofocus` prop): the first autofocus-marked
       node takes keyboard focus once, when nothing else is focused *)
    if not t.autofocus_done then
      (match
         List.find_opt
           (fun id -> bool_prop store id "autofocus")
           (Lui_store.preorder store)
       with
       | Some id ->
         t.autofocus_done <- true;
         if t.focused = 0 && node_enabled store id
            && (event_supported store id (ev_text id)
                || activatable store id)
         then begin
           set_focused t store id;
           push (Focus_changed id)
         end
       | None -> ());
    (* enter hook: appear-enabled nodes announce their mount *)
    let appear_now =
      List.filter
        (fun id ->
           node_enabled store id
           && bool_prop store id "appear-enabled"
           && event_supported store id (Appear id))
        (Lui_store.preorder store)
    in
    List.iter
      (fun id ->
         if not (Hashtbl.mem t.seen id) then push (Dispatch (Appear id)))
      appear_now;
    Hashtbl.reset t.seen;
    List.iter (fun id -> Hashtbl.replace t.seen id ()) appear_now;
    (* scroll-target requests on list containers *)
    List.iter
      (fun id ->
         if kind_name store id = "list" then
           match Lui_store.int_prop store id "scroll-token" with
           | Some tok ->
             (match Hashtbl.find_opt t.scroll_token id with
              | Some prev when prev = tok -> ()
              | _ ->
                Hashtbl.replace t.scroll_token id tok;
                let target = string_prop store id "scroll-target" in
                let item =
                  if target = "" then None
                  else
                    List.find_opt
                      (fun c -> string_prop store c "key" = target)
                      (Lui_store.preorder ~root:id store)
                in
                (match item with
                 | Some it ->
                   let anchor = string_prop store id "scroll-anchor" in
                   acts := List.rev_append (scroll_align t store id it anchor) !acts;
                   push (Dispatch (ScrollCompleted (id, tok, "succeeded")))
                 | None ->
                   push (Dispatch (ScrollCompleted (id, tok, "missing-target")))))
           | None -> ())
      (Lui_store.preorder store);
    List.iter
      (fun id ->
         acts := List.rev_append (report_vrange t store id) !acts)
      (Lui_store.preorder store);
    List.rev !acts

  let store_changed = sync

  (* ---- key sub-dispatchers ------------------------------------------- *)

  let move_caret t off mods =
    t.caret <- off;
    if not mods.Input.shift then t.sel_anchor <- off;
    t.dirty <- true

  (* Word jump helpers over byte offsets. *)
  let word_left s i =
    let rec skip j =
      if j <= 0 then 0
      else if word_byte s.[j - 1] then j else skip (j - 1)
    in
    let rec take j =
      if j <= 0 then 0
      else if word_byte s.[j - 1] then take (j - 1) else j
    in
    take (skip i)

  let word_right s i =
    let n = String.length s in
    let rec skip j =
      if j >= n then n
      else if word_byte s.[j] then j else skip (j + 1)
    in
    let rec take j =
      if j >= n then n
      else if word_byte s.[j] then take (j + 1) else j
    in
    take (skip i)

  (* Caret (line, column-in-bytes) then boundary on the target line —
     shared by Arrow_up/down in multi-line fields. *)
  let move_caret_line t store dir =
    let s = t.shadow in
    let c = min t.caret (String.length s) in
    let lines = String.split_on_char '\n' s in
    let rec find li base = function
      | l :: tl ->
        let e = base + String.length l in
        if c <= e then (li, c - base) else find (li + 1) (e + 1) tl
      | [] -> (List.length lines - 1, String.length (List.nth lines (List.length lines - 1)))
    in
    let li, col = find 0 0 lines in
    let li' = min (max 0 (li + dir)) (List.length lines - 1) in
    if li' <> li then begin
      let x = fst (t.measure store t.focused
                     (String.sub (List.nth lines li) 0 col)) in
      let rec base i acc = function
        | [] -> acc
        | l :: tl ->
          if i = li' then acc else base (i + 1) (acc + String.length l + 1) tl
      in
      base 0 0 lines
      + boundary_at_x t store t.focused (List.nth lines li') x
    end else c

  let text_key t store key (mods : Input.mods) prim =
    let n = t.focused in
    match key with
    | Input.Return ->
      (match kind_name store n with
       | "textarea" ->
         if (bool_prop store n "submit-on-enter" && not mods.shift)
            || mods.ctrl || mods.meta
         then submit store n else []
       | _ -> submit store n)
    | Input.Backspace ->
      let cur = t.shadow in
      let caret = min t.caret (String.length cur) in
      if sel_hi t > sel_lo t then splice t store n ""
      else if caret > 0 then delete_between t store n (utf8_prev cur caret) caret
      else []
    | Input.Delete ->
      let cur = t.shadow in
      let caret = min t.caret (String.length cur) in
      if sel_hi t > sel_lo t then splice t store n ""
      else if caret < String.length cur then
        delete_between t store n caret (utf8_next cur caret)
      else []
    | Input.Arrow_left ->
      let cur = t.shadow in
      let caret = min t.caret (String.length cur) in
      let dest =
        if prim then fst (line_bounds cur caret)
        else if mods.alt then word_left cur caret
        else if not mods.shift && sel_hi t > sel_lo t then sel_lo t
        else utf8_prev cur caret
      in
      move_caret t dest mods; []
    | Input.Arrow_right ->
      let cur = t.shadow in
      let caret = min t.caret (String.length cur) in
      let dest =
        if prim then snd (line_bounds cur caret)
        else if mods.alt then word_right cur caret
        else if not mods.shift && sel_hi t > sel_lo t then sel_hi t
        else utf8_next cur caret
      in
      move_caret t dest mods; []
    | Input.Arrow_up ->
      move_caret t (move_caret_line t store (-1)) mods; []
    | Input.Arrow_down ->
      move_caret t (move_caret_line t store 1) mods; []
    | Input.Home -> move_caret t 0 mods; []
    | Input.End -> move_caret t (String.length t.shadow) mods; []
    | _ -> []

  (* Slider/stepper value stepping, bounded by min/max props. *)
  let step_value store n dir =
    let cur =
      match Lui_store.prop store n "value" with
      | Some (FloatValue v) -> v
      | Some (IntValue i) -> float i
      | _ -> 0.
    in
    let step =
      match Lui_store.prop store n "step" with
      | Some (FloatValue v) -> v
      | Some (IntValue i) -> float i
      | _ -> 0.05
    in
    let lo, hi =
      ( (match Lui_store.prop store n "min" with
         | Some (FloatValue v) -> v | Some (IntValue i) -> float i
         | _ -> 0.),
        (match Lui_store.prop store n "max" with
         | Some (FloatValue v) -> v | Some (IntValue i) -> float i
         | _ -> 1.) )
    in
    let v = Float.max lo (Float.min hi (cur +. dir *. step)) in
    if v <> cur && event_supported store n (ValueChanged (n, v))
    then [ Dispatch (ValueChanged (n, v)) ] else []

  (* Arrow keys move inside a radio group: sibling radios of the same
     parent, focus follows the change. *)
  let radio_step t store n dir =
    match Lui_store.parent store n with
    | None -> []
    | Some p ->
      let siblings =
        List.filter
          (fun c -> kind_name store c = "radio" && node_enabled store c)
          (Lui_store.child_ids store p)
      in
      (match index_of n siblings with
       | Some i ->
         let i' = min (max 0 (i + dir)) (List.length siblings - 1) in
         let tgt = List.nth siblings i' in
         if tgt <> n then begin
           set_focused ~kbd:true t store tgt;
           Focus_changed tgt :: primary_press store tgt
         end else []
       | None -> [])

  let control_key t store key _mods =
    let n = t.focused in
    match kind_name store n, key with
    | ("slider" | "number-stepper"), Input.Arrow_left
    | ("slider" | "number-stepper"), Input.Arrow_down ->
      step_value store n (-1.)
    | ("slider" | "number-stepper"), Input.Arrow_right
    | ("slider" | "number-stepper"), Input.Arrow_up ->
      step_value store n 1.
    | "radio", (Input.Arrow_left | Input.Arrow_up) ->
      radio_step t store n (-1)
    | "radio", (Input.Arrow_right | Input.Arrow_down) ->
      radio_step t store n 1
    | _, (Input.Return | Input.Space) -> primary_press store n
    | _ -> []

  (* Keyboard on lists with no focused widget: arrows move the
     highlight, PgUp/PgDn page the scope, chars typeahead-jump and
     Return/Space activates the highlighted item. *)
  let list_key t store key mods =
    match key with
    | Input.Arrow_down -> move_hl t store 1
    | Input.Arrow_up -> move_hl t store (-1)
    | Input.Home -> hl_index t store (list_items t store) 0
    | Input.End ->
      hl_index t store (list_items t store)
        (List.length (list_items t store) - 1)
    | Input.Page_down | Input.Page_up ->
      let dir = if key = Input.Page_down then 1. else -1. in
      (match
         (if t.list_scope <> 0 && Lui_store.mem store t.list_scope
          then Some t.list_scope else None)
       with
       | Some a ->
         let ar = t.content_rect a in
         if rect_empty ar then []
         else scroll_by t store a (dir *. 0.9 *. ar.Lui_scene.h)
       | None -> [])
    | Input.Return | Input.Space ->
      if t.hl_item <> 0 && Lui_store.mem store t.hl_item
         && node_enabled store t.hl_item
      then primary_press store t.hl_item else []
    | Input.Other sc ->
      (match Input.char_of_scancode ~shift:mods.Input.shift sc with
       | Some c ->
         t.typeahead <- t.typeahead ^ String.make 1 c;
         (match typeahead_match t store with
          | Some it ->
            t.hl_item <- it; t.dirty <- true;
            scroll_show t store it
          | None -> [])
       | None -> [])
    | _ -> []

  let primary mods = mods.Input.ctrl || mods.Input.meta

  let handle t store rects input =
    let pre = sync t store in
    pre
    @
    (match input with
    | Input.Move (x, y) ->
      t.last_x <- x;
      t.last_y <- y;
      let dx, dy = x *. t.scale, y *. t.scale in
      if Option.is_some t.drag then begin
        (* live drop-target tracking while a drag is in flight *)
        let path = hit_path store rects ~x:dx ~y:dy in
        let tgt =
          match t.drag with
          | Some (_, payload) ->
            (match
               List.find_opt
                 (fun id -> drop_accepts store id payload) path
             with
             | Some id -> id
             | None -> 0)
          | None -> 0
        in
        if tgt <> t.drop_target then begin
          t.drop_target <- tgt;
          t.dirty <- true
        end;
        []
      end else if t.drag_src <> 0
                  && Float.abs (x -. t.down_x)
                     +. Float.abs (y -. t.down_y) > 6. then begin
        (* threshold crossed: promote the grab into a drag session;
           the payload is the data-drag-payload attr, falling back to
           the node's text prop *)
        let payload =
          match data_attr store t.drag_src "data-drag-payload" with
          | Some p -> p
          | None ->
            (match Lui_store.prop store t.drag_src "text" with
             | Some (StringValue s) -> s
             | _ -> kind_name store t.drag_src)
        in
        t.drag <- Some (t.drag_src, payload);
        t.sel_drag <- 0;
        t.dirty <- true;
        []
      end else if t.sel_drag <> 0 then begin
        (* drag-select: extend the selection over the glyphs under
           the pointer *)
        let id = t.sel_drag in
        (match t.sel_text with
         | Some (nid, a, _) when nid = id ->
           let off =
             offset_at_point t store rects id ~x:dx ~y:dy
               (text_of store id)
           in
           t.sel_text <- Some (id, a, off)
         | _ when id = t.focused ->
           t.caret <-
             offset_at_point t store rects id ~x:dx ~y:dy t.shadow
         | _ -> ());
        t.dirty <- true;
        []
      end else begin
      let path = hit_path store rects ~x:dx ~y:dy in
      let hover = match path with id :: _ -> id | [] -> 0 in
      let detail =
        match
          detail_target store path (fun id -> PointerEnter id)
        with
        | Some id -> id
        | None -> 0
      in
      let actions =
        if detail <> t.hover_detail then
          (if t.hover_detail <> 0
              && node_enabled store t.hover_detail
              && event_supported store t.hover_detail
                   (PointerLeave t.hover_detail)
           then [ Dispatch (PointerLeave t.hover_detail) ]
           else [])
          @ (if detail <> 0 then [ Dispatch (PointerEnter detail) ] else [])
        else []
      in
      if hover <> t.hovered || detail <> t.hover_detail then t.dirty <- true;
      t.hovered <- hover;
      t.hover_detail <- detail;
      actions
      end
    | Input.Button_down (x, y, btn, clicks, mods) ->
      t.last_x <- x;
      t.last_y <- y;
      (match btn with
       | Input.Left ->
         let dx, dy = x *. t.scale, y *. t.scale in
         let path = hit_path store rects ~x:dx ~y:dy in
         t.down_x <- x; t.down_y <- y;
         t.typeahead <- "";
         (* Overlay semantics: a press outside the top overlay light-
            dismisses it when its kind admits Dismiss; a modal surface
            swallows the press entirely (focus trap). *)
         let ov = top_overlay store in
         let inside =
           match ov with
           | None -> true
           | Some (oid, _, _) -> inside_ov store oid path
         in
         (match ov, inside with
          | Some (_, true, _), false -> []
          | _ ->
            let dismiss =
              match ov with
              | Some (oid, false, true) when not inside ->
                [ Dispatch (Dismiss oid) ]
              | _ -> []
            in
            let focus =
              match focus_target store path with
              | Some id -> id
              | None -> 0
            in
            let focus_actions =
              if focus <> t.focused then begin
                set_focused t store focus;
                [ Focus_changed focus ]
              end else []
            in
            (* Selection: click sets the caret, shift-click extends,
               double/triple click selects word/paragraph — on
               editable fields and on user-select=text nodes alike. *)
            (match
               (if focus <> 0 && List.mem focus path then `edit
                else if
                  List.exists (fun i -> selectable_text store i) path
                then `static
                else `none)
             with
             | `edit ->
               let off =
                 offset_at_point t store rects focus ~x:dx ~y:dy t.shadow
               in
               if mods.shift then t.caret <- off
               else if clicks >= 3 then
                 let a, b = line_bounds t.shadow off in
                 t.sel_anchor <- a; t.caret <- b
               else if clicks = 2 then
                 let a, b = word_bounds t.shadow off in
                 t.sel_anchor <- a; t.caret <- b
               else begin t.caret <- off; t.sel_anchor <- off end;
               t.sel_drag <- focus; t.sel_text <- None
             | `static ->
               let id =
                 List.find (fun i -> selectable_text store i) path in
               let text = text_of store id in
               let off =
                 offset_at_point t store rects id ~x:dx ~y:dy text in
               let a, b =
                 if clicks >= 3 then line_bounds text off
                 else if clicks = 2 then word_bounds text off
                 else (off, off)
               in
               t.sel_text <- Some (id, a, b); t.sel_drag <- id
             | `none ->
               t.sel_drag <- 0;
               if not mods.shift then t.sel_text <- None);
            t.drag_src <-
              (match List.find_opt (fun i -> draggable store i) path with
               | Some id -> id
               | None -> 0);
            let down =
              match
                detail_target store path (fun id ->
                    PointerDown (id, dummy_detail))
              with
              | Some id ->
                t.press_detail <- id;
                [ Dispatch
                    (PointerDown
                       (id, detail_of store id x y mods 0)) ]
              | None ->
                t.press_detail <- 0;
                []
            in
            t.pressed <-
              (match press_target store path with
               | Some id -> id
               | None -> 0);
            let double =
              if clicks = 2 then
                match
                  pick store path (fun s id ->
                      event_supported s id (DoublePress id))
                with
                | Some id -> [ Dispatch (DoublePress id) ]
                | None -> []
              else []
            in
            (* list context: the innermost scrollable ancestor with
               items under the pointer owns typeahead/arrows; a pressed
               list-item becomes the highlight *)
            (match
               List.find_opt
                 (fun i ->
                    scrollable store i
                    && List.exists
                         (fun c -> kind_name store c = "list-item")
                         (Lui_store.preorder ~root:i store))
                 path
             with
             | Some id -> t.list_scope <- id
             | None -> ());
            (match
               List.find_opt
                 (fun i -> kind_name store i = "list-item") path
             with
             | Some it -> t.hl_item <- it
             | None -> ());
            t.dirty <- true;
            dismiss @ focus_actions @ down @ double)
       | Input.Right ->
         let dx, dy = x *. t.scale, y *. t.scale in
         let path = hit_path store rects ~x:dx ~y:dy in
         (match
            detail_target store path (fun id ->
                ContextMenuPress (id, dummy_detail))
          with
          | Some id ->
            [ Dispatch
                (ContextMenuPress
                   (id, detail_of store id x y mods 2)) ]
          | None -> [])
       | _ -> [])
    | Input.Button_up (x, y, btn, mods) ->
      t.last_x <- x;
      t.last_y <- y;
      (match btn with
       | Input.Left when Option.is_some t.drag ->
         (* drop completes on the accepting target under the pointer;
            the click it rode on is consumed *)
         (match t.drag with
          | Some (_, payload) when t.drop_target <> 0 ->
            t.last_drop <- Some (t.drop_target, payload)
          | _ -> ());
         t.drag <- None;
         t.drag_src <- 0;
         t.drop_target <- 0;
         t.pressed <- 0;
         t.press_detail <- 0;
         t.sel_drag <- 0;
         t.dirty <- true;
         []
       | Input.Left ->
         t.sel_drag <- 0;
         t.drag_src <- 0;
         let up =
           if t.press_detail <> 0
              && node_enabled store t.press_detail
              && event_supported store t.press_detail
                   (PointerUp (t.press_detail, dummy_detail))
           then
             [ Dispatch
                 (PointerUp
                    (t.press_detail,
                     detail_of store t.press_detail x y mods 0)) ]
           else []
         in
         let dx, dy = x *. t.scale, y *. t.scale in
         let path = hit_path store rects ~x:dx ~y:dy in
         let release =
           match press_target store path with
           | Some id -> id
           | None -> 0
         in
         let click =
           if t.pressed <> 0 && release = t.pressed then begin
             let n = t.pressed in
             let pd =
               if pointer_enabled store n
                  && event_supported store n
                       (PressDetail (n, dummy_detail))
               then
                 [ Dispatch
                     (PressDetail (n, detail_of store n x y mods 0)) ]
               else []
             in
             pd @ primary_press store n
           end else []
         in
         t.pressed <- 0;
         t.press_detail <- 0;
         t.dirty <- true;
         up @ click
       | _ -> [])
    | Input.Text_input s -> feed_ime t store (`Commit s)
    | Input.Text_editing (text, start, len) ->
      feed_ime t store (`Editing (text, start, len))
    | Input.Caret r -> feed_ime t store (`Caret r)
    | Input.Paste s ->
      (* clipboard text the driver pulled after Paste_request *)
      if s = "" || not (editable t store) then []
      else splice t store t.focused s
    | Input.Key_down (key, mods, _repeat) ->
      (* While marked text is on screen the keys belong to the IME —
         SDL filters most of them already; this gate is the belt. *)
      if Lui_ime.composing t.ime then []
      else begin
        (* The accelerator table: "primary" is Cmd on macOS, Ctrl
           elsewhere — this host accepts either. Entries the wire has
           a channel for route through dispatch; clipboard/undo stay
           host-side (no wire event exists for them). *)
        let prim = primary mods in
        (match key with
         | Input.Escape ->
           (match t.drag with
            | Some _ ->
              (* cancel the drag: no drop, click consumed *)
              t.drag <- None; t.drag_src <- 0; t.drop_target <- 0;
              t.dirty <- true;
              []
            | None ->
              (match top_overlay store with
               | Some (oid, _, true) -> [ Dispatch (Dismiss oid) ]
               | Some (_, _, false) -> []
               | None ->
                 if t.focused <> 0 then begin
                   set_focused t store 0;
                   [ Focus_changed 0 ]
                 end else [ Quit ]))
         | Input.Other 4 when prim ->
           (* A: select all — editable range or the static selection's
              node *)
           (match editable t store, t.sel_text with
            | true, _ ->
              t.sel_anchor <- 0;
              t.caret <- String.length t.shadow;
              t.dirty <- true;
              []
            | false, Some (nid, _, _) ->
              t.sel_text <-
                Some (nid, 0, String.length (text_of store nid));
              t.dirty <- true;
              []
            | _ -> [])
         | Input.Other 6 when prim ->
           (* C: copy the active selection *)
           (match active_sel_text t store with
            | Some s -> [ Clipboard_write s ]
            | None -> [])
         | Input.Other 27 when prim && editable t store ->
           (* X: cut = copy + delete *)
           (match active_sel_text t store with
            | Some s -> Clipboard_write s :: splice t store t.focused ""
            | None -> [])
         | Input.Other 25 when prim && editable t store ->
           (* V: the driver turns this into Input.Paste with the
              clipboard text *)
           [ Paste_request ]
         | Input.Other 29 when prim && editable t store ->
           (* Z / shift-Z: host-side undo/redo of shadow edits *)
           (match mods.shift, t.undo, t.redo with
            | false, (s, c, a) :: tl, _ ->
              t.redo <- (t.shadow, t.caret, t.sel_anchor) :: t.redo;
              t.undo <- tl;
              t.shadow <- s; t.caret <- c; t.sel_anchor <- a;
              t.dirty <- true;
              [ Dispatch (TextChanged (t.focused, s)) ]
            | true, _, (s, c, a) :: tl ->
              t.undo <- (t.shadow, t.caret, t.sel_anchor) :: t.undo;
              t.redo <- tl;
              t.shadow <- s; t.caret <- c; t.sel_anchor <- a;
              t.dirty <- true;
              [ Dispatch (TextChanged (t.focused, s)) ]
            | _ -> [])
         | Input.Tab ->
           let dir = if mods.Input.shift then -1 else 1 in
           let next = step_focusable store t.focused dir in
           if next <> 0 && next <> t.focused then begin
             set_focused ~kbd:true t store next;
             Focus_changed next :: scroll_show t store next
           end else []
         | _ ->
           if editable t store then text_key t store key mods prim
           else if t.focused <> 0 then control_key t store key mods
           else list_key t store key mods)
      end
    | Input.Resize (w, h) -> [ Resize_host (w, h) ]
    | Input.Wheel (_dx, dy) ->
      (* Scroll the deepest scrollable ancestor under the pointer that
         actually has range. SDL reports +y for scroll-away
         (content up); offset grows with -dy, scaled to device px. *)
      let path =
        hit_path store rects
          ~x:(t.last_x *. t.scale) ~y:(t.last_y *. t.scale)
      in
      (match
         List.find_opt
           (fun id -> scrollable store id && scroll_cap t id > 0.001)
           path
       with
       | Some id ->
         let cap = scroll_cap t id in
         let off = scroll_offset t id in
         let off' =
           Float.max 0.
             (Float.min cap (off -. (dy *. 44. *. t.scale)))
         in
         if off' <> off then begin
           Hashtbl.replace t.scroll_off id off';
           t.dirty <- true
         end;
         []
       | None -> [])
    | Input.Quit_input -> [ Quit ])

  let state_of t store id =
    { Lui_paint.hovered = t.hovered = id || t.drop_target = id;
      pressed =
        (t.pressed = id
         ||
         match t.drag with
         | Some (src, _) -> src = id
         | None -> false);
      focused = t.focused = id;
      selected = bool_prop store id "selected" || t.hl_item = id;
      disabled = not (node_enabled store id) }

  let want_frame t host = t.dirty || Lui_host.wants_repaint host
  let frame_done t = t.dirty <- false
end

module Theme = struct
  let color = color

  let palette =
    [ ("background", color 22 23 32 255);
      ("foreground", color 228 230 238 255);
      ("card", color 30 31 44 255);
      ("card-foreground", color 228 230 238 255);
      ("popover", color 30 31 44 255);
      ("popover-foreground", color 228 230 238 255);
      ("primary", color 76 116 246 255);
      ("primary-foreground", color 255 255 255 255);
      ("secondary", color 44 46 62 255);
      ("secondary-foreground", color 228 230 238 255);
      ("muted", color 44 46 62 255);
      ("muted-foreground", color 152 158 178 255);
      ("accent", color 52 55 74 255);
      ("accent-foreground", color 228 230 238 255);
      ("destructive", color 239 68 68 255);
      ("destructive-foreground", color 255 255 255 255);
      ("border", color 56 59 76 255);
      ("input", color 40 42 58 255);
      ("ring", color 76 116 246 255);
      ("selection", color 76 116 246 90) ]

  let color_of_hex s =
    let n = String.length s in
    if n < 2 || s.[0] <> '#' then None
    else
      let hex i = int_of_string ("0x" ^ String.sub s i 2) in
      let dup i =
        let c = String.sub s i 1 in
        int_of_string ("0x" ^ c ^ c)
      in
      try
        (match n - 1 with
         | 3 -> Some (color (dup 1) (dup 2) (dup 3) 255)
         | 4 -> Some (color (dup 1) (dup 2) (dup 3) (dup 4))
         | 6 -> Some (color (hex 1) (hex 3) (hex 5) 255)
         | 8 -> Some (color (hex 1) (hex 3) (hex 5) (hex 7))
         | _ -> None)
      with _ -> None

  let color_of name =
    match List.assoc_opt name palette with
    | Some c -> Some c
    | None -> color_of_hex name
end

module Checksum = struct
  (* FNV-1a 64-bit over a canonical op description, so identical
     scenes on any platform produce the same digest. *)
  type t = { mutable hash : int64 }

  let create () = { hash = 0xcbf29ce484222325L }

  let add_int t v =
    let x = Int64.of_int (v land 0x3fffffff) in
    t.hash <- Int64.mul (Int64.logxor t.hash x) 0x100000001b3L

  let add_float t v = add_int t (int_of_float (v *. 64.))

  let add_color t (c : color) =
    add_int t c.r; add_int t c.g; add_int t c.b; add_int t c.a

  let add_rect t (r : rect) =
    add_float t r.x; add_float t r.y; add_float t r.w; add_float t r.h

  let add_paint t = function
    | Solid -> add_int t 0
    | Linear -> add_int t 1
    | Oklab -> add_int t 2
    | Stripes -> add_int t 3

  let add_radii t (a, b, c, d) =
    add_float t a; add_float t b; add_float t c; add_float t d

  let add_bool t b = add_int t (if b then 1 else 0)

  let add_op t = function
    | Fill o ->
      add_int t 10;
      add_rect t o.frect;
      add_radii t o.fradii;
      add_bool t o.fcontinuous;
      add_color t o.fcolor;
      add_paint t o.fpaint;
      add_color t o.fcolor2;
      add_radii t o.fgradient;
      add_radii t o.fborder;
      add_color t o.fborder_color;
      add_bool t o.fdashed;
      add_int t o.fwide;
      add_float t o.fopacity
    | Shadow o ->
      add_int t 11;
      add_rect t o.srect;
      add_radii t o.sradii;
      add_bool t o.scontinuous;
      add_color t o.scolor;
      add_float t o.sblur;
      add_bool t o.sinset;
      add_rect t o.scast;
      add_radii t o.scast_radii;
      add_bool t o.scast_continuous;
      add_int t o.swide;
      add_float t o.sopacity
    | Glyphs o ->
      add_int t 20;
      add_int t o.gstart; add_int t o.gend;
      add_paint t o.gpaint;
      add_color t o.gcolor; add_color t o.gcolor2;
      add_radii t o.ggradient;
      add_int t o.gwide2; add_float t o.gopacity
    | Image o ->
      add_int t 30;
      add_rect t o.irect2;
      add_radii t o.iradii;
      add_bool t o.icontinuous;
      add_int t o.iimage.iid; add_int t o.iimage.iversion;
      add_rect t o.isrc;
      add_bool t o.igrayscale;
      add_float t o.iopacity
    | Push_clip o ->
      add_int t 1;
      add_rect t o.crect;
      add_radii t o.cradii;
      add_bool t o.ccontinuous
    | Pop_clip -> add_int t 2
    | Effect o ->
      add_int t 40;
      add_rect t o.edrect;
      add_radii t o.edradii;
      add_bool t o.edcontinuous;
      add_int t o.edindex;
      add_float t o.edopacity
    | Hole o ->
      add_int t 50;
      add_rect t o.hrect;
      add_radii t o.hradii;
      add_bool t o.hcontinuous;
      add_float t o.hopacity

  let add_scene t (s : Lui_scene.t) =
    add_int t s.width;
    add_int t s.height;
    List.iter (add_op t) s.ops;
    List.iter
      (fun g ->
        add_float t g.gx; add_float t g.gy;
        add_float t g.gw; add_float t g.gh;
        add_color t g.gcolor;
        add_int t (if g.gcolored then 1 else 0))
      s.glyphs

  let value t = t.hash
end
