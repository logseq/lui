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
    ("max-height-viewport", Layout);
    ("margin", Layout); (* CSS shorthand, 1–4 lengths *)
    ("margin-horizontal", Layout);
    ("margin-vertical", Layout);
    ("margin-top", Layout);
    ("margin-right", Layout);
    ("margin-bottom", Layout);
    ("margin-left", Layout);
    ("font-family", Painted_by_text);
    ("font-style", Painted_by_text);
    ("text-decoration", Painted_by_text);
    ("list-style", Painted_by_text); (* list marker style *)
    ("flex-wrap", Layout);
    ("hover-foreground", Painted);
    ("hover-border", Painted);
    ("transition", Unmapped "prop transition animation, applied by the diff layer") ]

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

(* HSL (h in degrees, s and l in 0..1) to a premultiplied color. *)
let hsl h s l =
  let c = (1. -. Float.abs (2. *. l -. 1.)) *. s in
  let h' = Float.rem h 360. /. 60. in
  let h' = if h' < 0. then h' +. 6. else h' in
  let x = c *. (1. -. Float.abs (Float.rem h' 2. -. 1.)) in
  let m = l -. (c /. 2.) in
  let r, g, b =
    match int_of_float h' with
    | 0 -> (c, x, 0.) | 1 -> (x, c, 0.) | 2 -> (0., c, x)
    | 3 -> (0., x, c) | 4 -> (x, 0., c) | _ -> (c, 0., x)
  in
  let ch v = int_of_float ((v +. m) *. 255.) in
  color (ch r) (ch g) (ch b) 255

(* Stable per-string hue: initials of a name always get the same tint. *)
let hash_hue s =
  let h = ref 5381 in
  String.iter (fun c -> h := (!h * 33 + Char.code c) land max_int) s;
  float (!h mod 360)

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
  mounted_children : int -> int list option;
    (* virtualized container id → mounted child store ids: the child
       walk enumerates only that slice, so a scroll frame over a 100k
       virtual list touches ~30 rows, not 100k. [None] enumerates
       every child (ordinary containers). *)
  text_ops : int -> rect -> color -> string -> op list; (* text engine *)
  image_of : int -> image option;    (* node id → decoded image *)
  image_in : int -> rect -> image option;
    (* node id → target rect (logical px) → decoded image; for sources
       that rasterize on demand (svg icons) so a glyph drawn in a slot
       smaller than the node's own rect stays crisp *)
  shadow_of : string -> shadow_spec list; (* shadow spec parser *)
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
  deferred : (unit -> unit) Queue.t;
    (** Popup subtrees collected during the walk; painted after the
        whole tree so a popup declared mid-tree is never covered by
        later siblings — the overlay stacking contract these kinds
        carry on the web. *)
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
    mounted_children = (fun _ -> None);
    text_ops = (fun _ _ _ _ -> []);
    image_of = (fun _ -> None);
    image_in = (fun _ _ -> None);
    shadow_of = (fun _ -> []) }

(* ---------- shadow parsing ---------- *)

(* CSS box-shadow grammar, all comma-separated layers:
     [inset]? <dx> <dy> [<blur> [<spread>]] [<color>]
   Lengths may carry a px suffix; color may be hex, rgb()/rgba(),
   "transparent" or a resolver name. Unparseable layers are dropped;
   "none"/empty give []. The list stays in CSS order — the first
   layer is topmost (painted last). All lengths come out in logical
   px; callers scale to device px. *)
let parse_shadows resolve s =
  let layer_of l =
    let toks = tokens l in
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
  in
  let s = String.trim s in
  if s = "" || s = "none" then [] else List.filter_map layer_of (split_commas s)

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
   them, so control chrome still draws. [default_palette] mirrors the
   canonical light tokens kept in lui_theme; the lui_theme test asserts
   the two tables agree so fallbacks can't drift. *)
let default_palette : (string * color) list =
  [ ("background", color 255 255 255 255);
    ("foreground", color 24 24 27 255);
    ("text", color 24 24 27 255);
    ("text-muted", color 110 110 119 255);
    ("muted-foreground", color 110 110 119 255);
    ("muted", color 244 244 245 255);
    ("surface", color 244 244 245 255);
    ("surface-hover", color 233 233 236 255);
    ("surface-pressed", color 221 221 225 255);
    ("popover", color 255 255 255 255);
    ("card", color 255 255 255 255);
    ("border", color 217 217 222 255);
    ("input", color 217 217 222 255);
    ("control-border", color 169 170 174 255);
    ("switch-track", color 188 188 193 255);
    ("accent", color 37 99 235 255);
    ("accent-hover", color 29 78 216 255);
    ("accent-pressed", color 30 64 175 255);
    ("accent-text", color 255 255 255 255);
    ("primary", color 37 99 235 255);
    ("primary-foreground", color 255 255 255 255);
    ("secondary", color 244 244 245 255);
    ("danger", color 220 38 38 255);
    ("destructive", color 220 38 38 255);
    ("warning", color 217 119 6 255);
    ("success", color 22 163 74 255);
    ("focus", color 37 99 235 140);
    ("ring", color 37 99 235 140);
    ("selection", color 37 99 235 64);
    ("scrollbar-thumb", color 0 0 0 82);
    ("inverse", color 24 24 27 255);
    ("inverse-foreground", color 255 255 255 255);
    (* Modal popup backdrop — the dim a dialog or sheet paints over
       the content it covers (web .lui-modal-backdrop = black at 50%). *)
    ("scrim", color 0 0 0 128) ]

let theme ctx name =
  match ctx.hooks.color_of name with
  | Some c -> c
  | None -> (
    match List.assoc_opt name default_palette with
    | Some c -> c
    | None -> color 0 0 0 0)

let col_primary ctx = theme ctx "primary"
let col_primary_fg ctx = theme ctx "primary-foreground"
let col_secondary ctx = theme ctx "secondary"
let col_border ctx = theme ctx "border"
let col_background ctx = theme ctx "background"
let col_muted_fg ctx = theme ctx "muted-foreground"
let col_surface ctx = theme ctx "surface"
let col_surface_hover ctx = theme ctx "surface-hover"
let col_surface_pressed ctx = theme ctx "surface-pressed"
let col_accent ctx = theme ctx "accent"
let col_accent_hover ctx = theme ctx "accent-hover"
let col_accent_text ctx = theme ctx "accent-text"
let col_control_border ctx = theme ctx "control-border"
let col_switch_track ctx = theme ctx "switch-track"
let col_focus ctx = theme ctx "focus"
let col_scrollbar ctx = theme ctx "scrollbar-thumb"
let col_danger ctx = theme ctx "danger"
let col_popover ctx = theme ctx "popover"
let col_inverse ctx = theme ctx "inverse"
let col_inverse_fg ctx = theme ctx "inverse-foreground"
let col_muted ctx = theme ctx "muted"

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

(* One fill op; callers assemble the record fields they need.
   [continuous] draws the radii as squircle corners. *)
let fill ?(continuous = false) frect fradii ~paint ~c1 ~c2 ~grad ~border ~bcolor ~dashed ~alpha =
  Fill
    { frect; fradii; fcontinuous = continuous; fcolor = c1; fpaint = paint;
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
  (* Every layer of the shadow spec paints: outsets under the box,
     insets over the fill. CSS draws shadows front-to-back — the first
     listed is topmost — and cons-accumulating emits them bottom
     first. *)
  let outset, inset =
    match rs.rs_shadow with
    | Some s ->
      List.fold_left
        (fun (o, i) spec ->
          let op = shadow_op_of ctx r radii spec alpha in
          if spec.inset then (o, op :: i) else (op :: o, i))
        ([], []) (ctx.hooks.shadow_of s)
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
  (* CSS color inherits: nearest ancestor carrying a foreground wins,
     falling back to the theme text color. *)
  let rec walk id =
    match pcolor ctx.hooks store id "foreground" with
    | Some c -> Some c
    | None -> (
      match Lui_store.parent store id with
      | Some pid when pid <> id -> walk pid
      | _ -> None)
  in
  match walk id with
  | Some c -> c
  | None -> theme ctx "foreground"

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

(* ---------- text placement ---------- *)

type text_align = Ta_start | Ta_center | Ta_end

type text_placement = {
  tp_align : text_align;
  tp_pad_x : float; (* logical px inset on each side *)
  tp_pad_y : float; (* logical px measure adds top and bottom *)
  tp_top : bool;    (* anchor first line at pad-y instead of centering *)
}

(* Where a kind's own ink sits inside its chrome: labeled controls
   center, fields and rows pad their ink, plain text flows from the
   edge. The text-alignment and padding props win over the table.
   Every text engine feeds this into its pen math so all backends
   place glyphs identically. *)
let text_placement_of store id =
  let align, pad_x, pad_y, top =
    match Lui_store.kind store id with
    | "button" | "toggle-button" | "toggle" | "menu-trigger"
    | "swipe-action" | "file-picker" -> (Ta_center, 14., 6., false)
    | "number-stepper" -> (Ta_center, 10., 5., false)
    | "kbd" -> (Ta_center, 6., 2., false)
    | "avatar" -> (Ta_center, 0., 0., false)
    | "bottom-tab" | "tab" -> (Ta_center, 12., 5., false)
    | "tooltip" | "toast" -> (Ta_center, 8., 4., false)
    | "alert" | "bubble" -> (Ta_start, 10., 6., false)
    | "menu-item" ->
      (* icon slot [x+8, x+26] + 4px gap shifts the label — the web
         stylesheet's icon+gap-1 inside px-2 *)
      (Ta_start, (if pstr store id "icon" = None then 8. else 30.), 6., false)
    | "table-cell" | "table-row" -> (Ta_start, 10., 6., false)
    | "step" -> (Ta_center, 8., 4., false)
    | "list-item" -> (Ta_start, 12., 6., false)
    | "text-field" | "secure-field" | "input" | "search-field"
    | "select" | "combobox" -> (Ta_start, 10., 6., false)
    | "textarea" -> (Ta_start, 10., 6., true)
    | _ -> (Ta_start, 0., 0., false)
  in
  let align =
    match pstr store id "text-alignment" with
    | Some "center" -> Ta_center
    | Some "end" -> Ta_end
    | Some _ -> Ta_start
    | None -> align
  in
  let pad_x, pad_y =
    match
      ( pnum store id "padding-horizontal", pnum store id "padding",
        pnum store id "padding-vertical" )
    with
    | Some x, _, v -> (x, Option.value ~default:pad_y v)
    | None, Some p, v -> (p, Option.value ~default:p v)
    | None, None, v -> (pad_x, Option.value ~default:pad_y v)
  in
  { tp_align = align; tp_pad_x = pad_x; tp_pad_y = pad_y; tp_top = top }

let text_ops ?fg ctx store id r alpha ~placeholder_ok =
  let fg =
    match fg with Some c -> c | None -> text_fg ctx store id
  in
  let s =
    match pstr store id "text" with
    | Some s when s <> "" -> Some (s, fg)
    | _ ->
      if placeholder_ok then
        match pstr store id "placeholder" with
        | Some s when s <> "" -> Some (s, col_muted_fg ctx)
        | _ -> (
          (* bottom-tab and timeline items label through [title]. *)
          match pstr store id "title" with
          | Some s when s <> "" -> Some (s, fg)
          | _ -> None)
      else (
        match pstr store id "title" with
        | Some s when s <> "" -> Some (s, fg)
        | _ -> None)
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
    | None -> col_border ctx
  in
  let fill_c =
    match pcolor ctx.hooks store id "foreground" with
    | Some c -> c
    | None -> col_accent ctx
  in
  let half = r.h /. 2. in
  box_ops ctx store id rs r alpha
  @ [ fill ~continuous:true r (corners r (half, half, half, half) false) ~paint:Solid
        ~c1:track_c ~c2:track_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      fill ~continuous:true (rect r.x r.y (r.w *. frac) r.h)
        (corners r (half, half, half, half) false) ~paint:Solid ~c1:fill_c
        ~c2:fill_c ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
        ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]

(* checkbox: leading square; neutral-bordered page box when
   unchecked (accent edge on hover), accent fill + check glyph through
   the text hook when checked. *)
let checkbox_ops ctx store id st rs r alpha =
  let s = ctx.scale in
  let b = leading_box ctx r 16. in
  let checked = pbool store id "checked" in
  let accent =
    match pcolor ctx.hooks store id "border-color" with
    | Some c -> c
    | None -> col_accent ctx
  in
  let rad = chrome_radii ctx store id (4. *. s) in
  let chrome =
    if checked then
      fill ~continuous:true b (corners b rad false) ~paint:Solid ~c1:accent ~c2:accent
        ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
        ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha
      :: scale_ops alpha
           (ctx.hooks.text_ops id b (col_accent_text ctx) "\xe2\x9c\x93")
    else
      [ let edge = if st.hovered then accent else col_control_border ctx in
        fill ~continuous:true b (corners b rad false) ~paint:Solid
          ~c1:(col_background ctx) ~c2:(col_background ctx)
          ~grad:(0., 0., 0., 0.)
          ~border:(1. *. s, 1. *. s, 1. *. s, 1. *. s) ~bcolor:edge
          ~dashed:false ~alpha ]
  in
  box_ops ctx store id rs r alpha @ chrome @ label_after ctx store id r b 8. alpha

(* radio: leading circle; neutral-bordered page disc unchecked
   (accent edge on hover), accent ring + small on-accent dot checked. *)
let radio_ops ctx store id st rs r alpha =
  let s = ctx.scale in
  let b = leading_box ctx r 16. in
  let half = b.w /. 2. in
  let checked = pbool store id "checked" in
  let accent =
    match pcolor ctx.hooks store id "border-color" with
    | Some c -> c
    | None -> col_accent ctx
  in
  let chrome =
    if checked then
      [ fill b (corners b (half, half, half, half) false) ~paint:Solid
          ~c1:accent ~c2:accent ~grad:(0., 0., 0., 0.)
          ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
        (let c =
           match pcolor ctx.hooks store id "background" with
           | Some c -> c
           | None -> col_accent_text ctx
         in
         let d = Float.min (6. *. s) (b.w /. 2.) in
         fill
           (rect (b.x +. ((b.w -. d) /. 2.)) (b.y +. ((b.h -. d) /. 2.)) d d)
           (corners b (d /. 2., d /. 2., d /. 2., d /. 2.) false)
           ~paint:Solid ~c1:c ~c2:c ~grad:(0., 0., 0., 0.)
           ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha) ]
    else
      [ let edge = if st.hovered then accent else col_control_border ctx in
        fill b (corners b (half, half, half, half) false) ~paint:Solid
          ~c1:(col_background ctx) ~c2:(col_background ctx) ~grad:(0., 0., 0., 0.)
          ~border:(1. *. s, 1. *. s, 1. *. s, 1. *. s) ~bcolor:edge
          ~dashed:false ~alpha ]
  in
  box_ops ctx store id rs r alpha @ chrome @ label_after ctx store id r b 8. alpha

(* switch: trailing pill track with a white knob on the checked side;
   the knob carries a small contact shadow so it reads as raised. *)
let switch_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let tw = Float.min (36. *. s) r.w and th = Float.min (20. *. s) r.h in
  let tr = rect (r.x +. r.w -. tw) (r.y +. ((r.h -. th) /. 2.)) tw th in
  let checked = pbool store id "checked" in
  let track_c =
    if checked then col_accent ctx
    else
      match pcolor ctx.hooks store id "border-color" with
      | Some c -> c
      | None -> col_switch_track ctx
  in
  let d = Float.max 0. (th -. (4. *. s)) in
  let tx =
    if checked then tr.x +. tr.w -. (2. *. s) -. d else tr.x +. (2. *. s)
  in
  let thumb_r = rect tx (tr.y +. ((tr.h -. d) /. 2.)) d d in
  let thumb_c = color 255 255 255 255 in
  let thumb_radii = (d /. 2., d /. 2., d /. 2., d /. 2.) in
  box_ops ctx store id rs r alpha
  @ [ fill ~continuous:true tr (corners tr (th /. 2., th /. 2., th /. 2., th /. 2.) false)
        ~paint:Solid ~c1:track_c ~c2:track_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      shadow_op_of ctx thumb_r thumb_radii
        { dx = 0.; dy = 1.; blur = 3.; spread = 0.;
          scolor = color 0 0 0 64; inset = false }
        alpha;
      fill ~continuous:true thumb_r
        (corners thumb_r thumb_radii false)
        ~paint:Solid ~c1:thumb_c ~c2:thumb_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]

(* slider: thin track with an accent-filled lead and a white capsule
   knob riding it; the knob wears a rim plus an ambient/key shadow pair
   so it lifts off the track. *)
let slider_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let frac = frac_of store id in
  let th = Float.min (6. *. s) r.h in
  let pad = Float.min (10. *. s) (r.w /. 2.) in
  let tr = rect (r.x +. pad) (r.y +. ((r.h -. th) /. 2.)) (Float.max 0. (r.w -. (2. *. pad))) th in
  let track_c =
    match pcolor ctx.hooks store id "border-color" with
    | Some c -> c
    | None -> col_border ctx
  in
  let fill_c =
    match pcolor ctx.hooks store id "foreground" with
    | Some c -> c
    | None -> col_accent ctx
  in
  let kw = Float.min (20. *. s) (r.w /. 2.) and kh = Float.min (16. *. s) r.h in
  let cx = tr.x +. (tr.w *. frac) in
  let cx = Float.max (tr.x +. (kw /. 2.)) (Float.min (tr.x +. tr.w -. (kw /. 2.)) cx) in
  let thumb_r = rect (cx -. (kw /. 2.)) (r.y +. ((r.h -. kh) /. 2.)) kw kh in
  let thumb_radii = (kh /. 2., kh /. 2., kh /. 2., kh /. 2.) in
  box_ops ctx store id rs r alpha
  @ [ fill ~continuous:true tr (corners tr (th /. 2., th /. 2., th /. 2., th /. 2.) false)
        ~paint:Solid ~c1:track_c ~c2:track_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      fill ~continuous:true (rect tr.x tr.y (tr.w *. frac) tr.h)
        (corners tr (th /. 2., th /. 2., th /. 2., th /. 2.) false)
        ~paint:Solid ~c1:fill_c ~c2:fill_c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha;
      shadow_op_of ctx thumb_r thumb_radii
        { dx = 0.; dy = 0.5; blur = 1.; spread = 0.;
          scolor = color 0 0 0 20; inset = false }
        alpha;
      shadow_op_of ctx thumb_r thumb_radii
        { dx = 0.; dy = 1.5; blur = 7.; spread = 0.;
          scolor = color 0 0 0 26; inset = false }
        alpha;
      fill ~continuous:true thumb_r (corners thumb_r thumb_radii false)
        ~paint:Solid ~c1:(color 255 255 255 255) ~c2:(color 255 255 255 255)
        ~grad:(0., 0., 0., 0.)
        ~border:(1. *. s, 1. *. s, 1. *. s, 1. *. s)
        ~bcolor:(col_control_border ctx) ~dashed:false ~alpha ]

(* spinner: twelve dots around a circle, alpha fading with age so the
   frame reads as the paused tick of a rotating indicator. *)
let spinner_ops ctx store id rs r alpha =
  let s = ctx.scale in
  let side = Float.min r.w r.h in
  let cx = r.x +. (r.w /. 2.) and cy = r.y +. (r.h /. 2.) in
  let base =
    match pcolor ctx.hooks store id "foreground" with
    | Some c -> c
    | None -> col_primary ctx
  in
  let rad = side *. 0.34 and d = Float.max (1.5 *. s) (side *. 0.16) in
  let half = d /. 2. in
  let spokes = 12 in
  let dot i =
    let theta = Float.pi *. 2. *. float i /. float spokes in
    let x = cx +. (rad *. Float.sin theta) and y = cy -. (rad *. Float.cos theta) in
    (* fade clockwise: dot 0 brightest, trailing dots dimmer *)
    let a = 1. -. (float i /. float spokes *. 0.85) in
    let c = { base with a = int_of_float (float base.a *. a) } in
    let dr = rect (x -. half) (y -. half) d d in
    fill ~continuous:true dr (corners dr (half, half, half, half) false)
      ~paint:Solid ~c1:c ~c2:c ~grad:(0., 0., 0., 0.)
      ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false
      ~alpha
  in
  box_ops ctx store id rs r alpha
  @ List.init spokes dot

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

(* A control carrying an [icon] prop and no children renders its
   glyph centered — the web stylesheet's .lui-icon[data-size="icon"]
   18px box inside the control's own rect. The [icon] prop gates the
   image lookup: [image_of] is the host's decode channel, not an
   "is there an icon" test, so a hook that answers images eagerly
   must not mint a glyph for every unlabeled control. *)
let control_icon_ops ctx store id r alpha =
  match pstr store id "icon" with
  | None -> []
  | Some _ -> (
  match ctx.hooks.image_of id with
  | None -> []
  | Some img -> (
    match Lui_store.child_ids store id with
    | _ :: _ -> []
    | [] ->
      let s = ctx.scale in
      let size = Float.min (18. *. s) (Float.min r.w r.h) in
      if size <= 0. then []
      else
        let dst =
          match Lui_store.kind store id with
          | "menu-item" ->
            (* leading icon slot: 8px in, vertically centered —
               .lui-menu-item's icon span *)
            rect (r.x +. (8. *. s))
              (r.y +. ((r.h -. size) /. 2.)) size size
          | _ ->
            rect (r.x +. ((r.w -. size) /. 2.))
              (r.y +. ((r.h -. size) /. 2.)) size size
        in
        [ Image
            { irect2 = dst; iradii = (0., 0., 0., 0.);
              icontinuous = false; iimage = img;
              isrc =
                { x = 0.; y = 0.; w = float img.iw; h = float img.ih };
              igrayscale = false; iopacity = alpha } ]))

(* Labeled chrome carrying an [icon] prop and no children paints the
   glyph in a side slot — on the web the icon is a flex child sitting
   before ("leading", default) or after ("trailing") the label, so the
   label's rect steps aside by the icon zone (glyph + 6px gap). The
   text engine still applies the kind's own pad inside the shrunken
   rect, keeping the same visual gap. Icon-only nodes keep the
   centered slot from [control_icon_ops]. Like there, the [icon]
   prop gates the image lookup. *)
let labeled_content_ops ctx store id r alpha ~fg ~placeholder_ok =
  match
    ( (match pstr store id "icon" with
       | Some _ -> ctx.hooks.image_of id
       | None -> None),
      Lui_store.child_ids store id )
  with
  | Some img0, [] -> (
    let has_label =
      (match pstr store id "text" with
       | Some t -> t <> ""
       | None -> false)
      ||
      match pstr store id "title" with
      | Some t -> t <> ""
      | None -> false
    in
    if not has_label then control_icon_ops ctx store id r alpha
    else
      let s = ctx.scale in
      let size = Float.min (16. *. s) (Float.max 0. (r.h -. 2.)) in
      if size <= 0. then []
      else
        let tp = text_placement_of store id in
        let pad = tp.tp_pad_x *. s in
        let gap = 6. *. s in
        let trailing = pstr store id "icon-placement" = Some "trailing" in
        let ix =
          if trailing then r.x +. r.w -. pad -. size else r.x +. pad
        in
        let dst = rect ix (r.y +. ((r.h -. size) /. 2.)) size size in
        let text_r =
          if trailing then
            { r with w = Float.max 0. ((ix -. r.x) +. pad -. gap) }
          else
            { r with
              x = r.x +. size +. gap;
              w = Float.max 0. (r.w -. size -. gap) }
        in
        (* rasterize at the slot size when the host can — [image_of]
           answers at the node's own rect, which squishes an icon
           glyph on a wide list/button row. The rect is logical px. *)
        let img =
          match
            ctx.hooks.image_in id (rect 0. 0. (size /. s) (size /. s))
          with
          | Some i -> i
          | None -> img0
        in
        Image
          { irect2 = dst; iradii = (0., 0., 0., 0.);
            icontinuous = false; iimage = img;
            isrc =
              { x = 0.; y = 0.; w = float img.iw; h = float img.ih };
            igrayscale = false; iopacity = alpha }
        :: text_ops ~fg ctx store id text_r alpha ~placeholder_ok)
  | _ -> text_ops ~fg ctx store id r alpha ~placeholder_ok

(* vertical scrollbar thumb inside a scroll container's clip. *)
let scrollbar_ops ctx store id r alpha =
  match ctx.hooks.scroll_of id with
  | Some sm when sm.sm_extent > 0. && sm.sm_extent < 1. ->
    let s = ctx.scale in
    let w = 6. *. s and m = 2.5 *. s in
    let th = Float.max (r.h *. sm.sm_extent) (16. *. s) in
    let ty = r.y +. ((r.h -. th) *. clamp01 sm.sm_offset) in
    let c =
      match pcolor ctx.hooks store id "border-color" with
      | Some c -> c
      | None -> col_scrollbar ctx
    in
    let tr = rect (r.x +. r.w -. w -. m) ty w th in
    [ fill ~continuous:true tr (corners tr (w /. 2., w /. 2., w /. 2., w /. 2.) false)
        ~paint:Solid ~c1:c ~c2:c ~grad:(0., 0., 0., 0.)
        ~border:(0., 0., 0., 0.) ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]
  | _ -> []

(* ---------- default chrome for interactive kinds ---------- *)

(* Whether the node already carries the prop that would own an aspect;
   defaults below only fill gaps explicit styling left. *)
let prop_set store id name = Lui_store.prop store id name <> None

(* The default focus ring: a 2px border drawn 1px outside the box,
   corners grown to match. Emitted over the control when focused and
   the view didn't supply its own focus-shadow. *)
let focus_ring_op ctx r radii alpha =
  let w = 2. *. ctx.scale and o = 1. *. ctx.scale in
  let rr =
    rect (r.x -. w -. o) (r.y -. w -. o)
      (r.w +. (2. *. (w +. o))) (r.h +. (2. *. (w +. o)))
  in
  fill ~continuous:true rr
    (corners rr (grow_radii radii (w +. o)) false)
    ~paint:Solid ~c1:(color 0 0 0 0) ~c2:(color 0 0 0 0)
    ~grad:(0., 0., 0., 0.) ~border:(w, w, w, w)
    ~bcolor:(col_focus ctx) ~dashed:false ~alpha

(* Kinds that show the default focus ring when focused. *)
let focusable = function
  | "button" | "toggle-button" | "toggle" | "menu-trigger" | "menu-item"
  | "bottom-tab" | "tab" | "list-item" | "link" | "select" | "combobox"
  | "text-field" | "secure-field" | "input" | "search-field" | "textarea"
  | "checkbox" | "radio" | "switch" | "slider" | "number-stepper" -> true
  | _ -> false

(* Contextual role a direct child takes inside a group container: the
   group contracts restyle unstyled children — segments in button and
   toggle groups, tab triggers in a tabs strip, melted field chrome in
   an input-group composer. Styled children keep the look the view
   asked for. *)
type child_role = Role_none | Role_segment | Role_tab | Role_composer

let child_role_of store id kind unstyled =
  if not unstyled then Role_none
  else
    match Lui_store.parent store id with
    | None -> Role_none
    | Some pid -> (
      match Lui_store.kind store pid with
      | "button-group" | "toggle-group" -> (
        match kind with
        | "button" | "toggle-button" -> Role_segment
        | _ -> Role_none)
      | "tabs" -> if kind = "button" then Role_tab else Role_none
      | "input-group" -> (
        match kind with
        | "text-field" | "secure-field" | "input" | "search-field"
        | "textarea" | "select" | "combobox" -> Role_composer
        | _ -> Role_none)
      | _ -> Role_none)

(* Default surface treatment for kinds that arrive unstyled. Every
   aspect (fill, border, radius, shadow) defers to an explicit prop;
   when nothing is set the token palette supplies the whole look. *)
let default_chrome ctx store id st kind r rs alpha =
  let s = ctx.scale in
  let bg_styled = rs.rs_background <> None in
  let border_styled =
    prop_set store id "border-width" || prop_set store id "border-color"
  in
  let rad = chrome_radii ctx store id in
  let bw1 = (1. *. s, 1. *. s, 1. *. s, 1. *. s) in
  let zb = (0., 0., 0., 0.) in
  let zc = color 0 0 0 0 in
  let face bg rad bw bcolor ~dashed =
    fill ~continuous:true r (corners r rad false) ~paint:Solid ~c1:bg
      ~c2:bg ~grad:(0., 0., 0., 0.) ~border:bw ~bcolor ~dashed ~alpha
  in
  let hairline x y w =
    fill (rect x y w (Float.max 1. (1. *. s))) (0., 0., 0., 0.)
      ~paint:Solid ~c1:(col_border ctx) ~c2:(col_border ctx)
      ~grad:(0., 0., 0., 0.) ~border:zb ~bcolor:zc ~dashed:false ~alpha
  in
  let child_role =
    child_role_of store id kind (not (bg_styled || border_styled))
  in
  let last_sibling =
    match Lui_store.parent store id with
    | Some pid -> (
      match Lui_store.last_child_id store pid with
      | Some last -> last = id
      | None -> true)
    | None -> true
  in
  (* ambient + key shadow pair under floating surfaces *)
  let shadow_pair rad specs =
    match rs.rs_shadow with
    | Some _ -> []
    | None ->
      List.map
        (fun (dx, dy, blur, a) ->
          shadow_op_of ctx r rad
            { dx; dy; blur; spread = 0.; scolor = color 0 0 0 a;
              inset = false }
            alpha)
        specs
  in
  match kind with
  | "button" | "toggle-button" when child_role = Role_segment ->
    (* One segment of a shared track: only state lifts a face —
       selection a pressed pill, hover a subtle wash. *)
    let i = 2. *. s in
    let ri = rect (r.x +. i) (r.y +. i) (Float.max 0. (r.w -. (2. *. i)))
        (Float.max 0. (r.h -. (2. *. i)))
    in
    let ri_r = corners ri (rad (4. *. s)) false in
    if st.selected || st.pressed then
      [ fill ~continuous:true ri ri_r ~paint:Solid
          ~c1:(col_surface_pressed ctx) ~c2:(col_surface_pressed ctx)
          ~grad:(0., 0., 0., 0.) ~border:zb ~bcolor:zc ~dashed:false ~alpha ]
    else if st.hovered then
      [ fill ~continuous:true ri ri_r ~paint:Solid
          ~c1:(col_surface_hover ctx) ~c2:(col_surface_hover ctx)
          ~grad:(0., 0., 0., 0.) ~border:zb ~bcolor:zc ~dashed:false ~alpha ]
    else []
  | "button" when child_role = Role_tab ->
    (* A trigger in the tab strip: no face, the accent underline marks
       choice. *)
    if st.selected then
      let h = 2. *. s and i = 6. *. s in
      [ fill
          (rect (r.x +. i) (r.y +. r.h -. h)
             (Float.max 0. (r.w -. (2. *. i))) h)
          (0., 0., 0., 0.) ~paint:Solid ~c1:(col_accent ctx)
          ~c2:(col_accent ctx) ~grad:(0., 0., 0., 0.) ~border:zb ~bcolor:zc
          ~dashed:false ~alpha ]
    else []
  | "text-field" | "secure-field" | "input" | "search-field"
  | "textarea" | "select" | "combobox"
    when child_role = Role_composer ->
    []
  | "button-group" | "toggle-group" | "input-group" ->
    (* The shared track every segment lives in. *)
    let rad = rad (6. *. s) in
    (if bg_styled then [] else [ face (col_surface ctx) rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else [ face zc rad bw1 (col_control_border ctx) ~dashed:false ])
  | "bottom-tabs" ->
    (if bg_styled then [] else [ face (col_surface ctx) (rad 0.) zb zc ~dashed:false ])
    @ [ hairline r.x r.y r.w ]
  | "toolbar" ->
    (if bg_styled then [] else [ face (col_surface ctx) (rad 0.) zb zc ~dashed:false ])
    @ [ hairline r.x (r.y +. r.h -. Float.max 1. (1. *. s)) r.w ]
  | "table-row" ->
    (if bg_styled then []
     else if st.selected then
       [ face (col_accent ctx) (rad 0.) zb zc ~dashed:false ]
     else if st.hovered then
       [ face (col_surface_hover ctx) (rad 0.) zb zc ~dashed:false ]
     else [])
    (* The final row has no divider. *)
    @ (if last_sibling then [] else [ hairline r.x (r.y +. r.h -. 1.) r.w ])
  | "button" | "toggle-button" | "toggle" | "menu-trigger"
  | "number-stepper" ->
    let rad = rad (6. *. s) in
    (* variant contract mirrors the web stylesheet (.lui-button
       [data-variant]) and apple's LUIButtonVisualPolicy: ghost/text and
       icon-only default buttons are borderless and transparent until
       interacted with; outline keeps only the border; filled variants
       paint a colored face. *)
    let variant = Option.value ~default:"default" (pstr store id "variant") in
    let icon_only =
      pstr store id "icon" <> None
      && pstr store id "text" = None
      && Lui_store.child_ids store id = []
    in
    let borderless =
      variant = "ghost" || variant = "text"
      || (variant = "default" && icon_only)
    in
    let base_face =
      match variant with
      | "primary" -> Some (col_accent ctx)
      | "destructive" -> Some (col_danger ctx)
      | "secondary" -> Some (col_secondary ctx)
      | _ when borderless -> None
      | _ -> Some (col_surface ctx)
    in
    let face_ops =
      if bg_styled then []
      else
        match base_face with
        | Some base ->
          let face_c =
            if st.disabled then base
            else if st.pressed || (st.selected && kind <> "button") then (
              match variant with
              | "primary" -> col_accent_hover ctx
              | "secondary" | "destructive" -> base
              | _ -> col_surface_pressed ctx)
            else if st.hovered then (
              match variant with
              | "primary" -> col_accent_hover ctx
              | "secondary" -> col_surface_hover ctx
              | _ -> base)
            else base
          in
          [ face face_c rad zb zc ~dashed:false ]
        | None ->
          if st.disabled then []
          else if st.pressed || st.selected then
            [ face (col_surface_pressed ctx) rad zb zc ~dashed:false ]
          else if st.hovered then
            [ face (col_surface_hover ctx) rad zb zc ~dashed:false ]
          else []
    in
    face_ops
    @ (if border_styled || bg_styled || borderless
          || List.mem variant [ "primary"; "destructive"; "secondary" ]
       then []
       else [ face zc rad bw1 (col_control_border ctx) ~dashed:false ])
    @ control_icon_ops ctx store id r alpha
  | "text-field" | "secure-field" | "input" | "search-field" | "textarea"
  | "select" | "combobox" ->
    let rad = rad (6. *. s) in
    (if bg_styled then []
     else [ face (col_surface ctx) rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else
         [ let bc =
             if st.focused then col_accent ctx else col_control_border ctx
           in
           face zc rad bw1 bc ~dashed:false ])
  | "menu-item" ->
    (if bg_styled || (not st.hovered && not st.focused) then []
     else [ face (col_accent ctx) (rad (6. *. s)) zb zc ~dashed:false ])
    @ control_icon_ops ctx store id r alpha
  | "list-item" ->
    if bg_styled then []
    else if st.selected then
      [ face (col_accent ctx) (rad (6. *. s)) zb zc ~dashed:false ]
    else if st.hovered then
      [ face (col_surface_hover ctx) (rad (6. *. s)) zb zc ~dashed:false ]
    else []
  | "bottom-tab" | "tab" ->
    if st.selected then
      let h = 2. *. s and i = 6. *. s in
      [ fill
          (rect (r.x +. i) (r.y +. r.h -. h)
             (Float.max 0. (r.w -. (2. *. i))) h)
          (0., 0., 0., 0.) ~paint:Solid ~c1:(col_accent ctx)
          ~c2:(col_accent ctx) ~grad:(0., 0., 0., 0.) ~border:zb ~bcolor:zc
          ~dashed:false ~alpha ]
    else []
  | "swipe-action" ->
    if bg_styled then [] else [ face (col_danger ctx) (rad 0.) zb zc ~dashed:false ]
  | "file-picker" ->
    let rad = rad (6. *. s) in
    (if bg_styled then [] else [ face (col_surface ctx) rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else [ face zc rad bw1 (col_control_border ctx) ~dashed:true ])
  | "popover" | "dropdown-menu" | "menu" | "context-menu" ->
    (* Web .ui__popover-content: rounded-md 6px + shadow-md. *)
    let rad = rad (6. *. s) in
    shadow_pair rad [ (0., 4., 6., 26); (0., 2., 4., 26) ]
    @ (if bg_styled then [] else [ face (col_popover ctx) rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else [ face zc rad bw1 (col_border ctx) ~dashed:false ])
  | "dialog" | "sheet" | "drawer" | "modal" ->
    (* Web .lui-dialog card: rounded-lg 8px + shadow-lg. A sheet pins
       the right edge: only its left corners round (radius-xl 12px). *)
    let rad =
      if kind = "sheet" && not (prop_set store id "corner-radius")
      then (12. *. s, 0., 0., 12. *. s)
      else rad (8. *. s)
    in
    (* A modal surface dims the content it covers. An in-flow drawer
       pane (carries [selected]) is not modal and gets no scrim. *)
    let scrim =
      if kind = "drawer" && Lui_store.prop store id "selected" <> None
      then []
      else
        let scrim_c = theme ctx "scrim" in
        [ fill (rect ctx.viewport.x ctx.viewport.y ctx.viewport.w
                ctx.viewport.h)
            (0., 0., 0., 0.) ~paint:Solid ~c1:scrim_c ~c2:scrim_c
            ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
            ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha:1. ]
    in
    scrim
    @ (* Platform title chrome paints inside the top zone the layout
       reserved — title_pad gives a 26pt title lane and a 15pt
       description lane (+12pt grabber lane on sheets), stacked on the
       view's top padding. The ink rects hand the whole width to the
       text engine so its placement table applies the same horizontal
       padding the content uses — re-insetting here would double it. *)
    let pad_of n = Option.value ~default:0. (pnum store id n) *. s in
    let py = Float.max (pad_of "padding-vertical") (pad_of "padding") in
    let grabber = if kind = "sheet" then 12. *. s else 0. in
    let title_y = r.y +. py +. grabber in
    (* Surface first, chrome ink on top — the fill must not cover the
       title block. *)
    shadow_pair rad [ (0., 10., 15., 26); (0., 4., 6., 26) ]
    @ (if bg_styled then [] else [ face (col_popover ctx) rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else [ face zc rad bw1 (col_border ctx) ~dashed:false ])
    @ (match kind with
       (* The grabber handle only exists on phone-form-factor sheets;
          a right-edge desktop sheet paints none. *)
       | _ -> [])
    @ (* The chrome zone clips its own ink: a wrapped description must
         not spill into the children below it. *)
    (let zone =
       rect r.x (r.y +. py) r.w ((grabber +. 41.) *. s)
     in
     Push_clip
       { crect = zone; cradii = (0., 0., 0., 0.); ccontinuous = false }
     :: (match pstr store id "text" with
        | Some t when t <> "" ->
          ctx.hooks.text_ops id
            (rect r.x title_y r.w (26. *. s))
            (text_fg ctx store id) t
        | _ -> [])
     @ (match pstr store id "description" with
        | Some d when d <> "" ->
          ctx.hooks.text_ops id
            (rect r.x (title_y +. 26. *. s) r.w (15. *. s))
            (col_muted_fg ctx) d
        | _ -> [])
     @ [ Pop_clip ])
  | "toast" ->
    (* Web .lui-toast: card surface + border + radius-lg + shadow-lg. *)
    let rad = rad (8. *. s) in
    shadow_pair rad [ (0., 10., 15., 26); (0., 4., 6., 26) ]
    @ (if bg_styled then [] else [ face (theme ctx "card") rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else [ face zc rad bw1 (col_border ctx) ~dashed:false ])
  | "tooltip" | "alert" | "bubble" ->
    let rad = rad (5. *. s) in
    shadow_pair rad [ (0., 1., 2., 26); (0., 2., 8., 51) ]
    @ (if bg_styled then [] else [ face (col_inverse ctx) rad zb zc ~dashed:false ])
  | "card" ->
    let rad = rad (8. *. s) in
    shadow_pair rad [ (0., 1., 2., 20); (0., 4., 10., 15) ]
    @ (if bg_styled then []
       else [ face (theme ctx "card") rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else [ face zc rad bw1 (col_border ctx) ~dashed:false ])
  | "kbd" ->
    (* Key hint chip: muted fill, hairline frame, compact radius. *)
    let rad = rad (4. *. s) in
    (if bg_styled then [] else [ face (col_muted ctx) rad zb zc ~dashed:false ])
    @ (if border_styled || bg_styled then []
       else [ face zc rad bw1 (col_border ctx) ~dashed:false ])
  | _ -> []

(* Foreground color per kind and state when no foreground prop is set:
   selection and inverse surfaces flip the ink. Ink only flips when our
   chrome also supplies the accent/danger fill — a view-set background
   keeps the view's ink. *)
let default_text_fg ctx store id kind st rs =
  let bg_styled = rs.rs_background <> None in
  match pcolor ctx.hooks store id "foreground" with
  | Some c -> c
  | None -> (
    match kind with
    | "link" -> col_accent ctx
    | "kbd" -> col_muted_fg ctx
    | "menu-item" when st.hovered || st.focused ->
      if bg_styled then text_fg ctx store id else col_accent_text ctx
    | "list-item" | "table-row" when st.selected ->
      if bg_styled then text_fg ctx store id else col_accent_text ctx
    | "tab" ->
      (* Top-strip tabs mark choice with darker, heavier ink + the
         accent underline; the mobile tab bar keeps accent ink. *)
      if st.selected then text_fg ctx store id else col_muted_fg ctx
    | "bottom-tab" ->
      if st.selected then col_accent ctx else col_muted_fg ctx
    | "button"
      when child_role_of store id kind
             (not
                (bg_styled
                || prop_set store id "border-width"
                || prop_set store id "border-color"))
           = Role_tab ->
      (* Tab triggers mute until selected. *)
      if st.selected then text_fg ctx store id else col_muted_fg ctx
    | "swipe-action" ->
      if bg_styled then text_fg ctx store id else col_accent_text ctx
    | "tooltip" | "alert" | "bubble" ->
      if bg_styled then text_fg ctx store id else col_inverse_fg ctx
    | "text" | "label" | "heading" | "paragraph" -> (
      (* Ink children painted on an inverse surface take on-surface
         ink (e.g. a toast's label child) unless the view styled the
         surface's own background. *)
      match Lui_store.parent store id with
      | Some p -> (
        match Lui_store.kind store p with
        | "tooltip" | "alert" | "bubble" ->
          if bg_styled || prop_set store p "background" then
            text_fg ctx store id
          else col_inverse_fg ctx
        | _ -> text_fg ctx store id)
      | None -> text_fg ctx store id)
    | "list-section-header" | "list-section-footer" -> col_muted_fg ctx
    | _ -> text_fg ctx store id)

(* Disabled controls dim unless the view already drove an opacity. *)
let disabled_alpha store id st =
  if
    st.disabled
    && not (prop_set store id "disabled-opacity" || prop_set store id "opacity")
  then 0.55
  else 1.

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
  || (* A split pane always clips: a collapsed track's content must not
        leak into the sibling pane (web resizer panes clip likewise). *)
     (match Lui_store.parent store id with
      | Some pid -> Lui_store.kind store pid = "split"
      | None -> false)
  || match pstr store id "overflow" with
     | Some ("hidden" | "clip" | "auto" | "scroll") -> true
     | _ -> false

(* Popup surfaces the layout engine positions itself (mirror of
   Lui_layout.popup_kind) — their [x]/[y] props are anchor inputs,
   not absolute coordinates. *)
let popup_kind = function
  | "dialog" | "drawer" | "sheet" | "tooltip" | "toast"
  | "dropdown-menu" | "context-menu" | "popover" | "alert" -> true
  | _ -> false

(* The node's display box: layout result → popup x/y override →
   position/inset resolution → layout rect. Position edges resolve
   lazily: the common case — no [position] prop — never pays the four
   inset lookups, which matters because the viewport cull runs this on
   every visited node, visible or not.

   Standalone on (scale, viewport) rather than the full paint ctx so
   the hit-test mirror resolves placements identically — hit-testing
   shares this, and the two must never disagree on where a node sits. *)
let resolve_rect ~scale ~viewport store id kind p parent_r =
  match p.p_override with
  | Some r -> r
  | None -> (
    let s = scale in
    let side n = match pnum store id n with
      | Some v -> Some v
      | None -> pnum store id "inset"
    in
    match pstr store id "position" with
    | Some ("absolute" | "fixed") as pos -> (
      let it, ir, ib, il =
        (side "inset-top", side "inset-right", side "inset-bottom", side "inset-left")
      in
      let cb = if pos = Some "fixed" then viewport else parent_r in
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
    | Some "relative" -> (
      let it, ir, ib, il =
        (side "inset-top", side "inset-right", side "inset-bottom", side "inset-left")
      in
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
    | _ ->
      if popup_kind kind then
        (* Popup kinds carry [x]/[y] as an anchor point the layout
           engine already resolved into the node's rect — re-applying
           them here would undo the anchor/alignment math. *)
        p.p_rect
      else
        (* Popup coordinates are absolute placements on popup kinds. *)
        match (pnum store id "x", pnum store id "y") with
        | Some x, Some y -> { p.p_rect with x = x *. s; y = y *. s }
        | Some x, None -> { p.p_rect with x = x *. s }
        | None, Some y -> { p.p_rect with y = y *. s }
        | None, None -> p.p_rect)

(* The ctx-taking form [paint_node_body] calls; the labeled-args one
   above is the shared entry point. *)
let resolve_in ctx = resolve_rect ~scale:ctx.scale ~viewport:ctx.viewport

let zindex store id =
  match Lui_store.prop store id "z-index" with
  | Some (Lui_protocol.IntValue i) -> i
  | Some (Lui_protocol.FloatValue f) -> int_of_float f
  | Some (Lui_protocol.StringValue s) -> (
    match int_of_string_opt (String.trim s) with Some i -> i | None -> 0)
  | _ -> 0

(* Siblings paint in z-index order, DOM order breaking ties. The scan
   exits on the first nonzero z-index so a lone stacked sibling is the
   only reason to sort — most lists have none and pay one prop lookup
   per child, no fingerprint list, no sort. *)
let z_ordered store kids =
  if List.exists (fun c -> zindex store (Lui_store.node_id c) <> 0) kids
  then
    List.stable_sort
      (fun a b ->
        compare
          (zindex store (Lui_store.node_id a))
          (zindex store (Lui_store.node_id b)))
      kids
  else kids

let ordered_children store id = z_ordered store (Lui_store.children store id)

(* The children paint walks: a mounted window slice for virtualized
   containers, the full ordered list otherwise. *)
let paint_children ctx store id =
  match ctx.hooks.mounted_children id with
  | Some ids ->
    z_ordered store (List.filter_map (Lui_store.find_opt store) ids)
  | None -> ordered_children store id

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
let rec paint_own ctx store id st kind r rs alpha =
  let fg = default_text_fg ctx store id kind st rs in
  let own =
    match kind with
    | "spacer" -> []
    | "divider" -> divider_ops ctx store id rs r alpha
    | "progress" -> progress_ops ctx store id rs r alpha
    | "checkbox" -> checkbox_ops ctx store id st rs r alpha
    | "radio" -> radio_ops ctx store id st rs r alpha
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
        match pstr store id "text" with
        | Some s when s <> "" ->
          (* hue from the label so every name gets a stable tint *)
          let c = hsl (hash_hue s) 0.45 0.55 in
          [ fill ~continuous:true b (corners b rad false) ~paint:Solid ~c1:c ~c2:c
              ~grad:(0., 0., 0., 0.) ~border:(0., 0., 0., 0.)
              ~bcolor:(color 0 0 0 0) ~dashed:false ~alpha ]
          @ scale_ops alpha (ctx.hooks.text_ops id r (color 255 255 255 255) s)
        | _ -> box_ops ctx store id rs r alpha))
    | "text" | "label" | "heading" | "paragraph" | "br" | "link" | "kbd" ->
      box_ops ctx store id rs r alpha
      @ labeled_content_ops ctx store id r alpha ~fg ~placeholder_ok:false
    | "text-field" | "secure-field" | "input" | "search-field" | "textarea"
    | "select" | "combobox" ->
      box_ops ctx store id rs r alpha
      @ text_ops ~fg ctx store id r alpha ~placeholder_ok:true
    | "button" | "toggle-button" | "toggle" | "menu-item" | "menu-trigger"
    | "bottom-tab" | "list-item" | "swipe-action" | "file-picker" | "step"
    | "list-section-header" | "list-section-footer" | "tab" | "table-cell" ->
      (* labeled chrome: box decoration plus the label through the text
         engine; an icon prop takes a side slot *)
      box_ops ctx store id rs r alpha
      @ labeled_content_ops ctx store id r alpha ~fg ~placeholder_ok:false
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
  in
  (* token chrome first (shadow + face + border underneath), then the
     node's own ops — prop fills sit on top of the defaults and the
     label is never covered by a chrome face. *)
  default_chrome ctx store id st kind r rs alpha
  @ own
  @
  if
    st.focused && focusable kind
    && not (prop_set store id "focus-shadow")
  then [ focus_ring_op ctx r (radii_of ctx store id) alpha ]
  else []

(* A popup node: defer to the overlay pass so mid-tree popups paint
   above later siblings; everything else paints inline. [kind] arrives
   from the caller — the child loop already holds the node record, so
   the hot path never pays a second store lookup for it. *)
and paint_node ctx store scene id kind parent_r alpha =
  if popup_kind kind && not (unboxed store id) then
    Queue.add
      (fun () -> paint_node_body ctx store scene id kind parent_r alpha)
      ctx.deferred
  else paint_node_body ctx store scene id kind parent_r alpha

(* A visible node: resolve placement, cull against the viewport, then
   state/style/chrome/children. Geometry comes first deliberately —
   a culled node never pays for state resolution, so scrolling a huge
   tree costs one layout-hook hit plus a rect check per offscreen
   node. *)
and paint_node_body ctx store scene id kind parent_r alpha =
  if node_shown store id then (
    let contents = unboxed store id in
    let p = ctx.hooks.layout id in
    let r = resolve_in ctx store id kind p parent_r in
    (* Viewport cull: a node whose box misses the frame produces no
       chrome and no descendants. display:contents has no box of its
       own so it always walks children; zero-size nodes still walk so
       absolute/fixed descendants (resolved against parent_r) are not
       lost. Full damage/incremental paint is intentionally unfinished. *)
    let misses_viewport =
      (not contents)
      && (not (rect_empty r))
      && rect_empty (rect_intersect r ctx.viewport)
    in
    if misses_viewport then ()
    else begin
      let st = effective_state ctx.hooks store id in
      let rs = resolve_style store id st in
      (* display:contents generates no box, so its opacity and chrome
         do not apply — children paint with the parent's alpha and
         clip. *)
      let alpha =
        if contents then alpha
        else alpha *. rs.rs_opacity *. disabled_alpha store id st
      in
      (* An alpha-0 subtree emits no ops at all: the raster treats an
         op opacity of 0 as "unset" (opaque), so invisible nodes must
         be culled here rather than painted at opacity 0. *)
      if alpha <= 0. then ()
      else begin
        let clip =
          (not contents) && clips kind store id
          && ((not (rect_empty r))
              || (* An empty split pane still clips: its children's own
                    minimum sizes would otherwise paint through it. *)
                 (match Lui_store.parent store id with
                  | Some pid -> Lui_store.kind store pid = "split"
                  | None -> false))
        in
        if clip then
          emit1 scene
            (Push_clip
               { crect = r;
                 cradii = corners r (radii_of ctx store id) false;
                 ccontinuous = false });
        if not contents then
          emit scene (paint_own ctx store id st kind r rs alpha);
        (* Children of a display:contents node keep the parent's
           containing block — the node itself generates no box to
           anchor to. *)
        let child_parent = if contents then parent_r else r in
        List.iter
          (fun c ->
            paint_node ctx store scene (Lui_store.node_id c)
              (Lui_store.node_kind c) child_parent alpha)
          (paint_children ctx store id);
        if scrollable kind store id && not contents then
          emit scene (scrollbar_ops ctx store id r alpha);
        if clip then emit1 scene Pop_clip
      end
    end)

(* Full repaint: reset the scene and repaint the whole forest. *)
let paint hooks store scene ~width ~height ~scale ~clear =
  Lui_scene.reset scene ~width ~height ~scale ~clear;
  let ctx =
    { hooks; scale;
      viewport = rect 0. 0. (float width) (float height);
      deferred = Queue.create () }
  in
  List.iter
    (fun id ->
      paint_node ctx store scene id (Lui_store.kind store id)
        ctx.viewport 1.)
    (Lui_store.root_ids store);
  (* Nested popups (submenus) enqueue during this drain — they paint
     after their parent, preserving preorder among popups. *)
  while not (Queue.is_empty ctx.deferred) do
    (Queue.pop ctx.deferred) ()
  done;
  scene.ops <- List.rev scene.ops;
  scene.glyphs <- List.rev scene.glyphs;
  scene.wide <- List.rev scene.wide
