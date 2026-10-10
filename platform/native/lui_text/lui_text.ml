(* Text engine: font lookup, shaping and glyph rasterization, on the
   platform's own text stack. The engine-agnostic contract is in
   lui_text.mli; the macOS implementation lives in lui_text_coretext.c.

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
  = "lui_ct_named"
external c_system : float -> float -> bool -> bool -> font
  = "lui_ct_system"
external c_cascade : font -> string array -> float -> bool -> font
  = "lui_ct_cascade"
external c_fallback : font -> string -> font option = "lui_ct_fallback"
external c_metrics : font -> float * float * float * float
  = "lui_ct_metrics"
external c_is_color : font -> bool = "lui_ct_is_color"
external c_family : font -> string = "lui_ct_family"
external c_shape : font -> string -> float -> bool -> int -> line array
  = "lui_ct_shape"
external c_rasterize : font -> int -> float -> float -> float ->
  bitmap option
  = "lui_ct_rasterize"

(* CSS weight on the scale font descriptors and the system font take:
   -1 .. 1. *)
let ct_weight w =
  let steps = [| -0.8; -0.6; -0.4; 0.; 0.23; 0.3; 0.4; 0.56; 0.62 |] in
  let f = (float (min (max w 100) 900) -. 100.) /. 100. in
  let i = min (int_of_float f) (Array.length steps - 2) in
  steps.(i) +. (steps.(i + 1) -. steps.(i)) *. (f -. float i)

(* Generic family names and their concrete expansions. *)
type slot = System of bool | Named of string list

let slot_of_family f =
  let n = String.lowercase_ascii (String.trim f) in
  match n with
  | "" | "system-ui" | "ui-sans-serif" | "-apple-system"
  | "blinkmacsystemfont" | "sans-serif" -> Some (System false)
  | "monospace" | "ui-monospace" -> Some (System true)
  | "serif" | "ui-serif" ->
    Some (Named [ "Times New Roman"; "Times"; "Georgia" ])
  | _ -> Some (Named [ String.trim f ])

let slots_of_families families =
  List.concat_map (String.split_on_char ',') families
  |> List.filter_map slot_of_family

let make_font ~families ~weight ~italic ~size =
  let w = ct_weight weight in
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
  c_system size (ct_weight weight) italic monospace

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
    invalid_arg "Lui_text.rasterize";
  c_rasterize f id scale dx shade

let subpixel_positions ?(scale = 1.) f =
  (* The platform puts glyph pens at fewer fractional positions the
     larger the font: at most five a pixel, one from about 34 px. *)
  let px = size f *. scale in
  if px <= 0. then 1
  else min 5 (max 1 (int_of_float (ceil (100. /. (3. *. px) -. 1e-9))))

let baseline y = ceil (y -. 1e-3)
