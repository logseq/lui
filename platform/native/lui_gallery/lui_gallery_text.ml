(* CoreText-backed text channel for the gallery's real-text render
   (macOS only). Mirrors the window host's engine: shaped glyphs are
   rasterized into the scene's mask atlas and appended to
   [scene.glyphs]; the text_ops call returns one [Glyphs] op per run. *)

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

type t = {
  scene : unit -> Lui_scene.t;
  scale : unit -> float;
  store : unit -> Lui_store.t;
  slots : (glyph_key, slot option) Hashtbl.t;
}

let create ~scene ~scale ~store =
  { scene; scale; store; slots = Hashtbl.create 512 }

(* ---- font + text prop plumbing ---- *)

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

let num_prop store id name =
  match Lui_store.prop store id name with
  | Some (Lui_protocol.FloatValue f) -> Some f
  | Some (IntValue i) -> Some (float i)
  | Some (StringValue s) -> parse_len s
  | _ -> None

let font_of store id =
  let size =
    Option.value ~default:14. (num_prop store id "font-size")
  in
  let weight =
    match Lui_store.int_prop store id "font-weight" with
    | Some w -> min 900 (max 100 w)
    | None -> (
      match Lui_store.kind store id with
      | "heading" -> 700
      | _ -> 400)
  in
  Lui_text.system ~weight ~italic:false ~size ()

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
    let colored = Lui_text.is_color run_font in
    let slot =
      match
        Lui_text.rasterize ~scale ~dx
          ~shade:(float shade /. 8.) run_font gid
      with
      | Some b when b.Lui_text.w > 0 && b.Lui_text.h > 0 ->
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

(* Emit one positioned glyph; appends to [scene.glyphs] and returns
   whether one was added. *)
let emit_glyph t scene ~scale ~pen ~baseline ~font ~gid ~g_y ~fg =
  let ix = Float.floor pen in
  let n = Lui_text.subpixel_positions ~scale font in
  let sub =
    if n <= 1 then 0
    else min (n - 1) (int_of_float ((pen -. ix) *. float n +. 0.5))
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
    scene.glyphs <- scene.glyphs @ [ gl ];
    true

let text_ops t id r fg s =
  let scene = t.scene () in
  let scale = t.scale () in
  let store = t.store () in
  let font = font_of store id in
  let lines = Lui_text.shape font s in
  (* Vertical centering inside the node's rect, device pixels. *)
  let text_h =
    Array.fold_left
      (fun acc (l : Lui_text.line) ->
        acc +. l.ascent +. l.descent +. l.leading)
      0. lines
    *. scale
  in
  let y0 = r.y +. Float.max 0. ((r.h -. text_h) /. 2.) in
  let gstart = List.length scene.glyphs in
  let line_y = ref 0. in
  Array.iter
    (fun (l : Lui_text.line) ->
      let baseline =
        Lui_text.baseline (y0 +. !line_y +. l.ascent *. scale)
      in
      Array.iter
        (fun (run : Lui_text.run) ->
          Array.iter
            (fun (g : Lui_text.glyph) ->
              ignore
                (emit_glyph t scene ~scale
                   ~pen:(r.x +. g.x *. scale)
                   ~baseline ~font:run.font ~gid:g.id ~g_y:g.y ~fg))
            run.glyphs)
        l.runs;
      line_y :=
        !line_y +. (l.ascent +. l.descent +. l.leading) *. scale)
    lines;
  let gend = List.length scene.glyphs in
  if gend = gstart then []
  else
    [ Glyphs
        { gstart; gend; gpaint = Solid;
          gcolor = fg; gcolor2 = fg; ggradient = (0., 0., 0., 0.);
          gwide2 = 0; gopacity = 1. } ]

(* ---- layout measure ---- *)

let measure t id _text _w _h =
  let store = t.store () in
  let scale = t.scale () in
  let text =
    match Lui_store.string_prop store id "text" with
    | Some s when s <> "" -> s
    | _ -> (
      match Lui_store.string_prop store id "placeholder" with
      | Some s -> s
      | None -> "")
  in
  if text = "" then None
  else
    let w, h = Lui_text.measure (font_of store id) text in
    Some (w *. scale, h *. scale)
