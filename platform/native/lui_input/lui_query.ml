(* Read-only views over the retained store shared by every
   interaction machine in this library: prop/kind queries, event
   admission, rect hit testing, data-attr predicates, activation
   targets and text-measure helpers. Everything here is a pure
   function of (store, rects, point) — the "world snapshot" the pure
   state machines consume. Nothing mutates the store. *)

open Lui_scene
open Lui_protocol

(** Per-node device-pixel rectangles produced by the layout pass and
    consumed by the paint hooks and [hit_path]. *)
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

let event_supported store id event =
  match kind_of store id with
  | None -> false
  | Some kind ->
    Lui_protocol.event_supported_for_lookup kind
      (fun property -> Lui_store.prop store id (Lui_wire_schema.property_name property)) event

(* Everything [hit_path] needs from the store for one node on top of
   the shared walk's stacking/clip frame: overlay presentation, the
   pointer-enabled opt, and the spacer kind check. Computed once per
   node per store revision — see [hit_flags_of]. *)
type hit_flags = {
  hf_overlay : bool;
  hf_pen : bool option;
  hf_spacer : bool;
}

(* pointer-enabled=false makes a subtree hit-transparent like the web
   pointer-events:none: descendants inherit it and only an explicit
   pointer-enabled=true opts a node back in (registering pointer
   handlers sets that prop). A presented overlay (popover, dialog,
   menu, sheet, toast, or a [selected]-less drawer) always opts its
   own subtree back in — it is interactive content by definition —
   while a permanent overlay-layer host (data-overlay-layer) keeps
   whatever its own flag says. *)
let presented_overlay store id =
  let layer_host =
    match Lui_store.prop store id "data-attrs" with
    | Some (StringValue s) -> (
      try
        List.assoc_opt "data-overlay-layer"
          (Lui_protocol.data_attrs_decode s)
        = Some "true"
      with _ -> false)
    | _ -> false
  in
  (not layer_host)
  && (match Lui_store.kind store id with
      | "dialog" | "sheet" | "popover" | "dropdown-menu"
      | "context-menu" | "toast" ->
        true
      | "drawer" -> Lui_store.prop store id "selected" = None
      | _ -> false)

let hit_flags_compute store id =
  { hf_overlay = presented_overlay store id;
    hf_pen =
      (match Lui_store.prop store id "pointer-enabled" with
       | Some (BoolValue v) -> Some v
       | _ -> None);
    hf_spacer = Lui_store.kind store id = "spacer" }

(* hit_path's per-node flags, memoized for the (store, revision) of the
   last call: pointer events hit-test the same tree repeatedly, and the
   flags only move when the store does. Physical store identity keeps
   two windows' stores from aliasing; a revision mismatch resets and
   re-derives lazily. *)
let hit_flags_tbl : (int, hit_flags) Hashtbl.t = Hashtbl.create 256
let hit_flags_store : Lui_store.t option ref = ref None
let hit_flags_rev = ref (-1)

let hit_flags_of store id =
  (match !hit_flags_store with
   | Some s when s == store && !hit_flags_rev = Lui_store.revision store ->
     ()
   | _ ->
     Hashtbl.reset hit_flags_tbl;
     hit_flags_store := Some store;
     hit_flags_rev := Lui_store.revision store);
  match Hashtbl.find_opt hit_flags_tbl id with
  | Some f -> f
  | None ->
    let f = hit_flags_compute store id in
    Hashtbl.replace hit_flags_tbl id f;
    f

(* Hit-testing runs the same stacking walk the paint pass paints:
   z-ordered siblings, promoted popups escaping their ancestors' clip,
   display:contents pass-through, and the clip context computed with
   [Lui_paint.clips]'s exact rule. [rects] carries the driver's
   resolved boxes — fed back as placement overrides so the walk
   shares the stacking/clip result without re-resolving geometry.
   [?spatial] is the subtree-bound index built over that same mirror
   ([Lui_spatial.build] with [~rect_of:(Rects.get rects)]): with it,
   the walk descends only toward subtrees that could contain the
   point instead of visiting every node — O(log n + path) instead of
   O(n) per pointer event. *)
