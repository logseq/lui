(* Grid -> Lui_scene ops.  Text shaping and rasterization go through a
   pluggable engine record (a thin adapter over Lui_text, or over the
   pango/dwrite backends which share its shape) — the renderer never
   reimplements shaping. *)

module A = Terminal_attrs
module G = Terminal_grid

(* Neutral engine types: adapters translate the backend's records. *)
type sg = { sid : int; sx : float; sy : float; sadv : float }
type 'f srun = { sfont : 'f; sgs : sg array }          (* one font run *)
type sbm = { bleft : int; btop : int; bw : int; bh : int;
             bcolor : bool; bpixels : bytes }

type 'f engine = {
  create : ?families:string list -> ?weight:int -> ?italic:bool ->
    size:float -> unit -> 'f;
  metrics : 'f -> float * float * float * float; (* asc desc lead lh *)
  shape : 'f -> string -> 'f srun array;          (* single paragraph *)
  rasterize : ?scale:float -> ?dx:float -> ?shade:float -> 'f -> int ->
    sbm option;
  subpixel : ?scale:float -> 'f -> int;
  baseline : float -> float;
  is_color : 'f -> bool;
}

(* Adapter for the CoreText backend; other engines adapt the same way. *)
let engine_of_lui_text : Lui_text.font engine =
  { create =
      (fun ?families ?weight ?italic ~size () ->
         Lui_text.create ?families ?weight ?italic ~size ());
    metrics =
      (fun f ->
         let m = Lui_text.metrics f in
         (m.Lui_text.ascent, m.Lui_text.descent, m.Lui_text.leading,
          m.Lui_text.line_height));
    shape =
      (fun f s ->
         let lines = Lui_text.shape f s in
         if Array.length lines = 0 then [||]
         else
           Array.map
             (fun (r : Lui_text.run) ->
                { sfont = r.Lui_text.font;
                  sgs = Array.map
                      (fun (g : Lui_text.glyph) ->
                         { sid = g.Lui_text.id; sx = g.Lui_text.x;
                           sy = g.Lui_text.y; sadv = g.Lui_text.advance })
                      r.Lui_text.glyphs })
             lines.(0).Lui_text.runs);
    rasterize =
      (fun ?scale ?dx ?shade f id ->
         match Lui_text.rasterize ?scale ?dx ?shade f id with
         | None -> None
         | Some b ->
           Some { bleft = b.Lui_text.left; btop = b.Lui_text.top;
                  bw = b.Lui_text.w; bh = b.Lui_text.h;
                  bcolor = b.Lui_text.color; bpixels = b.Lui_text.pixels });
    subpixel = (fun ?scale f -> Lui_text.subpixel_positions ?scale f);
    baseline = Lui_text.baseline;
    is_color = Lui_text.is_color;
  }

(* ------------------------------------------------------------------ *)

type 'f fonts = { regular : 'f; bold : 'f; italic : 'f; bold_italic : 'f }

(* Cache key for a rasterized glyph in the atlas (same fields as the
   window text engine). *)
type gkey = Obj.t * int * int * int * int

type slot = {
  sl_x : int; sl_y : int; sl_w : int; sl_h : int;
  sl_left : int; sl_top : int; sl_colored : bool;
}

type 'f t = {
  eng : 'f engine;
  fonts : 'f fonts;
  mutable theme : A.theme;
  size : float;
  mutable scale : float;
  mutable cell_w : int;          (* device px *)
  mutable cell_h : int;
  mutable baseline : int;        (* device px from row top *)
  slots : (gkey, slot option) Hashtbl.t;
  mutable hover_link : int;   (* link id to underline, 0 = none *)
}

let cell_w t = t.cell_w
let cell_h t = t.cell_h
let font_size t = t.size
let set_theme t th = t.theme <- th
let set_hover_link t id = t.hover_link <- id
let hover_link t = t.hover_link

(* The font a style asks for. *)
let font_of t (a : A.t) =
  match a.A.bold, a.A.italic with
  | true, true -> t.fonts.bold_italic
  | true, false -> t.fonts.bold
  | false, true -> t.fonts.italic
  | false, false -> t.fonts.regular

(* Max ASCII advance drives the cell width; the line height the
   reference uses is ascent+descent+leading. *)
