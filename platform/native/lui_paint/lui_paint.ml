(* Node → scene translation: the paint pass.

   Walks the retained store and emits Lui_scene ops for every visible
   node, using the rects the layout pass computed. Extension nodes are
   painted by registered extension renderers, keeping the kernel closed
   while staying open to any app's own kinds.

   Coordinate spaces: layout rects and the scene itself are device px.
   Every length that arrives over the wire (border widths, corner radii,
   shadow offsets, insets, control metrics) is a logical px and is
   multiplied by the frame scale before it becomes geometry.

   Interactive-state channels override the base props in the same order
   the reference stylesheet's rules cascade — each channel falls back to
   the layer below when its prop is absent:

     background: hover-bg → pressed-bg → selected-bg → background
     opacity:    hover-opacity → pressed-opacity → disabled-opacity → opacity
     shadow:     hover-shadow → pressed-shadow → selected-shadow
                 → selected-hover-shadow (selected+hover)
                 → focus-shadow (highest precedence) → shadow *)

open Lui_scene

(* ---------- prop coverage table ----------

   Every protocol property and where it is handled. `Painted` means this
   module consumes the prop into scene ops; the other tags name the
   owner so the gaps stay visible. Extension-prop names the paint pass
   also reads ("border-style") are listed under the table. *)

type coverage =
  | Painted            (* consumed here, produces ops *)
  | Painted_by_text    (* forwarded to the text-engine hook *)
  | Painted_by_image   (* resolved through the image hook *)
  | Layout             (* consumed by the layout engine *)
  | Host               (* host concern: events, a11y, platform chrome *)
  | Unmapped of string (* no mapping yet — gap *)

let prop_coverage =
  [ ("text", Painted_by_text);
    ("enabled", Painted); (* folds into state.disabled *)
    ("gap", Layout);
    ("main", Layout);
    ("cross", Layout);
    ("grow", Layout);
    ("columns", Layout);
    ("padding", Layout);
    ("padding-horizontal", Layout);
    ("padding-vertical", Layout);
    ("background", Painted);
    ("foreground", Painted);
    ("border-color", Painted); (* CSS shorthand, 1–4 colors *)
    ("border-width", Painted); (* CSS shorthand, 1–4 lengths *)
    ("corner-radius", Painted);
    ("width", Layout);
    ("height", Layout);
    ("min-width", Layout);
    ("max-width", Layout);
    ("min-height", Layout);
    ("max-height", Layout);
    ("container-relative-frame", Layout);
    ("container-relative-frame-inset", Layout);
    ("placeholder", Painted_by_text);
    ("accessibility-label", Host);
    ("accessibility-identifier", Host);
    ("style-class", Host);
    ("heading-level", Painted_by_text);
    ("checked", Painted); (* checkbox/radio/switch/toggle chrome *)
    ("value", Painted);   (* progress fill, slider thumb fraction *)
    ("orientation", Painted); (* divider axis; layout reads it too *)
    ("placement", Host);
    ("size", Layout);     (* control size preset → element dims *)
    ("name", Painted_by_image); (* icon resolution *)
    ("variant", Host);    (* styling hint; resolved upstream to props *)
    ("icon", Painted_by_image);
    ("icon-placement", Layout);
    ("selected", Painted); (* folds into state.selected *)
    ("autofocus", Host);
    ("submit-on-enter", Host);
    ("long-press-enabled", Host);
    ("change-enabled", Host);
    ("toggle-enabled", Host);
    ("press-enabled", Host);
    ("submit-enabled", Host);
    ("double-press-enabled", Host);
    ("appear-enabled", Host);
    ("image", Painted_by_image);
    ("surface", Painted_by_image);
    ("active", Host);
    ("title", Painted_by_text);
    ("description", Painted_by_text);
    ("meta", Painted_by_text);
    ("indicator", Unmapped "timeline indicator chrome");
    ("connector", Unmapped "timeline connector line");
    ("source-x", Painted); (* image source rect, image px *)
    ("source-y", Painted);
    ("source-width", Painted);
    ("source-height", Painted);
    ("anchor", Host); (* popup anchoring is host-owned *)
    ("anchor-alignment", Host);
    ("anchor-offset", Host);
    ("tooltip-delay", Host);
    ("duration", Host);
    ("text-alignment", Painted_by_text);
    ("role", Host);
    ("tree-level", Layout); (* row indent *)
    ("expanded", Unmapped "disclosure chevron glyph");
    ("resize-duration", Host);
    ("resize-easing", Host);
    ("resize-origin", Host);
    ("theme", Host); (* input to the host color resolver *)
    ("theme-mode", Host);
    ("key", Layout); (* node identity *)
    ("separator", Unmapped "list-section separator line");
    ("style", Host); (* list style hint *)
    ("scroll-target", Host);
    ("scroll-anchor", Host);
    ("scroll-token", Host);
    ("scroll-animated", Host);
    ("track-visible-range", Host);
    ("edge", Layout); (* edge-inset side *)
    ("request", Host); (* file picker *)
    ("types", Host);
    ("multiple", Host);
    ("source", Host);
    ("completion", Host);
    ("min", Painted); (* value fraction normalization *)
    ("max", Painted);
    ("step", Host); (* input snapping, not a paint concern *)
    ("detents", Host);
    ("sizing", Host);
    ("path", Painted_by_image); (* file-preview source *)
    ("url", Host);
    ("max-pixel-size", Painted_by_image); (* decode hint *)
    ("image-fit", Painted); (* "fit" letterbox vs "fill" stretch *)
    ("visible", Painted); (* subtree paint gate *)
    ("alignment", Layout); (* overlay position hint *)
    ("pointer-enabled", Host); (* hit testing *)
    ("data-attrs", Host);
    ("as", Host); (* element tag, web channel *)
    ("alt", Host);
    ("loading", Host);
    ("referrer-policy", Host);
    ("target", Host);
    ("opacity", Painted); (* composites down the subtree *)
    ("display", Painted); (* "contents" unboxes, "none" hides *)
    ("tooltip", Host);
    ("tooltip-keys", Host);
    ("input-type", Host);
    ("accept", Host);
    ("directory", Host);
    ("x", Painted); (* popup absolute placement override *)
    ("y", Painted);
    ("available-height", Layout);
    ("font-size", Painted_by_text);
    ("font-weight", Painted_by_text);
    ("line-height", Painted_by_text);
    ("letter-spacing", Painted_by_text);
    ("position", Painted); (* relative/absolute/fixed *)
    ("inset", Painted);
    ("inset-top", Painted);
    ("inset-right", Painted);
    ("inset-bottom", Painted);
    ("inset-left", Painted);
    ("z-index", Painted); (* sibling paint order *)
    ("white-space", Painted_by_text);
    ("text-overflow", Painted_by_text);
    ("overflow", Painted); (* clip + scrollbar gate *)
    ("user-select", Host);
    ("cursor", Host);
    ("shadow", Painted);
    ("hover-background", Painted);
    ("hover-opacity", Painted);
    ("hover-shadow", Painted);
    ("pressed-background", Painted);
    ("pressed-opacity", Painted);
    ("pressed-shadow", Painted);
    ("focus-shadow", Painted);
    ("selected-background", Painted);
    ("selected-shadow", Painted);
    ("selected-hover-shadow", Painted);
    ("disabled-opacity", Painted);
    ("width-viewport", Layout);
    ("height-viewport", Layout);
    ("min-width-viewport", Layout);
    ("max-width-viewport", Layout);
    ("min-height-viewport", Layout);
    ("max-height-viewport", Layout) ]

