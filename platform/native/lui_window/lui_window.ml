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
  drop_files : string list;
      (** [--drop-file PATH] repeat flag: synthetic OS file drops the
          headless driver injects on frame 1 (at the deepest target
          accepting the ["file:"] payload) — exercises the SDL_DROPFILE
          channel without a real OS drag. *)
  windows : int;
      (** [--windows N]: number of top-level windows the driver opens,
          each an independent surface (1–8). Default 1. *)
}

let default_config =
  { width = 960; height = 640; headless_frames = None; drop_files = [];
    windows = 1 }

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
    | "--drop-file" :: v :: tl ->
      loop { cfg with drop_files = v :: cfg.drop_files } tl
    | "--windows" :: v :: tl ->
      (match int_of_string_opt v with
       | Some n when n > 0 && n <= 8 -> loop { cfg with windows = n } tl
       | _ -> Error "invalid --windows (expected 1-8)")
    | ("--width" | "--height" | "--headless" | "--drop-file"
      | "--windows") :: [] ->
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

  (* Win32 virtual-key codes → the SDL-scancode numbering the rest of
     this module speaks. [Other] must mean the same thing on every
     platform: the accelerator table matches [Other] against SDL
     scancode values (A=4, C=6, V=25, X=27, Z=29) and typeahead goes
     through [char_of_scancode], so feeding raw VK codes (A=0x41)
     would make every letter shortcut unreachable on Windows. The
     table follows the positional (scancode-style) reading of VKs —
     same keys SDL's own Win32 backend maps the same way. *)
  let sdl_scancode_of_win32_vk = function
    | vk when vk >= 0x41 && vk <= 0x5A -> vk - 0x41 + 4   (* A-Z *)
    | 0x30 -> 39                                        (* 0 *)
    | vk when vk >= 0x31 && vk <= 0x39 -> vk - 0x31 + 30 (* 1-9 *)
    | 0x60 -> 98                                       (* numpad 0 *)
    | vk when vk >= 0x61 && vk <= 0x69 -> vk - 0x61 + 89 (* numpad 1-9 *)
    | 0x6A -> 85    (* VK_MULTIPLY → KP_MULTIPLY *)
    | 0x6B -> 87    (* VK_ADD → KP_PLUS *)
    | 0x6D -> 86    (* VK_SUBTRACT → KP_MINUS *)
    | 0x6E -> 99    (* VK_DECIMAL → KP_PERIOD *)
    | 0x6F -> 84    (* VK_DIVIDE → KP_DIVIDE *)
    | vk when vk >= 0x70 && vk <= 0x7B -> vk - 0x70 + 58  (* F1-F12 *)
    | vk when vk >= 0x7C && vk <= 0x87 -> vk - 0x7C + 104 (* F13-F24 *)
    | 0x10 -> 225   (* VK_SHIFT → LSHIFT *)
    | 0x11 -> 224   (* VK_CONTROL → LCTRL *)
    | 0x12 -> 226   (* VK_MENU → LALT *)
    | 0x14 -> 57    (* VK_CAPITAL → CAPSLOCK *)
    | 0x5B -> 227   (* VK_LWIN → LGUI *)
    | 0x5C -> 231   (* VK_RWIN → RGUI *)
    | 0x5D -> 101   (* VK_APPS → APPLICATION *)
    | 0x2C -> 70    (* VK_SNAPSHOT → PRINTSCREEN *)
    | 0x2D -> 73    (* VK_INSERT → INSERT *)
    | 0x13 -> 72    (* VK_PAUSE → PAUSE *)
    | 0x90 -> 83    (* VK_NUMLOCK → NUMLOCKCLEAR *)
    | 0x91 -> 71    (* VK_SCROLL → SCROLLLOCK *)
    | 0xA0 -> 225 | 0xA1 -> 229       (* L/R SHIFT *)
    | 0xA2 -> 224 | 0xA3 -> 228       (* L/R CONTROL *)
    | 0xA4 -> 226 | 0xA5 -> 230       (* L/R MENU (alt) *)
    | 0xBA -> 51    (* VK_OEM_1 → SEMICOLON *)
    | 0xBB -> 46    (* VK_OEM_PLUS → EQUALS *)
    | 0xBC -> 54    (* VK_OEM_COMMA → COMMA *)
    | 0xBD -> 45    (* VK_OEM_MINUS → MINUS *)
    | 0xBE -> 55    (* VK_OEM_PERIOD → PERIOD *)
    | 0xBF -> 56    (* VK_OEM_2 → SLASH *)
    | 0xC0 -> 53    (* VK_OEM_3 → GRAVE *)
    | 0xDB -> 47    (* VK_OEM_4 → LEFTBRACKET *)
    | 0xDC -> 49    (* VK_OEM_5 → BACKSLASH *)
    | 0xDD -> 48    (* VK_OEM_6 → RIGHTBRACKET *)
    | 0xDE -> 52    (* VK_OEM_7 → APOSTROPHE *)
    | n -> n

  (* Win32 virtual-key codes → keys in the same space
     [key_of_sdl_scancode] produces: named keys map to their variant,
     the rest become [Other] of the SDL scancode above. *)
  let key_of_win32_vk = function
    | 0x0D -> Return (* VK_RETURN — keypad-enter is the same VK *)
    | 0x1B -> Escape
    | 0x08 -> Backspace
    | 0x2E -> Delete
    | 0x09 -> Tab
    | 0x20 -> Space
    | 0x24 -> Home
    | 0x21 -> Page_up
    | 0x22 -> Page_down
    | 0x23 -> End
    | 0x25 -> Arrow_left
    | 0x27 -> Arrow_right
    | 0x26 -> Arrow_up
    | 0x28 -> Arrow_down
    | vk -> Other (sdl_scancode_of_win32_vk vk)
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

let kind_name = Lui_query.kind_name
let kind_of = Lui_query.kind_of

(* Enabled unless the prop explicitly says otherwise — mirrors the
   paint pipeline's disabled fold (BoolValue false or "false"). *)
let node_enabled = Lui_query.node_enabled
let pointer_enabled = Lui_query.pointer_enabled
let bool_prop = Lui_query.bool_prop
let string_prop = Lui_query.string_prop

(* The only properties dispatch admission consults. *)
let event_supported = Lui_query.event_supported

(* hit_path's per-node flag memo lives in Lui_query — a pure function
   of (store, revision) shared by pointer and drop paths. *)
let hit_path = Lui_query.hit_path
let hit = Lui_query.hit
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
    (* Pixel-snapping contract: stored geometry is edge-snapped once at
       production so the hit-test mirror, scroll extents, clip and
       caret share the rasterizer's device-pixel edges. Children lay
       out inside the snapped box. *)
    let r = rect_snap r in
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
  (* Interaction runtime composed out of the platform-neutral
     machines in the lui_input library. Each subsystem — pointer
     tracking, focus/autofocus, the editable text session, the
     static-text selection, list highlight/typeahead, scroll offsets
     and visible-range reports, drag & drop, overlays and menus —
     is a pure state machine: an input goes in, a next state plus
     intents comes out. This record is the composer: it owns the
     machine states and the driver-wired hooks, sequences the
     machines for each input and performs the intents they return
     (dispatches, focus moves, scroll ops, store mirrors, repaints). *)

  type caret_ops = {
    c_before : int -> int;
    c_after : int -> int;
    c_up : int -> int;
    c_down : int -> int;
    c_rect : int -> float * float * float;
  }

  (* Layout-engine forwards for virtual-list math: item counts,
     content-space item rects (mounted or not), key → index lookup
     and the last fed viewport — the pieces scroll-target,
     visible-range and reveal logic need on logical items. The
     record is defined in {!Lui_scroll} — the machine that consumes
     it — and re-exported here for the drivers that install it. *)
  type vlist_hook = Lui_scroll.vlist = {
    vh_count : int -> int option;
    vh_item : int -> index:int -> rect option;
    vh_index_of_key : int -> string -> int option;
    vh_view : int -> (float * float) option;
  }

  type t = {
    mutable scale : float;
    mutable dirty : bool;
    mutable sync_rev : int;    (* last synced Lui_store.revision *)
    mutable sync_menu : int;   (* open_menu as of last sync *)
    mutable rects_epoch : int;
    mutable measure : Lui_store.t -> int -> string -> float * float;
    mutable hit_text :
      (Lui_store.t -> int -> string -> lx:float -> ly:float ->
       lw:float -> lh:float -> int) option;
    mutable caret_ops :
      (Lui_store.t -> int -> string -> lw:float -> lh:float ->
       caret_ops) option;
    mutable content_rect : int -> rect;
    (* Layout engine forwards for virtual-list math, consumed by the
       scroll machine through {!senv}. *)
    mutable vlist_hook : Lui_scroll.vlist option;
    (* composed machine states — see platform/native/lui_input *)
    mutable pointer : Lui_pointer.state;
    mutable focus : Lui_focus.state;
    mutable session : Lui_text_input.state;
    mutable selection : Lui_selection.state;
    mutable gesture : Lui_gesture.state;
    mutable scroll : Lui_scroll.state;
    mutable drag : Lui_drag.state;
    mutable overlay : Lui_overlay.state;
    (* Paint-hint channels for the retained fragment pass: scroll
       containers whose offset moved this frame (their whole subtree
       re-derives — ops embed shifted rects), containers whose
       scrollable range changed (thumb metrics only), and the
       interaction snapshot the last hints diff ran against. *)
    scrolled : (int, unit) Hashtbl.t;
    scroll_metrics : (int, unit) Hashtbl.t;
    mutable paint_snap : snap;
  }

  and snap = {
    ps_hovered : int;
    ps_pressed : int;
    ps_focused : int;
    ps_drop_target : int;
    ps_drag_src : int;
    ps_hl : int;
    ps_menu : int;
    ps_caret : int;
    ps_anchor : int;
    ps_sel_text : (int * int * int * int) option;
    ps_marked : string;
    ps_shadow : string;
    ps_focus_vis : bool;
  }

  let create () =
    { scale = 1.; dirty = true; sync_rev = -1; sync_menu = -1;
      rects_epoch = 0;
      measure =
        (fun _store _id s -> (8. *. float (String.length s), 16.));
      hit_text = None; caret_ops = None;
      content_rect = (fun _ -> rect 0. 0. 0. 0.);
      vlist_hook = None;
      pointer = Lui_pointer.initial;
      focus = Lui_focus.initial;
      session = Lui_text_input.initial;
      selection = Lui_selection.initial;
      gesture = Lui_gesture.initial;
      scroll = Lui_scroll.initial;
      drag = Lui_drag.initial;
      overlay = Lui_overlay.initial;
      scrolled = Hashtbl.create 8;
      scroll_metrics = Hashtbl.create 8;
      paint_snap =
        { ps_hovered = 0; ps_pressed = 0; ps_focused = 0;
          ps_drop_target = 0; ps_drag_src = 0; ps_hl = 0; ps_menu = 0;
          ps_caret = 0; ps_anchor = 0; ps_sel_text = None;
          ps_marked = ""; ps_shadow = ""; ps_focus_vis = false } }

  let set_scale t s = t.scale <- s
  let set_measure t f = t.measure <- f
  let set_hit_text t f = t.hit_text <- Some f
  let set_caret_ops t f = t.caret_ops <- Some f
  let notify_layout t = t.rects_epoch <- t.rects_epoch + 1
  let set_content_rect t f = t.content_rect <- f
  let set_vlist_hook t h = t.vlist_hook <- h

  (* ---- state accessors -------------------------------------------- *)

  let hovered t = Lui_pointer.hovered t.pointer
  let pressed t = Lui_pointer.pressed t.pointer
  let focused t = Lui_focus.focused t.focus
  let caret t = Lui_text_input.caret t.session
  let shadow t = Lui_text_input.text t.session
  let ime t = Lui_text_input.ime t.session
  let marked t = Lui_text_input.marked t.session

  (* (session id, host-local edit revision, adopted model
     revision) of the active text session — observability for the
     edit protocol. *)
  let text_revisions t =
    (Lui_text_input.session_id t.session,
     Lui_text_input.local_revision t.session,
     Lui_text_input.model_revision t.session)
  let sel_anchor t = Lui_text_input.anchor t.session
  let sel_text t = Lui_selection.text t.selection
  let focus_visible t = Lui_focus.kbd_visible t.focus
  let hl_item t = Lui_gesture.hl t.gesture
  let typeahead t = Lui_gesture.typeahead t.gesture
  let last_drop t = Lui_drag.last_drop t.drag
  let drag_active t = Lui_drag.active t.drag
  let overlay_top t = Lui_overlay.top t.overlay
  let open_menu t = Lui_overlay.open_menu t.overlay
  let pointer t = Lui_pointer.position t.pointer
  let hidden t store id = Lui_overlay.hidden store t.overlay id
  let scrollable = Lui_scroll.scrollable

  (* Scroll axes: y is the established vertical path; x adds
     horizontal range for wheel-x / shift+wheel and horizontal
     reveal. *)
  type axis = X | Y

  let conv_axis = function X -> Lui_scroll.X | Y -> Lui_scroll.Y
  let scroll_offset t = Lui_scroll.offset t.scroll Lui_scroll.Y
  let scroll_epoch t = Lui_scroll.epoch t.scroll
  let scroll_cap t = Lui_scroll.cap t.scroll Lui_scroll.Y
  let scroll_offset_x t = Lui_scroll.offset t.scroll Lui_scroll.X
  let scroll_cap_x t = Lui_scroll.cap t.scroll Lui_scroll.X

  (* Install the next scroll state, recording which containers'
     offsets moved (a moved offset shifts every descendant rect, so
     the subtree re-derives) and which caps changed (thumb metrics
     only) for the paint-hint channel. *)
  let set_scroll t (s' : Lui_scroll.state) =
    let module M = Lui_scroll.IdMap in
    let prev : Lui_scroll.state = t.scroll in
    M.iter
      (fun id o ->
        if Lui_scroll.offset s' Y id <> o then
          Hashtbl.replace t.scrolled id ())
      prev.off;
    M.iter
      (fun id o ->
        if Lui_scroll.offset prev Y id <> o then
          Hashtbl.replace t.scrolled id ())
      s'.off;
    M.iter
      (fun id o ->
        if Lui_scroll.offset s' X id <> o then
          Hashtbl.replace t.scrolled id ())
      prev.off_x;
    M.iter
      (fun id o ->
        if Lui_scroll.offset prev X id <> o then
          Hashtbl.replace t.scrolled id ())
      s'.off_x;
    M.iter
      (fun id c ->
        if Lui_scroll.cap s' Y id <> c then
          Hashtbl.replace t.scroll_metrics id ())
      prev.cap;
    M.iter
      (fun id c ->
        if Lui_scroll.cap prev Y id <> c then
          Hashtbl.replace t.scroll_metrics id ())
      s'.cap;
    M.iter
      (fun id c ->
        if Lui_scroll.cap s' X id <> c then
          Hashtbl.replace t.scroll_metrics id ())
      prev.cap_x;
    M.iter
      (fun id c ->
        if Lui_scroll.cap prev X id <> c then
          Hashtbl.replace t.scroll_metrics id ())
      s'.cap_x;
    t.scroll <- s'

  let set_scroll_cap_axis t axis id cap =
    (* Snapped-geometry contract: the scrollable range lives on the
       same device-pixel edges as the rects it derives from — a
       fractional remainder rounds out instead of becoming phantom
       scroll range. *)
    let cap = Float.max 0. (Lui_scene.snap cap) in
    let s', m = Lui_scroll.set_cap t.scroll axis id cap in
    set_scroll t s';
    (* a clamped offset repaints — the intent can only be Repaint *)
    if m <> [] then t.dirty <- true

  let set_scroll_cap t = set_scroll_cap_axis t Lui_scroll.Y
  let set_scroll_cap_x t = set_scroll_cap_axis t Lui_scroll.X

  (* ---- driver hooks packaged for the machines ----------------------- *)

  (* The caret model's record is the same shape under a different
     owner — it converts field by field. *)
  let hooks t : Lui_query.text_hooks =
    { Lui_query.measure = t.measure;
      hit_text = t.hit_text;
      caret_ops =
        (match t.caret_ops with
         | Some f ->
           Some
             (fun store id s ~lw ~lh ->
                let o = f store id s ~lw ~lh in
                { Lui_query.c_before = o.c_before;
                  c_after = o.c_after; c_up = o.c_up;
                  c_down = o.c_down; c_rect = o.c_rect })
         | None -> None);
      scale = t.scale }

  let senv t : Lui_scroll.env =
    { Lui_scroll.content_rect = t.content_rect;
      rects_epoch = t.rects_epoch;
      vlist = t.vlist_hook }

  (* The public [Input] vocabulary predates the machines' own event
     types — identical shapes, so the boundary converts. *)
  let conv_key : Input.key -> Lui_input.key = function
    | Input.Return -> Lui_input.Return
    | Input.Escape -> Lui_input.Escape
    | Input.Backspace -> Lui_input.Backspace
    | Input.Delete -> Lui_input.Delete
    | Input.Tab -> Lui_input.Tab
    | Input.Space -> Lui_input.Space
    | Input.Arrow_left -> Lui_input.Arrow_left
    | Input.Arrow_right -> Lui_input.Arrow_right
    | Input.Arrow_up -> Lui_input.Arrow_up
    | Input.Arrow_down -> Lui_input.Arrow_down
    | Input.Home -> Lui_input.Home
    | Input.End -> Lui_input.End
    | Input.Page_up -> Lui_input.Page_up
    | Input.Page_down -> Lui_input.Page_down
    | Input.Other n -> Lui_input.Other n

  let conv_mods (m : Input.mods) : Lui_input.mods =
    { Lui_input.ctrl = m.Input.ctrl; shift = m.Input.shift;
      alt = m.Input.alt; meta = m.Input.meta }

  let dummy_detail = Lui_query.dummy_detail

  let detail_of store id x y mods button =
    Lui_query.detail_of store id x y (conv_mods mods) button

  (* Every focus move flows through here: the focus machine records
     it, the text session re-attaches to the node's prop (its live
     composition cancels silently — marked text was never
     dispatched, so local rollback is the whole of it), and the
     static selection and editable undo reset — those are owned by
     the focused node. Callers emit [Focus_changed] when it moved. *)
  let focus_move ?(kbd = false) t store id =
    if id <> Lui_focus.focused t.focus then begin
      t.focus <- Lui_focus.set t.focus ~id ~kbd;
      t.session <-
        Lui_text_input.attach t.session ~node:id
          ~text:(if id = 0 then "" else Lui_query.text_of store id);
      t.selection <- Lui_selection.clear t.selection;
      t.dirty <- true
    end

  let set_focused ?(kbd = false) t store id = focus_move ~kbd t store id

  (* Perform one machine intent: side effects land on the composer
     state here and the driver-facing [action] list comes back. *)
  let rec perform t store = function
    | `Dispatch e -> [ Dispatch e ]
    | `Repaint -> t.dirty <- true; []
    | `Focus (id, kbd) ->
      if id <> Lui_focus.focused t.focus then begin
        focus_move ~kbd t store id;
        [ Focus_changed id ]
      end else []
    | `Clear_selection ->
      t.selection <- Lui_selection.clear t.selection;
      t.dirty <- true;
      []
    | `Mirror_text (id, s) ->
      (if Lui_query.retains_text store id then
         Lui_store.apply_op store
           (SetProp (id, TextValue, StringValue s)));
      []
    | `Ime_rect r -> [ Ime_rect r ]
    | `Scroll_show id ->
      let s', m = Lui_scroll.scroll_show (senv t) store t.scroll id in
      set_scroll t s';
      perform_all t store m
    | `Scroll_by (axis, id, d) ->
      let s', m =
        Lui_scroll.scroll_by ~axis (senv t) store t.scroll id d
      in
      set_scroll t s';
      perform_all t store m
  and perform_all t store m_acts =
    List.concat_map (perform t store) m_acts

  (* The text a copy/cut puts on the clipboard: the static
     selection's joined string, else the focused editable's
     selection slice. *)
  let active_sel_text t store =
    match Lui_selection.selected_text store t.selection with
    | Some s -> Some s
    | None ->
      if Lui_text_input.editable store (Lui_focus.focused t.focus)
      then begin
        let lo = Lui_text_input.sel_lo t.session
        and hi = Lui_text_input.sel_hi t.session in
        if hi > lo then
          Some
            (String.sub (Lui_text_input.text t.session) lo (hi - lo))
        else None
      end else None

  (* The sync half, run on store revisions and before each input:
     dead-focus cleanup, model-side text adoption, the modal
     focus-scope transition, autofocus inside the top overlay's
     scope, the Appear lifecycle and scroll bookkeeping. Intents go
     through [perform]; dispatches land in action order. *)
  let sync t store =
    let acts = ref [] in
    let run m_acts =
      List.iter
        (fun m ->
           acts := List.rev_append (perform t store m) !acts)
        m_acts
    in
    let rev = Lui_store.revision store in
    if rev <> t.sync_rev
       || Lui_overlay.open_menu t.overlay <> t.sync_menu
    then begin
      t.sync_rev <- rev;
      t.sync_menu <- Lui_overlay.open_menu t.overlay;
      run (Lui_focus.sync_dead store t.focus);
      (let n = Lui_focus.focused t.focus in
       if n <> 0 && Lui_query.retains_text store n then begin
         let s', m =
           Lui_text_input.sync_model store t.session
             ~model_text:(Lui_query.text_of store n)
         in
         t.session <- s';
         run m
       end);
      (let ov', m =
         Lui_overlay.sync store t.overlay
           ~focused:(Lui_focus.focused t.focus)
       in
       t.overlay <- ov';
       run m);
      (let f', cand =
         Lui_focus.scan_autofocus store t.focus
           ~scope:(Lui_overlay.top t.overlay)
       in
       t.focus <- f';
       match cand with
       | Some id when id <> Lui_focus.focused t.focus ->
         focus_move t store id;
         acts := Focus_changed id :: !acts
       | _ -> ());
      (let f', m = Lui_focus.scan_appear store t.focus in
       t.focus <- f';
       run m);
      let s', m = Lui_scroll.sync (senv t) store t.scroll in
      set_scroll t s';
      run m
    end;
    (* visible-range reports follow scroll offsets, which live in
       the machine rather than the store — they run on every sync,
       memoized on their inputs *)
    (let s', m = Lui_scroll.report_tracked (senv t) store t.scroll in
     set_scroll t s';
     run m);
    List.rev !acts

  let store_changed t store = sync t store

  let handle t store rects input =
    let acts = ref [] in
    let emit_all l = acts := List.rev_append l !acts in
    let run m_acts = emit_all (perform_all t store m_acts) in
    emit_all (sync t store);
    (match input with
     | Input.Move (x, y) ->
       t.pointer <- Lui_pointer.note_pos t.pointer ~x ~y;
       let dx, dy = x *. t.scale, y *. t.scale in
       if Lui_drag.active t.drag then begin
         (* live drop-target tracking while a drag is in flight *)
         let path = hit_path store rects ~x:dx ~y:dy in
         let d, m = Lui_drag.track store t.drag ~path in
         t.drag <- d;
         run m
       end else begin
         match Lui_drag.promote store t.drag ~x ~y with
         | Some (d, m) ->
           (* threshold crossed: the grab becomes a drag session *)
           t.drag <- d;
           t.selection <- Lui_selection.clear_drag t.selection;
           run m
         | None ->
           if Lui_selection.drag_id t.selection <> 0 then begin
             (* drag-select: the focus endpoint follows the pointer
                across the anchor's selectable siblings, or inside
                the focused editable *)
             (match Lui_selection.text t.selection with
              | Some _ ->
                let s', m =
                  Lui_selection.drag_move (hooks t) store rects
                    t.selection ~x:dx ~y:dy
                in
                t.selection <- s';
                run m
              | None
                when Lui_selection.drag_id t.selection
                     = Lui_focus.focused t.focus ->
                let s', m =
                  Lui_text_input.point_move (hooks t) store rects
                    t.session ~x:dx ~y:dy
                in
                t.session <- s';
                run m
              | None -> t.dirty <- true)
           end else begin
             let path = hit_path store rects ~x:dx ~y:dy in
             let p, m = Lui_pointer.move store t.pointer ~path ~x ~y in
             t.pointer <- p;
             run m
           end
       end
     | Input.Button_down (x, y, btn, clicks, mods) ->
       t.pointer <- Lui_pointer.note_pos t.pointer ~x ~y;
       (match btn with
        | Input.Left ->
          let dx, dy = x *. t.scale, y *. t.scale in
          let path = hit_path store rects ~x:dx ~y:dy in
          t.drag <- Lui_drag.note_down t.drag ~x ~y;
          t.gesture <- Lui_gesture.reset_typeahead t.gesture;
          (* a press outside the open menu closes it host-side *)
          (let ov', m =
             Lui_overlay.close_on_outside_press store t.overlay path
           in
           t.overlay <- ov';
           run m);
          (* overlay press semantics: a modal surface swallows
             outside presses entirely; a light-dismissible one
             emits its Dismiss *)
          (match Lui_overlay.press store t.overlay path with
           | ov', `Swallow -> t.overlay <- ov'
           | ov', `Proceed dismiss ->
             t.overlay <- ov';
             emit_all (perform_all t store dismiss);
             let focus =
               match Lui_query.focus_target store path with
               | Some id -> id
               | None -> 0
             in
             (if focus <> Lui_focus.focused t.focus then begin
                focus_move t store focus;
                emit_all [ Focus_changed focus ]
              end);
             (* Selection: click sets the caret, shift-click
                extends, double/triple click selects word/paragraph
                — on editable fields and user-select=text nodes
                alike. *)
             (if focus <> 0 && List.mem focus path then begin
                let s', _m =
                  Lui_text_input.press (hooks t) store rects t.session
                    ~x:dx ~y:dy ~clicks ~shift:mods.Input.shift
                in
                t.session <- s';
                t.selection <-
                  Lui_selection.arm_drag
                    (Lui_selection.clear t.selection) focus
              end
              else if
                List.exists
                  (fun i -> Lui_query.selectable_text store i) path
              then begin
                let s', m =
                  Lui_selection.press (hooks t) store rects t.selection
                    ~path ~clicks ~shift:mods.Input.shift ~x:dx ~y:dy
                in
                t.selection <- s';
                run m
              end else
                t.selection <-
                  Lui_selection.clear_drag
                    (Lui_selection.press_none t.selection
                       ~shift:mods.Input.shift));
             t.drag <- Lui_drag.arm store t.drag ~path;
             let p, m =
               Lui_pointer.down store t.pointer ~path ~x ~y
                 ~button:Lui_input.Left ~clicks ~mods:(conv_mods mods)
             in
             t.pointer <- p;
             (* list context: the innermost scrollable ancestor with
                items under the pointer owns typeahead/arrows; a
                pressed list-item becomes the highlight *)
             t.gesture <-
               Lui_gesture.note_list_context store t.gesture ~path;
             t.dirty <- true;
             run m)
        | Input.Right ->
          let dx, dy = x *. t.scale, y *. t.scale in
          let path = hit_path store rects ~x:dx ~y:dy in
          let p, m =
            Lui_pointer.down store t.pointer ~path ~x ~y
              ~button:Lui_input.Right ~clicks ~mods:(conv_mods mods)
          in
          t.pointer <- p;
          run m
        | _ -> ())
     | Input.Button_up (x, y, btn, mods) ->
       t.pointer <- Lui_pointer.note_pos t.pointer ~x ~y;
       (match btn with
        | Input.Left when Lui_drag.active t.drag ->
          (* the drop completes on the accepting target under the
             pointer; the click it rode on is consumed *)
          let d, m = Lui_drag.drop t.drag in
          t.drag <- d;
          t.pointer <- Lui_pointer.clear_press t.pointer;
          t.selection <- Lui_selection.clear_drag t.selection;
          run m
        | Input.Left ->
          t.selection <- Lui_selection.clear_drag t.selection;
          t.drag <- Lui_drag.clear_arm t.drag;
          let p, up_acts =
            Lui_pointer.up store t.pointer ~x ~y
              ~button:Lui_input.Left ~mods:(conv_mods mods)
          in
          t.pointer <- p;
          emit_all (perform_all t store up_acts);
          let dx, dy = x *. t.scale, y *. t.scale in
          let path = hit_path store rects ~x:dx ~y:dy in
          let release =
            match Lui_query.press_target store path with
            | Some id -> id
            | None -> 0
          in
          (let n = Lui_pointer.pressed t.pointer in
           if n <> 0 && release = n then begin
             (if pointer_enabled store n
                 && event_supported store n
                      (PressDetail (n, dummy_detail))
              then
                acts :=
                  Dispatch
                    (PressDetail
                       (n, detail_of store n x y mods 0))
                  :: !acts);
             (* a click landing anywhere on a menu trigger toggles
                its owned panel; activating a node inside the open
                panel closes it after the press *)
             (let ov', m =
                Lui_overlay.click_menu store t.overlay ~path
                  ~pressed:n
              in
              t.overlay <- ov';
              run m);
             emit_all
               (perform_all t store
                  (Lui_query.primary_press store n));
             (* a toggle-only container owns the click even when a
                kind-pressable child was the deepest target — the
                container bubbles up *)
             (match
                List.find_opt
                  (fun i ->
                     i <> n
                     && kind_name store i = "drawer"
                     && bool_prop store i "toggle-enabled"
                     && event_supported store i
                          (ToggleChanged (i, true)))
                  path
              with
              | Some d ->
                acts :=
                  Dispatch
                    (ToggleChanged
                       (d, not (bool_prop store d "selected")))
                  :: !acts
              | None -> ())
           end);
          t.pointer <- Lui_pointer.clear_press t.pointer;
          t.dirty <- true
        | _ -> ())
     | Input.Text_input s ->
       let s', m =
         Lui_text_input.feed_ime store t.session (`Commit s)
       in
       t.session <- s';
       run m
     | Input.Text_editing (text, start, len) ->
       let s', m =
         Lui_text_input.feed_ime store t.session
           (`Editing (text, start, len))
       in
       t.session <- s';
       run m
     | Input.Caret r ->
       (* The caret is painted geometry too: it snaps to the same
          device-pixel edges as the rects it anchors on. *)
       let s', m =
         Lui_text_input.feed_ime store t.session (`Caret (rect_snap r))
       in
       t.session <- s';
       run m
     | Input.Paste s ->
       (* clipboard text the driver pulled after Paste_request *)
       if s <> "" && Lui_text_input.editable store (focused t)
       then begin
         let s', m = Lui_text_input.insert t.session s in
         t.session <- s';
         run m
       end
     | Input.Key_down (key, mods, _repeat) ->
       (* While marked text is on screen the keys belong to the
          IME — SDL filters most of them already; this gate is the
          belt. *)
       if not (Lui_text_input.composing t.session) then begin
         (* The accelerator table: "primary" is Cmd on macOS, Ctrl
            elsewhere — this host accepts either. Entries the wire
            has a channel for route through dispatch;
            clipboard/undo stay host-side (no wire event exists). *)
         let prim = mods.Input.ctrl || mods.Input.meta in
         (match key with
          | Input.Escape ->
            if Lui_drag.active t.drag then begin
              (* cancel the drag: no drop, click consumed *)
              let d, m = Lui_drag.cancel t.drag in
              t.drag <- d;
              run m
            end else begin
              (* Escape peels one layer at a time: the open menu,
                 then a dismissible overlay; a non-dismissible top
                 overlay eats the key. *)
              let ov', res = Lui_overlay.escape store t.overlay in
              t.overlay <- ov';
              (match res with
               | `Closed_menu -> t.dirty <- true
               | `Dismissed oid ->
                 acts := Dispatch (Dismiss oid) :: !acts
               | `Blocked -> ()
               | `Pass ->
                 if Lui_focus.focused t.focus <> 0 then begin
                   focus_move t store 0;
                   acts := Focus_changed 0 :: !acts
                 end else acts := Quit :: !acts)
            end
          | Input.Other 4 when prim ->
            (* A: select all — the editable range, or every
               selectable sibling in the static selection's
               container *)
            if Lui_text_input.editable store (focused t) then begin
              let s', m = Lui_text_input.select_all t.session in
              t.session <- s';
              run m
            end else begin
              let s', m =
                Lui_selection.select_all store t.selection
              in
              t.selection <- s';
              run m
            end
          | Input.Other 6 when prim ->
            (match active_sel_text t store with
             | Some s -> acts := Clipboard_write s :: !acts
             | None -> ())
          | Input.Other 27 when prim ->
            if Lui_text_input.editable store (focused t) then
              (match active_sel_text t store with
               | Some s ->
                 acts := Clipboard_write s :: !acts;
                 let s', m = Lui_text_input.splice t.session "" in
                 t.session <- s';
                 run m
               | None -> ())
          | Input.Other 25 when prim ->
            if Lui_text_input.editable store (focused t)
            then acts := Paste_request :: !acts
          | Input.Other 29 when prim ->
            if Lui_text_input.editable store (focused t) then begin
              let s', m =
                Lui_text_input.undo t.session ~shift:mods.Input.shift
              in
              t.session <- s';
              run m
            end
          | Input.Tab ->
            let dir = if mods.Input.shift then -1 else 1 in
            let next =
              Lui_focus.step store
                ~scope:(Lui_overlay.modal_scope store t.overlay)
                ~cur:(Lui_focus.focused t.focus) ~dir
            in
            if next <> 0 && next <> Lui_focus.focused t.focus
            then begin
              focus_move ~kbd:true t store next;
              acts := Focus_changed next :: !acts;
              let s', m =
                Lui_scroll.scroll_show (senv t) store t.scroll next
              in
              set_scroll t s';
              run m
            end
          | _ ->
            if Lui_text_input.editable store (focused t) then begin
              let s', m =
                Lui_text_input.key (hooks t) store rects t.session
                  ~k:(conv_key key) ~mods:(conv_mods mods) ~prim
              in
              t.session <- s';
              run m
            end
            else if Lui_focus.focused t.focus <> 0 then begin
              let g', m =
                Lui_gesture.control_key store t.gesture
                  ~node:(Lui_focus.focused t.focus)
                  ~key:(conv_key key) ~mods:(conv_mods mods)
              in
              t.gesture <- g';
              run m
            end else begin
              let scope =
                Option.value ~default:0
                  (Lui_overlay.modal_scope store t.overlay)
              in
              let g', m =
                Lui_gesture.list_key store t.gesture ~scope
                  ~content_rect:t.content_rect ~key:(conv_key key)
                  ~mods:(conv_mods mods)
              in
              t.gesture <- g';
              run m
            end)
       end
     | Input.Resize (w, h) -> acts := Resize_host (w, h) :: !acts
     | Input.Wheel (dx, dy) ->
       let sx, sy = Lui_pointer.position t.pointer in
       let path =
         hit_path store rects ~x:(sx *. t.scale)
           ~y:(sy *. t.scale)
       in
       let s', m =
         Lui_scroll.wheel (senv t) store t.scroll ~path
           ~scale:t.scale ~dx ~dy ~mods:Lui_input.mods_none
       in
       set_scroll t s';
       run m
     | Input.Wheel_mods (dx, dy, mods) ->
       let sx, sy = Lui_pointer.position t.pointer in
       let path =
         hit_path store rects ~x:(sx *. t.scale)
           ~y:(sy *. t.scale)
       in
       let s', m =
         Lui_scroll.wheel (senv t) store t.scroll ~path
           ~scale:t.scale ~dx ~dy ~mods:(conv_mods mods)
       in
       set_scroll t s';
       run m
     | Input.Drop_file p ->
       (* OS drops land at the pointer's last position on the
          deepest matching target; payloads are namespaced
          ("file:"/"text:") so data-drop-accept prefixes can tell
          them from internal drags *)
       let sx, sy = Lui_pointer.position t.pointer in
       let path =
         hit_path store rects ~x:(sx *. t.scale)
           ~y:(sy *. t.scale)
       in
       let d, m =
         Lui_drag.os_drop store t.drag ~path ~payload:("file:" ^ p)
       in
       t.drag <- d;
       run m
     | Input.Drop_text s ->
       let sx, sy = Lui_pointer.position t.pointer in
       let path =
         hit_path store rects ~x:(sx *. t.scale)
           ~y:(sy *. t.scale)
       in
       let d, m =
         Lui_drag.os_drop store t.drag ~path ~payload:("text:" ^ s)
       in
       t.drag <- d;
       run m
     | Input.Quit_input -> acts := Quit :: !acts);
    List.rev !acts

  let state_of t store id =
    { Lui_paint.hovered =
        (Lui_pointer.hovered t.pointer = id
         || Lui_drag.target t.drag = id);
      pressed =
        (Lui_pointer.pressed t.pointer = id
         || Lui_drag.source t.drag = id);
      focused = Lui_focus.focused t.focus = id;
      selected =
        (bool_prop store id "selected" || Lui_gesture.hl t.gesture = id);
      disabled = not (node_enabled store id) }

  (* Ids whose paint inputs moved outside the store journal: the
     interaction-state slots [state_of] reads, the editing session
     behind the focused node's text ops, menu visibility, and every
     scroll container that moved — a moved offset shifts all
     descendant rects (ops embed them), so the whole subtree
     re-derives. Drains the scroll tables and rolls the snapshot. *)
  (* Returns (hard, soft): hard ids re-plan (interaction state, caret,
     metric thumbs); soft ids merely shifted — scrolled subtrees move
     under unchanged props, so the fragment pass may translate their
     cached ops instead. *)
  let paint_hints t store =
    let h = Hashtbl.create 16 in
    let soft = Hashtbl.create 16 in
    let mark id = if id <> 0 then Hashtbl.replace h id () in
    let mark_soft id = if id <> 0 then Hashtbl.replace soft id () in
    let s = t.paint_snap in
    let drag_src = Lui_drag.source t.drag
    and drop_target = Lui_drag.target t.drag in
    if s.ps_hovered <> hovered t then (mark s.ps_hovered; mark (hovered t));
    if s.ps_pressed <> pressed t then (mark s.ps_pressed; mark (pressed t));
    if s.ps_focused <> focused t then (mark s.ps_focused; mark (focused t));
    if s.ps_drop_target <> drop_target then
      (mark s.ps_drop_target; mark drop_target);
    if s.ps_drag_src <> drag_src then (mark s.ps_drag_src; mark drag_src);
    if s.ps_hl <> hl_item t then (mark s.ps_hl; mark (hl_item t));
    if s.ps_menu <> open_menu t then (mark s.ps_menu; mark (open_menu t));
    (* Caret/selection/marked/shadow ride the focused node's text
       ops; the ring channel reads focus_visible. *)
    if
      s.ps_caret <> caret t || s.ps_anchor <> sel_anchor t
      || s.ps_marked <> marked t || s.ps_shadow <> shadow t
      || s.ps_focus_vis <> focus_visible t
    then mark (focused t);
    if s.ps_sel_text <> sel_text t then begin
      (match s.ps_sel_text with
       | Some (a, _, b, _) -> mark a; mark b
       | None -> ());
      (match sel_text t with
       | Some (a, _, b, _) -> mark a; mark b
       | None -> ())
    end;
    (* Moved offset: the container's thumb is a hard repaint; every
       descendant just translates. *)
    Hashtbl.iter
      (fun id () ->
        mark id;
        List.iter mark_soft (Lui_store.preorder ~root:id store))
      t.scrolled;
    Hashtbl.reset t.scrolled;
    (* Range-only change: the thumb metrics, nothing below. *)
    Hashtbl.iter (fun id () -> mark id) t.scroll_metrics;
    Hashtbl.reset t.scroll_metrics;
    t.paint_snap <-
      { ps_hovered = hovered t; ps_pressed = pressed t;
        ps_focused = focused t; ps_drop_target = drop_target;
        ps_drag_src = drag_src; ps_hl = hl_item t;
        ps_menu = open_menu t; ps_caret = caret t;
        ps_anchor = sel_anchor t; ps_sel_text = sel_text t;
        ps_marked = marked t; ps_shadow = shadow t;
        ps_focus_vis = focus_visible t };
    (h, soft)

  let scroll_to ?(axis = Y) t store id off =
    let s', m =
      Lui_scroll.scroll_to ~axis:(conv_axis axis) (senv t) store
        t.scroll id off
    in
    set_scroll t s';
    perform_all t store m

  let scroll_by ?(axis = Y) t store id d =
    let s', m =
      Lui_scroll.scroll_by ~axis:(conv_axis axis) (senv t) store
        t.scroll id d
    in
    set_scroll t s';
    perform_all t store m

  let drop_accepts = Lui_query.drop_accepts

  let scroll_show t store id =
    let s', m = Lui_scroll.scroll_show (senv t) store t.scroll id in
    set_scroll t s';
    perform_all t store m

  (* Repaint pacing: the open menu changing under a fixed layout
     needs a layout invalidation before the next frame. *)
  let want_frame t host =
    if Lui_overlay.menu_moved t.overlay then begin
      Lui_host.invalidate_layout host;
      t.overlay <- Lui_overlay.menu_laid_out t.overlay
    end;
    t.dirty || Lui_host.wants_repaint host

  let frame_done t = t.dirty <- false
end

module Theme = struct
  let color = color

  (* Dark token table — mirrors the canonical dark tokens in
     platform/native/lui_theme; the lui_theme test cross-checks it. *)
  let palette =
    [ ("background", color 24 24 27 255);
      ("foreground", color 244 244 245 255);
      ("text", color 244 244 245 255);
      ("text-muted", color 161 161 170 255);
      ("card", color 39 39 42 255);
      ("card-foreground", color 244 244 245 255);
      ("popover", color 39 39 42 255);
      ("popover-foreground", color 244 244 245 255);
      ("surface", color 39 39 42 255);
      ("surface-hover", color 50 50 54 255);
      ("surface-pressed", color 60 60 65 255);
      ("primary", color 59 130 246 255);
      ("primary-foreground", color 255 255 255 255);
      ("secondary", color 39 39 42 255);
      ("secondary-foreground", color 244 244 245 255);
      ("muted", color 39 39 42 255);
      ("muted-foreground", color 161 161 170 255);
      ("accent", color 59 130 246 255);
      ("accent-hover", color 96 165 250 255);
      ("accent-pressed", color 37 99 235 255);
      ("accent-text", color 255 255 255 255);
      ("accent-foreground", color 255 255 255 255);
      (* the surface-gray the old "accent" name meant; apps wanting the
         shadcn hover surface use this. *)
      ("accent-surface", color 50 50 54 255);
      ("destructive", color 239 68 68 255);
      ("destructive-foreground", color 255 255 255 255);
      ("danger", color 239 68 68 255);
      ("warning", color 245 158 11 255);
      ("success", color 34 197 94 255);
      ("border", color 63 63 70 255);
      ("control-border", color 108 108 114 255);
      ("switch-track", color 91 91 97 255);
      ("input", color 63 63 70 255);
      ("ring", color 96 165 250 153);
      ("focus", color 96 165 250 153);
      ("selection", color 59 130 246 102);
      ("scrollbar-thumb", color 255 255 255 89);
      ("inverse", color 244 244 245 255);
      ("inverse-foreground", color 24 24 27 255);
      ("scrim", color 0 0 0 128) ]

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

  (* CSS rgb()/rgba() functional notation — comma-separated
     (rgba(67, 63, 56, 0.25)) and modern space/slash forms. *)
  let color_of_fn name =
    let n = String.length name in
    let body pre =
      String.length pre < n
      && String.sub name 0 (String.length pre) = pre
      && name.[n - 1] = ')'
    in
    let inner pre =
      String.sub name (String.length pre) (n - String.length pre - 1)
    in
    let split ch s =
      String.split_on_char ch s
      |> List.map String.trim
      |> List.filter (fun t -> t <> "")
    in
    let chan t =
      let pct = String.length t > 0 && t.[String.length t - 1] = '%' in
      match
        float_of_string_opt
          (if pct then String.sub t 0 (String.length t - 1) else t)
      with
      | Some v -> Some (int_of_float (Float.round (if pct then v *. 2.55 else v)))
      | None -> None
    in
    let alpha t =
      let pct = String.length t > 0 && t.[String.length t - 1] = '%' in
      match
        float_of_string_opt
          (if pct then String.sub t 0 (String.length t - 1) else t)
      with
      | Some v ->
        Some
          (int_of_float
             (Float.round
                (if pct then v *. 2.55
                 else if v <= 1. then v *. 255.
                 else v)))
      | None -> None
    in
    let emit comps a =
      match List.map chan comps with
      | [ Some r; Some g; Some b ] ->
        Some (color r g b (Option.value a ~default:255))
      | _ -> None
    in
    (* CSS hsl()/hsla() — comma-separated (hsla(10, 78%, 54%, 0.9)) and
       modern space/slash forms; hue in degrees, s/l percents. *)
    let pct_num t =
      let n = String.length t in
      if n > 0 && t.[n - 1] = '%' then
        float_of_string_opt (String.sub t 0 (n - 1))
      else None
    in
    let hsl_emit comps a =
      let hue t =
        let t =
          if String.ends_with ~suffix:"deg" t then
            String.sub t 0 (String.length t - 3)
          else t
        in
        float_of_string_opt t
      in
      match comps with
      | [ h; s; l ] -> (
        match hue h, pct_num s, pct_num l with
        | Some h, Some s, Some l ->
          let h =
            let h = Float.rem h 360. in
            if h < 0. then h +. 360. else h
          in
          let s = Float.max 0. (Float.min 1. (s /. 100.)) in
          let l = Float.max 0. (Float.min 1. (l /. 100.)) in
          let c = (1. -. Float.abs (2. *. l -. 1.)) *. s in
          let hp = h /. 60. in
          let x = c *. (1. -. Float.abs (Float.rem hp 2. -. 1.)) in
          let r1, g1, b1 =
            if hp < 1. then (c, x, 0.)
            else if hp < 2. then (x, c, 0.)
            else if hp < 3. then (0., c, x)
            else if hp < 4. then (0., x, c)
            else if hp < 5. then (x, 0., c)
            else (c, 0., x)
          in
          let m = l -. (c /. 2.) in
          let ch v = int_of_float (Float.round ((v +. m) *. 255.)) in
          Some
            (color (ch r1) (ch g1) (ch b1) (Option.value a ~default:255))
        | _ -> None)
      | _ -> None
    in
    let pre, is_hsl =
      if body "hsla(" then (Some "hsla(", true)
      else if body "hsl(" then (Some "hsl(", true)
      else if body "rgba(" then (Some "rgba(", false)
      else if body "rgb(" then (Some "rgb(", false)
      else (None, false)
    in
    match pre with
    | None -> None
    | Some p -> (
      let emit = if is_hsl then hsl_emit else emit in
      let inner = inner p in
      match split ',' inner with
      | [ a; b; c ] -> emit [ a; b; c ] None
      | [ a; b; c; d ] -> emit [ a; b; c ] (alpha d)
      | _ -> (
        match split '/' inner with
        | [ core ] -> emit (split ' ' core) None
        | [ core; a ] -> emit (split ' ' core) (alpha a)
        | _ -> None))

  let color_of name =
    match List.assoc_opt name palette with
    | Some c -> Some c
    | None -> (
      if name = "transparent" then Some (color 0 0 0 0)
      else
        match color_of_hex name with
        | Some _ as c -> c
        | None -> color_of_fn name)
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

module Frame = struct
  (* Per-surface frame scheduler — the "mark dirty → frame callback →
     present" half of the pipeline contract

       event → action queue → stabilize → patch flush → mark dirty →
       frame callback → layout/scene → present

     Mutations never draw: they [request_frame]. The driver's frame
     callback [poll]s and only a [Present] decision lays out, rebuilds
     the scene and presents. [poll] also carries the pacing contract:
     a shown surface runs at the monitor's refresh rate (a vsync
     swap paces itself, so it presents whenever dirty), a hidden or
     minimized surface is throttled to the background cadence — it
     still presents occasionally so previews and screenshots stay
     live, just ~60x cheaper — and a clean surface is [Idle], telling
     the driver it may sleep until an event wakes the loop. *)
  type visibility =
    | Shown
    | Hidden
    | Minimized

  type decision =
    | Present  (** run layout/scene/present now *)
    | Wait_ms of float  (** present pending; ms until the deadline *)
    | Idle  (** nothing pending — the loop may sleep for events *)

  type t = {
    mutable dirty : bool;
    mutable visibility : visibility;
    mutable refresh_hz : float;
    mutable bg_period_ms : float;
    mutable last_present_ms : float;
  }

  let create () =
    { dirty = true;  (* the first frame always paints *)
      visibility = Shown;
      refresh_hz = 60.;
      bg_period_ms = 250.;
      last_present_ms = Float.neg_infinity }

  let request_frame t = t.dirty <- true
  let dirty t = t.dirty
  let visibility t = t.visibility
  let refresh_hz t = t.refresh_hz

  let set_visibility t v =
    if v <> t.visibility then begin
      t.visibility <- v;
      (* Back on screen: present fresh content regardless of when the
         surface last painted. *)
      if v = Shown then t.dirty <- true
    end

  let set_refresh_hz t hz =
    if hz > 0. && hz <= 1000. then t.refresh_hz <- hz

  let set_bg_period_ms t ms =
    if ms > 0. then t.bg_period_ms <- ms

  (* The cadence a visibility allows: refresh-rate pacing while shown,
     the background period while throttled. *)
  let period_ms t =
    match t.visibility with
    | Shown -> 1000. /. t.refresh_hz
    | Hidden | Minimized -> t.bg_period_ms

  let poll t ~now_ms ~vsync =
    if not t.dirty then Idle
    else if vsync then Present
    else begin
      let next = t.last_present_ms +. period_ms t in
      if now_ms >= next then Present
      else Wait_ms (next -. now_ms)
    end

  let presented t ~now_ms =
    t.dirty <- false;
    t.last_present_ms <- now_ms
end

module Multi = struct
  (* Multi-window manager: a registry of independent surfaces. Each
     surface owns a full pipeline — host (store, layout, scene,
     renderer), interaction state ([Ui.t]) and hit-test mirror —
     so windows never share app state and every window can render a
     different view onto the same app kind. The driver payload ['d]
     keeps this layer backend-free: the SDL driver stores its OS
     window handle/context there, tests store [unit].

     Window-model decision (documented here since it shapes the whole
     design): N independent surfaces was picked over one shared store
     rendered into several windows or a wire-level window node.
     Reasons:
       - The wire protocol has no window/subtree kind; adding one
         would change shared modules and every consumer, not just
         this host.
       - [Lui_host] fuses store + layout + scene per surface; a
         shared store across windows would need scene fan-out in
         host, while independent hosts need zero core changes.
       - Independent surfaces give per-window checksums, apps and
         a11y trees for free, and closing a window tears down just
         its own pipeline.
     Cost: N windows can't show live views of one model (each has
     its own app instance). For the desktop backend that is the
     intended semantic anyway. *)

  type 'd surface = {
    mutable id : int;        (** Registry key; the SDL driver uses
                                 [SDL_GetWindowID], tests use any int.
                                 Mutable because a backend demote
                                 recreates the OS window, which mints
                                 a fresh id — see [rekey]. *)
    host : Lui_host.t;
    ui : Ui.t;
    rects : Rects.t;
    driver : 'd;
    mutable logical_w : int; (** Window size in logical units, as
                                 reported by resize events. *)
    mutable logical_h : int;
    mutable drawable_w : int; (** Backing pixels last applied. *)
    mutable drawable_h : int;
    scale_cell : float ref;  (** Backing scale drawable/logical; shared
                                 with the hooks/text engine of this
                                 surface's host. *)
    mutable display : int;   (** Display index last seen (-1 unknown);
                                 managed by the driver for monitor
                                 crossing detection. *)
  }

  type 'd t = {
    wins : (int, 'd surface) Hashtbl.t;
    mutable order : int list;  (** Registration order: deterministic
                                   iteration for tests/headless. *)
    mutable focused_id : int;  (** 0 = no window focused *)
  }

  let create () = { wins = Hashtbl.create 8; order = []; focused_id = 0 }

  let make_surface ~id ~host ~driver ~ui ~rects ~scale_cell ~w ~h =
    { id; host; ui; rects; driver;
      logical_w = w; logical_h = h;
      drawable_w = int_of_float (float w *. !scale_cell);
      drawable_h = int_of_float (float h *. !scale_cell);
      scale_cell; display = -1 }

  let register t s =
    Hashtbl.replace t.wins s.id s;
    if not (List.mem s.id t.order) then t.order <- t.order @ [ s.id ]

  let unregister t id =
    match Hashtbl.find_opt t.wins id with
    | Some s ->
      Hashtbl.remove t.wins id;
      t.order <- List.filter (fun i -> i <> id) t.order;
      if t.focused_id = id then t.focused_id <- 0;
      Some s
    | None -> None

  (* The OS window was recreated under a new id (e.g. a renderer demote
     replaces the SDL window): re-key the surface without disturbing
     registration order or the focused-window slot. *)
  let rekey t old_id new_id =
    match Hashtbl.find_opt t.wins old_id with
    | None -> false
    | Some s ->
      Hashtbl.remove t.wins old_id;
      s.id <- new_id;
      Hashtbl.replace t.wins new_id s;
      t.order <-
        List.map (fun i -> if i = old_id then new_id else i) t.order;
      if t.focused_id = old_id then t.focused_id <- new_id;
      true

  let find t id = Hashtbl.find_opt t.wins id
  let count t = List.length t.order
  let iter t f =
    List.iter
      (fun id -> match Hashtbl.find_opt t.wins id with
         | Some s -> f s
         | None -> ())
      t.order
  let focused t = t.focused_id
  let set_focused t id =
    t.focused_id <- id

  let clear_focus t = t.focused_id <- 0

  let find_focused t =
    match Hashtbl.find_opt t.wins t.focused_id with
    | Some s -> Some s
    | None -> (match t.order with
        | id :: _ -> Hashtbl.find_opt t.wins id
        | [] -> None)

  let first t =
    match t.order with
    | id :: _ -> Hashtbl.find_opt t.wins id
    | [] -> None

  let last t =
    match List.rev t.order with
    | id :: _ -> Hashtbl.find_opt t.wins id
    | [] -> None

  let any t p =
    let hit = ref false in
    iter t (fun s -> if p s then hit := true);
    !hit

  let dispatch s input = Ui.handle s.ui (Lui_host.store s.host) s.rects input

  let drawable_scale dw w =
    Float.max 0.01 (float dw /. float (max 1 w))

  let apply_logical_size s ~w ~h =
    s.logical_w <- w;
    s.logical_h <- h

  let apply_drawable s ~dw ~dh =
    let ns = drawable_scale dw s.logical_w in
    if dw = s.drawable_w && dh = s.drawable_h
       && abs_float (ns -. !(s.scale_cell)) < 0.0001
    then false
    else begin
      s.drawable_w <- dw;
      s.drawable_h <- dh;
      s.scale_cell := ns;
      Ui.set_scale s.ui ns;
      Lui_host.resize s.host ~width:dw ~height:dh ~scale:ns;
      true
    end

  let scale s = !(s.scale_cell)
end

(** Shared native host assembly: the wiring every window driver used
    to hand-roll — the real layout engine synced per repaint, paint
    hooks (theme colors, scroll metrics, IME marked-text overlay,
    shadows), trigger-menu visibility, the pointer-anchored context
    menu, the scroll-offset-shifted hit-test mirror, the scroll caps
    that let wheel input find a target, and the IME caret anchor.
    Platform drivers keep only OS event translation, window
    management and frame presentation; everything else lives here so
    macOS, Linux and Windows paint and hit-test identically. *)
module Assembly = struct
  (* The platform text engine reduced to the three callbacks the
     shared wiring needs: glyph measure for layout/caret math,
     glyph-run emission for the paint hook, and layout-accurate point
     hit resolution for caret/selection. Each driver's
     [Lui_window_text] satisfies this directly. *)
  type text = {
    measure : int -> string -> float * float;
    text_ops : int -> rect -> color -> string -> op list;
    hit_text :
      int -> string -> lx:float -> ly:float -> lw:float -> lh:float ->
      int;
    caret_ops :
      int -> string -> lw:float -> lh:float -> Ui.caret_ops;
  }

  (* [populate] and [caret_rect] are stored closures rather than
     module functions because they capture the pre-host cells
     (host_cell / shift memo / scale) the hooks also capture. *)
  type t = {
    host : Lui_host.t;
    ui : Ui.t;
    rects : Rects.t;         (* hit-test mirror, device px *)
    scale_cell : float ref;  (* shared with the hooks/text engine *)
    engine_rect : int -> rect;
        (** Unshifted engine rect — content-space input for
            [scroll_show]/visible-range. *)
    populate : unit -> action list;
        (** rebuild the hit mirror + scroll caps, fold measured anchor
            drift back into scroll offsets — the VisibleRange
            dispatches those corrections produce come back for the
            driver to apply *)
    caret_rect : unit -> rect;
        (** Focused field's caret rect, device px — candidate-window
            anchor while composing. *)
  }

  let host t = t.host
  let ui t = t.ui
  let rects t = t.rects
  let scale_cell t = t.scale_cell
  let engine_rect t = t.engine_rect
  let populate t = t.populate ()
  let caret_rect t = t.caret_rect ()
  let store t = Lui_host.store t.host
  let handle t input = Ui.handle t.ui (store t) t.rects input
  let store_changed t = Ui.store_changed t.ui (store t)

  (* One frame's paint path: the engine re-syncs inside
     [Lui_host.repaint], then the hit mirror and scroll caps are
     rebuilt from the fresh rects — always in this order, on every
     platform. Returns the frame bytes plus the actions populate's
     anchor-drift corrections produced. *)
  let repaint t =
    (* Interaction-state diffs reach the fragment pass through the
       host's hint table — the store journal cannot see them. *)
    let hard, soft = Ui.paint_hints t.ui (store t) in
    Hashtbl.iter
      (fun id () -> Lui_host.note_paint t.host id)
      hard;
    Hashtbl.iter
      (fun id () -> Lui_host.note_moved t.host id)
      soft;
    let px = Lui_host.repaint t.host in
    let acts = t.populate () in
    (px, acts)

  let backend t profile = Lui_host.backend t.host profile

  let first_autofocus t =
    List.find_opt
      (fun id -> bool_prop (store t) id "autofocus")
      (Lui_store.preorder (store t))

  let create ?layout ~scale_cell ~(text : text) ~renderer ~width ~height
      () =
    (* Destructure once. [emit_text] is renamed deliberately: inside a
       [Lui_paint.{ }] record literal the module's own [text_ops]
       function is in scope and would shadow the field binding. *)
    let ({ measure; text_ops = emit_text; hit_text; caret_ops } : text) =
      text
    in
    let host_cell = ref None in
    let rects = Rects.create () in
    let ui = Ui.create () in
    Ui.set_scale ui !scale_cell;
    let store_of () = Lui_host.store (Option.get !host_cell) in
    (* Rect lookups for paint and hit tests, all in device px.
       [engine_rect] is the layout engine's placement; a node shifts
       up by the scroll offsets of its scrollable ancestors; a scroll
       container's extent is the unshifted span of its
       descendants. *)
    let engine_rect id =
      match !host_cell with
      | Some h ->
        Option.value ~default:Rects.zero (Lui_host.layout_rect h id)
      | None -> Rects.zero
    in
    (* [shifted_rect] runs once per painted node and the
       ancestor-offset sum is otherwise O(depth) each — memoize it
       for as long as both the store shape and the scroll offsets
       stand still. *)
    let shift_memo : (int, float * float) Hashtbl.t = Hashtbl.create 64 in
    let shift_epoch = ref (-1, -1) in
    let rec scroll_shift_of id =
      let epoch =
        (Lui_store.revision (store_of ()), Ui.scroll_epoch ui)
      in
      if epoch <> !shift_epoch then begin
        Hashtbl.reset shift_memo;
        shift_epoch := epoch
      end;
      match Hashtbl.find_opt shift_memo id with
      | Some v -> v
      | None ->
        let v =
          match Lui_store.parent (store_of ()) id with
          | Some p ->
            let sx, sy = scroll_shift_of p in
            (sx +. Ui.scroll_offset_x ui p, sy +. Ui.scroll_offset ui p)
          | None -> (0., 0.)
        in
        Hashtbl.replace shift_memo id v;
        v
    in
    let shifted_rect id =
      let r = engine_rect id in
      let sx, sy = scroll_shift_of id in
      { r with x = r.x -. sx; y = r.y -. sy }
    in
    let content_box id =
      List.fold_left
        (fun (l, t, rgt, b) d ->
           if d = id then (l, t, rgt, b)
           else
             let r = engine_rect d in
             (Float.min l r.x, Float.min t r.y,
              Float.max rgt (r.x +. r.w), Float.max b (r.y +. r.h)))
        (Float.max_float, Float.max_float,
         Float.min_float, Float.min_float)
        (Lui_store.preorder ~root:id (store_of ()))
    in
    (* Virtual-list viewport feed: the node's content-space visible
       range — its own scroll offset plus how far the frame clip has
       scrolled into its (shifted) box. Outer scroller clips are not
       tracked, so a clipped-away list just mounts a few extra
       rows. *)
    let vport_of id =
      if Lui_store.kind (store_of ()) id <> "virtual-list" then None
      else begin
        let er = engine_rect id in
        let sx, sy = scroll_shift_of id in
        let shifted =
          { er with
            Lui_scene.x = er.Lui_scene.x -. sx;
            y = er.Lui_scene.y -. sy }
        in
        let scn =
          match !host_cell with
          | Some h -> Lui_host.scene h
          | None -> failwith "vport before host"
        in
        let frame =
          Lui_scene.rect 0. 0. (float scn.Lui_scene.width)
            (float scn.Lui_scene.height)
        in
        let clip = Lui_scene.rect_intersect shifted frame in
        Some
          ( Ui.scroll_offset ui id
            +. Float.max 0. (clip.Lui_scene.y -. shifted.Lui_scene.y),
            Float.max 0. clip.Lui_scene.h )
      end
    in
    let vport_of id =
      match !host_cell with
      | Some _ -> vport_of id
      | None -> None
    in
    let hooks =
      Lui_paint.
        { color_of = Theme.color_of;
          layout =
            (fun id -> Lui_paint.placement_of_rect (shifted_rect id));
          state_of =
            (fun id ->
               match !host_cell with
               | Some h -> Ui.state_of ui (Lui_host.store h) id
               | None -> Lui_paint.state_neutral);
          mounted_children =
            (fun id ->
               match !host_cell with
               | Some h -> Lui_host.layout_mounted_children h id
               | None -> None);
          scroll_of =
            (fun id ->
               let cap = Ui.scroll_cap ui id in
               if cap <= 0.001 then None
               else
                 let cr = engine_rect id in
                 let content =
                   match
                     !host_cell
                     |> Option.map (fun h ->
                            Lui_host.layout_virtual_extent h id)
                     |> Option.join
                   with
                   | Some ext -> Float.max ext 0.001
                   | None ->
                     let _, top, _, bot = content_box id in
                     Float.max (bot -. top) 0.001
                 in
                 Some
                   Lui_paint.
                     { sm_offset = Ui.scroll_offset ui id /. cap;
                       sm_extent =
                         Float.min 1. (cr.h /. content) });
          text_ops =
            (fun id r fg s ->
               let ops = emit_text id r fg s in
               let marked = Ui.marked ui in
               if marked = "" || id <> Ui.focused ui then ops
               else begin
                 (* Composition overlay: marked text drawn underlined
                    at the caret of the focused field. It is
                    paint-only — never dispatched — and cleared the
                    moment the composition commits or cancels. When
                    the node's text prop is empty [s] is the
                    placeholder: drop its glyphs so the marked string
                    paints alone. *)
                 let caret =
                   min (Ui.caret ui) (String.length (Ui.shadow ui))
                 in
                 let ops =
                   let has_text =
                     match !host_cell with
                     | Some h -> (
                       match
                         Lui_store.prop (Lui_host.store h) id "text"
                       with
                       | Some (Lui_protocol.StringValue v) -> v <> ""
                       | _ -> false)
                     | None -> false
                   in
                   if has_text then ops else []
                 in
                 (* The caret's real position inside the laid-out
                    shadow — the same rect the IME candidate anchor
                    uses, so marked text and its underline land where
                    the commit will insert. *)
                 let cx, _, _ =
                   (caret_ops id (Ui.shadow ui) ~lw:r.Lui_scene.w
                      ~lh:r.Lui_scene.h)
                     .Ui.c_rect caret
                 in
                 let mw, mh = measure id marked in
                 let underline =
                   Lui_scene.Fill
                     { frect =
                         Lui_scene.rect
                           (r.Lui_scene.x +. cx)
                           (r.Lui_scene.y
                            +. (r.Lui_scene.h +. mh) /. 2. -. 2.)
                           mw 2.;
                       fradii = (0., 0., 0., 0.); fcontinuous = false;
                       fcolor = fg; fpaint = Lui_scene.Solid;
                       fcolor2 = fg;
                       fgradient = (0., 0., 0., 0.);
                       fborder = (0., 0., 0., 0.);
                       fborder_color = Lui_scene.color 0 0 0 0;
                       fdashed = false; fwide = 0; fopacity = 1. }
                 in
                 let mr = { r with Lui_scene.x = r.Lui_scene.x +. cx } in
                 ops @ [ underline ] @ emit_text id mr fg marked
               end);
          image_of = (fun _ -> None);
          image_in = (fun _ _ -> None);
          shadow_of = Lui_paint.parse_shadows Theme.color_of }
    in
    let host =
      Lui_host.create ~hooks ?layout
        (* Measure the text the engine selected (label/title/text per
           kind) plus the placement padding it will paint around it —
           feeding the raw glyph metric collapses every labeled
           control to bare-text size (buttons, fields, kbd...). *)
        ~measure:(fun id s _w _h ->
          let w, h = measure id s in
          let tp = Lui_paint.text_placement_of (store_of ()) id in
          let sc = !scale_cell in
          Some
            (w +. (2. *. tp.tp_pad_x *. sc),
             h +. (2. *. tp.tp_pad_y *. sc)))
        ~renderer ~width ~height ~scale:!scale_cell ()
    in
    host_cell := Some host;
    let store = Lui_host.store host in
    (* Trigger-owned menu panels stay hidden until opened; the
       predicate reads the interaction state's mutable open-menu slot
       each sync. *)
    Lui_host.set_hidden host (Some (fun id -> Ui.hidden ui store id));
    (* Unanchored context menus open at the pointer. The anchor feeds
       [refine_popups] only while a context-menu is open — reporting
       the live pointer position unconditionally would defeat the
       layout memo on every pointer-driven repaint, so the accessor
       returns [None] the rest of the time. *)
    Lui_host.set_ctx_anchor host
      (Some
         (fun () ->
            match Ui.open_menu ui with
            | 0 -> None
            | id when Lui_store.kind store id = "context-menu" ->
              Some (Ui.pointer ui)
            | _ -> None));
    (* Virtual lists: feed each node's content-space visible range
       during layout sync so only the mounted window is
       materialized. A scroll move repaints (the offset lives in the
       scroll machine's dirty path), the repaint re-syncs the engine
       and the engine re-reads this feed — that is the scroll-driven
       remount. *)
    Lui_host.set_vport host vport_of;
    (* Populate the hit-test mirror from the layout engine: each
       node's shifted rect clipped to its scrollable ancestors'
       viewports (so scrolled-off content can't be hit), then each
       scroll container's range on both axes from its unshifted
       content extent. Runs after every repaint while the engine is
       fresh. *)
    (* Scroll-container ids memoized on the store revision: a scroll
       frame changes no props, so the cap refresh below does not
       re-walk the whole tree on every frame (a 100k-row list has ~3
       scrollables). *)
    let scrollables = ref (-1, []) in
    let populate () =
      Hashtbl.reset rects;
      (* One preorder pass carrying the ancestors' accumulated scroll
         offset and clip: the node's own offset shifts only its
         children, and a scrollable node's already-stored mirror rect
         becomes its descendants' clip — the same result the old
         per-node ancestor walk produced, without re-summing the
         chain for every node. Placement goes through the same
         [Lui_paint.resolve_rect] the paint pass uses, so
         position/inset, fixed and popup coordinates hit-test where
         they paint; [parent_r] is the parent's resolved box (a
         display:contents node forwards its own containing block). *)
      let scn = Lui_host.scene host in
      let viewport =
        Lui_scene.rect 0. 0. (float scn.Lui_scene.width)
          (float scn.Lui_scene.height)
      in
      let rec visit id ~sx ~sy ~parent_r =
        let base = engine_rect id in
        let shifted =
          { base with
            Lui_scene.x = base.Lui_scene.x -. sx;
            Lui_scene.y = base.Lui_scene.y -. sy }
        in
        let resolved =
          Lui_paint.resolve_rect ~scale:!scale_cell ~viewport store id
            (Lui_store.kind store id)
            (Lui_paint.placement_of_rect shifted) parent_r
        in
        (* Clipping is NOT baked in: the shared hit walk recomputes the
           exact stacking/clip context (clip kinds, promoted popups
           escaping ancestor clips), so each node keeps its full
           resolved box. *)
        Hashtbl.replace rects id resolved;
        let sx' = sx +. Ui.scroll_offset_x ui id
        and sy' = sy +. Ui.scroll_offset ui id in
        let child_parent =
          if Lui_paint.unboxed store id then parent_r else resolved
        in
        (* A virtual list only hit-tests its mounted window —
           unmounted rows have no rect and cannot be hit anyway. *)
        let cids =
          match Lui_host.layout_mounted_children host id with
          | Some ids -> ids
          | None -> Lui_store.child_ids store id
        in
        List.iter
          (fun c ->
             visit c ~sx:sx' ~sy:sy' ~parent_r:child_parent)
          cids
      in
      List.iter
        (fun id -> visit id ~sx:0. ~sy:0. ~parent_r:viewport)
        (Lui_store.root_ids store);
      let srev = Lui_store.revision store in
      let sids =
        match !scrollables with
        | r, ids when r = srev -> ids
        | _ ->
          let ids =
            List.filter
              (fun id -> Ui.scrollable store id)
              (Lui_store.preorder store)
          in
          scrollables := (srev, ids);
          ids
      in
      List.iter
        (fun id ->
           let cr = engine_rect id in
           match Lui_host.layout_virtual_extent host id with
           | Some ext ->
             (* Virtual extent, not the mounted rows' box: the cap
                spans the full logical content. *)
             Ui.set_scroll_cap ui id
               (Float.max 0. (ext -. cr.Lui_scene.h));
             Ui.set_scroll_cap_x ui id 0.
           | None ->
             let l, t, rgt, b = content_box id in
             Ui.set_scroll_cap ui id
               (Float.max 0. (b -. t -. cr.Lui_scene.h));
             Ui.set_scroll_cap_x ui id
               (Float.max 0. (rgt -. l -. cr.Lui_scene.w)))
        sids;
      (* Rects were just rebuilt — visible-range memos key on the
         epoch. *)
      Ui.notify_layout ui;
      (* Anchor correction: rows that measured off-estimate above the
         viewport shifted everything below — fold the drift back into
         the scroll offset so the top row does not visibly jump. *)
      List.concat_map
        (fun id ->
           let d = Lui_host.layout_take_drift host id in
           if Float.abs d > 0.001 then
             Ui.scroll_to ui store id (Ui.scroll_offset ui id +. d)
           else [])
        (Lui_host.layout_vlists host)
    in
    (* Caret rect of the focused field, device px: the node's layout
       rect shifted to the caret's real position inside the laid-out
       text — wrap, line pitch, alignment and insets included. This is
       the candidate-window anchor while composing. *)
    let caret_rect () =
      let id = Ui.focused ui in
      let r = Rects.get rects id in
      if Lui_scene.rect_empty r then r
      else begin
        let text' = Ui.shadow ui in
        let ops = caret_ops id text' ~lw:r.Lui_scene.w ~lh:r.Lui_scene.h in
        let cx, cy, ch =
          ops.Ui.c_rect (min (Ui.caret ui) (String.length text'))
        in
        Lui_scene.rect (r.Lui_scene.x +. cx) (r.Lui_scene.y +. cy) 2.
          (Float.max 2. ch)
      end
    in
    (* Ui driver hooks: real glyph measurement for caret/selection
       math, unshifted engine rects for scroll_show/visible-range. *)
    Ui.set_measure ui (fun _store id s -> measure id s);
    Ui.set_hit_text ui
      (fun _store id s ~lx ~ly ~lw ~lh ->
         hit_text id s ~lx ~ly ~lw ~lh);
    (* Keyboard caret moves run on the same layouts: grapheme clusters
       horizontally, visual (soft-wrapped) lines vertically. *)
    Ui.set_caret_ops ui (fun _store id s ~lw ~lh -> caret_ops id s ~lw ~lh);
    (* Virtual lists: expose the extent model to the scroll machine
       (scroll-target, visible-range), and synthesize rects for
       unmounted rows so reveal/scroll-align work on logical
       items. *)
    Ui.set_vlist_hook ui
      (Some
         Ui.
           { vh_count =
               (fun id ->
                  if Lui_store.kind store id = "virtual-list"
                  then Some (Lui_store.child_count store id)
                  else None);
             vh_item =
               (fun id ~index ->
                  Lui_host.layout_virtual_item host id ~index);
             vh_index_of_key =
               (fun id key ->
                  Lui_host.layout_virtual_index_of_key host id key);
             vh_view =
               (fun id -> Lui_host.layout_virtual_view host id) });
    Ui.set_content_rect ui
      (fun id ->
         let r = engine_rect id in
         if not (Lui_scene.rect_empty r) then r
         else
           (* Unmounted virtual-list row: the model still knows where
              it sits, so scroll-to-item reaches it. *)
           match Lui_store.parent store id with
           | Some p -> (
             match Lui_host.layout_virtual_index_of_id host p id with
             | Some i ->
               Option.value ~default:r
                 (Lui_host.layout_virtual_item host p ~index:i)
             | None -> r)
           | None -> r);
    { host; ui; rects; scale_cell; engine_rect; populate; caret_rect }
end
