(* Text engine: font lookup, shaping and glyph rasterization, on the
   platform's own text stack (Fontconfig, Pango and cairo on Linux).
   The engine-agnostic contract is in lui_text_pango.mli; the native
   implementation lives in lui_text_pango_stubs.c.

   Record layouts below are what the C stubs fill, in declaration
   order. *)

(* The platform backend hands us its font handles as custom blocks;
   nothing in OCaml constructs or destructs them. *)
type font = Obj.t

type glyph = {
  id : int;
  x : float;
  y : float;
  advance : float;
  cluster : int;
}

type run = {
  font : font;
  start : int;
  stop : int;
  rtl : bool;
  glyphs : glyph array;
  rcolor : int option;
  under : int;
}

type line = {
  start : int;
  stop : int;
  width : float;
  ascent : float;
  descent : float;
  leading : float;
  runs : run array;
}

type bitmap = {
  left : int;
  top : int;
  w : int;
  h : int;
  color : bool;
  pixels : bytes;
}

external c_named : string -> float -> float -> bool -> font option
  = "lui_pango_named"
external c_system : float -> float -> bool -> bool -> font
  = "lui_pango_system"
external c_cascade : font -> string array -> float -> bool -> font
  = "lui_pango_cascade"
external c_fallback : font -> string -> font option
  = "lui_pango_fallback"
external c_metrics : font -> float * float * float * float
  = "lui_pango_metrics"
external c_is_color : font -> bool = "lui_pango_is_color"
external c_family : font -> string = "lui_pango_family"
external c_shape : font -> string -> float -> bool -> int -> line array
  = "lui_pango_shape"
external c_rasterize : font -> int -> float -> float -> float ->
  bitmap option
  = "lui_pango_rasterize"

(* CSS weight, which the platform font descriptions take natively. *)
let pango_weight w = float (min (max w 100) 900)

(* Generic family names and their concrete expansions. *)
type slot = System of bool | Named of string list

let slot_of_family f =
  let n = String.lowercase_ascii (String.trim f) in
  match n with
  | "" | "system-ui" | "ui-sans-serif" | "sans" | "sans-serif" ->
    Some (System false)
  | "monospace" | "ui-monospace" -> Some (System true)
  | "serif" | "ui-serif" -> Some (Named [ "serif" ])
  | "cursive" | "fantasy" | "emoji" | "math" | "fangsong" ->
    Some (Named [ n ])
  | _ -> Some (Named [ String.trim f ])

let slots_of_families families =
  List.concat_map (String.split_on_char ',') families
  |> List.filter_map slot_of_family