(* Extension-prop names the pass reads outside the protocol list:
   "border-style" ("dashed"/"dotted" → fdashed). *)

(* ---------- colors ---------- *)

let hex_opt c =
  if c >= '0' && c <= '9' then Char.code c - Char.code '0'
  else if c >= 'a' && c <= 'f' then Char.code c - Char.code 'a' + 10
  else if c >= 'A' && c <= 'F' then Char.code c - Char.code 'A' + 10
  else -1

(* Parse "#rgb", "#rrggbb", "#rrggbbaa". Returns None for theme names;
   the host resolver handles those. *)
let color_of_hex s =
  let n = String.length s in
  if n >= 2 && s.[0] = '#' then
    let d i = hex_opt s.[i] in
    if n = 4 then
      match (d 1, d 2, d 3) with
      | r, g, b when r >= 0 && g >= 0 && b >= 0 ->
        Some (color (r * 17) (g * 17) (b * 17) 255)
      | _ -> None
    else if n = 7 || n = 9 then
      let pair i = (d i * 16) + d (i + 1) in
      let a = if n = 9 then pair 7 else 255 in
      if d 1 < 0 || d 2 < 0 || d 3 < 0 || d 4 < 0 || d 5 < 0 || d 6 < 0
         || (n = 9 && (d 7 < 0 || d 8 < 0)) then None
      else Some (color (pair 1) (pair 3) (pair 5) a)
    else None
  else None

(* ---------- tokenizing ----------

   Whitespace/comma tokenizers that keep parenthesized groups together,
   so "rgb(0 0 0)" and "linear-gradient(90deg, a, b)" tokenize sanely. *)

let tokens s =
  let acc = ref [] and buf = Buffer.create 16 and depth = ref 0 in
  let flush () =
    if Buffer.length buf > 0 then (
      acc := Buffer.contents buf :: !acc;
      Buffer.clear buf)
  in
  String.iter
    (fun c ->
      if !depth > 0 then (
        Buffer.add_char buf c;
        if c = '(' then incr depth else if c = ')' then decr depth)
      else
        match c with
        | '(' -> incr depth; Buffer.add_char buf c
        | ' ' | '\t' | '\n' | '\r' -> flush ()
        | c -> Buffer.add_char buf c)
    s;
  flush ();
  List.rev !acc

let split_commas s =
  let acc = ref [] and buf = Buffer.create 16 and depth = ref 0 in
  let flush () =
    acc := String.trim (Buffer.contents buf) :: !acc;
    Buffer.clear buf
  in
  String.iter
    (fun c ->
      if !depth > 0 then (
        Buffer.add_char buf c;
        if c = '(' then incr depth else if c = ')' then decr depth)
      else
        match c with
        | '(' -> incr depth; Buffer.add_char buf c
        | ',' -> flush ()
        | c -> Buffer.add_char buf c)
    s;
  flush ();
  List.rev !acc |> List.filter (fun t -> t <> "")

(* "name(...)" → inner argument string. *)
let fn_args name s =
  let n = String.length name and len = String.length s in
  if len > n + 1 && String.sub s 0 n = name && s.[n] = '('
     && s.[len - 1] = ')'
  then Some (String.sub s (n + 1) (len - n - 2))
  else None

(* A length token: bare number or px-suffixed, in logical px. *)
let px_of_token t =
  let t =
    if String.ends_with ~suffix:"px" t then
      String.sub t 0 (String.length t - 2)
    else t
  in
  float_of_string_opt t

let clamp01 f = Float.max 0. (Float.min 1. f)

(* ---------- color values ---------- *)

(* A channel number: 0-255 integer or a percentage. *)
let channel_of_token t =
  if String.ends_with ~suffix:"%" t then
    match float_of_string_opt (String.sub t 0 (String.length t - 1)) with
    | Some p -> Some (int_of_float (Float.round (p *. 255. /. 100.)))
    | None -> None
  else
    match int_of_string_opt t with
    | Some i -> Some i
    | None -> None

let alpha_of_token t =
  if String.ends_with ~suffix:"%" t then
    match float_of_string_opt (String.sub t 0 (String.length t - 1)) with
    | Some p -> Some (int_of_float (Float.round (p *. 255. /. 100.)))
    | None -> None
  else
    match float_of_string_opt t with
    | Some a -> Some (int_of_float (Float.round (clamp01 a *. 255.)))
    | None -> None

(* "rgb(...)"/"rgba(...)" — comma or space separated, optional "/a". *)
let parse_rgb s =
  let inner =
    match fn_args "rgb" s with
    | Some i -> Some i
    | None -> fn_args "rgba" s
  in
  match inner with
  | None -> None
  | Some inner ->
    let inner = String.map (fun c -> if c = '/' then ' ' else c) inner in
    let ts =
      if String.contains inner ',' then split_commas inner
      else tokens inner
    in
    (match ts with
     | [r; g; b] | [r; g; b; _] -> (
       match (channel_of_token r, channel_of_token g, channel_of_token b) with
       | Some r, Some g, Some b ->
         let a =
           match ts with
           | [_; _; _; a] -> (
             match alpha_of_token a with Some a -> a | None -> 255)
           | _ -> 255
         in
         Some (color r g b a)
       | _ -> None)
     | _ -> None)

(* Any color value: hex, rgb()/rgba(), "transparent", or a name the
   host resolver knows. [resolve] is hooks.color_of. *)
