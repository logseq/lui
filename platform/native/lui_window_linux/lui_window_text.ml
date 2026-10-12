(* Pango-backed text engine for the window host: turns the paint
   pipeline's text_ops requests into glyph ops on the scene's shared
   atlases and measures leaf text for the layout stub.

   The engine is device-pixel correct: fonts are created at logical
   (point) size, glyph positions are scaled by the backing scale and
   snapped to device pixels, and rasterization happens at the full
   scale so high-DPI text stays sharp.

   Same shape as every other platform's text engine — the platform
   stack is bound once here and the rest of the module only sees the
   engine-agnostic interface. *)

module Lui_text = Lui_text_pango

open Lui_scene

(* Cache key for one rasterized glyph in an atlas. *)
type glyph_key = {
  gk_font : Lui_text.font;
  gk_id : int;
  gk_sub : int;   (* quantized subpixel origin slot *)
  gk_shade : int; (* quantized ink luminance, 0..8 *)
  gk_scale : int; (* device scale, thousandths *)
}

(* Atlas position plus the bitmap's draw offsets — everything the
   glyph record needs, so a cached glyph never re-rasterizes. *)
type slot = {
  sl_x : int;
  sl_y : int;
  sl_w : int;
  sl_h : int;
  sl_left : int;
  sl_top : int;
  sl_colored : bool;
}

(* The text-side typography props, resolved as a unit so shaping,
   measuring and painting always agree. [ts_kern] is extra advance
   per glyph in points (letter-spacing); [ts_lh] the explicit
   line-height in points, 0 for the font's own; the three booleans
   drive paint-side decorations; [ts_nowrap]/[ts_ellipsis] implement
   white-space/text-overflow. *)
type text_style = {
  ts_font : Lui_text.font;
  ts_kern : float;
  ts_lh : float;
  ts_nowrap : bool;
  ts_ellipsis : bool;
  ts_under : bool;
  ts_strike : bool;
  ts_over : bool;
}

type t = {
  scene : unit -> Lui_scene.t;
  scale : unit -> float;
  store : unit -> Lui_store.t;
  slots : (glyph_key, slot option) Hashtbl.t;
  (* Bounded LRU of shaped layouts keyed by (text, wrap, direction,
     font): text_ops and measure share it, so the shape a node's
     measure produced is the one its paint reuses. *)
  shapes : Lui_text.Cache.t;
  (* node id -> (store revision, text style): font resolution walks
     the ancestor chain per call, so memoize it for the revision it
     was computed at — any prop change bumps the revision. *)
  styles : (int, int * text_style) Hashtbl.t;
  (* O(1) [List.length scene.glyphs] bookkeeping — see [gcount]. *)
  mutable gcount : int;
  mutable ghead : Lui_scene.glyph list;
}

let create ~scene ~scale ~store =
  { scene; scale; store; slots = Hashtbl.create 512;
    shapes = Lui_text.Cache.create 512;
    styles = Hashtbl.create 64; gcount = 0; ghead = [] }

(* ---- font + text prop plumbing ---- *)

let rec parse_len s =
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
  if stop = 0 then
    (* "var(--name, <fallback>)" — the app's declared default is a
       plain number; custom-prop resolution lives in the host's
       color_of hook, so here the fallback is the value *)
    if String.length s > 4 && String.sub s 0 4 = "var(" then
      match String.rindex_opt s ',' with
      | Some comma ->
        let fb =
          String.sub s (comma + 1) (n - comma - 1)
          |> String.trim
          |> fun t ->
            if String.length t > 0 && t.[String.length t - 1] = ')' then
              String.sub t 0 (String.length t - 1)
            else t
        in
        parse_len fb
      | None -> None
    else None
  else
    let unit =
      match String.sub s stop (String.length s - stop) |> String.trim with
      | "rem" | "em" -> 16.
      | _ -> 1.
    in
    (try Some (float_of_string (String.sub s 0 stop) *. unit)
     with _ -> None)

let num_prop store id name =
  match Lui_store.prop store id name with
  | Some (Lui_protocol.FloatValue f) -> Some f
  | Some (IntValue i) -> Some (float i)
  | Some (StringValue s) -> parse_len s
  | _ -> None

(* A selected top-strip tab — the bare kind or a direct button child
   of a tabs strip — draws heavier ink. *)