let make_font ~families ~weight ~italic ~size =
  let w = pango_weight weight in
  (* The first family the system has decides the font; the rest of the
     named families come before the system's fallbacks. *)
  let rec first_match = function
    | [] -> None
    | n :: ns ->
      (match c_named n size w italic with
       | Some _ as f -> f
       | None -> first_match ns)
  in
  let rec pick = function
    | [] -> `Sys (c_system size w italic false)
    | System mono :: _ -> `Sys (c_system size w italic mono)
    | Named names :: rest ->
      (match first_match names with
       | Some f -> `Named (f, rest)
       | None -> pick rest)
  in
  match pick (slots_of_families families) with
  | `Sys f -> f
  | `Named (f, rest) ->
    let cascade =
      List.concat_map (function Named ns -> ns | System _ -> []) rest
    in
    (match cascade with
     | [] -> f
     | ns -> c_cascade f (Array.of_list ns) w italic)

(* The same arguments give the same font. *)
let cache : (string list * float * int * bool, font) Hashtbl.t =
  Hashtbl.create 16

let create ?(families = []) ?(weight = 400) ?(italic = false) ~size () =
  let key = (families, size, weight, italic) in
  match Hashtbl.find_opt cache key with
  | Some f -> f
  | None ->
    let f = make_font ~families ~weight ~italic ~size in
    Hashtbl.add cache key f;
    f

let system ?(weight = 400) ?(italic = false) ?(monospace = false)
    ~size () =
  c_system size (pango_weight weight) italic monospace

let fallback = c_fallback

type metrics = {
  size : float;
  ascent : float;
  descent : float;
  leading : float;
  line_height : float;
}

let metrics f =
  let size, ascent, descent, leading = c_metrics f in
  { size; ascent; descent; leading;
    line_height = ascent +. descent +. leading }

let size f =
  let s, _, _, _ = c_metrics f in
  s

let family = c_family
let is_color = c_is_color

let shape ?(width = 0.) ?(rtl = false) f s =
  let m = metrics f in
  let rec lines_of base acc i =
    (* Split on '\n': each piece is shaped as its own paragraph, and an
       empty piece still occupies a line, like the empty last line of a
       trailing newline. *)
    let next =
      match String.index_from_opt s i '\n' with
      | Some n -> n
      | None -> String.length s
    in
    let seg = String.sub s i (next - i) in
    let acc =
      if seg = "" then
        { start = base; stop = base; width = 0.; ascent = m.ascent;
          descent = m.descent; leading = m.leading; runs = [||] }
        :: acc
      else
        List.rev_append
          (Array.to_list (c_shape f seg width rtl base))
          acc
    in
    if next >= String.length s then List.rev acc
    else lines_of (next + 1) acc (next + 1)
  in
  Array.of_list (lines_of 0 [] 0)

let measure ?(width = 0.) ?(rtl = false) f s =
  Array.fold_left
    (fun (mw, h) l ->
       (max mw l.width, h +. l.ascent +. l.descent +. l.leading))
    (0., 0.) (shape ~width ~rtl f s)

let rasterize ?(scale = 1.) ?(dx = 0.) ?(shade = 1.) f id =
  if scale <= 0. || dx < 0. || dx >= 1. then
    invalid_arg "Lui_text_pango.rasterize";
  c_rasterize f id scale dx shade

let subpixel_positions ?(scale = 1.) f =
  (* The platform puts glyph pens at fewer fractional positions the
     larger the font: at most five a pixel, one from about 34 px. *)
  let px = size f *. scale in
  if px <= 0. then 1
  else min 5 (max 1 (int_of_float (ceil (100. /. (3. *. px) -. 1e-9))))

let baseline y = ceil (y -. 1e-3)

(* ================================================================== *)
(* Editing model: styled spans, grapheme clusters, layout, carets,
   hit-testing, selections and a bounded layout cache.

   Everything below except the engine hooks is backend-agnostic: it
   works on the [line]/[run]/[glyph] records every engine produces.
   A Pango or DirectWrite port reuses this whole section verbatim by
   implementing the same hooks ([graphemes], [shape_spans],
   [truncate]). *)

(* ---- span styling ---- *)

(* Per-range style overrides. [sfont] replaces the base font (size is a
   font property, so size changes come through it); [scolor] packs the
   ink color as [0xRRGGBBAA]; [skern] adds points of advance after each
   glyph (letter-spacing); [sunder] is the engine's underline style
   (0 none, 1 single, 2 thick, 9 double). *)
type span_style = {
  sfont : font option;
  scolor : int option;
  skern : float;
  sunder : int;
}

let default_style =
  { sfont = None; scolor = None; skern = 0.; sunder = 0 }

(* A styled byte range of a shared source string: every span passed to
   [shape_spans] carries the same [text], and [range] selects the bytes
   it styles. Ranges may overlap; later spans win per attribute. *)
type span = {
  text : string;
  style : span_style;
  range : int * int;
}

let span_text = function
  | [] -> ""
  | s :: _ -> s.text

(* What the C stub consumes per span: the styled byte range relative
   to the segment being shaped, with resolved attributes. A tuple, not
   a record — the C side reads the fields positionally and OCaml never
   does, so record labels would warn as unused. *)
type span_attr =
  int * int * font option * int option * float * int

external c_shape_spans : font -> string -> float -> bool -> int ->
  span_attr array -> line array
  = "lui_pango_shape_spans_byte" "lui_pango_shape_spans"

external c_graphemes : string -> int array = "lui_pango_graphemes"

external c_truncate : font -> string -> float -> int -> int ->
  line array
  = "lui_pango_truncate"

let shape_spans ?(width = 0.) ?(rtl = false) f spans =
  match spans with
  | [] -> shape ~width ~rtl f ""
  | { text = s; _ } :: _ ->
    let m = metrics f in
    let rec lines_of base acc i =
      (* Same '\n' split as [shape]: paragraphs are shaped one by one
         and each span is clipped to the segment it intersects. *)
      let next =
        match String.index_from_opt s i '\n' with
        | Some n -> n
        | None -> String.length s
      in
      let seg = String.sub s i (next - i) in
      let acc =
        if seg = "" then
          { start = base; stop = base; width = 0.; ascent = m.ascent;
            descent = m.descent; leading = m.leading; runs = [||] }
          :: acc
        else
          let attrs =
            List.filter_map
              (fun sp ->
                 let a, b = sp.range in
                 let lo = max a i and hi = min b next in
                 if hi <= lo then None
                 else
                   Some
                     ( lo - i, hi - i, sp.style.sfont,
                       sp.style.scolor, sp.style.skern,
                       sp.style.sunder ))
              spans
          in
          List.rev_append
            (Array.to_list
               (c_shape_spans f seg width rtl base
                  (Array.of_list attrs)))
            acc
      in
      if next >= String.length s then List.rev acc
      else lines_of (next + 1) acc (next + 1)
    in
    Array.of_list (lines_of 0 [] 0)

(* ---- grapheme clusters ---- *)

(* [graphemes s] is the sorted array of byte offsets where grapheme
   clusters start or end: it always holds 0 and [String.length s], so
   consecutive entries delimit the clusters. The platform's own segment
   rules answer it (grapheme cluster boundaries on this backend:
   combining marks, emoji ZWJ chains, regional indicator pairs and
   Hangul syllables stay whole). *)
let graphemes s =
  if s = "" then [| 0 |] else c_graphemes s

(* Membership test over a sorted boundary table. *)
let mem_break (b : int array) i =
  let lo = ref 0 and hi = ref (Array.length b) in
  let found = ref false in
  while !lo < !hi && not !found do
    let mid = (!lo + !hi) / 2 in
    if b.(mid) = i then found := true
    else if b.(mid) < i then lo := mid + 1
    else hi := mid
  done;
  !found

(* ---- layout ---- *)

(* Point rects, so fractional caret x and subpixel hit geometry stay
   exact; field names are unique across this module's records on
   purpose — record-label disambiguation picks the newest label. *)
type rect = { rx : float; ry : float; rw : float; rh : float }

(* An indivisible caret unit on a line: a byte range the caret can
   enter only at its edges. Units are the cells where a grapheme
   boundary and a shaping-cluster boundary coincide: a ligature
   (several graphemes, one glyph cluster) and a multi-glyph grapheme
   (an emoji drawn by several glyphs) both stay whole. [cx0]/[cx1] is
   the unit's drawn interval in line coordinates — kept fractional so
   subpixel-accurate glyph positions drive hit-testing exactly. *)
type cunit = {
  cs : int;
  ce : int;
  cx0 : float;
  cx1 : float;
  crtl : bool;
  cnl : bool;
}

type line_layout = {
  ll_line : line;
  ll_top : float;
  ll_height : float;
  ll_baseline : float;
  ll_units : cunit array;  (* byte-sorted; a trailing [cnl] unit, when
                              present, covers the line's [\n] *)
}

type layout = {
  lay_text : string;
  lay_wrap : float;
  lay_rtl : bool;
  lay_base : font;
  lay_lines : line_layout array;
  lay_width : float;
  lay_height : float;
  lay_breaks : int array;
}

(* Visual edge helpers: a unit's leading edge is the caret spot before
   its first byte, the trailing edge the spot after its last. In an
   rtl unit the first byte sits at the right edge. *)
let lead_x (u : cunit) = if u.crtl then u.cx1 else u.cx0
let trail_x (u : cunit) = if u.crtl then u.cx0 else u.cx1

(* The byte index a visual edge reports: the left edge of an rtl unit
   is the position *after* its last byte. *)
let edge_left_i (u : cunit) = if u.crtl then u.ce else u.cs
let edge_right_i (u : cunit) = if u.crtl then u.cs else u.ce

(* A line's caret units: grapheme ∩ cluster boundaries tile the line's
   bytes; each unit's interval is the union of the glyphs whose cluster
   starts inside it. [next_start] is the following line's [start] (-1
   for none); when it exceeds [stop] the gap is the line's newline and
   gets a half-em pseudo-unit so selections can light it up. *)
let units_of_line ~em ~wrap ~rtl ~next_start ~breaks (l : line) =
  let bounds =
    let acc = ref [ l.start; l.stop ] in
    Array.iter
      (fun (r : run) ->
         Array.iter
           (fun (g : glyph) -> acc := g.cluster :: !acc)
           r.glyphs)
      l.runs;
    List.sort_uniq compare !acc |> Array.of_list
  in
  let is_caret i =
    i = l.start || i = l.stop || mem_break breaks i
  in
  let cbs = Array.of_list (List.filter is_caret (Array.to_list bounds)) in
  let units = ref [] in
  for k = Array.length cbs - 2 downto 0 do
    let cs = cbs.(k) and ce = cbs.(k + 1) in
    let x0 = ref Float.max_float and x1 = ref (-.Float.max_float) in
    let dir = ref rtl and ng = ref 0 in
    Array.iter
      (fun (r : run) ->
         Array.iter
           (fun (g : glyph) ->
              if g.cluster >= cs && g.cluster < ce then begin
                if !ng = 0 then dir := r.rtl;
                incr ng;
                let a = min g.x (g.x +. g.advance) in
                let b = max g.x (g.x +. g.advance) in
                if a < !x0 then x0 := a;
                if b > !x1 then x1 := b
              end)
           r.glyphs)
      l.runs;
    (* A bound with no glyph is a degenerate cluster start; give the
       unit a zero-width interval at the previous edge rather than
       dropping its bytes from caret coverage. *)
    let x0, x1 =
      if !ng > 0 then (!x0, !x1)
      else (match !units with
        | u :: _ -> (u.cx1, u.cx1)
        | [] -> (0., 0.))
    in
    units :=
      { cs; ce; cx0 = x0; cx1 = x1; crtl = !dir; cnl = false }
      :: !units
  done;
  let base_arr = Array.of_list !units in
  if next_start > l.stop then begin
    (* The [\n] sits past the last unit's trailing edge: right of it
       in an ltr line, left in an rtl one. *)
    let n = Array.length base_arr in
    let anchor, dir =
      if n > 0 then
        let u = base_arr.(n - 1) in
        if u.crtl then (u.cx0, true) else (u.cx1, false)
      else ((if rtl && wrap > 0. then wrap else 0.), rtl)
    in
    let x0, x1 =
      if dir then (anchor -. em /. 2., anchor)
      else (anchor, anchor +. em /. 2.)
    in
    Array.append base_arr
      [| { cs = l.stop; ce = next_start; cx0 = x0; cx1 = x1;
           crtl = dir; cnl = true } |]
  end
  else base_arr

let layout_of_lines ?breaks ?(width = 0.) ?(rtl = false) f s
    (lines : line array) =
  let breaks =
    match breaks with
    | Some b -> b
    | None -> graphemes s
  in
  let em = max 1. (size f) in
  let n = Array.length lines in
  let y = ref 0. and w = ref 0. in
  let lbs =
    Array.init n
      (fun i ->
         let l = lines.(i) in
         let h = l.ascent +. l.descent +. l.leading in
         let next_start =
           if i + 1 < n then lines.(i + 1).start else -1
         in
         let units = units_of_line ~em ~wrap:width ~rtl ~next_start
           ~breaks l in
         let lb =
           { ll_line = l; ll_top = !y; ll_height = h;
             ll_baseline = !y +. l.ascent; ll_units = units }
         in
         if l.width > !w then w := l.width;
         y := !y +. h;
         lb)
  in
  { lay_text = s; lay_wrap = width; lay_rtl = rtl; lay_base = f;
    lay_lines = lbs; lay_width = !w; lay_height = !y;
    lay_breaks = breaks }

let layout ?(width = 0.) ?(rtl = false) ?breaks f s =
  layout_of_lines ?breaks ~width ~rtl f s (shape ~width ~rtl f s)

let layout_spans ?(width = 0.) ?(rtl = false) ?breaks f spans =
  layout_of_lines ?breaks ~width ~rtl f (span_text spans)
    (shape_spans ~width ~rtl f spans)

(* ---- caret, hit-testing, selection ---- *)

(* The line owning byte [i]: the last line starting at or before it.
   An index shared by a wrapped line's end and the next line's start
   lands on the next line; the index just before a [\n] stays on the
   previous one. *)
let line_of_index (lay : layout) i =
  let lines = lay.lay_lines in
  let best = ref 0 in
  for k = 0 to Array.length lines - 1 do
    if lines.(k).ll_line.start <= i then best := k
  done;
  lines.(!best)

let line_index_of (lay : layout) i =
  let best = ref 0 in
  for k = 0 to Array.length lay.lay_lines - 1 do
    if lay.lay_lines.(k).ll_line.start <= i then best := k
  done;
  !best

let caret_rect (lay : layout) i =
  let len = String.length lay.lay_text in
  let i = min (max i 0) len in
  let lb = line_of_index lay i in
  let x =
    match lb.ll_units with
    | [||] ->
      if lay.lay_rtl && lay.lay_wrap > 0. then lay.lay_wrap else 0.
    | us ->
      let n = Array.length us in
      if i <= us.(0).cs then lead_x us.(0)
      else if i >= us.(n - 1).ce then trail_x us.(n - 1)
      else begin
        (* byte-sorted binary search: the unit with cs <= i < ce *)
        let lo = ref 0 and hi = ref (n - 1) in
        while !hi - !lo > 1 do
          let mid = (!lo + !hi) / 2 in
          if us.(mid).cs <= i then lo := mid else hi := mid
        done;
        let u = us.(!lo) in
        if i - u.cs <= u.ce - i then lead_x u else trail_x u
      end
  in
  { rx = x; ry = lb.ll_top; rw = 0.; rh = lb.ll_height }

(* Byte index a point inside [lb] lands on: the nearest unit edge,
   always a grapheme boundary. Units are visited in left-to-right
   order; gaps and overhangs resolve to the nearer edge. *)
let hit_x (lb : line_layout) px =
  let us = lb.ll_units in
  let n = Array.length us in
  if n = 0 then lb.ll_line.start
  else begin
    let vs = Array.copy us in
    Array.sort (fun (a : cunit) (b : cunit) -> compare a.cx0 b.cx0) vs;
    if px <= vs.(0).cx0 then edge_left_i vs.(0)
    else if px >= vs.(n - 1).cx1 then edge_right_i vs.(n - 1)
    else begin
      let res = ref (edge_right_i vs.(n - 1)) in
      let stop = ref false in
      for k = 0 to n - 1 do
        if not !stop then begin
          let u = vs.(k) in
          if px >= u.cx0 && px <= u.cx1 then begin
            res :=
              (* The newline pseudo-unit's whole span is the line's
                 end: clicks past the last glyph land on its first
                 edge, not across the [\n]. *)
              (if u.cnl then u.cs
               else if px -. u.cx0 <= u.cx1 -. px then edge_left_i u
               else edge_right_i u);
            stop := true
          end
          else if px < u.cx0 && k > 0 then begin
            (* Between units: nearer of the two adjacent edges. *)
            let p = vs.(k - 1) in
            res :=
              (if px -. p.cx1 <= u.cx0 -. px then edge_right_i p
               else edge_left_i u);
            stop := true
          end
        end
      done;
      !res
    end
  end

let hit_test (lay : layout) (px, py) =
  let lines = lay.lay_lines in
  let n = Array.length lines in
  if n = 0 then 0
  else
    let rec find k =
      if k = n - 1 then lines.(k)
      else if py < lines.(k).ll_top +. lines.(k).ll_height
      then lines.(k)
      else find (k + 1)
    in
    hit_x (find 0) px

let selection_rects (lay : layout) (a, b) =
  let len = String.length lay.lay_text in
  let lo = min (max (min a b) 0) len
  and hi = min (max (max a b) 0) len in
  if lo >= hi then []
  else begin
    let rects = ref [] in
    Array.iter
      (fun (lb : line_layout) ->
         let cov =
           Array.to_list lb.ll_units
           |> List.filter (fun u -> u.cs < hi && u.ce > lo)
           |> List.sort (fun (a : cunit) (b : cunit) ->
                compare a.cx0 b.cx0)
         in
         (* Covered intervals merge only while they touch: a unit left
            out between two covered ones (a bidi gap) stays a gap. *)
         match cov with
         | [] -> ()
         | u0 :: rest ->
           let x0 = ref u0.cx0 and x1 = ref u0.cx1 in
           List.iter
             (fun u ->
                if u.cx0 <= !x1 +. 0.01 then x1 := max !x1 u.cx1
                else begin
                  rects :=
                    { rx = !x0; ry = lb.ll_top; rw = !x1 -. !x0;
                      rh = lb.ll_height }
                    :: !rects;
                  x0 := u.cx0;
                  x1 := u.cx1
                end)
             rest;
           rects :=
             { rx = !x0; ry = lb.ll_top; rw = !x1 -. !x0;
               rh = lb.ll_height }
             :: !rects)
      lay.lay_lines;
    List.rev !rects
  end

(* ---- caret movement ---- *)

(* Every caret position of the layout, sorted: unit edges plus the
   text's own ends (a trailing empty line contributes none). *)
let caret_positions (lay : layout) =
  let acc = ref [ 0; String.length lay.lay_text ] in
  Array.iter
    (fun (lb : line_layout) ->
       Array.iter (fun u -> acc := u.cs :: u.ce :: !acc) lb.ll_units)
    lay.lay_lines;
  List.sort_uniq compare !acc |> Array.of_list

let caret_before (lay : layout) i =
  let best = ref 0 in
  Array.iter
    (fun b -> if b < i && b > !best then best := b)
    (caret_positions lay);
  !best

let caret_after (lay : layout) i =
  let best = ref (String.length lay.lay_text) in
  Array.iter
    (fun b -> if b > i && b < !best then best := b)
    (caret_positions lay);
  !best

(* Vertical movement keeps the caret's x and hit-tests the next line.
   At the document edges it clamps to the string's ends. *)
let caret_vert ~dir (lay : layout) i =
  let n = Array.length lay.lay_lines in
  if n <= 1 then if dir < 0 then 0 else String.length lay.lay_text
  else begin
    let li = line_index_of lay i in
    let target = li + dir in
    if target < 0 then 0
    else if target >= n then String.length lay.lay_text
    else hit_x lay.lay_lines.(target) (caret_rect lay i).rx
  end

let caret_up lay i = caret_vert ~dir:(-1) lay i
let caret_down lay i = caret_vert ~dir:1 lay i

(* ---- UTF-16 index mapping ---- *)

(* Decode one UTF-8 character at byte [i]: (code point, byte length).
   The C side emits U+FFFD per bad byte; the same rule here keeps the
   maps aligned with what shaping sees. *)
let decode_utf8 s i =
  let len = String.length s in
  let c = Char.code s.[i] in
  if c < 0x80 then (c, 1)
  else if c < 0xC0 then (0xFFFD, 1)
  else
    let need, init =
      if c < 0xE0 then (2, c land 0x1F)
      else if c < 0xF0 then (3, c land 0x0F)
      else if c < 0xF8 then (4, c land 0x07)
      else (0, 0)
    in
    if need = 0 || i + need > len then (0xFFFD, 1)
    else
      let rec cont k r =
        if k = need then Some r
        else
          let cc = Char.code s.[i + k] in
          if cc land 0xC0 <> 0x80 then None
          else cont (k + 1) ((r lsl 6) lor (cc land 0x3F))
      in
      match cont 1 init with
      | Some r
        when r >= (match need with 2 -> 0x80 | 3 -> 0x800 | _ -> 0x10000)
             && r <= 0x10FFFF && not (r >= 0xD800 && r < 0xE000) ->
        (r, need)
      | _ -> (0xFFFD, 1)

let units_of_cp cp = if cp > 0xFFFF then 2 else 1

let utf16_length s =
  let n = String.length s in
  let rec go i acc =
    if i >= n then acc
    else
      let cp, w = decode_utf8 s i in
      go (i + w) (acc + units_of_cp cp)
  in
  go 0 0

let utf16_of_byte s i =
  let n = String.length s in
  let i = min (max i 0) n in
  let rec go p acc =
    if p >= n then acc
    else
      let cp, w = decode_utf8 s p in
      (* A byte inside a character maps to the unit index where that
         character starts. *)
      if p + w > i then acc
      else go (p + w) (acc + units_of_cp cp)
  in
  go 0 0

let byte_of_utf16 s u =
  let n = String.length s in
  let rec go p acc =
    if p >= n then n
    else
      let cp, w = decode_utf8 s p in
      let un = units_of_cp cp in
      (* A unit inside a character — a surrogate's second half — maps
         to the character's start byte. *)
      if acc + un > u then p
      else go (p + w) (acc + un)
  in
  go 0 0

(* ---- truncation ---- *)

(* [truncate ~width f s] is [s]'s first paragraph shrunk to one line
   of at most [width] points, [mode] picking where the engine's
   ellipsis token goes. *)
let truncate ?(mode = `End) ?(rtl = false) ~width f s =
  let s =
    match String.index_opt s '\n' with
    | Some n -> String.sub s 0 n
    | None -> s
  in
  if s = "" || width <= 0. then None
  else
    let m =
      match mode with
      | `End -> 0
      | `Start -> 1
      | `Middle -> 2
    in
    match c_truncate f s width m (if rtl then 1 else 0) with
    | [| l |] -> Some l
    | _ -> None

(* ---- bounded layout cache ---- *)

(* Shaped layouts are expensive; editing paths measure often and paint
   sometimes, so the cache is measure-first: [measure] populates the
   same entry a later [layout] reuses. Entries keyed by
   (text, wrap width, direction, font, span signature) live in an LRU;
   an entry whose text exceeds [max_bytes] is built but not kept, so a
   giant paragraph can't evict everything else. *)
module Cache = struct
  (* The span part of a key: (start, stop, font, color, kern, under)
     per span, kern quantized to thousandths of a point. *)
  type span_sig =
    (int * int * font option * int option * int * int) list

  type key =
    | K_sentinel
    | K of string * float * bool * font * span_sig

  (* Intrusive doubly-linked list behind the table: head.next is the
     hottest entry, head.prev the eviction candidate. *)
  type node = {
    nkey : key;
    nlay : layout option;  (* None only on the sentinel *)
    mutable nprev : node;
    mutable nnext : node;
  }

  type t = {
    cap : int;
    maxb : int;
    tbl : (key, node) Hashtbl.t;
    head : node;
    mutable hits : int;
    mutable misses : int;
    mutable ver : int;
  }

  let create ?(max_bytes = 65536) cap =
    let rec head =
      { nkey = K_sentinel; nlay = None; nprev = head; nnext = head }
    in
    { cap = max 1 cap; maxb = max_bytes; tbl = Hashtbl.create 64;
      head; hits = 0; misses = 0; ver = 0 }

  let detach n =
    n.nprev.nnext <- n.nnext;
    n.nnext.nprev <- n.nprev

  let push_front t n =
    n.nprev <- t.head;
    n.nnext <- t.head.nnext;
    t.head.nnext.nprev <- n;
    t.head.nnext <- n

  let clear t =
    Hashtbl.reset t.tbl;
    t.head.nnext <- t.head;
    t.head.nprev <- t.head

  (* Glyph identities inside a layout reference the atlas implicitly:
      when the atlas version bumps the entries must not survive. *)
  let set_version t v =
    if v <> t.ver then begin
      clear t;
      t.ver <- v
    end

  let version t = t.ver
  let stats t = (t.hits, t.misses)
  let length t = Hashtbl.length t.tbl

  let get t ~key ~text_len build =
    match Hashtbl.find_opt t.tbl key with
    | Some n ->
      detach n;
      push_front t n;
      t.hits <- t.hits + 1;
      Option.get n.nlay
    | None ->
      t.misses <- t.misses + 1;
      let v = build () in
      if text_len <= t.maxb then begin
        let n =
          { nkey = key; nlay = Some v; nprev = t.head; nnext = t.head }
        in
        push_front t n;
        Hashtbl.replace t.tbl key n;
        if Hashtbl.length t.tbl > t.cap then begin
          let lru = t.head.nprev in
          if lru != t.head then begin
            detach lru;
            Hashtbl.remove t.tbl lru.nkey
          end
        end
      end;
      v

  let layout t ?(rtl = false) ?(width = 0.) f s =
    get t ~key:(K (s, width, rtl, f, [])) ~text_len:(String.length s)
      (fun () -> layout ~width ~rtl f s)

  let measure t ?(rtl = false) ?(width = 0.) f s =
    let l = layout t ~rtl ~width f s in
    (l.lay_width, l.lay_height)

  let sig_of_spans spans =
    List.map
      (fun sp ->
         let a, b = sp.range in
         (a, b, sp.style.sfont, sp.style.scolor,
          int_of_float (sp.style.skern *. 1024.), sp.style.sunder))
      spans

  let layout_spans t ?(rtl = false) ?(width = 0.) f spans =
    let s = span_text spans in
    get t ~key:(K (s, width, rtl, f, sig_of_spans spans))
      ~text_len:(String.length s)
      (fun () -> layout_spans ~width ~rtl f spans)
end