let color_of_value resolve s =
  let s = String.trim s in
  match color_of_hex s with
  | Some c -> Some c
  | None -> (
    if s = "transparent" then Some (color 0 0 0 0)
    else
      match parse_rgb s with
      | Some c -> Some c
      | None -> resolve s)

(* ---------- context ---------- *)

(* Per-node interaction state, supplied by the host via state_of.
   [selected]/[disabled] additionally fold the corresponding wire props
   so prop-driven styling works before any host state arrives. *)
type state = {
  hovered : bool;
  pressed : bool;
  selected : bool;
  focused : bool;
  disabled : bool;
}

let state_neutral =
  { hovered = false; pressed = false; selected = false; focused = false;
    disabled = false }

(* What layout computed for a node. [p_override] is a device-px rect
   that replaces the node's placement outright (already-resolved
   absolute placement); when absent, paint applies the position/inset
   props on top of [p_rect]. *)
type placement = { p_rect : rect; p_override : rect option }

let placement_of_rect r = { p_rect = r; p_override = None }

(* Scroll fractions a scroll container reports: [sm_extent] is the
   share of content visible in the viewport (0..1), [sm_offset] the
   share of the scrollable range currently scrolled (0..1). None means
   no scrollbar is drawn. *)
type scroll_metrics = { sm_offset : float; sm_extent : float }

(* Host-injected lookups so paint stays platform-free. *)
type hooks = {
  color_of : string -> color option; (* theme/resource name → color *)
  layout : int -> placement;         (* node id → layout result *)
  state_of : int -> state;           (* node id → interaction state *)
  scroll_of : int -> scroll_metrics option; (* scroll container metrics *)
  text_ops : int -> rect -> color -> string -> op list; (* text engine *)
  image_of : int -> image option;    (* node id → decoded image *)
  shadow_of : string -> shadow_spec option; (* shadow spec parser *)
}

and shadow_spec = {
  dx : float;     (* logical px *)
  dy : float;
  blur : float;
  spread : float;
  scolor : color;
  inset : bool;
}

(* Per-frame paint context handed to extension renderers. *)
type ctx = {
  hooks : hooks;
  scale : float;    (* device px per logical px *)
  viewport : rect;  (* frame rect, device px — fixed-position containing block *)
}

type extension_renderer = {
  paint : ctx -> Lui_store.t -> Lui_store.node -> rect -> op list;
}

let extension_renderers : (string, extension_renderer) Hashtbl.t =
  Hashtbl.create 8

let register_extension ~identifier renderer =
  Hashtbl.replace extension_renderers identifier renderer

let default_hooks =
  { color_of = (fun _ -> None);
    layout = (fun _ -> placement_of_rect (rect 0. 0. 0. 0.));
    state_of = (fun _ -> state_neutral);
    scroll_of = (fun _ -> None);
    text_ops = (fun _ _ _ _ -> []);
    image_of = (fun _ -> None);
    shadow_of = (fun _ -> None) }

(* ---------- shadow parsing ---------- *)

(* CSS box-shadow grammar, first layer only:
     [inset]? <dx> <dy> [<blur> [<spread>]] [<color>]
   Lengths may carry a px suffix; color may be hex, rgb()/rgba(),
   "transparent" or a resolver name. Returns None for "none"/unparseable.
   All lengths come out in logical px; callers scale to device px. *)
let parse_shadow resolve s =
  let s = String.trim s in
  if s = "" || s = "none" then None
  else
    let layer = match split_commas s with l :: _ -> l | [] -> s in
    let toks = tokens layer in
    let inset = List.mem "inset" toks in
    let lens = List.filter_map px_of_token toks in
    let col_tok =
      List.find_opt
        (fun t -> t <> "inset" && px_of_token t = None)
        toks
    in
    match lens with
    | dx :: dy :: rest ->
      let blur = match rest with b :: _ -> Float.max 0. b | [] -> 0. in
      let spread = match rest with _ :: sp :: _ -> sp | _ -> 0. in
      let scolor =
        match col_tok with
        | Some t -> (
          match color_of_value resolve t with
          | Some c -> c
          | None -> color 0 0 0 255)
        | None -> color 0 0 0 255
      in
      Some { dx; dy; blur; spread; scolor; inset }
    | _ -> None

(* ---------- prop helpers ---------- *)

let pstr store id name = Lui_store.string_prop store id name

(* A numeric prop: accepts IntValue/FloatValue or a numeric string. *)
let pnum store id name =
  match Lui_store.prop store id name with
  | Some (Lui_protocol.FloatValue f) -> Some f
  | Some (Lui_protocol.IntValue i) -> Some (float i)
  | Some (Lui_protocol.StringValue s) ->
    float_of_string_opt (String.trim s)
  | _ -> None

let pbool store id name =
  match Lui_store.prop store id name with
  | Some (Lui_protocol.BoolValue b) -> b
  | Some (Lui_protocol.StringValue s) -> s = "true"
  | _ -> false

let pcolor hooks store id name =
  match pstr store id name with
  | None -> None
  | Some s -> color_of_value hooks.color_of s

(* A length-list prop: numbers or a whitespace-separated shorthand. *)
let pnums store id name =
  match Lui_store.prop store id name with
  | Some (Lui_protocol.FloatValue f) -> [ f ]
  | Some (Lui_protocol.IntValue i) -> [ float i ]
  | Some (Lui_protocol.StringValue s) ->
    tokens s |> List.filter_map px_of_token
  | _ -> []

(* CSS shorthand order: 1 → all, 2 → v h, 3 → t h b, 4 → t r b l. *)
let edges_of_or zero = function
  | [ a ] -> (a, a, a, a)
  | [ v; h ] -> (v, h, v, h)
  | [ t; h; b ] -> (t, h, b, h)
  | [ t; r; b; l ] -> (t, r, b, l)
  | _ -> (zero, zero, zero, zero)

let edges_of_floats l = edges_of_or 0. l

(* ---------- state resolution ---------- *)

(* Wire props that imply interaction state on top of what the host
   reports through state_of. *)
let effective_state hooks store id =
  let s = hooks.state_of id in
  { s with
    selected =
      s.selected || pbool store id "selected";
    disabled =
      s.disabled
      || (match Lui_store.prop store id "enabled" with
          | Some (Lui_protocol.BoolValue b) -> not b
          | Some (Lui_protocol.StringValue v) -> v = "false"
          | _ -> false) }

(* Base props after the state channels cascade through them. *)
type resolved = {
  rs_background : string option;
  rs_opacity : float;
  rs_shadow : string option;
}

let opacity_of store id =
  match pnum store id "opacity" with
  | Some f -> clamp01 f
  | None -> 1.