let selected_tab_trigger store id =
  Lui_store.bool_prop store id "selected"
  && (match Lui_store.kind store id with
     | "tab" -> true
     | "button" -> (
       match Lui_store.parent store id with
       | Some pid -> Lui_store.kind store pid = "tabs"
       | None -> false)
     | _ -> false)

(* font-size and font-weight inherit like the CSS they model: a node
   without its own value uses the nearest ancestor's. kbd's smaller
   default still applies before the walk. *)
let inherited_num store id name =
  let rec walk id =
    match num_prop store id name with
    | Some v -> Some v
    | None -> (
      match Lui_store.parent store id with
      | Some pid when pid <> id -> walk pid
      | _ -> None)
  in
  walk id

let inherited_int store id name =
  let rec walk id =
    match Lui_store.int_prop store id name with
    | Some v -> Some v
    | None -> (
      match Lui_store.parent store id with
      | Some pid when pid <> id -> walk pid
      | _ -> None)
  in
  walk id

let inherited_str store id name =
  let rec walk id =
    match Lui_store.prop store id name with
    | Some (Lui_protocol.StringValue s) -> Some s
    | _ -> (
      match Lui_store.parent store id with
      | Some pid when pid <> id -> walk pid
      | _ -> None)
  in
  walk id

(* A node's own [text-decoration] value as paint flags. The prop does
   not inherit (CSS), and the wire admits only the space-separated
   tokens checked here. *)
let decoration_of store id =
  match Lui_store.prop store id "text-decoration" with
  | Some (Lui_protocol.StringValue s) ->
    let has tok =
      List.exists
        (fun t -> String.trim t = tok)
        (String.split_on_char ' ' s)
    in
    (has "underline", has "line-through", has "overline")
  | _ -> (false, false, false)

(* [line-height]: a unitless number is a multiplier of the computed
   font size (the CSS <number> semantics the wire schema declares);
   a length suffix resolves through [parse_len]. *)
let line_height_of store id ~size =
  match inherited_str store id "line-height" with
  | Some s ->
    let s = String.trim s in
    if s = "" || s = "normal" then 0.
    else
      (match float_of_string_opt s with
       | Some f when f > 0. -> f *. size
       | _ ->
         (match parse_len s with
          | Some v when v > 0. -> v
          | _ -> 0.))
  | None -> 0.

let resolve_style store id =
  let size =
    match inherited_num store id "font-size" with
    | Some v -> v
    | None -> (
      (* Keycaps set smaller type than the surrounding copy. *)
      match Lui_store.kind store id with
      | "kbd" -> 11.
      | _ -> 14.)
  in
  let weight =
    match inherited_int store id "font-weight" with
    | Some w -> min 900 (max 100 w)
    | None ->
      (match Lui_store.kind store id with
       | "heading" -> 700
       | "tab" | "button" when selected_tab_trigger store id -> 600
       | "dialog" | "sheet" -> 600
       | _ -> 400)
  in
  let italic =
    match inherited_str store id "font-style" with
    | Some "italic" | Some "oblique" -> true
    | _ -> false
  in
  let families =
    match inherited_str store id "font-family" with
    | Some s ->
      List.filter_map
        (fun f -> match String.trim f with "" -> None | f -> Some f)
        (String.split_on_char ',' s)
    | None -> []
  in
  (* [create] with no families resolves to the system font, and goes
     through the engine's own cache so the same (weight, italic, size)
     reuses one font object instead of allocating a fresh Pango font
     per node per frame. *)
  let font = Lui_text.create ~families ~weight ~italic ~size () in
  let under, strike, over = decoration_of store id in
  { ts_font = font;
    ts_kern =
      Option.value ~default:0.
        (inherited_num store id "letter-spacing");
    ts_lh = line_height_of store id ~size;
    ts_nowrap =
      (inherited_str store id "white-space" = Some "nowrap");
    (* text-overflow does not inherit. *)
    ts_ellipsis =
      (Lui_store.string_prop store id "text-overflow"
       = Some "ellipsis");
    ts_under = under; ts_strike = strike; ts_over = over }

(* The node's text style, memoized on the store revision: the props
   above inherit down the ancestor chain, so resolving them is an
   O(depth) walk every frame otherwise. Any prop mutation bumps the
   revision and re-walks lazily. *)