let compute_cells eng regular _size scale =
  let asc, desc, _lead, lh = eng.metrics regular in
  let line_h = int_of_float (ceil (lh *. scale -. 0.05)) in
  let ascii =
    let b = Bytes.create (0x7E - 0x20) in
    for i = 0x20 to 0x7E - 1 do Bytes.set b (i - 0x20) (Char.chr i) done;
    Bytes.unsafe_to_string b
  in
  let runs = eng.shape regular ascii in
  let max_adv =
    Array.fold_left
      (fun acc (r : 'f srun) ->
         Array.fold_left
           (fun a (g : sg) -> Float.max a g.sadv) acc r.sgs)
      0. runs
  in
  let cw =
    if max_adv <= 0. then 8 * int_of_float scale
    else int_of_float (ceil (max_adv *. scale -. 0.05))
  in
  let bl =
    int_of_float
      (((float line_h -. (asc +. desc) *. scale) /. 2.)
       +. asc *. scale +. 0.5)
  in
  (max 4 cw, max 8 line_h, max 0 bl)

let create eng ?(families = [ "monospace" ]) ?(weight = 400) ~size ~scale
    ~theme () =
  let mk ?weight ?italic () =
    eng.create ~families ?weight ?italic ~size () in
  let regular = mk ~weight ~italic:false () in
  let bold = mk ~weight:(min 900 (weight + 300)) ~italic:false () in
  let italic = mk ~weight ~italic:true () in
  let bold_italic = mk ~weight:(min 900 (weight + 300)) ~italic:true () in
  let cell_w, cell_h, baseline = compute_cells eng regular size scale in
  { eng; fonts = { regular; bold; italic; bold_italic };
    theme; size; scale;
    cell_w; cell_h; baseline;
    slots = Hashtbl.create 1024; hover_link = 0 }

let set_scale t scale =
  if scale <> t.scale then begin
    let cw, ch, bl = compute_cells t.eng t.fonts.regular t.size scale in
    t.scale <- scale; t.cell_w <- cw; t.cell_h <- ch; t.baseline <- bl;
    Hashtbl.clear t.slots
  end

(* ------------------------------------------------------------------ *)
(* Atlas path — mirrors the window text engine. *)

let shade_of (c : Lui_scene.color) =
  let lum =
    (0.2126 *. float c.Lui_scene.r +. 0.7152 *. float c.Lui_scene.g
     +. 0.0722 *. float c.Lui_scene.b)
    /. 255.
  in
  min 8 (max 0 (int_of_float (lum *. 8. +. 0.5)))

let atlas_put ~colored atlas (b : sbm) =
  let rec try_alloc () =
    match Lui_scene.Atlas.alloc_last atlas b.bw b.bh with
    | Some pos -> Some pos
    | None ->
      if Lui_scene.Atlas.grow atlas then try_alloc () else None
  in
  match try_alloc () with
  | None -> None
  | Some (x, y) ->
    Lui_scene.Atlas.put atlas ~x ~y ~w:b.bw ~h:b.bh ~src:b.bpixels
      ~stride:(b.bw * (if colored then 4 else 1));
    Some (x, y)

let slot_of t font gid sub shade scale scene =
  let key =
    (Obj.repr font, gid, sub, shade, int_of_float (scale *. 1024.))
  in
  match Hashtbl.find_opt t.slots key with
  | Some s -> s
  | None ->
    let n = t.eng.subpixel ~scale font in
    let dx = if n <= 1 then 0. else float sub /. float n in
    let colored = t.eng.is_color font in
    let slot =
      match t.eng.rasterize ~scale ~dx ~shade:(float shade /. 8.) font gid
      with
      | Some b when b.bw > 0 && b.bh > 0 ->
        let atlas =
          if colored then scene.Lui_scene.color_atlas
          else scene.Lui_scene.mask_atlas
        in
        (match atlas_put ~colored atlas b with
         | Some (x, y) ->
           Some { sl_x = x; sl_y = y; sl_w = b.bw; sl_h = b.bh;
                  sl_left = b.bleft; sl_top = b.btop;
                  sl_colored = colored }
         | None -> None)
      | _ -> None
    in
    Hashtbl.replace t.slots key slot;
    slot

let emit_glyph t scene ~pen ~baseline ~font ~gid ~g_y ~fg =
  let scale = t.scale in
  let ix = Float.floor pen in
  let n = t.eng.subpixel ~scale font in
  let sub =
    if n <= 1 then 0
    else min (n - 1) (int_of_float ((pen -. ix) *. float n +. 0.5))
  in
  match slot_of t font gid sub (shade_of fg) scale scene with
  | None -> ()
  | Some s ->
    let gl : Lui_scene.glyph =
      { gx = ix +. float s.sl_left;
        gy = baseline +. g_y *. scale +. float s.sl_top;
        gw = float s.sl_w; gh = float s.sl_h;
        gu = s.sl_x; gv = s.sl_y;
        guw = s.sl_w; gvh = s.sl_h;
        gcolor = fg; gwide = 0;
        gcolored = s.sl_colored;
        gsubpixel = false; gthin = false }
    in
    scene.Lui_scene.glyphs <- gl :: scene.Lui_scene.glyphs

(* ------------------------------------------------------------------ *)
(* Ops *)

let fill r (c : Lui_scene.color) =
  Lui_scene.Fill
    { frect = r; fradii = (0., 0., 0., 0.); fcontinuous = false;
      fcolor = c; fpaint = Lui_scene.Solid; fcolor2 = c;
      fgradient = (0., 0., 0., 0.); fborder = (0., 0., 0., 0.);
      fborder_color = Lui_scene.color 0 0 0 0; fdashed = false;
      fwide = 0; fopacity = 1. }

let glyphs_op gstart gend (c : Lui_scene.color) =
  Lui_scene.Glyphs
    { gstart; gend; gpaint = Lui_scene.Solid; gcolor = c; gcolor2 = c;
      ggradient = (0., 0., 0., 0.); gwide2 = 0; gopacity = 1. }

(* One viewport row -> ops appended (paint order) to [ops]. *)
let render_row t grid ~doc ~vy (cw : float) (ch : float)
    ~(ops : Lui_scene.op list ref) ~(scene : Lui_scene.t) ~blink_on =
  let cols = G.cols grid in
  let th = t.theme in
  let y0 = float vy *. ch in
  let cw_f = cw in
  let row = G.doc_row grid doc in
  let cells = row.G.cells in
  (* background pass: contiguous (paper, selected) spans *)
  let x = ref 0 in
  while !x < cols do
    let c0 = cells.(!x) in
    let sel0 = G.sel_covers grid ~row:doc ~col:!x in
    let _, bg0, _ = A.resolve th c0.G.attrs in
    let rec run_end j =
      if j >= cols then j
      else begin
        let c = cells.(j) in
        let _, bj, _ = A.resolve th c.G.attrs in
        if c.G.spacer ||
           (bj = bg0 && G.sel_covers grid ~row:doc ~col:j = sel0)
        then run_end (j + 1) else j
      end
    in
    let x1 = run_end (!x + 1) in
    if sel0 then
      ops := fill (Lui_scene.rect (float !x *. cw_f) y0
                     (float (x1 - !x) *. cw_f) ch) th.A.selection :: !ops
    else if bg0 <> th.A.bg || c0.G.attrs.A.bg <> A.Default then
      ops := fill (Lui_scene.rect (float !x *. cw_f) y0
                     (float (x1 - !x) *. cw_f) ch) bg0 :: !ops;
    x := x1
  done;
  (* glyph pass: each cell's cluster shaped and drawn at its column —
     terminal grids stay cell-aligned *)
  x := 0;
  let gstart = List.length scene.Lui_scene.glyphs in
  while !x < cols do
    let c = cells.(!x) in
    let a = c.G.attrs in
    let fg, _, _ = A.resolve th a in
    let sel = G.sel_covers grid ~row:doc ~col:!x in
    let fg =
      match sel, th.A.selection_text with
      | true, Some c -> c
      | _ -> fg
    in
    if c.G.text <> "" && not c.G.spacer && not a.A.invisible &&
       not (a.A.blink && not blink_on) then begin
      let font = font_of t a in
      let baseline = y0 +. float t.baseline in
      let runs = t.eng.shape font c.G.text in
      Array.iter
        (fun (r : 'f srun) ->
           Array.iter
             (fun (g : sg) ->
                emit_glyph t scene ~pen:(float !x *. cw_f +. g.sx *. t.scale)
                  ~baseline ~font:r.sfont ~gid:g.sid ~g_y:g.sy ~fg)
             r.sgs)
        runs
    end;
    (* decorations span contiguous same-attr cells *)
    let link0 = c.G.link in
    let rec run_end j =
      if j >= cols then j
      else
        let cj = cells.(j) in
        if not (A.equal cj.G.attrs a) || cj.G.link <> link0 then j
        else run_end (j + 1)
    in
    let x1 = run_end (!x + 1) in
    let _, _, ulc = A.resolve th a in
    let ul_thick = ch *. 0.08 in
    let deco color x0 x1 y h =
      if h > 0.5 then
        ops := fill (Lui_scene.rect x0 y (x1 -. x0) h) color :: !ops
    in
    let rx0 = float !x *. cw_f and rx1 = float x1 *. cw_f in
    let base_y = y0 +. float t.baseline in
    (match a.A.underline with
     | A.No_underline -> ()
     | A.Single ->
       deco ulc rx0 rx1 (base_y +. ul_thick) (Float.max 1. ul_thick)
     | A.Double ->
       deco ulc rx0 rx1 (base_y +. ul_thick *. 0.5)
         (Float.max 1. (ul_thick *. 0.5));
       deco ulc rx0 rx1 (base_y +. ul_thick *. 2.)
         (Float.max 1. (ul_thick *. 0.5))
     | A.Curly ->
       deco ulc rx0 rx1 (base_y +. ul_thick) (Float.max 1. ul_thick)
     | A.Dotted | A.Dashed ->
       let seg = Float.max 2. (cw_f *. 0.6) in
       let rec loop x =
         if x < rx1 then begin
           deco ulc x (Float.min rx1 (x +. seg *. 0.5))
             (base_y +. ul_thick) (Float.max 1. ul_thick);
           loop (x +. seg)
         end
       in
       loop rx0);
    if a.A.strike then
      deco ulc rx0 rx1 (base_y -. (ch *. 0.25)) (Float.max 1. ul_thick);
    if a.A.overline then
      deco ulc rx0 rx1 (y0 +. 1.) (Float.max 1. ul_thick);
    if t.hover_link <> 0 && c.G.link = t.hover_link then
      deco th.A.fg rx0 rx1 (base_y +. ul_thick *. 2.) (Float.max 1. ul_thick);
    x := x1
  done;
  let gend = List.length scene.Lui_scene.glyphs in
  if gend > gstart then begin
    let fg = th.A.fg in
    ops := glyphs_op gstart gend fg :: !ops
  end

(* ------------------------------------------------------------------ *)

(* Scrollbar: a thin track + thumb on the right edge. *)
let render_scrollbar _t grid ~w ~h ops =
  let total = G.sb_len grid + G.rows grid in
  if total <= 0 then ()
  else begin
    let track_w = 6. in
    let frac = float (G.rows grid) /. float total in
    let thumb_h = Float.max 16. (float h *. frac) in
    let seen = float (total - G.view grid - G.rows grid) in
    let top_frac = seen /. float total in
    let ty = float h *. top_frac in
    ops := fill (Lui_scene.rect (float w -. track_w) ty track_w thumb_h)
             (Lui_scene.color 128 128 128 90) :: !ops
  end

let render ?(blink_on = true) t grid scene ~w ~h =
  let cw = float t.cell_w and ch = float t.cell_h in
  let rows = G.rows grid in
  let ops = ref [] in
  let rows_vis = min rows (int_of_float (float h /. ch) + 1) in
  let view = G.view grid in
  for vy = 0 to rows_vis - 1 do
    let doc = G.sb_len grid - view + vy in
    if doc >= 0 && doc < G.sb_len grid + rows then
      render_row t grid ~doc ~vy cw ch ~ops ~scene ~blink_on
  done;
  (* cursor only in the live viewport *)
  if view = 0 then begin
    let cx, cy = G.cursor grid in
    if cy < rows_vis then begin
      let style, blink = G.cursor_style grid in
      let th = t.theme in
      let x = float cx *. cw and y = float cy *. ch in
      if G.mode_cursor_visible grid then begin
        (match style with
         | 3 | 4 ->
           ops := fill (Lui_scene.rect x (y +. ch -. max 1. (ch *. 0.1)) cw
                          (max 1. (ch *. 0.1))) th.A.cursor :: !ops
         | 5 | 6 ->
           ops := fill (Lui_scene.rect x y (max 1. (cw *. 0.12)) ch)
                    th.A.cursor :: !ops
         | _ ->
           let on = blink_on || not blink in
           if on then
             ops := fill (Lui_scene.rect x y cw ch) th.A.cursor :: !ops
           else
             ops :=
               Lui_scene.Fill
                 { frect = Lui_scene.rect x y cw ch;
                   fradii = (0., 0., 0., 0.); fcontinuous = false;
                   fcolor = Lui_scene.color 0 0 0 0;
                   fpaint = Lui_scene.Solid;
                   fcolor2 = Lui_scene.color 0 0 0 0;
                   fgradient = (0., 0., 0., 0.);
                   fborder = (1., 1., 1., 1.);
                   fborder_color = th.A.cursor;
                   fdashed = false; fwide = 0; fopacity = 1. } :: !ops);
        (* invert the cell under a solid cursor *)
        if blink_on || not blink then
          match G.screen_cell grid cy cx with
          | Some c when c.G.text <> "" ->
            let fg = th.A.cursor_text in
            let font = font_of t c.G.attrs in
            let baseline = y +. float t.baseline in
            let runs = t.eng.shape font c.G.text in
            let gstart = List.length scene.Lui_scene.glyphs in
            Array.iter
              (fun (r : 'f srun) ->
                 Array.iter
                   (fun (g : sg) ->
                      emit_glyph t scene ~pen:(x +. g.sx *. t.scale)
                        ~baseline ~font:r.sfont ~gid:g.sid ~g_y:g.sy ~fg)
                   r.sgs)
              runs;
            let gend = List.length scene.Lui_scene.glyphs in
            if gend > gstart then ops := glyphs_op gstart gend fg :: !ops
          | _ -> ()
      end
    end
  end;
  if G.view grid > 0 || G.sb_len grid > 0 then
    render_scrollbar t grid ~w ~h ops;
  (* scene.ops is reversed paint order; !ops already holds ours newest
     first, so a plain append keeps the invariant *)
  scene.Lui_scene.ops <- !ops @ scene.Lui_scene.ops