let resolve_style store id st =
  let bg = ref (pstr store id "background")
  and sh = ref (pstr store id "shadow")
  and op = ref (opacity_of store id) in
  let ifstr name r = match pstr store id name with
    | Some v -> r := Some v
    | None -> ()
  in
  let ifnum name r = match pnum store id name with
    | Some v -> r := clamp01 v
    | None -> ()
  in
  if st.hovered then (
    ifstr "hover-background" bg;
    ifstr "hover-shadow" sh;
    ifnum "hover-opacity" op);
  if st.pressed then (
    ifstr "pressed-background" bg;
    ifstr "pressed-shadow" sh;
    ifnum "pressed-opacity" op);
  if st.selected then (
    ifstr "selected-background" bg;
    ifstr "selected-shadow" sh);
  if st.selected && st.hovered then ifstr "selected-hover-shadow" sh;
  if st.disabled then ifnum "disabled-opacity" op;
  if st.focused then ifstr "focus-shadow" sh;
  { rs_background = !bg; rs_opacity = !op; rs_shadow = !sh }

(* ---------- fills ---------- *)

(* Theme tokens with sRGB fallbacks when the host resolver doesn't know
   them, so control chrome still draws. *)
let theme ctx name fallback =
  match ctx.hooks.color_of name with
  | Some c -> c
  | None -> fallback

let col_primary ctx = theme ctx "primary" (color 37 99 235 255)
let col_primary_fg ctx = theme ctx "primary-foreground" (color 255 255 255 255)
let col_secondary ctx = theme ctx "secondary" (color 229 231 235 255)
let col_border ctx = theme ctx "border" (color 209 213 219 255)
let col_background ctx = theme ctx "background" (color 255 255 255 255)
let col_muted_fg ctx = theme ctx "muted-foreground" (color 107 114 128 255)

(* CSS gradient direction → unit-space gradient line endpoints.
   [deg] is the CSS angle: 0 points up, 90 right, clockwise. *)
let gradient_dir deg =
  let a = deg *. Float.pi /. 180. in
  let ux = sin a and uy = ~-.(cos a) in
  (0.5 -. (ux /. 2.), 0.5 -. (uy /. 2.), 0.5 +. (ux /. 2.), 0.5 +. (uy /. 2.))

(* The angle argument of a gradient spec: "<f>deg", a bare number, or
   "to <dirs>" with 1–2 direction words (corners take the mean angle). *)
let angle_of_arg s =
  let s = String.trim s in
  if String.starts_with ~prefix:"to " s then
    let dirs = tokens (String.sub s 3 (String.length s - 3)) in
    let sum, n =
      List.fold_left
        (fun (sum, n) d ->
          match d with
          | "top" -> (sum +. 0., n + 1)
          | "right" -> (sum +. 90., n + 1)
          | "bottom" -> (sum +. 180., n + 1)
          | "left" -> (sum +. 270., n + 1)
          | _ -> (sum, n))
        (0., 0) dirs
    in
    if n = 0 then None else Some (sum /. float n)
  else
    let s =
      if String.ends_with ~suffix:"deg" s then
        String.sub s 0 (String.length s - 3)
      else s
    in
    float_of_string_opt s

(* Parse a background value into scene paint: a plain color → Solid;
   "linear-gradient(<angle>, c1, c2)" → Linear;
   "oklab-gradient(<angle>, c1, c2)" → Oklab;
   "stripes(<angle>, c1, c2)" → Stripes.
   Angle defaults to 180° (top → bottom) when omitted. *)
let paint_of hooks s =
  let s = String.trim s in
  let gradient kind inner =
    match split_commas inner with
    | [] -> None
    | args ->
      let angle, cols =
        match args with
        | a :: rest -> (
          match angle_of_arg a with
          | Some d -> (d, rest)
          | None -> (180., args))
        | [] -> (180., args)
      in
      (match cols with
       | [ c1; c2 ] -> (
         match (color_of_value hooks.color_of c1, color_of_value hooks.color_of c2) with
         | Some c1, Some c2 -> Some (kind, c1, c2, gradient_dir angle)
         | _ -> None)
       | _ -> None)
  in
  match fn_args "linear-gradient" s with
  | Some inner -> gradient Linear inner
  | None -> (
    match fn_args "oklab-gradient" s with
    | Some inner -> gradient Oklab inner
    | None -> (
      match fn_args "stripes" s with
      | Some inner -> gradient Stripes inner
      | None -> (
        match color_of_value hooks.color_of s with
        | Some c -> Some (Solid, c, c, (0., 0., 0., 0.))
        | None -> None)))

(* One fill op; callers assemble the record fields they need. *)
let fill frect fradii ~paint ~c1 ~c2 ~grad ~border ~bcolor ~dashed ~alpha =
  Fill
    { frect; fradii; fcontinuous = false; fcolor = c1; fpaint = paint;
      fcolor2 = c2; fgradient = grad; fborder = border;
      fborder_color = bcolor; fdashed = dashed; fwide = 0;
      fopacity = alpha }

let solid c = (Solid, c, c, (0., 0., 0., 0.))
let transparent_paint = solid (color 0 0 0 0)

(* Scale an op's own opacity by the node's accumulated subtree alpha. *)
let scale_op alpha = function
  | Fill f -> Fill { f with fopacity = f.fopacity *. alpha }
  | Shadow s -> Shadow { s with sopacity = s.sopacity *. alpha }
  | Glyphs g -> Glyphs { g with gopacity = g.gopacity *. alpha }
  | Image i -> Image { i with iopacity = i.iopacity *. alpha }
  | Effect e -> Effect { e with edopacity = e.edopacity *. alpha }
  | Hole h -> Hole { h with hopacity = h.hopacity *. alpha }
  | (Push_clip _ | Pop_clip) as op -> op

let scale_ops alpha ops = List.map (scale_op alpha) ops

let grow_radii (tl, tr, br, bl) d = (tl +. d, tr +. d, br +. d, bl +. d)
let shrink_radii (tl, tr, br, bl) d =
  (Float.max 0. (tl -. d), Float.max 0. (tr -. d), Float.max 0. (br -. d),
   Float.max 0. (bl -. d))

(* A shadow spec (logical px) becomes a scene Shadow op (device px).
   Spread folds into the shadow rect: outset shadows inflate, inset
   shadows deflate — a "0 0 0 Npx" ring lands spread-wide on the right
   side of the cast edge either way. *)