let style_of t store id =
  let rev = Lui_store.revision store in
  match Hashtbl.find_opt t.styles id with
  | Some (r, s) when r = rev -> s
  | _ ->
    let s = resolve_style store id in
    Hashtbl.replace t.styles id (rev, s);
    s

(* The layout text_ops, measure and hit-testing share: letter-spacing
   rides in as a span so shaped runs carry the extra advance. *)
let layout_of t (st : text_style) ~width s =
  if st.ts_kern = 0. then
    Lui_text.Cache.layout t.shapes ~width st.ts_font s
  else
    Lui_text.Cache.layout_spans t.shapes ~width st.ts_font
      [ { Lui_text.text = s;
          style =
            { Lui_text.default_style with Lui_text.skern = st.ts_kern };
          range = (0, String.length s) } ]

(* The height [lay] occupies once the line-height override applies:
   every line takes [ts_lh] points instead of its natural metrics. *)
let styled_height (st : text_style) (lay : Lui_text.layout) =
  if st.ts_lh > 0. then
    float (Array.length lay.Lui_text.lay_lines) *. st.ts_lh
  else lay.Lui_text.lay_height

(* Logical-pixel extent of [s] in [st], for the measure hooks. *)
let extent_of t st s =
  let lay = layout_of t st ~width:0. s in
  (lay.Lui_text.lay_width, styled_height st lay)

(* A line's painted height in points: the line-height override wins,
   else the natural advance. *)
let line_h (st : text_style) (l : Lui_text.line) =
  if st.ts_lh > 0. then st.ts_lh
  else l.ascent +. l.descent +. l.leading

(* ---- atlas upload ---- *)

(* Quantized ink luminance the engine thickens dark-on-light stems
   with (0 black .. 8 white). *)
let shade_of (c : color) =
  let lum =
    (0.2126 *. float c.r +. 0.7152 *. float c.g +. 0.0722 *. float c.b)
    /. 255.
  in
  min 8 (max 0 (int_of_float (lum *. 8. +. 0.5)))

let atlas_put ~colored atlas b =
  let rec try_alloc () =
    match Atlas.alloc_last atlas b.Lui_text.w b.Lui_text.h with
    | Some pos -> Some pos
    | None ->
      (* Atlas full: grow moves no lasting rects, so cached slots
         stay valid; then retry. *)
      if Atlas.grow atlas then try_alloc () else None
  in
  match try_alloc () with
  | None -> None
  | Some (x, y) ->
    Atlas.put atlas ~x ~y ~w:b.Lui_text.w ~h:b.Lui_text.h
      ~src:b.Lui_text.pixels
      ~stride:(b.Lui_text.w * (if colored then 4 else 1));
    Some (x, y)

(* Rasterize + upload a glyph, memoized so each unique (font, glyph,
   subpixel origin, ink shade, scale) rasterizes once. *)
let slot_of t run_font gid sub shade scale scene =
  let key =
    { gk_font = run_font; gk_id = gid; gk_sub = sub;
      gk_shade = shade; gk_scale = int_of_float (scale *. 1024.) }
  in
  match Hashtbl.find_opt t.slots key with
  | Some s -> s
  | None ->
    let n = Lui_text.subpixel_positions ~scale run_font in
    let dx = if n <= 1 then 0. else float sub /. float n in
    let slot =
      match
        Lui_text.rasterize ~scale ~dx
          ~shade:(float shade /. 8.) run_font gid
      with
      | Some b when b.Lui_text.w > 0 && b.Lui_text.h > 0 ->
        (* The bitmap's own format decides the atlas: a color font can
           still rasterize a monochrome glyph (coverage mask). *)
        let colored = b.Lui_text.color in
        let atlas =
          if colored then scene.color_atlas else scene.mask_atlas
        in
        (match atlas_put ~colored atlas b with
         | Some (x, y) ->
           Some
             { sl_x = x; sl_y = y; sl_w = b.w; sl_h = b.h;
               sl_left = b.left; sl_top = b.top; sl_colored = colored }
         | None -> None)
      | _ -> None
    in
    Hashtbl.replace t.slots key slot;
    slot

(* ---- paint hook ---- *)

(* [List.length scene.glyphs] in O(1): the build list only grows by
   consing, so while its head is still the cell this engine last
   prepended or observed, the count is unchanged. A foreign prepend
   shows a different head cell and forces a recount; [t.ghead]
   retains the cell so the GC cannot recycle its address. *)