let hit_path ?spatial store rects ~x ~y =
  let path = ref [] in
  (* pointer-events accumulate down the tree; the ghost pass threads
     the same [on] update so a promoted popup keeps its clipped-away
     ancestors' flags. *)
  let flags_or on fl =
    match fl.hf_pen with Some v -> v | None -> on || fl.hf_overlay
  in
  let enter on (f : Lui_paint.frame) =
    let fl = hit_flags_of store f.f_id in
    let on = flags_or on fl in
    (* spacers are layout voids — they paint nothing and must never be
       the hit target (a full-window spacer in an overlay layer would
       otherwise swallow every DOM event). *)
    if on && not fl.hf_spacer
       && not (rect_empty f.f_clipped)
       && rect_contains f.f_clipped x y
    then path := f.f_id :: !path;
    { Lui_paint.b_emit = false; b_down = true; b_ctx = on }
  in
  (* The walk's "viewport" is the pointer point itself: a clip that
     misses it can contain no hit, so the walk prunes the subtree —
     promoted popups still escape. *)
  Lui_paint.walk ~scale:1.
    ~viewport:(rect x y 1e-4 1e-4) store
    ~layout:(fun id ->
      let r = Rects.get rects id in
      { Lui_paint.p_rect = r; p_override = Some r })
    ~enter
    ~ghost_enter:(fun on id _contents ->
      flags_or on (hit_flags_of store id))
    ~leave:(fun _ _ -> ())
    ?spatial:(Option.map (fun i -> (i, Lui_spatial.Point (x, y))) spatial)
    true;
  (* The head is the node visited last in paint order: visually
     topmost. *)
  !path

let hit ?spatial store rects ~x ~y =
  match hit_path ?spatial store rects ~x ~y with
  | id :: _ -> Some id
  | [] -> None

(* Ancestor check used by overlay inside-tests and modal scope. *)
let is_desc store id anc =
  let rec go cur =
    match Lui_store.parent store cur with
    | Some p -> p = anc || go p
    | None -> false
  in
  go id

(* ---- props-as-text -------------------------------------------------- *)

let text_of store id = string_prop store id "text"

(* Field kinds whose [text] prop the host mirrors local edits into —
   the store copy stays a frame-accurate model echo. *)
let retains_text store id =
  match Lui_store.kind store id with
  | "text-field" | "secure-field" | "input" | "search-field" | "textarea"
  | "combobox" -> true
  | _ -> false

let index_of id items =
  let rec go i = function
    | a :: _ when a = id -> Some i
    | _ :: tl -> go (i + 1) tl
    | [] -> None
  in
  go 0 items

(* ---- data-* attribute predicates ------------------------------------- *)

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

(* ---- activation targets ----------------------------------------------- *)

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
      Lui_input.mods_to_int mods lor (if button = 2 then 8 else 0);
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
  (* DOM click semantics: the activation lands on the deepest
     ancestor that opted into press handling ("press-enabled" is
     what [register_press] sets), not on a passive leaf — bare
     text/box kinds admit Press unconditionally and would otherwise
     swallow the click before it reaches the pressable wrapper.
     Toggle kinds flip their state on press instead of emitting it —
     [ToggleButton] does not admit Press at all, so admit
     [ToggleChanged] as an activation signal too. *)
  match
    select_activation store path
      (fun s id -> Lui_store.bool_prop s id "press-enabled")
  with
  | Some id -> Some id
  | None ->
    select_activation store path
      (fun s id ->
        kind_name s id = "menu-trigger"
        || event_supported s id (ev_press id)
        || event_supported s id (ToggleChanged (id, true)))

let detail_target store path make =
  pick store path (fun s id ->
      pointer_enabled s id && event_supported s id (make id))

(* Click on a pressable node, mirroring the web click dispatch:
   toggle kinds flip their state instead of emitting Press. *)
let primary_press store id =
  let dispatch e =
    if node_enabled store id && event_supported store id e
    then [ `Dispatch e ] else []
  in
  match kind_name store id with
  | "toggle-button" | "toggle" | "drawer" ->
    dispatch (ToggleChanged (id, not (bool_prop store id "selected")))
  | "checkbox" | "switch" ->
    dispatch (ToggleChanged (id, not (bool_prop store id "checked")))
  | "radio" ->
    if event_supported store id (Change id) then [ `Dispatch (Change id) ]
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

let submit store id =
  if event_supported store id (ev_submit id) then [ `Dispatch (Submit id) ]
  else []

(* ---- length props ------------------------------------------------------ *)

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

let pad_axis store id ~scale name fallback =
  match len_prop store id name ~scale with
  | Some v -> v
  | None ->
    Option.value ~default:0. (len_prop store id fallback ~scale)

(* ---- text measurement helpers -------------------------------------------

   Caret/selection math over byte offsets. The window driver wires a
   glyph-measure hook ([measure]) and, optionally, a layout-accurate
   point-to-byte map ([hit_text]); deterministic defaults keep the
   machines testable without a text engine. *)

(* The text engine's caret model for one editable string, built
   over the same laid-out text the painter and [hit_text] resolve
   against: [c_before]/[c_after] step byte offsets across grapheme
   clusters, [c_up]/[c_down] move across visual (soft-wrapped)
   lines, [c_rect] is the caret's device-pixel (x, y, h) in node
   content coordinates for the IME candidate anchor. *)
type caret_ops = {
  c_before : int -> int;
  c_after : int -> int;
  c_up : int -> int;
  c_down : int -> int;
  c_rect : int -> float * float * float;
}

type text_hooks = {
  measure : Lui_store.t -> int -> string -> float * float;
  hit_text :
    (Lui_store.t -> int -> string -> lx:float -> ly:float ->
     lw:float -> lh:float -> int) option;
  caret_ops :
    (Lui_store.t -> int -> string -> lw:float -> lh:float ->
     caret_ops) option;
  scale : float;
}

let default_hooks =
  { measure = (fun _store _id s -> (8. *. float (String.length s), 16.));
    hit_text = None;
    caret_ops = None;
    scale = 1. }

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

(* UTF-8 byte boundaries of [s] ascending, 0 and len included. *)
let utf8_bounds s =
  let n = String.length s in
  let rec go i acc =
    if i >= n then List.rev (n :: acc)
    else if Char.code s.[i] land 0xC0 = 0x80 then go (i + 1) acc
    else go (i + 1) (i :: acc)
  in
  go 0 []

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

(* Clamp [offset] back to a UTF-8 code-point boundary of [text]. *)
let clamp_boundary text offset =
  let len = String.length text in
  let rec back i =
    if i <= 0 then 0
    else if Char.code text.[i] land 0xC0 = 0x80 then back (i - 1)
    else i
  in
  if offset >= len then len else back (max 0 offset)

(* Nearest byte boundary in one [line] whose measured prefix width
   reaches [lx] device px. *)
let boundary_at_x hooks store id line lx =
  if lx <= 0. then 0
  else
    let rec choose prev = function
      | b :: tl ->
        let w = fst (hooks.measure store id (String.sub line 0 b)) in
        if w >= lx then
          let wp = fst (hooks.measure store id (String.sub line 0 prev)) in
          if lx -. wp < w -. lx then prev else b
        else choose b tl
      | [] -> String.length line
    in
    choose 0 (utf8_bounds line)

(* Byte offset in [text] under the device-px point [(x,y)] inside
   node [id]'s shifted rect, honoring padding and line breaks. When
   the driver wired a [hit_text] hook the text engine resolves the
   point against the same layout it painted — wrap, alignment and
   vertical placement included — instead of per-prefix measures. *)
let offset_at_point hooks store rects id ~x ~y text =
  let r = Rects.get rects id in
  let ph =
    pad_axis store id ~scale:hooks.scale "padding-horizontal" "padding" in
  let pv =
    pad_axis store id ~scale:hooks.scale "padding-vertical" "padding" in
  let lx = x -. r.Lui_scene.x -. ph
  and ly = y -. r.Lui_scene.y -. pv in
  match hooks.hit_text with
  | Some f ->
    f store id text ~lx:(x -. r.Lui_scene.x) ~ly:(y -. r.Lui_scene.y)
      ~lw:r.w ~lh:r.h
  | None ->
    let lh = Float.max 1. (snd (hooks.measure store id "Ag")) in
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
    base 0 0 lines + boundary_at_x hooks store id line lx

(* Caret (line, column-in-bytes) then boundary on the target line —
   shared by Arrow_up/down in multi-line fields. *)
let move_caret_line hooks store focused s c dir =
  let c = min c (String.length s) in
  let lines = String.split_on_char '\n' s in
  let rec find li base = function
    | l :: tl ->
      let e = base + String.length l in
      if c <= e then (li, c - base) else find (li + 1) (e + 1) tl
    | [] ->
      (List.length lines - 1,
       String.length (List.nth lines (List.length lines - 1)))
  in
  let li, col = find 0 0 lines in
  let li' = min (max 0 (li + dir)) (List.length lines - 1) in
  if li' <> li then begin
    let x =
      fst (hooks.measure store focused
             (String.sub (List.nth lines li) 0 col))
    in
    let rec base i acc = function
      | [] -> acc
      | l :: tl ->
        if i = li' then acc else base (i + 1) (acc + String.length l + 1) tl
    in
    base 0 0 lines
    + boundary_at_x hooks store focused (List.nth lines li') x
  end else c