let shadow_op_of ctx r radii spec alpha =
  let s = ctx.scale in
  let dx = spec.dx *. s and dy = spec.dy *. s in
  let spread = spec.spread *. s in
  let srect, sradii =
    if spec.inset then
      let r' =
        rect (r.x +. spread) (r.y +. spread)
          (Float.max 0. (r.w -. (2. *. spread)))
          (Float.max 0. (r.h -. (2. *. spread)))
      in
      (rect (r'.x +. dx) (r'.y +. dy) r'.w r'.h, shrink_radii radii spread)
    else
      let r' =
        rect (r.x -. spread) (r.y -. spread) (r.w +. (2. *. spread))
          (r.h +. (2. *. spread))
      in
      (rect (r'.x +. dx) (r'.y +. dy) r'.w r'.h, grow_radii radii spread)
  in
  Shadow
    { srect; sradii = corners srect sradii false; scontinuous = false;
      scolor = spec.scolor; sblur = spec.blur *. s; sinset = spec.inset;
      scast = r; scast_radii = radii; scast_continuous = false; swide = 0;
      sopacity = alpha }

(* ---------- box props ---------- *)

let radii_of ctx store id =
  match pnums store id "corner-radius" with
  | [] -> (0., 0., 0., 0.)
  | l ->
    let (t, r, b, l) = edges_of_floats l in
    (t *. ctx.scale, r *. ctx.scale, b *. ctx.scale, l *. ctx.scale)

let border_widths ctx store id =
  match pnums store id "border-width" with
  | [] -> (0., 0., 0., 0.)
  | l ->
    let (t, r, b, l) = edges_of_floats l in
    (t *. ctx.scale, r *. ctx.scale, b *. ctx.scale, l *. ctx.scale)

(* Border colors: the whole value resolves → uniform; otherwise each
   shorthand token resolves → per-edge. Unresolvable → no borders. *)
let border_colors hooks store id =
  match pstr store id "border-color" with
  | None -> []
  | Some s -> (
    match color_of_value hooks.color_of s with
    | Some c -> [ c ]
    | None ->
      let ts = tokens s in
      let cs = List.filter_map (color_of_value hooks.color_of) ts in
      if List.length cs = List.length ts && cs <> [] then cs else [])

let dashed_border store id =
  match pstr store id "border-style" with
  | Some ("dashed" | "dotted") -> true
  | _ -> false

(* One fill per border edge when colors differ per edge; the corners
   then meet edge-to-edge instead of inheriting a single color. *)
let per_edge_border_fills r radii bw cs dashed alpha =
  let (wt, wr, wb, wl) = bw in
  let (ct, cr, cb, cl) = edges_of_or (color 0 0 0 0) cs in
  let edge w col border =
    if w > 0. then
      Some
        (fill r (corners r radii false) ~paint:Solid ~c1:(color 0 0 0 0)
           ~c2:(color 0 0 0 0) ~grad:(0., 0., 0., 0.) ~border ~bcolor:col
           ~dashed ~alpha)
    else None
  in
  List.filter_map Fun.id
    [ edge wt ct (wt, 0., 0., 0.); edge wr cr (0., wr, 0., 0.);
      edge wb cb (0., 0., wb, 0.); edge wl cl (0., 0., 0., wl) ]

(* Ops drawn for the node's own box decoration: outset shadow under the
   box, fill and borders, inset shadow over the fill. *)
let box_ops ctx store id rs r alpha =
  let radii = radii_of ctx store id in
  let bw = border_widths ctx store id in
  let bcs = border_colors ctx.hooks store id in
  let dashed = dashed_border store id in
  let shadow_op =
    match rs.rs_shadow with
    | Some s -> (
      match ctx.hooks.shadow_of s with
      | Some spec -> Some (shadow_op_of ctx r radii spec alpha, spec.inset)
      | None -> None)
    | None -> None
  in
  let outset, inset =
    match shadow_op with
    | Some (op, false) -> ([ op ], [])
    | Some (op, true) -> ([], [ op ])
    | None -> ([], [])
  in
  let bg =
    match rs.rs_background with
    | Some s -> paint_of ctx.hooks s
    | None -> None
  in
  let fills =
    match bcs with
    | [] | [ _ ] -> (
      let bc = match bcs with [ c ] -> c | _ -> color 0 0 0 0 in
      match (bg, has_border bw) with
      | None, false -> []
      | _ ->
        let (p, c1, c2, g) =
          match bg with Some p -> p | None -> transparent_paint
        in
        [ fill r (corners r radii false) ~paint:p ~c1 ~c2 ~grad:g
            ~border:bw ~bcolor:bc ~dashed ~alpha ])
    | cs ->
      let base =
        match bg with
        | Some (p, c1, c2, g) ->
          [ fill r (corners r radii false) ~paint:p ~c1 ~c2 ~grad:g
              ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed ~alpha ]
        | None -> []
      in
      base @ per_edge_border_fills r radii bw cs dashed alpha
  in
  outset @ fills @ inset

(* ---------- helpers for control chrome ---------- *)

let text_fg ctx store id =
  match pcolor ctx.hooks store id "foreground" with
  | Some c -> c
  | None -> theme ctx "foreground" (color 0 0 0 255)

(* Leading-edge square used by checkbox and radio. *)
let leading_box ctx r side_logical =
  let side = Float.min (side_logical *. ctx.scale) (Float.min r.w r.h) in
  rect r.x (r.y +. ((r.h -. side) /. 2.)) side side

(* Label text to the right of a leading control box, bounded by the
   node's own rect, with the node's accumulated opacity folded in. *)
let label_after ctx store id r box gap_logical alpha =
  match pstr store id "text" with
  | Some s when s <> "" ->
    let x = box.x +. box.w +. (gap_logical *. ctx.scale) in
    scale_ops alpha
      (ctx.hooks.text_ops id
         (rect x r.y (Float.max 0. (r.x +. r.w -. x)) r.h)
         (text_fg ctx store id) s)
  | _ -> []

(* The node's effective corner radii when set, else a default for
   control chrome. *)
let chrome_radii ctx store id default =
  let (t, r, b, l) = radii_of ctx store id in
  if t = 0. && r = 0. && b = 0. && l = 0. then (default, default, default, default)
  else (t, r, b, l)

let frac_of store id =
  match pnum store id "value" with
  | None -> 0.
  | Some v -> (
    match (pnum store id "min", pnum store id "max") with
    | Some lo, Some hi when hi > lo -> clamp01 ((v -. lo) /. (hi -. lo))
    | _ -> clamp01 v)

(* ---------- kind visuals ---------- *)