let gcount t scene =
  if scene.glyphs == t.ghead then t.gcount
  else begin
    t.gcount <- List.length scene.glyphs;
    t.ghead <- scene.glyphs;
    t.gcount
  end

(* Emit one positioned glyph; prepends to [scene.glyphs] and returns
   whether one was added. [nsub] is the run font's subpixel position
   count — the caller computes it once per run instead of per glyph. *)
let emit_glyph t scene ~scale ~nsub ~pen ~baseline ~font ~gid ~g_y ~fg =
  let ix = Float.floor pen in
  let sub =
    if nsub <= 1 then 0
    else min (nsub - 1) (int_of_float ((pen -. ix) *. float nsub +. 0.5))
  in
  match slot_of t font gid sub (shade_of fg) scale scene with
  | None -> false
  | Some s ->
    let gl =
      { gx = ix +. float s.sl_left;
        gy = baseline +. g_y *. scale +. float s.sl_top;
        gw = float s.sl_w; gh = float s.sl_h;
        gu = s.sl_x; gv = s.sl_y;
        guw = s.sl_w; gvh = s.sl_h;
        gcolor = fg; gwide = 0;
        gcolored = s.sl_colored;
        gsubpixel = false; gthin = false }
    in
    (* Cons, like the other engines: [scene.glyphs] is built reversed
       and the paint pass reverses it once when sealing, so the
       [gstart]/[gend] span recorded around a run stays the glyphs the
       run emitted. *)
    ignore (gcount t scene);
    let cell = gl :: scene.glyphs in
    scene.glyphs <- cell;
    t.ghead <- cell;
    t.gcount <- t.gcount + 1;
    true

