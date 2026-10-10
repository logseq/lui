(* Text engine: font lookup, shaping and glyph rasterization, on the
   platform's own text stack (DirectWrite on Windows). The
   engine-agnostic contract is in lui_text_dwrite.mli; the native
   implementation lives in lui_text_dwrite_stubs.c.

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
  = "lui_dwrite_named"
external c_system : float -> float -> bool -> bool -> font
  = "lui_dwrite_system"
external c_cascade : font -> string array -> float -> bool -> font
  = "lui_dwrite_cascade"
external c_fallback : font -> string -> font option
  = "lui_dwrite_fallback"
external c_metrics : font -> float * float * float * float
  = "lui_dwrite_metrics"
external c_is_color : font -> bool = "lui_dwrite_is_color"
external c_family : font -> string = "lui_dwrite_family"
external c_shape : font -> string -> float -> bool -> int -> line array
  = "lui_dwrite_shape"
external c_rasterize : font -> int -> float -> float -> float ->
  bitmap option
  = "lui_dwrite_rasterize"

(* What the C stub consumes per span: the styled byte range relative
   to the segment being shaped, with resolved attributes. A tuple, not
   a record — the C side reads the fields positionally and OCaml never
   does, so record labels would warn as unused. *)
type span_attr =
  int * int * font option * int option * float * int

external c_shape_spans : font -> string -> float -> bool -> int ->
  span_attr array -> line array
  = "lui_dwrite_shape_spans_byte" "lui_dwrite_shape_spans"

(* CSS weight, which the platform font matching takes natively. *)
let dwrite_weight w = float (min (max w 100) 900)
(* Generic family names and their concrete expansions. *)
type slot = System of bool | Named of string list

let slot_of_family f =
  let n = String.lowercase_ascii (String.trim f) in
  match n with
  | "" | "system-ui" | "ui-sans-serif" | "sans" | "sans-serif"
  | "-apple-system" | "blinkmacsystemfont" -> Some (System false)
  | "monospace" | "ui-monospace" -> Some (System true)
  | "serif" | "ui-serif" ->
    Some (Named [ "Times New Roman"; "Cambria"; "Georgia" ])
  | "cursive" | "fantasy" | "emoji" | "math" | "fangsong" ->
    Some (Named [ n ])
  | _ -> Some (Named [ String.trim f ])

let slots_of_families families =
  List.concat_map (String.split_on_char ',') families
  |> List.filter_map slot_of_family

let make_font ~families ~weight ~italic ~size =
  let w = dwrite_weight weight in
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
  c_system size (dwrite_weight weight) italic monospace

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
(0., 0.)
(shape ~width ~rtl f s)

let rasterize ?(scale = 1.) ?(dx = 0.) ?(shade = 1.) f id =
  if scale <= 0. || dx < 0. || dx >= 1. then
    invalid_arg "Lui_text_dwrite.rasterize";
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
(* Grapheme cluster break classes by code point range, generated from *)
(* UCD GraphemeBreakProperty.txt (Unicode 16). Class tags: *)
(* 1 CR  2 LF  3 Control  4 Extend  5 ZWJ  6 RI  7 Prepend *)
(* 8 SpacingMark  9 L  10 V  11 T  12 LV  13 LVT  (0 = Other) *)
(* Each entry is (first, last + 1, class). *)
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
          else cont (k + 1)
((r lsl 6) lor (cc land 0x3F))
      in
      match cont 1 init with
      | Some r
        when r >= (match need with 2 -> 0x80 | 3 -> 0x800 | _ -> 0x10000)
             && r <= 0x10FFFF && not (r >= 0xD800 && r < 0xE000) ->
        (r, need)
      | _ -> (0xFFFD, 1)


let gcb_table = [|
   (0x0,0xA,3); (0xA,0xB,2); (0xB,0xD,3); (0xD,0xE,1); (0xE,0x20,3); (0x7F,0xA0,3); (0xAD,0xAE,3); (0x300,0x370,4); (0x483,0x48A,4); (0x591,0x5BE,4); (0x5BF,0x5C0,4); (0x5C1,0x5C3,4); (0x5C4,0x5C6,4); (0x5C7,0x5CA,4); (0x600,0x606,7); (0x610,0x61B,4); (0x61C,0x61D,3); (0x64B,0x660,4); (0x670,0x671,4); (0x6D6,0x6DD,4); (0x6DD,0x6DE,7); (0x6DF,0x6E5,4); (0x6E7,0x6E9,4); (0x6EA,0x6EE,4); (0x70F,0x710,7); (0x711,0x712,4); (0x730,0x74B,4); (0x7A6,0x7B1,4); (0x7EB,0x7F4,4); (0x7FD,0x7FE,4); (0x816,0x81A,4); (0x81B,0x824,4); (0x825,0x828,4); (0x829,0x82E,4); (0x859,0x85C,4); (0x890,0x892,7); (0x897,0x8A0,4); (0x8CA,0x8E2,4); (0x8E2,0x8E3,7); (0x8E3,0x903,4); (0x903,0x904,8); (0x93A,0x93B,4); (0x93B,0x93C,8); (0x93C,0x93D,4); (0x93E,0x941,8); (0x941,0x949,4); (0x949,0x94D,8); (0x94D,0x94E,4); (0x94E,0x950,8); (0x951,0x958,4); (0x962,0x964,4); (0x981,0x982,4); (0x982,0x984,8); (0x9BC,0x9BD,4); (0x9BE,0x9BF,4); (0x9BF,0x9C1,8); (0x9C1,0x9C5,4); (0x9C7,0x9C9,8); (0x9CB,0x9CD,8); (0x9CD,0x9CE,4); (0x9D7,0x9D8,4); (0x9E2,0x9E4,4); (0x9FE,0x9FF,4); (0xA01,0xA03,4); (0xA03,0xA04,8); (0xA3C,0xA3D,4); (0xA3E,0xA41,8); (0xA41,0xA43,4); (0xA47,0xA49,4); (0xA4B,0xA4E,4); (0xA51,0xA52,4); (0xA70,0xA72,4); (0xA75,0xA76,4); (0xA81,0xA83,4); (0xA83,0xA84,8); (0xABC,0xABD,4); (0xABE,0xAC1,8); (0xAC1,0xAC6,4); (0xAC7,0xAC9,4); (0xAC9,0xACA,8); (0xACB,0xACD,8); (0xACD,0xACE,4); (0xAE2,0xAE4,4); (0xAFA,0xB00,4); (0xB01,0xB02,4); (0xB02,0xB04,8); (0xB3C,0xB3D,4); (0xB3E,0xB40,4); (0xB40,0xB41,8); (0xB41,0xB45,4); (0xB47,0xB49,8); (0xB4B,0xB4D,8); (0xB4D,0xB4E,4); (0xB53,0xB58,4); (0xB62,0xB64,4); (0xB82,0xB83,4); (0xBBE,0xBBF,4); (0xBBF,0xBC0,8); (0xBC0,0xBC1,4); (0xBC1,0xBC3,8); (0xBC6,0xBC9,8); (0xBCA,0xBCD,8); (0xBCD,0xBCE,4); (0xBD7,0xBD8,4); (0xC00,0xC01,4); (0xC01,0xC04,8); (0xC04,0xC05,4); (0xC3C,0xC3D,4); (0xC3E,0xC41,4); (0xC41,0xC45,8); (0xC46,0xC49,4); (0xC4A,0xC4E,4); (0xC55,0xC57,4); (0xC62,0xC64,4); (0xC81,0xC82,4); (0xC82,0xC84,8); (0xCBC,0xCBD,4); (0xCBE,0xCBF,8); (0xCBF,0xCC1,4); (0xCC1,0xCC2,8); (0xCC2,0xCC3,4); (0xCC3,0xCC5,8); (0xCC6,0xCC9,4); (0xCCA,0xCCE,4); (0xCD5,0xCD7,4); (0xCE2,0xCE4,4); (0xCF3,0xCF4,8); (0xD00,0xD02,4); (0xD02,0xD04,8); (0xD3B,0xD3D,4); (0xD3E,0xD3F,4); (0xD3F,0xD41,8); (0xD41,0xD45,4); (0xD46,0xD49,8); (0xD4A,0xD4D,8); (0xD4D,0xD4E,4); (0xD4E,0xD4F,7); (0xD57,0xD58,4); (0xD62,0xD64,4); (0xD81,0xD82,4); (0xD82,0xD84,8); (0xDCA,0xDCB,4); (0xDCF,0xDD0,4); (0xDD0,0xDD2,8); (0xDD2,0xDD5,4); (0xDD6,0xDD7,4); (0xDD8,0xDDF,8); (0xDDF,0xDE0,4); (0xDF2,0xDF4,8); (0xE31,0xE32,4); (0xE33,0xE34,8); (0xE34,0xE3B,4); (0xE47,0xE4F,4); (0xEB1,0xEB2,4); (0xEB3,0xEB4,8); (0xEB4,0xEBD,4); (0xEC8,0xECF,4); (0xF18,0xF1A,4); (0xF35,0xF36,4); (0xF37,0xF38,4); (0xF39,0xF3A,4); (0xF3E,0xF40,8); (0xF71,0xF7F,4); (0xF7F,0xF80,8); (0xF80,0xF85,4); (0xF86,0xF88,4); (0xF8D,0xF98,4); (0xF99,0xFBD,4); (0xFC6,0xFC7,4); (0x102D,0x1031,4); (0x1031,0x1032,8); (0x1032,0x1038,4); (0x1039,0x103B,4); (0x103B,0x103D,8); (0x103D,0x103F,4); (0x1056,0x1058,8); (0x1058,0x105A,4); (0x105E,0x1061,4); (0x1071,0x1075,4); (0x1082,0x1083,4); (0x1084,0x1085,8); (0x1085,0x1087,4); (0x108D,0x108E,4); (0x109D,0x109E,4); (0x1100,0x1160,9); (0x1160,0x11A8,10); (0x11A8,0x1200,11); (0x135D,0x1360,4); (0x1712,0x1716,4); (0x1732,0x1735,4); (0x1752,0x1754,4); (0x1772,0x1774,4); (0x17B4,0x17B6,4); (0x17B6,0x17B7,8); (0x17B7,0x17BE,4); (0x17BE,0x17C6,8); (0x17C6,0x17C7,4); (0x17C7,0x17C9,8); (0x17C9,0x17D4,4); (0x17DD,0x17DE,4); (0x180B,0x180E,4); (0x180E,0x180F,3); (0x180F,0x1810,4); (0x1885,0x1887,4); (0x18A9,0x18AA,4); (0x1920,0x1923,4); (0x1923,0x1927,8); (0x1927,0x1929,4); (0x1929,0x192C,8); (0x1930,0x1932,8); (0x1932,0x1933,4); (0x1933,0x1939,8); (0x1939,0x193C,4); (0x1A17,0x1A19,4); (0x1A19,0x1A1B,8); (0x1A1B,0x1A1C,4); (0x1A55,0x1A56,8); (0x1A56,0x1A57,4); (0x1A57,0x1A58,8); (0x1A58,0x1A5F,4); (0x1A60,0x1A61,4); (0x1A62,0x1A63,4); (0x1A65,0x1A6D,4); (0x1A6D,0x1A73,8); (0x1A73,0x1A7D,4); (0x1A7F,0x1A80,4); (0x1AB0,0x1AF1,4); (0x1B00,0x1B04,4); (0x1B04,0x1B05,8); (0x1B34,0x1B3E,4); (0x1B3E,0x1B42,8); (0x1B42,0x1B45,4); (0x1B6B,0x1B74,4); (0x1B80,0x1B82,4); (0x1B82,0x1B83,8); (0x1BA1,0x1BA2,8); (0x1BA2,0x1BA6,4); (0x1BA6,0x1BA8,8); (0x1BA8,0x1BAE,4); (0x1BE6,0x1BE7,4); (0x1BE7,0x1BE8,8); (0x1BE8,0x1BEA,4); (0x1BEA,0x1BED,8); (0x1BED,0x1BEE,4); (0x1BEE,0x1BEF,8); (0x1BEF,0x1BF4,4); (0x1C24,0x1C2C,8); (0x1C2C,0x1C34,4); (0x1C34,0x1C36,8); (0x1C36,0x1C38,4); (0x1CD0,0x1CD3,4); (0x1CD4,0x1CE1,4); (0x1CE1,0x1CE2,8); (0x1CE2,0x1CE9,4); (0x1CED,0x1CEE,4); (0x1CF4,0x1CF5,4); (0x1CF7,0x1CF8,8); (0x1CF8,0x1CFA,4); (0x1DC0,0x1E00,4); (0x200B,0x200C,3); (0x200C,0x200D,4); (0x200D,0x200E,5); (0x200E,0x2010,3); (0x2028,0x202F,3); (0x2060,0x2070,3); (0x20D0,0x20F1,4); (0x2CEF,0x2CF2,4); (0x2D7F,0x2D80,4); (0x2DE0,0x2E00,4); (0x302A,0x3030,4); (0x3099,0x309B,4); (0xA66F,0xA673,4); (0xA674,0xA67E,4); (0xA69E,0xA6A0,4); (0xA6F0,0xA6F2,4); (0xA802,0xA803,4); (0xA806,0xA807,4); (0xA80B,0xA80C,4); (0xA823,0xA825,8); (0xA825,0xA827,4); (0xA827,0xA828,8); (0xA82C,0xA82D,4); (0xA880,0xA882,8); (0xA8B4,0xA8C4,8); (0xA8C4,0xA8C6,4); (0xA8E0,0xA8F2,4); (0xA8FF,0xA900,4); (0xA926,0xA92E,4); (0xA947,0xA952,4); (0xA952,0xA953,8); (0xA953,0xA954,4); (0xA960,0xA97D,9); (0xA980,0xA983,4); (0xA983,0xA984,8); (0xA9B3,0xA9B4,4); (0xA9B4,0xA9B6,8); (0xA9B6,0xA9BA,4); (0xA9BA,0xA9BC,8); (0xA9BC,0xA9BE,4); (0xA9BE,0xA9C0,8); (0xA9C0,0xA9C1,4); (0xA9E5,0xA9E6,4); (0xAA29,0xAA2F,4); (0xAA2F,0xAA31,8); (0xAA31,0xAA33,4); (0xAA33,0xAA35,8); (0xAA35,0xAA37,4); (0xAA43,0xAA44,4); (0xAA4C,0xAA4D,4); (0xAA4D,0xAA4E,8); (0xAA7C,0xAA7D,4); (0xAAB0,0xAAB1,4); (0xAAB2,0xAAB5,4); (0xAAB7,0xAAB9,4); (0xAABE,0xAAC0,4); (0xAAC1,0xAAC2,4); (0xAAEB,0xAAEC,8); (0xAAEC,0xAAEE,4); (0xAAEE,0xAAF0,8); (0xAAF5,0xAAF6,8); (0xAAF6,0xAAF7,4); (0xABE3,0xABE5,8); (0xABE5,0xABE6,4); (0xABE6,0xABE8,8); (0xABE8,0xABE9,4); (0xABE9,0xABEB,8); (0xABEC,0xABED,8); (0xABED,0xABEE,4); (0xAC00,0xAC01,12); (0xAC01,0xAC1C,13); (0xAC1C,0xAC1D,12); (0xAC1D,0xAC38,13); (0xAC38,0xAC39,12); (0xAC39,0xAC54,13); (0xAC54,0xAC55,12); (0xAC55,0xAC70,13); (0xAC70,0xAC71,12); (0xAC71,0xAC8C,13); (0xAC8C,0xAC8D,12); (0xAC8D,0xACA8,13); (0xACA8,0xACA9,12); (0xACA9,0xACC4,13); (0xACC4,0xACC5,12); (0xACC5,0xACE0,13); (0xACE0,0xACE1,12); (0xACE1,0xACFC,13); (0xACFC,0xACFD,12); (0xACFD,0xAD18,13); (0xAD18,0xAD19,12); (0xAD19,0xAD34,13); (0xAD34,0xAD35,12); (0xAD35,0xAD50,13); (0xAD50,0xAD51,12); (0xAD51,0xAD6C,13); (0xAD6C,0xAD6D,12); (0xAD6D,0xAD88,13); (0xAD88,0xAD89,12); (0xAD89,0xADA4,13); (0xADA4,0xADA5,12); (0xADA5,0xADC0,13); (0xADC0,0xADC1,12); (0xADC1,0xADDC,13); (0xADDC,0xADDD,12); (0xADDD,0xADF8,13); (0xADF8,0xADF9,12); (0xADF9,0xAE14,13); (0xAE14,0xAE15,12); (0xAE15,0xAE30,13); (0xAE30,0xAE31,12); (0xAE31,0xAE4C,13); (0xAE4C,0xAE4D,12); (0xAE4D,0xAE68,13); (0xAE68,0xAE69,12); (0xAE69,0xAE84,13); (0xAE84,0xAE85,12); (0xAE85,0xAEA0,13); (0xAEA0,0xAEA1,12); (0xAEA1,0xAEBC,13); (0xAEBC,0xAEBD,12); (0xAEBD,0xAED8,13); (0xAED8,0xAED9,12); (0xAED9,0xAEF4,13); (0xAEF4,0xAEF5,12); (0xAEF5,0xAF10,13); (0xAF10,0xAF11,12); (0xAF11,0xAF2C,13); (0xAF2C,0xAF2D,12); (0xAF2D,0xAF48,13); (0xAF48,0xAF49,12); (0xAF49,0xAF64,13); (0xAF64,0xAF65,12); (0xAF65,0xAF80,13); (0xAF80,0xAF81,12); (0xAF81,0xAF9C,13); (0xAF9C,0xAF9D,12); (0xAF9D,0xAFB8,13); (0xAFB8,0xAFB9,12); (0xAFB9,0xAFD4,13); (0xAFD4,0xAFD5,12); (0xAFD5,0xAFF0,13); (0xAFF0,0xAFF1,12); (0xAFF1,0xB00C,13); (0xB00C,0xB00D,12); (0xB00D,0xB028,13); (0xB028,0xB029,12); (0xB029,0xB044,13); (0xB044,0xB045,12); (0xB045,0xB060,13); (0xB060,0xB061,12); (0xB061,0xB07C,13); (0xB07C,0xB07D,12); (0xB07D,0xB098,13); (0xB098,0xB099,12); (0xB099,0xB0B4,13); (0xB0B4,0xB0B5,12); (0xB0B5,0xB0D0,13); (0xB0D0,0xB0D1,12); (0xB0D1,0xB0EC,13); (0xB0EC,0xB0ED,12); (0xB0ED,0xB108,13); (0xB108,0xB109,12); (0xB109,0xB124,13); (0xB124,0xB125,12); (0xB125,0xB140,13); (0xB140,0xB141,12); (0xB141,0xB15C,13); (0xB15C,0xB15D,12); (0xB15D,0xB178,13); (0xB178,0xB179,12); (0xB179,0xB194,13); (0xB194,0xB195,12); (0xB195,0xB1B0,13); (0xB1B0,0xB1B1,12); (0xB1B1,0xB1CC,13); (0xB1CC,0xB1CD,12); (0xB1CD,0xB1E8,13); (0xB1E8,0xB1E9,12); (0xB1E9,0xB204,13); (0xB204,0xB205,12); (0xB205,0xB220,13); (0xB220,0xB221,12); (0xB221,0xB23C,13); (0xB23C,0xB23D,12); (0xB23D,0xB258,13); (0xB258,0xB259,12); (0xB259,0xB274,13); (0xB274,0xB275,12); (0xB275,0xB290,13); (0xB290,0xB291,12); (0xB291,0xB2AC,13); (0xB2AC,0xB2AD,12); (0xB2AD,0xB2C8,13); (0xB2C8,0xB2C9,12); (0xB2C9,0xB2E4,13); (0xB2E4,0xB2E5,12); (0xB2E5,0xB300,13); (0xB300,0xB301,12); (0xB301,0xB31C,13); (0xB31C,0xB31D,12); (0xB31D,0xB338,13); (0xB338,0xB339,12); (0xB339,0xB354,13); (0xB354,0xB355,12); (0xB355,0xB370,13); (0xB370,0xB371,12); (0xB371,0xB38C,13); (0xB38C,0xB38D,12); (0xB38D,0xB3A8,13); (0xB3A8,0xB3A9,12); (0xB3A9,0xB3C4,13); (0xB3C4,0xB3C5,12); (0xB3C5,0xB3E0,13); (0xB3E0,0xB3E1,12); (0xB3E1,0xB3FC,13); (0xB3FC,0xB3FD,12); (0xB3FD,0xB418,13); (0xB418,0xB419,12); (0xB419,0xB434,13); (0xB434,0xB435,12); (0xB435,0xB450,13); (0xB450,0xB451,12); (0xB451,0xB46C,13); (0xB46C,0xB46D,12); (0xB46D,0xB488,13); (0xB488,0xB489,12); (0xB489,0xB4A4,13); (0xB4A4,0xB4A5,12); (0xB4A5,0xB4C0,13); (0xB4C0,0xB4C1,12); (0xB4C1,0xB4DC,13); (0xB4DC,0xB4DD,12); (0xB4DD,0xB4F8,13); (0xB4F8,0xB4F9,12); (0xB4F9,0xB514,13); (0xB514,0xB515,12); (0xB515,0xB530,13); (0xB530,0xB531,12); (0xB531,0xB54C,13); (0xB54C,0xB54D,12); (0xB54D,0xB568,13); (0xB568,0xB569,12); (0xB569,0xB584,13); (0xB584,0xB585,12); (0xB585,0xB5A0,13); (0xB5A0,0xB5A1,12); (0xB5A1,0xB5BC,13); (0xB5BC,0xB5BD,12); (0xB5BD,0xB5D8,13); (0xB5D8,0xB5D9,12); (0xB5D9,0xB5F4,13); (0xB5F4,0xB5F5,12); (0xB5F5,0xB610,13); (0xB610,0xB611,12); (0xB611,0xB62C,13); (0xB62C,0xB62D,12); (0xB62D,0xB648,13); (0xB648,0xB649,12); (0xB649,0xB664,13); (0xB664,0xB665,12); (0xB665,0xB680,13); (0xB680,0xB681,12); (0xB681,0xB69C,13); (0xB69C,0xB69D,12); (0xB69D,0xB6B8,13); (0xB6B8,0xB6B9,12); (0xB6B9,0xB6D4,13); (0xB6D4,0xB6D5,12); (0xB6D5,0xB6F0,13); (0xB6F0,0xB6F1,12); (0xB6F1,0xB70C,13); (0xB70C,0xB70D,12); (0xB70D,0xB728,13); (0xB728,0xB729,12); (0xB729,0xB744,13); (0xB744,0xB745,12); (0xB745,0xB760,13); (0xB760,0xB761,12); (0xB761,0xB77C,13); (0xB77C,0xB77D,12); (0xB77D,0xB798,13); (0xB798,0xB799,12); (0xB799,0xB7B4,13); (0xB7B4,0xB7B5,12); (0xB7B5,0xB7D0,13); (0xB7D0,0xB7D1,12); (0xB7D1,0xB7EC,13); (0xB7EC,0xB7ED,12); (0xB7ED,0xB808,13); (0xB808,0xB809,12); (0xB809,0xB824,13); (0xB824,0xB825,12); (0xB825,0xB840,13); (0xB840,0xB841,12); (0xB841,0xB85C,13); (0xB85C,0xB85D,12); (0xB85D,0xB878,13); (0xB878,0xB879,12); (0xB879,0xB894,13); (0xB894,0xB895,12); (0xB895,0xB8B0,13); (0xB8B0,0xB8B1,12); (0xB8B1,0xB8CC,13); (0xB8CC,0xB8CD,12); (0xB8CD,0xB8E8,13); (0xB8E8,0xB8E9,12); (0xB8E9,0xB904,13); (0xB904,0xB905,12); (0xB905,0xB920,13); (0xB920,0xB921,12); (0xB921,0xB93C,13); (0xB93C,0xB93D,12); (0xB93D,0xB958,13); (0xB958,0xB959,12); (0xB959,0xB974,13); (0xB974,0xB975,12); (0xB975,0xB990,13); (0xB990,0xB991,12); (0xB991,0xB9AC,13); (0xB9AC,0xB9AD,12); (0xB9AD,0xB9C8,13); (0xB9C8,0xB9C9,12); (0xB9C9,0xB9E4,13); (0xB9E4,0xB9E5,12); (0xB9E5,0xBA00,13); (0xBA00,0xBA01,12); (0xBA01,0xBA1C,13); (0xBA1C,0xBA1D,12); (0xBA1D,0xBA38,13); (0xBA38,0xBA39,12); (0xBA39,0xBA54,13); (0xBA54,0xBA55,12); (0xBA55,0xBA70,13); (0xBA70,0xBA71,12); (0xBA71,0xBA8C,13); (0xBA8C,0xBA8D,12); (0xBA8D,0xBAA8,13); (0xBAA8,0xBAA9,12); (0xBAA9,0xBAC4,13); (0xBAC4,0xBAC5,12); (0xBAC5,0xBAE0,13); (0xBAE0,0xBAE1,12); (0xBAE1,0xBAFC,13); (0xBAFC,0xBAFD,12); (0xBAFD,0xBB18,13); (0xBB18,0xBB19,12); (0xBB19,0xBB34,13); (0xBB34,0xBB35,12); (0xBB35,0xBB50,13); (0xBB50,0xBB51,12); (0xBB51,0xBB6C,13); (0xBB6C,0xBB6D,12); (0xBB6D,0xBB88,13); (0xBB88,0xBB89,12); (0xBB89,0xBBA4,13); (0xBBA4,0xBBA5,12); (0xBBA5,0xBBC0,13); (0xBBC0,0xBBC1,12); (0xBBC1,0xBBDC,13); (0xBBDC,0xBBDD,12); (0xBBDD,0xBBF8,13); (0xBBF8,0xBBF9,12); (0xBBF9,0xBC14,13); (0xBC14,0xBC15,12); (0xBC15,0xBC30,13); (0xBC30,0xBC31,12); (0xBC31,0xBC4C,13); (0xBC4C,0xBC4D,12); (0xBC4D,0xBC68,13); (0xBC68,0xBC69,12); (0xBC69,0xBC84,13); (0xBC84,0xBC85,12); (0xBC85,0xBCA0,13); (0xBCA0,0xBCA1,12); (0xBCA1,0xBCBC,13); (0xBCBC,0xBCBD,12); (0xBCBD,0xBCD8,13); (0xBCD8,0xBCD9,12); (0xBCD9,0xBCF4,13); (0xBCF4,0xBCF5,12); (0xBCF5,0xBD10,13); (0xBD10,0xBD11,12); (0xBD11,0xBD2C,13); (0xBD2C,0xBD2D,12); (0xBD2D,0xBD48,13); (0xBD48,0xBD49,12); (0xBD49,0xBD64,13); (0xBD64,0xBD65,12); (0xBD65,0xBD80,13); (0xBD80,0xBD81,12); (0xBD81,0xBD9C,13); (0xBD9C,0xBD9D,12); (0xBD9D,0xBDB8,13); (0xBDB8,0xBDB9,12); (0xBDB9,0xBDD4,13); (0xBDD4,0xBDD5,12); (0xBDD5,0xBDF0,13); (0xBDF0,0xBDF1,12); (0xBDF1,0xBE0C,13); (0xBE0C,0xBE0D,12); (0xBE0D,0xBE28,13); (0xBE28,0xBE29,12); (0xBE29,0xBE44,13); (0xBE44,0xBE45,12); (0xBE45,0xBE60,13); (0xBE60,0xBE61,12); (0xBE61,0xBE7C,13); (0xBE7C,0xBE7D,12); (0xBE7D,0xBE98,13); (0xBE98,0xBE99,12); (0xBE99,0xBEB4,13); (0xBEB4,0xBEB5,12); (0xBEB5,0xBED0,13); (0xBED0,0xBED1,12); (0xBED1,0xBEEC,13); (0xBEEC,0xBEED,12); (0xBEED,0xBF08,13); (0xBF08,0xBF09,12); (0xBF09,0xBF24,13); (0xBF24,0xBF25,12); (0xBF25,0xBF40,13); (0xBF40,0xBF41,12); (0xBF41,0xBF5C,13); (0xBF5C,0xBF5D,12); (0xBF5D,0xBF78,13); (0xBF78,0xBF79,12); (0xBF79,0xBF94,13); (0xBF94,0xBF95,12); (0xBF95,0xBFB0,13); (0xBFB0,0xBFB1,12); (0xBFB1,0xBFCC,13); (0xBFCC,0xBFCD,12); (0xBFCD,0xBFE8,13); (0xBFE8,0xBFE9,12); (0xBFE9,0xC004,13); (0xC004,0xC005,12); (0xC005,0xC020,13); (0xC020,0xC021,12); (0xC021,0xC03C,13); (0xC03C,0xC03D,12); (0xC03D,0xC058,13); (0xC058,0xC059,12); (0xC059,0xC074,13); (0xC074,0xC075,12); (0xC075,0xC090,13); (0xC090,0xC091,12); (0xC091,0xC0AC,13); (0xC0AC,0xC0AD,12); (0xC0AD,0xC0C8,13); (0xC0C8,0xC0C9,12); (0xC0C9,0xC0E4,13); (0xC0E4,0xC0E5,12); (0xC0E5,0xC100,13); (0xC100,0xC101,12); (0xC101,0xC11C,13); (0xC11C,0xC11D,12); (0xC11D,0xC138,13); (0xC138,0xC139,12); (0xC139,0xC154,13); (0xC154,0xC155,12); (0xC155,0xC170,13); (0xC170,0xC171,12); (0xC171,0xC18C,13); (0xC18C,0xC18D,12); (0xC18D,0xC1A8,13); (0xC1A8,0xC1A9,12); (0xC1A9,0xC1C4,13); (0xC1C4,0xC1C5,12); (0xC1C5,0xC1E0,13); (0xC1E0,0xC1E1,12); (0xC1E1,0xC1FC,13); (0xC1FC,0xC1FD,12); (0xC1FD,0xC218,13); (0xC218,0xC219,12); (0xC219,0xC234,13); (0xC234,0xC235,12); (0xC235,0xC250,13); (0xC250,0xC251,12); (0xC251,0xC26C,13); (0xC26C,0xC26D,12); (0xC26D,0xC288,13); (0xC288,0xC289,12); (0xC289,0xC2A4,13); (0xC2A4,0xC2A5,12); (0xC2A5,0xC2C0,13); (0xC2C0,0xC2C1,12); (0xC2C1,0xC2DC,13); (0xC2DC,0xC2DD,12); (0xC2DD,0xC2F8,13); (0xC2F8,0xC2F9,12); (0xC2F9,0xC314,13); (0xC314,0xC315,12); (0xC315,0xC330,13); (0xC330,0xC331,12); (0xC331,0xC34C,13); (0xC34C,0xC34D,12); (0xC34D,0xC368,13); (0xC368,0xC369,12); (0xC369,0xC384,13); (0xC384,0xC385,12); (0xC385,0xC3A0,13); (0xC3A0,0xC3A1,12); (0xC3A1,0xC3BC,13); (0xC3BC,0xC3BD,12); (0xC3BD,0xC3D8,13); (0xC3D8,0xC3D9,12); (0xC3D9,0xC3F4,13); (0xC3F4,0xC3F5,12); (0xC3F5,0xC410,13); (0xC410,0xC411,12); (0xC411,0xC42C,13); (0xC42C,0xC42D,12); (0xC42D,0xC448,13); (0xC448,0xC449,12); (0xC449,0xC464,13); (0xC464,0xC465,12); (0xC465,0xC480,13); (0xC480,0xC481,12); (0xC481,0xC49C,13); (0xC49C,0xC49D,12); (0xC49D,0xC4B8,13); (0xC4B8,0xC4B9,12); (0xC4B9,0xC4D4,13); (0xC4D4,0xC4D5,12); (0xC4D5,0xC4F0,13); (0xC4F0,0xC4F1,12); (0xC4F1,0xC50C,13); (0xC50C,0xC50D,12); (0xC50D,0xC528,13); (0xC528,0xC529,12); (0xC529,0xC544,13); (0xC544,0xC545,12); (0xC545,0xC560,13); (0xC560,0xC561,12); (0xC561,0xC57C,13); (0xC57C,0xC57D,12); (0xC57D,0xC598,13); (0xC598,0xC599,12); (0xC599,0xC5B4,13); (0xC5B4,0xC5B5,12); (0xC5B5,0xC5D0,13); (0xC5D0,0xC5D1,12); (0xC5D1,0xC5EC,13); (0xC5EC,0xC5ED,12); (0xC5ED,0xC608,13); (0xC608,0xC609,12); (0xC609,0xC624,13); (0xC624,0xC625,12); (0xC625,0xC640,13); (0xC640,0xC641,12); (0xC641,0xC65C,13); (0xC65C,0xC65D,12); (0xC65D,0xC678,13); (0xC678,0xC679,12); (0xC679,0xC694,13); (0xC694,0xC695,12); (0xC695,0xC6B0,13); (0xC6B0,0xC6B1,12); (0xC6B1,0xC6CC,13); (0xC6CC,0xC6CD,12); (0xC6CD,0xC6E8,13); (0xC6E8,0xC6E9,12); (0xC6E9,0xC704,13); (0xC704,0xC705,12); (0xC705,0xC720,13); (0xC720,0xC721,12); (0xC721,0xC73C,13); (0xC73C,0xC73D,12); (0xC73D,0xC758,13); (0xC758,0xC759,12); (0xC759,0xC774,13); (0xC774,0xC775,12); (0xC775,0xC790,13); (0xC790,0xC791,12); (0xC791,0xC7AC,13); (0xC7AC,0xC7AD,12); (0xC7AD,0xC7C8,13); (0xC7C8,0xC7C9,12); (0xC7C9,0xC7E4,13); (0xC7E4,0xC7E5,12); (0xC7E5,0xC800,13); (0xC800,0xC801,12); (0xC801,0xC81C,13); (0xC81C,0xC81D,12); (0xC81D,0xC838,13); (0xC838,0xC839,12); (0xC839,0xC854,13); (0xC854,0xC855,12); (0xC855,0xC870,13); (0xC870,0xC871,12); (0xC871,0xC88C,13); (0xC88C,0xC88D,12); (0xC88D,0xC8A8,13); (0xC8A8,0xC8A9,12); (0xC8A9,0xC8C4,13); (0xC8C4,0xC8C5,12); (0xC8C5,0xC8E0,13); (0xC8E0,0xC8E1,12); (0xC8E1,0xC8FC,13); (0xC8FC,0xC8FD,12); (0xC8FD,0xC918,13); (0xC918,0xC919,12); (0xC919,0xC934,13); (0xC934,0xC935,12); (0xC935,0xC950,13); (0xC950,0xC951,12); (0xC951,0xC96C,13); (0xC96C,0xC96D,12); (0xC96D,0xC988,13); (0xC988,0xC989,12); (0xC989,0xC9A4,13); (0xC9A4,0xC9A5,12); (0xC9A5,0xC9C0,13); (0xC9C0,0xC9C1,12); (0xC9C1,0xC9DC,13); (0xC9DC,0xC9DD,12); (0xC9DD,0xC9F8,13); (0xC9F8,0xC9F9,12); (0xC9F9,0xCA14,13); (0xCA14,0xCA15,12); (0xCA15,0xCA30,13); (0xCA30,0xCA31,12); (0xCA31,0xCA4C,13); (0xCA4C,0xCA4D,12); (0xCA4D,0xCA68,13); (0xCA68,0xCA69,12); (0xCA69,0xCA84,13); (0xCA84,0xCA85,12); (0xCA85,0xCAA0,13); (0xCAA0,0xCAA1,12); (0xCAA1,0xCABC,13); (0xCABC,0xCABD,12); (0xCABD,0xCAD8,13); (0xCAD8,0xCAD9,12); (0xCAD9,0xCAF4,13); (0xCAF4,0xCAF5,12); (0xCAF5,0xCB10,13); (0xCB10,0xCB11,12); (0xCB11,0xCB2C,13); (0xCB2C,0xCB2D,12); (0xCB2D,0xCB48,13); (0xCB48,0xCB49,12); (0xCB49,0xCB64,13); (0xCB64,0xCB65,12); (0xCB65,0xCB80,13); (0xCB80,0xCB81,12); (0xCB81,0xCB9C,13); (0xCB9C,0xCB9D,12); (0xCB9D,0xCBB8,13); (0xCBB8,0xCBB9,12); (0xCBB9,0xCBD4,13); (0xCBD4,0xCBD5,12); (0xCBD5,0xCBF0,13); (0xCBF0,0xCBF1,12); (0xCBF1,0xCC0C,13); (0xCC0C,0xCC0D,12); (0xCC0D,0xCC28,13); (0xCC28,0xCC29,12); (0xCC29,0xCC44,13); (0xCC44,0xCC45,12); (0xCC45,0xCC60,13); (0xCC60,0xCC61,12); (0xCC61,0xCC7C,13); (0xCC7C,0xCC7D,12); (0xCC7D,0xCC98,13); (0xCC98,0xCC99,12); (0xCC99,0xCCB4,13); (0xCCB4,0xCCB5,12); (0xCCB5,0xCCD0,13); (0xCCD0,0xCCD1,12); (0xCCD1,0xCCEC,13); (0xCCEC,0xCCED,12); (0xCCED,0xCD08,13); (0xCD08,0xCD09,12); (0xCD09,0xCD24,13); (0xCD24,0xCD25,12); (0xCD25,0xCD40,13); (0xCD40,0xCD41,12); (0xCD41,0xCD5C,13); (0xCD5C,0xCD5D,12); (0xCD5D,0xCD78,13); (0xCD78,0xCD79,12); (0xCD79,0xCD94,13); (0xCD94,0xCD95,12); (0xCD95,0xCDB0,13); (0xCDB0,0xCDB1,12); (0xCDB1,0xCDCC,13); (0xCDCC,0xCDCD,12); (0xCDCD,0xCDE8,13); (0xCDE8,0xCDE9,12); (0xCDE9,0xCE04,13); (0xCE04,0xCE05,12); (0xCE05,0xCE20,13); (0xCE20,0xCE21,12); (0xCE21,0xCE3C,13); (0xCE3C,0xCE3D,12); (0xCE3D,0xCE58,13); (0xCE58,0xCE59,12); (0xCE59,0xCE74,13); (0xCE74,0xCE75,12); (0xCE75,0xCE90,13); (0xCE90,0xCE91,12); (0xCE91,0xCEAC,13); (0xCEAC,0xCEAD,12); (0xCEAD,0xCEC8,13); (0xCEC8,0xCEC9,12); (0xCEC9,0xCEE4,13); (0xCEE4,0xCEE5,12); (0xCEE5,0xCF00,13); (0xCF00,0xCF01,12); (0xCF01,0xCF1C,13); (0xCF1C,0xCF1D,12); (0xCF1D,0xCF38,13); (0xCF38,0xCF39,12); (0xCF39,0xCF54,13); (0xCF54,0xCF55,12); (0xCF55,0xCF70,13); (0xCF70,0xCF71,12); (0xCF71,0xCF8C,13); (0xCF8C,0xCF8D,12); (0xCF8D,0xCFA8,13); (0xCFA8,0xCFA9,12); (0xCFA9,0xCFC4,13); (0xCFC4,0xCFC5,12); (0xCFC5,0xCFE0,13); (0xCFE0,0xCFE1,12); (0xCFE1,0xCFFC,13); (0xCFFC,0xCFFD,12); (0xCFFD,0xD018,13); (0xD018,0xD019,12); (0xD019,0xD034,13); (0xD034,0xD035,12); (0xD035,0xD050,13); (0xD050,0xD051,12); (0xD051,0xD06C,13); (0xD06C,0xD06D,12); (0xD06D,0xD088,13); (0xD088,0xD089,12); (0xD089,0xD0A4,13); (0xD0A4,0xD0A5,12); (0xD0A5,0xD0C0,13); (0xD0C0,0xD0C1,12); (0xD0C1,0xD0DC,13); (0xD0DC,0xD0DD,12); (0xD0DD,0xD0F8,13); (0xD0F8,0xD0F9,12); (0xD0F9,0xD114,13); (0xD114,0xD115,12); (0xD115,0xD130,13); (0xD130,0xD131,12); (0xD131,0xD14C,13); (0xD14C,0xD14D,12); (0xD14D,0xD168,13); (0xD168,0xD169,12); (0xD169,0xD184,13); (0xD184,0xD185,12); (0xD185,0xD1A0,13); (0xD1A0,0xD1A1,12); (0xD1A1,0xD1BC,13); (0xD1BC,0xD1BD,12); (0xD1BD,0xD1D8,13); (0xD1D8,0xD1D9,12); (0xD1D9,0xD1F4,13); (0xD1F4,0xD1F5,12); (0xD1F5,0xD210,13); (0xD210,0xD211,12); (0xD211,0xD22C,13); (0xD22C,0xD22D,12); (0xD22D,0xD248,13); (0xD248,0xD249,12); (0xD249,0xD264,13); (0xD264,0xD265,12); (0xD265,0xD280,13); (0xD280,0xD281,12); (0xD281,0xD29C,13); (0xD29C,0xD29D,12); (0xD29D,0xD2B8,13); (0xD2B8,0xD2B9,12); (0xD2B9,0xD2D4,13); (0xD2D4,0xD2D5,12); (0xD2D5,0xD2F0,13); (0xD2F0,0xD2F1,12); (0xD2F1,0xD30C,13); (0xD30C,0xD30D,12); (0xD30D,0xD328,13); (0xD328,0xD329,12); (0xD329,0xD344,13); (0xD344,0xD345,12); (0xD345,0xD360,13); (0xD360,0xD361,12); (0xD361,0xD37C,13); (0xD37C,0xD37D,12); (0xD37D,0xD398,13); (0xD398,0xD399,12); (0xD399,0xD3B4,13); (0xD3B4,0xD3B5,12); (0xD3B5,0xD3D0,13); (0xD3D0,0xD3D1,12); (0xD3D1,0xD3EC,13); (0xD3EC,0xD3ED,12); (0xD3ED,0xD408,13); (0xD408,0xD409,12); (0xD409,0xD424,13); (0xD424,0xD425,12); (0xD425,0xD440,13); (0xD440,0xD441,12); (0xD441,0xD45C,13); (0xD45C,0xD45D,12); (0xD45D,0xD478,13); (0xD478,0xD479,12); (0xD479,0xD494,13); (0xD494,0xD495,12); (0xD495,0xD4B0,13); (0xD4B0,0xD4B1,12); (0xD4B1,0xD4CC,13); (0xD4CC,0xD4CD,12); (0xD4CD,0xD4E8,13); (0xD4E8,0xD4E9,12); (0xD4E9,0xD504,13); (0xD504,0xD505,12); (0xD505,0xD520,13); (0xD520,0xD521,12); (0xD521,0xD53C,13); (0xD53C,0xD53D,12); (0xD53D,0xD558,13); (0xD558,0xD559,12); (0xD559,0xD574,13); (0xD574,0xD575,12); (0xD575,0xD590,13); (0xD590,0xD591,12); (0xD591,0xD5AC,13); (0xD5AC,0xD5AD,12); (0xD5AD,0xD5C8,13); (0xD5C8,0xD5C9,12); (0xD5C9,0xD5E4,13); (0xD5E4,0xD5E5,12); (0xD5E5,0xD600,13); (0xD600,0xD601,12); (0xD601,0xD61C,13); (0xD61C,0xD61D,12); (0xD61D,0xD638,13); (0xD638,0xD639,12); (0xD639,0xD654,13); (0xD654,0xD655,12); (0xD655,0xD670,13); (0xD670,0xD671,12); (0xD671,0xD68C,13); (0xD68C,0xD68D,12); (0xD68D,0xD6A8,13); (0xD6A8,0xD6A9,12); (0xD6A9,0xD6C4,13); (0xD6C4,0xD6C5,12); (0xD6C5,0xD6E0,13); (0xD6E0,0xD6E1,12); (0xD6E1,0xD6FC,13); (0xD6FC,0xD6FD,12); (0xD6FD,0xD718,13); (0xD718,0xD719,12); (0xD719,0xD734,13); (0xD734,0xD735,12); (0xD735,0xD750,13); (0xD750,0xD751,12); (0xD751,0xD76C,13); (0xD76C,0xD76D,12); (0xD76D,0xD788,13); (0xD788,0xD789,12); (0xD789,0xD7A4,13); (0xD7B0,0xD7C7,10); (0xD7CB,0xD7FC,11); (0xFB1E,0xFB1F,4); (0xFE00,0xFE10,4); (0xFE20,0xFE30,4); (0xFEFF,0xFF00,3); (0xFF9E,0xFFA0,4); (0xFFF0,0xFFFC,3); (0x101FD,0x101FE,4); (0x102E0,0x102E1,4); (0x10376,0x1037B,4); (0x10A01,0x10A04,4); (0x10A05,0x10A07,4); (0x10A0C,0x10A10,4); (0x10A38,0x10A3B,4); (0x10A3F,0x10A40,4); (0x10AE5,0x10AE7,4); (0x10D24,0x10D28,4); (0x10D69,0x10D6E,4); (0x10EAB,0x10EAD,4); (0x10ECB,0x10ED0,4); (0x10EF0,0x10F00,4); (0x10F46,0x10F51,4); (0x10F82,0x10F86,4); (0x11000,0x11001,8); (0x11001,0x11002,4); (0x11002,0x11003,8); (0x11038,0x11047,4); (0x11070,0x11071,4); (0x11073,0x11075,4); (0x1107F,0x11082,4); (0x11082,0x11083,8); (0x110B0,0x110B3,8); (0x110B3,0x110B7,4); (0x110B7,0x110B9,8); (0x110B9,0x110BB,4); (0x110BD,0x110BE,7); (0x110C2,0x110C3,4); (0x110CD,0x110CE,7); (0x11100,0x11103,4); (0x11127,0x1112C,4); (0x1112C,0x1112D,8); (0x1112D,0x11135,4); (0x11145,0x11147,8); (0x11173,0x11174,4); (0x11180,0x11182,4); (0x11182,0x11183,8); (0x111B3,0x111B6,8); (0x111B6,0x111BF,4); (0x111BF,0x111C0,8); (0x111C0,0x111C1,4); (0x111C2,0x111C4,7); (0x111C9,0x111CD,4); (0x111CE,0x111CF,8); (0x111CF,0x111D0,4); (0x1122C,0x1122F,8); (0x1122F,0x11232,4); (0x11232,0x11234,8); (0x11234,0x11238,4); (0x1123E,0x1123F,4); (0x11241,0x11242,4); (0x112DF,0x112E0,4); (0x112E0,0x112E3,8); (0x112E3,0x112EB,4); (0x11300,0x11302,4); (0x11302,0x11304,8); (0x1133B,0x1133D,4); (0x1133E,0x1133F,4); (0x1133F,0x11340,8); (0x11340,0x11341,4); (0x11341,0x11345,8); (0x11347,0x11349,8); (0x1134B,0x1134D,8); (0x1134D,0x1134E,4); (0x11357,0x11358,4); (0x11362,0x11364,8); (0x11366,0x1136D,4); (0x11370,0x11375,4); (0x113B8,0x113B9,4); (0x113B9,0x113BB,8); (0x113BB,0x113C1,4); (0x113C2,0x113C3,4); (0x113C5,0x113C6,4); (0x113C7,0x113CA,4); (0x113CA,0x113CB,8); (0x113CC,0x113CE,8); (0x113CE,0x113D1,4); (0x113D1,0x113D2,7); (0x113D2,0x113D3,4); (0x113E1,0x113E3,4); (0x11435,0x11438,8); (0x11438,0x11440,4); (0x11440,0x11442,8); (0x11442,0x11445,4); (0x11445,0x11446,8); (0x11446,0x11447,4); (0x1145E,0x1145F,4); (0x114B0,0x114B1,4); (0x114B1,0x114B3,8); (0x114B3,0x114B9,4); (0x114B9,0x114BA,8); (0x114BA,0x114BB,4); (0x114BB,0x114BD,8); (0x114BD,0x114BE,4); (0x114BE,0x114BF,8); (0x114BF,0x114C1,4); (0x114C1,0x114C2,8); (0x114C2,0x114C4,4); (0x115AF,0x115B0,4); (0x115B0,0x115B2,8); (0x115B2,0x115B6,4); (0x115B8,0x115BC,8); (0x115BC,0x115BE,4); (0x115BE,0x115BF,8); (0x115BF,0x115C1,4); (0x115DC,0x115DE,4); (0x11630,0x11633,8); (0x11633,0x1163B,4); (0x1163B,0x1163D,8); (0x1163D,0x1163E,4); (0x1163E,0x1163F,8); (0x1163F,0x11641,4); (0x116AB,0x116AC,4); (0x116AC,0x116AD,8); (0x116AD,0x116AE,4); (0x116AE,0x116B0,8); (0x116B0,0x116B8,4); (0x1171D,0x1171E,4); (0x1171E,0x1171F,8); (0x1171F,0x11720,4); (0x11722,0x11726,4); (0x11726,0x11727,8); (0x11727,0x1172C,4); (0x1182C,0x1182F,8); (0x1182F,0x11838,4); (0x11838,0x11839,8); (0x11839,0x1183B,4); (0x11930,0x11931,4); (0x11931,0x11936,8); (0x11937,0x11939,8); (0x1193B,0x1193F,4); (0x1193F,0x11940,7); (0x11940,0x11941,8); (0x11941,0x11942,7); (0x11942,0x11943,8); (0x11943,0x11944,4); (0x119D1,0x119D4,8); (0x119D4,0x119D8,4); (0x119DA,0x119DC,4); (0x119DC,0x119E0,8); (0x119E0,0x119E1,4); (0x119E4,0x119E5,8); (0x11A01,0x11A0B,4); (0x11A33,0x11A39,4); (0x11A39,0x11A3A,8); (0x11A3B,0x11A3F,4); (0x11A47,0x11A48,4); (0x11A51,0x11A57,4); (0x11A57,0x11A59,8); (0x11A59,0x11A5C,4); (0x11A84,0x11A8A,7); (0x11A8A,0x11A97,4); (0x11A97,0x11A98,8); (0x11A98,0x11A9A,4); (0x11B60,0x11B61,4); (0x11B61,0x11B62,8); (0x11B62,0x11B65,4); (0x11B65,0x11B66,8); (0x11B66,0x11B67,4); (0x11B67,0x11B68,8); (0x11C2F,0x11C30,8); (0x11C30,0x11C37,4); (0x11C38,0x11C3E,4); (0x11C3E,0x11C3F,8); (0x11C3F,0x11C40,4); (0x11C92,0x11CA8,4); (0x11CA9,0x11CAA,8); (0x11CAA,0x11CB1,4); (0x11CB1,0x11CB2,8); (0x11CB2,0x11CB4,4); (0x11CB4,0x11CB5,8); (0x11CB5,0x11CB7,4); (0x11D31,0x11D37,4); (0x11D3A,0x11D3B,4); (0x11D3C,0x11D3E,4); (0x11D3F,0x11D46,4); (0x11D46,0x11D47,7); (0x11D47,0x11D48,4); (0x11D8A,0x11D8F,8); (0x11D90,0x11D92,4); (0x11D93,0x11D95,8); (0x11D95,0x11D96,4); (0x11D96,0x11D97,8); (0x11D97,0x11D98,4); (0x11DF0,0x11DF1,4); (0x11EF3,0x11EF5,4); (0x11EF5,0x11EF7,8); (0x11F00,0x11F02,4); (0x11F02,0x11F03,7); (0x11F03,0x11F04,8); (0x11F34,0x11F36,8); (0x11F36,0x11F3B,4); (0x11F3E,0x11F40,8); (0x11F40,0x11F43,4); (0x11F5A,0x11F5B,4); (0x13430,0x13440,3); (0x13440,0x13441,4); (0x13447,0x13456,4); (0x1611E,0x1612A,4); (0x1612A,0x1612D,8); (0x1612D,0x16130,4); (0x16AF0,0x16AF5,4); (0x16B30,0x16B37,4); (0x16D63,0x16D64,10); (0x16D67,0x16D6B,10); (0x16F4F,0x16F50,4); (0x16F51,0x16F88,8); (0x16F8F,0x16F93,4); (0x16FE4,0x16FE5,4); (0x16FF0,0x16FF2,4); (0x1BC9D,0x1BC9F,4); (0x1BCA0,0x1BCA4,3); (0x1CF00,0x1CF2E,4); (0x1CF30,0x1CF47,4); (0x1D127,0x1D129,4); (0x1D165,0x1D16A,4); (0x1D16D,0x1D173,4); (0x1D173,0x1D17B,3); (0x1D17B,0x1D183,4); (0x1D185,0x1D18C,4); (0x1D1AA,0x1D1AE,4); (0x1D242,0x1D245,4); (0x1D250,0x1D253,4); (0x1D25B,0x1D25D,4); (0x1D25F,0x1D260,4); (0x1D280,0x1D282,4); (0x1DA00,0x1DA37,4); (0x1DA3B,0x1DA6D,4); (0x1DA75,0x1DA76,4); (0x1DA84,0x1DA85,4); (0x1DA9B,0x1DAA0,4); (0x1DAA1,0x1DAB0,4); (0x1E000,0x1E007,4); (0x1E008,0x1E019,4); (0x1E01B,0x1E022,4); (0x1E023,0x1E025,4); (0x1E026,0x1E02B,4); (0x1E08F,0x1E090,4); (0x1E130,0x1E137,4); (0x1E2AE,0x1E2AF,4); (0x1E2EC,0x1E2F0,4); (0x1E4EC,0x1E4F0,4); (0x1E5EE,0x1E5F0,4); (0x1E6E3,0x1E6E4,4); (0x1E6E6,0x1E6E7,4); (0x1E6EE,0x1E6F0,4); (0x1E6F5,0x1E6F6,4); (0x1E8D0,0x1E8D7,4); (0x1E944,0x1E94B,4); (0x1F1E6,0x1F200,6); (0x1F3FB,0x1F400,4); (0xE0000,0xE0020,3); (0xE0020,0xE0080,4); (0xE0080,0xE0100,3); (0xE0100,0xE01F0,4); (0xE01F0,0xE1000,3)   
|]

(* Extended_Pictographic ranges, from UCD emoji-data.txt. *)
let ext_pict = [|
   (0xA9,0xAA); (0xAE,0xAF); (0x203C,0x203D); (0x2049,0x204A); (0x2122,0x2123); (0x2139,0x213A); (0x2194,0x219A); (0x21A9,0x21AB); (0x231A,0x231C); (0x2328,0x2329); (0x23CF,0x23D0); (0x23E9,0x23F4); (0x23F8,0x23FB); (0x24C2,0x24C3); (0x25AA,0x25AC); (0x25B6,0x25B7); (0x25C0,0x25C1); (0x25FB,0x25FF); (0x2600,0x2605); (0x260E,0x260F); (0x2611,0x2612); (0x2614,0x2616); (0x2618,0x2619); (0x261D,0x261E); (0x2620,0x2621); (0x2622,0x2624); (0x2626,0x2627); (0x262A,0x262B); (0x262E,0x2630); (0x2638,0x263B); (0x2640,0x2641); (0x2642,0x2643); (0x2648,0x2654); (0x265F,0x2661); (0x2663,0x2664); (0x2665,0x2667); (0x2668,0x2669); (0x267B,0x267C); (0x267E,0x2680); (0x2692,0x2698); (0x2699,0x269A); (0x269B,0x269D); (0x26A0,0x26A2); (0x26A7,0x26A8); (0x26AA,0x26AC); (0x26B0,0x26B2); (0x26BD,0x26BF); (0x26C4,0x26C6); (0x26C8,0x26C9); (0x26CE,0x26D0); (0x26D1,0x26D2); (0x26D3,0x26D5); (0x26E9,0x26EB); (0x26F0,0x26F6); (0x26F7,0x26FB); (0x26FD,0x26FE); (0x2702,0x2703); (0x2705,0x2706); (0x2708,0x270E); (0x270F,0x2710); (0x2712,0x2713); (0x2714,0x2715); (0x2716,0x2717); (0x271D,0x271E); (0x2721,0x2722); (0x2728,0x2729); (0x2733,0x2735); (0x2744,0x2745); (0x2747,0x2748); (0x274C,0x274D); (0x274E,0x274F); (0x2753,0x2756); (0x2757,0x2758); (0x2763,0x2765); (0x2795,0x2798); (0x27A1,0x27A2); (0x27B0,0x27B1); (0x27BF,0x27C0); (0x2934,0x2936); (0x2B05,0x2B08); (0x2B1B,0x2B1D); (0x2B50,0x2B51); (0x2B55,0x2B56); (0x3030,0x3031); (0x303D,0x303E); (0x3297,0x3298); (0x3299,0x329A); (0x1F004,0x1F005); (0x1F02C,0x1F030); (0x1F094,0x1F0A0); (0x1F0AF,0x1F0B1); (0x1F0C0,0x1F0C1); (0x1F0CF,0x1F0D1); (0x1F0F6,0x1F100); (0x1F170,0x1F172); (0x1F17E,0x1F180); (0x1F18E,0x1F18F); (0x1F191,0x1F19B); (0x1F1AF,0x1F1E6); (0x1F201,0x1F210); (0x1F21A,0x1F21B); (0x1F22F,0x1F230); (0x1F232,0x1F23B); (0x1F23C,0x1F240); (0x1F249,0x1F260); (0x1F266,0x1F322); (0x1F324,0x1F394); (0x1F396,0x1F398); (0x1F399,0x1F39C); (0x1F39E,0x1F3F1); (0x1F3F3,0x1F3F6); (0x1F3F7,0x1F3FB); (0x1F400,0x1F4FE); (0x1F4FF,0x1F53E); (0x1F549,0x1F54F); (0x1F550,0x1F568); (0x1F56F,0x1F571); (0x1F573,0x1F57B); (0x1F587,0x1F588); (0x1F58A,0x1F58E); (0x1F590,0x1F591); (0x1F595,0x1F597); (0x1F5A4,0x1F5A6); (0x1F5A8,0x1F5A9); (0x1F5B1,0x1F5B3); (0x1F5BC,0x1F5BD); (0x1F5C2,0x1F5C5); (0x1F5D1,0x1F5D4); (0x1F5DC,0x1F5DF); (0x1F5E1,0x1F5E2); (0x1F5E3,0x1F5E4); (0x1F5E8,0x1F5E9); (0x1F5EF,0x1F5F0); (0x1F5F3,0x1F5F4); (0x1F5FA,0x1F650); (0x1F680,0x1F6C6); (0x1F6CB,0x1F6D3); (0x1F6D5,0x1F6E6); (0x1F6E9,0x1F6EA); (0x1F6EB,0x1F6F1); (0x1F6F3,0x1F700); (0x1F7DC,0x1F7F1); (0x1F80C,0x1F810); (0x1F848,0x1F850); (0x1F85A,0x1F860); (0x1F888,0x1F890); (0x1F8AE,0x1F8B0); (0x1F8BC,0x1F8C0); (0x1F8C2,0x1F8D0); (0x1F8D9,0x1F900); (0x1F90C,0x1F93B); (0x1F93C,0x1F946); (0x1F947,0x1FA00); (0x1FA58,0x1FA60); (0x1FA6E,0x1FB00); (0x1FC00,0x1FFFE);
|]

(* [graphemes s] is the sorted array of byte offsets where grapheme
   clusters start or end: it always holds 0 and [String.length s], so
   consecutive entries delimit the clusters.

   DirectWrite has no grapheme-segmentation API (its cluster maps are
   shaping clusters, which may split an emoji ZWJ chain), so the
   boundaries come from UAX #29 run over the generated tables above —
   GraphemeBreakProperty classes and Extended_Pictographic from the
   Unicode Character Database — covering rules GB3-GB999: combining
   marks, emoji ZWJ chains, regional indicator pairs, Hangul syllables
   and CR/LF sequences are never split. *)
(* The class of a code point by binary search over [gcb_table]. *)
let gcb_class cp =
  let lo = ref 0 and hi = ref (Array.length gcb_table) in
  while !lo < !hi do
    let mid = (!lo + !hi) / 2 in
    let (a, b, _) = gcb_table.(mid) in
    if cp < a then hi := mid
    else if cp >= b then lo := mid + 1
    else begin lo := mid; hi := mid end
  done;
  if !lo < Array.length gcb_table then
    let (a, b, c) = gcb_table.(!lo) in
    if cp >= a && cp < b then c else 0
  else 0

let mem_ext_pict cp =
  let lo = ref 0 and hi = ref (Array.length ext_pict) in
  while !lo < !hi do
    let mid = (!lo + !hi) / 2 in
    let (a, b) = ext_pict.(mid) in
    if cp < a then hi := mid
    else if cp >= b then lo := mid + 1
    else begin lo := mid; hi := mid end
  done;
  !lo < Array.length ext_pict
  && (let (a, b) = ext_pict.(!lo) in cp >= a && cp < b)
(* The break rules between a left and a right class, per UAX #29
   GB3-GB999. GB11 and GB12/13 need context, so [ctx] flags them. *)
let no_break ctx_l ctx_r cls_l cls_r =
  match cls_l, cls_r with
  | 1, 2 -> true                       (* GB3: CR x LF *)
  | (1 | 2 | 3), _ -> false            (* GB4: break after control *)
  | _, (1 | 2 | 3) -> false            (* GB5: break before control *)
  | 9, (9 | 10 | 12 | 13) -> true      (* GB6 *)
  | (12 | 10), (10 | 11) -> true       (* GB7 *)
  | (13 | 11), 11 -> true              (* GB8 *)
  | _, (4 | 5) -> true                 (* GB9: x Extend/ZWJ *)
  | _, 8 -> true                       (* GB9a: x SpacingMark *)
  | 7, _ -> true                       (* GB9b: Prepend x *)
  | 5, _ when ctx_l -> true            (* GB11: ExtPict Extend* ZWJ x ExtPict *)
  | _, 6 when ctx_r -> true            (* GB12/13: RI x RI *)
  | _ -> false                         (* GB999 *)

let graphemes s =
  if s = "" then [| 0 |]
  else begin
    let n = String.length s in
    let chars = ref [] and offs = ref [] in
    let i = ref 0 in
    while !i < n do
      let cp, w = decode_utf8 s !i in
      chars := (gcb_class cp, mem_ext_pict cp) :: !chars;
      offs := !i :: !offs;
      i := !i + w
    done;
    let chars = Array.of_list (List.rev !chars) in
    let offs = Array.of_list (List.rev !offs) in
    let m = Array.length chars in
    let bounds = ref [ 0 ] in
    for k = 1 to m - 1 do
      let cl, _ = chars.(k - 1) in
      let cr, pict_r = chars.(k) in
      (* GB11: the left char is the ZWJ; an ExtPict must precede it
         with only Extend in between. *)
      let gb11 =
        cl = 5 && pict_r
        && begin
          let j = ref (k - 2) in
          while !j >= 0 && fst chars.(!j) = 4 do decr j done;
          !j >= 0 && snd chars.(!j)
        end
      in
      (* GB12/13: RI x RI only when an odd count of RI precedes. *)
      let gb12 =
        cr = 6
        && begin
          let j = ref (k - 1) and cnt = ref 0 in
          while !j >= 0 && fst chars.(!j) = 6 do incr cnt; decr j done;
          !cnt mod 2 = 1
        end
      in
      if not (no_break gb11 gb12 cl cr) then
        bounds := offs.(k) :: !bounds
    done;
    bounds := n :: !bounds;
    Array.of_list (List.rev !bounds)
  end

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
    Array.sort (fun (a : cunit)
(b : cunit) -> compare a.cx0 b.cx0) vs;
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

let hit_test (lay : layout)
(px, py) =
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

let selection_rects (lay : layout)
(a, b) =
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
           |> List.sort (fun (a : cunit)
(b : cunit) ->
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
    else hit_x lay.lay_lines.(target)
(caret_rect lay i).rx
  end

let caret_up lay i = caret_vert ~dir:(-1) lay i
let caret_down lay i = caret_vert ~dir:1 lay i

(* ---- UTF-16 index mapping ---- *)

let units_of_cp cp = if cp > 0xFFFF then 2 else 1

let utf16_length s =
  let n = String.length s in
  let rec go i acc =
    if i >= n then acc
    else
      let cp, w = decode_utf8 s i in
      go (i + w)
(acc + units_of_cp cp)
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
      else go (p + w)
(acc + units_of_cp cp)
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
      else go (p + w)
(acc + un)
  in
  go 0 0

(* ---- truncation ---- *)
(* [truncate ~width f s] is [s]'s first paragraph shrunk to one line
   of at most [width] points, [mode] picking where the engine's
   ellipsis token goes.

   DirectWrite trims only at a line's end (the DWRITE_TRIMMING
   constants), so all
   three modes use one manual cut in OCaml: binary search over grapheme
   boundaries for the kept piece(s), then the shaped ellipsis token
   (U+2026) spliced in as a run whose glyphs report [cluster] at the
   string's end — caret units near it walk the fake glyphs on the
   whole-em grid, matching the CoreText backend's token behaviour. *)
let truncate ?(mode = `End) ?(rtl = false) ~width f s =
  let s =
    match String.index_opt s '\n' with
    | Some n -> String.sub s 0 n
    | None -> s
  in
  if s = "" || width <= 0. then None
  else begin
    let len = String.length s in
    let m = metrics f in
    (* The ellipsis token, shaped once; its runs get reclustered and
       shifted into place below. *)
    let ew, ers =
      match shape ~rtl f "\xE2\x80\xA6" with
      | [| l |] when Array.length l.runs > 0 -> (l.width, l.runs)
      | _ -> (0., [||])
    in
    if fst (measure ~rtl f s) <= width || ew <= 0. then
      (* It fits already (or the token can't be shaped): the plain
         line, when it is one. *)
(match shape ~rtl f s with [| l |] -> Some l | _ -> None)
    else if ew > width then None
    else begin
      let breaks = graphemes s in
      let nb = Array.length breaks in
      let seg_w a b = fst (measure ~rtl f (String.sub s a (b - a))) in
      (* Largest kept prefix end: a grapheme boundary whose prefix
         measures no more than [w]. *)
      let find_prefix w =
        let lo = ref 0 and hi = ref (nb - 1) in
        while !lo < !hi do
          let mid = (!lo + !hi + 1) / 2 in
          if seg_w 0 breaks.(mid) <= w then lo := mid else hi := mid - 1
        done;
        breaks.(!lo)
      in
      let find_suffix w =
        let lo = ref 0 and hi = ref (nb - 1) in
        while !lo < !hi do
          let mid = (!lo + !hi) / 2 in
          if seg_w breaks.(mid) len <= w then hi := mid
          else lo := mid + 1
        done;
        breaks.(!lo)
      in
      let token xoff =
        Array.map
          (fun (r : run) ->
             { r with
               start = len; stop = len;
               glyphs =
                 Array.map
                   (fun (g : glyph) ->
                      { g with x = g.x +. xoff; cluster = len })
                   r.glyphs })
          ers
      in
      let shift dx (l : line) =
        { l with
          runs =
            Array.map
              (fun (r : run) ->
                 { r with
                   glyphs =
                     Array.map
                       (fun (g : glyph) -> { g with x = g.x +. dx })
                       r.glyphs })
              l.runs }
      in
      let shape_seg a b =
        if b <= a then
          { start = a; stop = a; width = 0.; ascent = m.ascent;
            descent = m.descent; leading = m.leading; runs = [||] }
        else
          (match c_shape f (String.sub s a (b - a)) 0. rtl a with
           | [| l |] -> l
           | lines -> lines.(0))
      in
      match mode with
      | `End ->
        let b = find_prefix (width -. ew) in
        let l = shape_seg 0 b in
        Some
          { l with
            start = 0; stop = len;
            width = l.width +. ew;
            runs = Array.append l.runs (token l.width) }
      | `Start ->
        let a = find_suffix (width -. ew) in
        let l = shift ew (shape_seg a len) in
        Some
          { l with
            start = 0; stop = len;
            width = l.width +. ew;
            runs = Array.append (token 0.) l.runs }
      | `Middle ->
        let b = find_prefix ((width -. ew) /. 2.) in
        let a = max b (find_suffix (width -. ew -. seg_w 0 b)) in
        let head = shape_seg 0 b and t = shift (seg_w 0 b +. ew)
(shape_seg a len) in
        Some
          { start = 0; stop = len;
            width = seg_w 0 b +. ew +. t.width;
            ascent = max head.ascent t.ascent;
            descent = max head.descent t.descent;
            leading = max head.leading t.leading;
            runs =
              Array.concat
                [ head.runs; token (seg_w 0 b); t.runs ] }
    end
  end

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