let text_ops ctx store id r alpha ~placeholder_ok =
  let s =
    match pstr store id "text" with
    | Some s when s <> "" -> Some (s, text_fg ctx store id)
    | _ ->
      if placeholder_ok then
        match pstr store id "placeholder" with
        | Some s when s <> "" -> Some (s, col_muted_fg ctx)
        | _ -> None
      else None
  in
  match s with
  | Some (s, fg) -> scale_ops alpha (ctx.hooks.text_ops id r fg s)
  | None -> []

(* divider: a 1 logical px line centered on the node's minor axis. *)
let divider_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let vertical =
    match pstr store id "orientation" with
    | Some "vertical" -> true
    | Some "horizontal" -> false
    | _ -> r.h > r.w
  in
  let c =
    match pcolor ctx.hooks store id "border-color" with
    | Some c -> c
    | None -> (
      match pcolor ctx.hooks store id "background" with
      | Some c -> c
      | None -> col_border ctx)
  in
  let t = Float.min (1. *. s) (if vertical then r.w else r.h) in
  let lr =
    if vertical then rect (r.x +. ((r.w -. t) /. 2.)) r.y t r.h
    else rect r.x (r.y +. ((r.h -. t) /. 2.)) r.w t
  in
  box_ops ctx store id rs r alpha
  @ [ fill lr (0., 0., 0., 0.) ~paint:Solid ~c1:c ~c2:c
        ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
        ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]

(* progress: rounded track plus a value-proportional fill. *)
let progress_ops ctx store id rs r alpha =
  let frac = frac_of store id in
  let track_c =
    match pcolor ctx.hooks store id "background" with
    | Some c -> c
    | None -> col_secondary ctx
  in
  let fill_c =
    match pcolor ctx.hooks store id "foreground" with
    | Some c -> c
    | None -> col_primary ctx
  in
  let half = r.h /. 2. in
  box_ops ctx store id rs r alpha
  @ [ fill r (corners r (half, half, half, half) false) ~paint:Solid
        ~c1:track_c ~c2:track_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      fill (rect r.x r.y (r.w *. frac) r.h)
        (corners r (half, half, half, half) false) ~paint:Solid ~c1:fill_c
        ~c2:fill_c ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
        ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]

(* checkbox: leading square; border when unchecked, filled + check
   glyph through the text hook when checked. *)
let checkbox_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let b = leading_box ctx r 16. in
  let checked = pbool store id "checked" in
  let accent =
    match pcolor ctx.hooks store id "border-color" with
    | Some c -> c
    | None -> col_primary ctx
  in
  let rad = chrome_radii ctx store id (4. *. s) in
  let chrome =
    if checked then
      fill b (corners b rad false) ~paint:Solid ~c1:accent ~c2:accent
        ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
        ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha
      :: scale_ops alpha
           (ctx.hooks.text_ops id b (col_primary_fg ctx) "\xe2\x9c\x93")
    else
      [ fill b (corners b rad false) ~paint:Solid ~c1:(color 0 0 0 0)
          ~c2:(color 0 0 0 0) ~grad:(0., 0., 0., 0.)
          ~border:(1. *. s, 1. *. s, 1. *. s, 1. *. s) ~bcolor:accent
          ~dashed:false ~alpha ]
  in
  box_ops ctx store id rs r alpha @ chrome @ label_after ctx store id r b 8. alpha

(* radio: leading circle; ring border unchecked, disc ring checked. *)
let radio_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let b = leading_box ctx r 16. in
  let half = b.w /. 2. in
  let checked = pbool store id "checked" in
  let accent =
    match pcolor ctx.hooks store id "border-color" with
    | Some c -> c
    | None -> col_primary ctx
  in
  let chrome =
    if checked then
      let inner = b.w /. 2. in
      [ fill b (corners b (half, half, half, half) false) ~paint:Solid
          ~c1:accent ~c2:accent ~grad:(0., 0., 0., 0.)
          ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
        (let c =
           match pcolor ctx.hooks store id "background" with
           | Some c -> c
           | None -> col_background ctx
         in
         let d = inner in
         fill
           (rect (b.x +. ((b.w -. d) /. 2.)) (b.y +. ((b.h -. d) /. 2.)) d d)
           (corners b (d /. 2., d /. 2., d /. 2., d /. 2.) false)
           ~paint:Solid ~c1:c ~c2:c ~grad:(0., 0., 0., 0.)
           ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha) ]
    else
      [ fill b (corners b (half, half, half, half) false) ~paint:Solid
          ~c1:(color 0 0 0 0) ~c2:(color 0 0 0 0) ~grad:(0., 0., 0., 0.)
          ~border:(1. *. s, 1. *. s, 1. *. s, 1. *. s) ~bcolor:accent
          ~dashed:false ~alpha ]
  in
  box_ops ctx store id rs r alpha @ chrome @ label_after ctx store id r b 8. alpha

(* switch: trailing rounded track with a thumb on the checked side. *)
let switch_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let tw = Float.min (44. *. s) r.w and th = Float.min (24. *. s) r.h in
  let tr = rect (r.x +. r.w -. tw) (r.y +. ((r.h -. th) /. 2.)) tw th in
  let checked = pbool store id "checked" in
  let track_c =
    if checked then col_primary ctx
    else
      match pcolor ctx.hooks store id "border-color" with
      | Some c -> c
      | None -> theme ctx "input" (color 229 231 235 255)
  in
  let d = Float.max 0. (th -. (4. *. s)) in
  let tx =
    if checked then tr.x +. tr.w -. (2. *. s) -. d else tr.x +. (2. *. s)
  in
  let thumb_r = rect tx (tr.y +. ((tr.h -. d) /. 2.)) d d in
  let thumb_c = col_background ctx in
  box_ops ctx store id rs r alpha
  @ [ fill tr (corners tr (th /. 2., th /. 2., th /. 2., th /. 2.) false)
        ~paint:Solid ~c1:track_c ~c2:track_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      fill thumb_r (corners thumb_r (d /. 2., d /. 2., d /. 2., d /. 2.) false)
        ~paint:Solid ~c1:thumb_c ~c2:thumb_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]

(* slider: thin track, filled portion, round thumb at the fraction. *)
let slider_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let frac = frac_of store id in
  let th = Float.min (4. *. s) r.h in
  let tr = rect r.x (r.y +. ((r.h -. th) /. 2.)) r.w th in
  let track_c =
    match pcolor ctx.hooks store id "border-color" with
    | Some c -> c
    | None -> theme ctx "input" (color 229 231 235 255)
  in
  let fill_c =
    match pcolor ctx.hooks store id "foreground" with
    | Some c -> c
    | None -> col_primary ctx
  in
  let d = Float.min (16. *. s) r.h in
  let cx = r.x +. (r.w *. frac) in
  let cx = Float.max (r.x +. (d /. 2.)) (Float.min (r.x +. r.w -. (d /. 2.)) cx) in
  let thumb_r = rect (cx -. (d /. 2.)) (r.y +. ((r.h -. d) /. 2.)) d d in
  box_ops ctx store id rs r alpha
  @ [ fill tr (corners tr (th /. 2., th /. 2., th /. 2., th /. 2.) false)
        ~paint:Solid ~c1:track_c ~c2:track_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      fill (rect tr.x tr.y (tr.w *. frac) tr.h)
        (corners tr (th /. 2., th /. 2., th /. 2., th /. 2.) false)
        ~paint:Solid ~c1:fill_c ~c2:fill_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      fill thumb_r (corners thumb_r (d /. 2., d /. 2., d /. 2., d /. 2.) false)
        ~paint:Solid ~c1:fill_c ~c2:fill_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]

(* spinner: a ring drawn as border edges with one quarter missing —
   the static placeholder until an animated arc op exists. *)
let spinner_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let side = Float.min r.w r.h in
  let b = rect (r.x +. ((r.w -. side) /. 2.)) (r.y +. ((r.h -. side) /. 2.)) side side in
  let half = side /. 2. in
  let w = 2. *. s in
  let c =
    match pcolor ctx.hooks store id "foreground" with
    | Some c -> c
    | None -> col_primary ctx
  in
  let edge border =
    fill b (corners b (half, half, half, half) false) ~paint:Solid
      ~c1:(color 0 0 0 0) ~c2:(color 0 0 0 0) ~grad:(0., 0., 0., 0.) ~border
      ~bcolor:c ~dashed:false ~alpha
  in
  box_ops ctx store id rs r alpha
  @ [ edge (w, 0., 0., 0.); edge (0., 0., w, 0.); edge (0., 0., 0., w) ]

(* icon: host-decoded glyph image, else a foreground square so the
   missing path stays visible in tests. *)
let icon_ops ctx store id rs r alpha =
  box_ops ctx store id rs r alpha
  @
  match ctx.hooks.image_of id with
  | Some img ->
    [ Image
        { irect2 = r; iradii = (0., 0., 0., 0.); icontinuous = false;
          iimage = img;
          isrc = { x = 0.; y = 0.; w = float img.iw; h = float img.ih };
          igrayscale = false; iopacity = alpha } ]
  | None -> []

(* image rect + source rect from the source-* props and image-fit. *)
let image_ops ctx store id r alpha radii =
  match ctx.hooks.image_of id with
  | None -> []
  | Some img ->
    let sw, sh = float img.iw, float img.ih in
    let isrc =
      match
        ( pnum store id "source-x", pnum store id "source-y",
          pnum store id "source-width", pnum store id "source-height" )
      with
      | Some sx, Some sy, Some sw', Some sh' when sw' > 0. && sh' > 0. ->
        rect sx sy sw' sh'
      | _ -> rect 0. 0. sw sh
    in
    let dst =
      match pstr store id "image-fit" with
      | Some "fit" ->
        (* letterbox the source inside the layout rect *)
        let k = Float.min (r.w /. isrc.w) (r.h /. isrc.h) in
        let w = isrc.w *. k and h = isrc.h *. k in
        rect (r.x +. ((r.w -. w) /. 2.)) (r.y +. ((r.h -. h) /. 2.)) w h
      | _ -> r
    in
    [ Image
        { irect2 = dst; iradii = radii; icontinuous = false; iimage = img;
          isrc; igrayscale = false; iopacity = alpha } ]

(* vertical scrollbar thumb inside a scroll container's clip. *)
let scrollbar_ops ctx store id r alpha =
  match ctx.hooks.scroll_of id with
  | Some sm when sm.sm_extent > 0. && sm.sm_extent < 1. ->
    let s = ctx.scale in
    let w = 4. *. s and m = 2. *. s in
    let th = Float.max (r.h *. sm.sm_extent) (16. *. s) in
    let ty = r.y +. ((r.h -. th) *. clamp01 sm.sm_offset) in
    let c =
      match pcolor ctx.hooks store id "border-color" with
      | Some c -> c
      | None -> theme ctx "muted-foreground" (color 128 128 128 160)
    in
    let tr = rect (r.x +. r.w -. w -. m) ty w th in
    [ fill tr (corners tr (w /. 2., w /. 2., w /. 2., w /. 2.) false)
        ~paint:Solid ~c1:c ~c2:c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]
  | _ -> []

(* ---------- node paint ---------- *)

let scroll_kind = function
  | "scroll" | "list" | "virtual-list" -> true
  | _ -> false

let scrollable kind store id =
  scroll_kind kind
  || match pstr store id "overflow" with
     | Some ("auto" | "scroll") -> true
     | _ -> false

let clips kind store id =
  scrollable kind store id
  || match pstr store id "overflow" with
     | Some ("hidden" | "clip" | "auto" | "scroll") -> true
     | _ -> false

(* The node's display box: layout result → popup x/y override →
   position/inset resolution → layout rect. *)
let resolve_rect ctx store id p parent_r =
  match p.p_override with
  | Some r -> r
  | None ->
    let s = ctx.scale in
    let side n = match pnum store id n with
      | Some v -> Some v
      | None -> pnum store id "inset"
    in
    let it, ir, ib, il =
      (side "inset-top", side "inset-right", side "inset-bottom", side "inset-left")
    in
    let pos = pstr store id "position" in
    if pos = Some "absolute" || pos = Some "fixed" then (
      let cb = if pos = Some "fixed" then ctx.viewport else parent_r in
      let x =
        match il with
        | Some l -> cb.x +. (l *. s)
        | None -> (
          match ir with
          | Some v -> cb.x +. cb.w -. (v *. s) -. p.p_rect.w
          | None -> p.p_rect.x)
      in
      let y =
        match it with
        | Some t -> cb.y +. (t *. s)
        | None -> (
          match ib with
          | Some v -> cb.y +. cb.h -. (v *. s) -. p.p_rect.h
          | None -> p.p_rect.y)
      in
      { p.p_rect with x; y })
    else if pos = Some "relative" then (
      let dx =
        match il with
        | Some l -> l
        | None -> (match ir with Some v -> ~-.v | None -> 0.)
      in
      let dy =
        match it with
        | Some t -> t
        | None -> (match ib with Some v -> ~-.v | None -> 0.)
      in
      { p.p_rect with
        x = p.p_rect.x +. (dx *. s); y = p.p_rect.y +. (dy *. s) })
    else
      (* Popup coordinates are absolute placements on popup kinds. *)
      match (pnum store id "x", pnum store id "y") with
      | Some x, Some y -> { p.p_rect with x = x *. s; y = y *. s }
      | Some x, None -> { p.p_rect with x = x *. s }
      | None, Some y -> { p.p_rect with y = y *. s }
      | None, None -> p.p_rect

let zindex store id =
  match Lui_store.prop store id "z-index" with
  | Some (Lui_protocol.IntValue i) -> i
  | Some (Lui_protocol.FloatValue f) -> int_of_float f
  | Some (Lui_protocol.StringValue s) -> (
    match int_of_string_opt (String.trim s) with Some i -> i | None -> 0)
  | _ -> 0

(* Siblings paint in z-index order, DOM order breaking ties. *)
let ordered_children store id =
  Lui_store.children store id
  |> List.stable_sort (fun a b ->
       compare
         (zindex store (Lui_store.node_id a))
         (zindex store (Lui_store.node_id b)))

let node_shown store id =
  (match Lui_store.prop store id "visible" with
   | Some (Lui_protocol.BoolValue false) -> false
   | Some (Lui_protocol.StringValue "false") -> false
   | _ -> true)
  && (match pstr store id "display" with Some "none" -> false | _ -> true)

let unboxed store id = pstr store id "display" = Some "contents"

let emit scene ops = scene.ops <- List.rev_append ops scene.ops
let emit1 scene op = scene.ops <- op :: scene.ops

(* Ops for a single node's own chrome. *)
let rec paint_own ctx store id kind r rs alpha =
  match kind with
  | "spacer" -> []
  | "divider" -> divider_ops ctx store id rs r alpha
  | "progress" -> progress_ops ctx store id rs r alpha
  | "checkbox" -> checkbox_ops ctx store id rs r alpha
  | "radio" -> radio_ops ctx store id rs r alpha
  | "switch" -> switch_ops ctx store id rs r alpha
  | "slider" -> slider_ops ctx store id rs r alpha
  | "spinner" -> spinner_ops ctx store id rs r alpha
  | "icon" -> icon_ops ctx store id rs r alpha
  | "image" | "file-image" | "media-surface" | "file-preview" ->
    box_ops ctx store id rs r alpha
    @ image_ops ctx store id r alpha (corners r (radii_of ctx store id) false)
  | "avatar" -> (
    let half = r.h /. 2. in
    let rad = (half, half, half, half) in
    match ctx.hooks.image_of id with
    | Some _ -> box_ops ctx store id rs r alpha @ image_ops ctx store id r alpha (corners r rad false)
    | None -> (
      let rad = chrome_radii ctx store id half in
      let b = rect r.x r.y r.w r.h in
      let c = theme ctx "primary" (color 37 99 235 255) in
      match pstr store id "text" with
      | Some s when s <> "" ->
        [ fill b (corners b rad false) ~paint:Solid ~c1:c ~c2:c
            ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
            ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]
        @ scale_ops alpha (ctx.hooks.text_ops id r (col_primary_fg ctx) s)
      | _ -> box_ops ctx store id rs r alpha))
  | "text" | "label" | "heading" | "paragraph" | "br" | "link" | "kbd" ->
    box_ops ctx store id rs r alpha
    @ text_ops ctx store id r alpha ~placeholder_ok:false
  | "text-field" | "secure-field" | "input" | "search-field" | "textarea"
  | "select" | "combobox" ->
    box_ops ctx store id rs r alpha
    @ text_ops ctx store id r alpha ~placeholder_ok:true
  | "button" | "toggle-button" | "toggle" | "menu-item" | "menu-trigger"
  | "bottom-tab" | "list-item" | "swipe-action" | "file-picker"
  | "list-section-header" | "list-section-footer" ->
    (* labeled chrome: box decoration plus the label through the text
       engine *)
    box_ops ctx store id rs r alpha
    @ text_ops ctx store id r alpha ~placeholder_ok:false
  | kind -> (
    match String.index_opt kind ':' with
    | Some _ when String.length kind > 10 && String.sub kind 0 10 = "extension:" -> (
      let identifier = String.sub kind 10 (String.length kind - 10) in
      match Hashtbl.find_opt extension_renderers identifier with
      | Some renderer -> (
        match Lui_store.find_opt store id with
        | Some node -> scale_ops alpha (renderer.paint ctx store node r)
        | None -> box_ops ctx store id rs r alpha)
      | None -> box_ops ctx store id rs r alpha)
    | _ -> box_ops ctx store id rs r alpha)

(* A visible node: resolve state and placement, clip, own chrome,
   children in z order, scrollbar, unclip. *)
and paint_node ctx store scene id parent_r alpha =
  if node_shown store id then (
    let st = effective_state ctx.hooks store id in
    let rs = resolve_style store id st in
    let p = ctx.hooks.layout id in
    let r = resolve_rect ctx store id p parent_r in
    let kind = Lui_store.kind store id in
    let contents = unboxed store id in
    (* display:contents generates no box, so its opacity and chrome do
       not apply — children paint with the parent's alpha and clip. *)
    let alpha = if contents then alpha else alpha *. rs.rs_opacity in
    let clip =
      (not contents) && (not (rect_empty r)) && clips kind store id
    in
    if clip then
      emit1 scene
        (Push_clip
           { crect = r; cradii = corners r (radii_of ctx store id) false;
             ccontinuous = false });
    if not contents then emit scene (paint_own ctx store id kind r rs alpha);
    (* Children of a display:contents node keep the parent's containing
       block — the node itself generates no box to anchor to. *)
    let child_parent = if contents then parent_r else r in
    List.iter
      (fun c -> paint_node ctx store scene (Lui_store.node_id c) child_parent alpha)
      (ordered_children store id);
    if scrollable kind store id && not contents then
      emit scene (scrollbar_ops ctx store id r alpha);
    if clip then emit1 scene Pop_clip)

(* Full repaint: reset the scene and repaint the whole forest. *)
let paint hooks store scene ~width ~height ~scale ~clear =
  Lui_scene.reset scene ~width ~height ~scale ~clear;
  let ctx =
    { hooks; scale;
      viewport = rect 0. 0. (float width) (float height) }
  in
  List.iter
    (fun id -> paint_node ctx store scene id ctx.viewport 1.)
    (Lui_store.root_ids store);
  scene.ops <- List.rev scene.ops