let text_ops t id r fg s =
  let scene = t.scene () in
  let scale = t.scale () in
  let store = t.store () in
  let st = style_of t store id in
  let font = st.ts_font in
  (* The layout comes from the bounded cache: measure populated the
     same entry on the layout pass, so a repaint pays no shaping. *)
  let lay = layout_of t st ~width:0. s in
  (* text-overflow:ellipsis truncates a single overflowing line at the
     node's width. *)
  let lines : Lui_text.line array =
    if
      st.ts_ellipsis && Array.length lay.Lui_text.lay_lines = 1
      && lay.Lui_text.lay_lines.(0).Lui_text.ll_line.Lui_text.width
         *. scale > r.w
    then
      (match Lui_text.truncate ~width:(r.w /. scale) font s with
       | Some l -> [| l |]
       | None -> [||])
    else
      Array.map
        (fun (ll : Lui_text.line_layout) -> ll.Lui_text.ll_line)
        lay.Lui_text.lay_lines
  in
  (* Vertical centering inside the node's rect, device pixels. *)
  let text_h =
    Array.fold_left (fun a l -> a +. line_h st l) 0. lines *. scale
  in
  let y0 = r.y +. Float.max 0. ((r.h -. text_h) /. 2.) in
  let gstart = gcount t scene in
  (* Decoration fills draw under the ink, one rect per line per
     decoration, em-sized like the CSS defaults. *)
  let decos = ref [] in
  let em = (Lui_text.metrics font).size in
  let thick = Float.max 1. (em *. 0.0625 *. scale) in
  let line_y = ref 0. in
  Array.iter
    (fun (l : Lui_text.line) ->
       let lh = line_h st l in
       (* line-height splits its extra space above and below the
          glyphs — CSS half-leading. *)
       let half_lead =
         Float.max 0.
           ((lh -. l.ascent -. l.descent -. l.leading) /. 2.)
       in
       let baseline =
         Lui_text.baseline
           (y0 +. !line_y +. (half_lead +. l.ascent) *. scale)
       in
       if st.ts_under || st.ts_strike || st.ts_over then begin
         let fill dy =
           decos :=
             Fill
               { frect =
                   { x = r.x; y = baseline +. dy *. scale;
                     w = l.width *. scale; h = thick };
                 fradii = (0., 0., 0., 0.); fcontinuous = false;
                 fcolor = fg; fpaint = Solid; fcolor2 = fg;
                 fgradient = (0., 0., 0., 0.);
                 fborder = (0., 0., 0., 0.); fborder_color = fg;
                 fdashed = false; fwide = 0; fopacity = 1. }
             :: !decos
         in
         if st.ts_under then fill (em *. 0.09);
         if st.ts_strike then fill (-. (em *. 0.3));
         if st.ts_over then fill (-. (l.ascent +. em *. 0.09))
       end;
       Array.iter
         (fun (run : Lui_text.run) ->
            (* Subpixel positions are a (font, scale) constant — hoist
               out of the per-glyph loop. *)
            let nsub = Lui_text.subpixel_positions ~scale run.font in
            Array.iter
              (fun (g : Lui_text.glyph) ->
                 ignore
                   (emit_glyph t scene ~scale ~nsub
                      ~pen:(r.x +. g.x *. scale)
                      ~baseline ~font:run.font ~gid:g.id ~g_y:g.y ~fg))
              run.glyphs)
         l.runs;
       line_y := !line_y +. lh *. scale)
    lines;
  let gend = gcount t scene in
  if gend = gstart && !decos = [] then []
  else
    let glyph_ops =
      if gend = gstart then []
      else
        [ Glyphs
            { gstart; gend; gpaint = Solid;
              gcolor = fg; gcolor2 = fg; ggradient = (0., 0., 0., 0.);
              gwide2 = 0; gopacity = 1. } ]
    in
    List.rev !decos @ glyph_ops

(* ---- layout measure ---- *)

(* Kinds whose intrinsic size is their text; everything else falls
   back to the layout stub's fixed extents. *)
let textish = function
  | "text" | "heading" | "paragraph" | "label" | "kbd" | "link"
  | "button" | "toggle-button" | "text-field" | "secure-field"
  | "input" | "search-field" | "textarea" | "list-item" | "menu-item"
  | "select" | "combobox" | "checkbox" | "radio" | "switch" -> true
  | _ -> false

let measure t store id ~scale =
  if not (textish (Lui_store.kind store id)) then (0., 0.)
  else
    let text =
      match Lui_store.string_prop store id "text" with
      | Some s when s <> "" -> s
      | _ ->
        (match Lui_store.string_prop store id "placeholder" with
         | Some s -> s
         | None -> "")
    in
    if text = "" then (0., 0.)
    else
      let st = style_of t store id in
      let w, h = extent_of t st text in
      (w *. scale, h *. scale)

(* Device-pixel (w, h) of an arbitrary string in node [id]'s font —
   the caret offset and the composition overlay measure through this
   so they stay consistent with what [text_ops] paints. *)
let measure_text t id s =
  let store = t.store () in
  let st = style_of t store id in
  if s = "" then
    if Lui_store.is_editable_text_kind (Lui_store.kind store id) then
      let height =
        if st.ts_lh > 0. then st.ts_lh
        else (Lui_text.metrics st.ts_font).line_height
      in
      (0., height *. t.scale ())
    else (0., 0.)
  else
    let w, h = extent_of t st s in
    (w *. t.scale (), h *. t.scale ())

(* Byte offset in [text] under the device-px point [(lx, ly)] inside
   the node's rect [lw]x[lh] (both measured from the rect's origin;
   [lw] is unused — the engine paints unwrapped): the same vertical
   centering [text_ops] paints, resolved against the cached layout's
   cluster boundaries. *)
let hit_text t id text ~lx ~ly ~lw:_ ~lh =
  let store = t.store () in
  let scale = t.scale () in
  let st = style_of t store id in
  let lay = layout_of t st ~width:0. text in
  let text_h = styled_height st lay *. scale in
  let y0 = Float.max 0. ((lh -. text_h) /. 2.) in
  let py = (ly -. y0) /. scale in
  (* With a line-height override the painted pitch is [ts_lh], not the
     layout's own line tops — remap [py] into the matching layout
     line so [hit_test] picks the one the pointer actually covers. *)
  let py' =
    let n = Array.length lay.Lui_text.lay_lines in
    if st.ts_lh <= 0. || n = 0 then py
    else
      let k =
        min (n - 1)
          (max 0 (int_of_float (Float.floor (py /. st.ts_lh))))
      in
      let ll = lay.Lui_text.lay_lines.(k) in
      let frac =
        Float.min 1. (Float.max 0. (py /. st.ts_lh -. float k))
      in
      ll.Lui_text.ll_top +. frac *. ll.Lui_text.ll_height
  in
  Lui_text.hit_test lay (lx /. scale, py')
