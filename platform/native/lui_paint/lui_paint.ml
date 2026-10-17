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
    ("inert", Host); (* input and accessibility; paint stays retained *)
    ("gap", Layout);
    ("main", Layout);
    ("cross", Layout);
    ("grow", Layout);
    ("columns", Layout);
    ("padding", Layout);
    ("padding-horizontal", Layout);
    ("padding-vertical", Layout);
    ("padding-top", Layout);
    ("padding-right", Layout);
    ("padding-bottom", Layout);
    ("padding-left", Layout);
    ("background", Painted);
    ("foreground", Painted);
    ("border-color", Painted); (* CSS shorthand, 1–4 colors *)
    ("border-width", Painted); (* CSS shorthand, 1–4 lengths; also insets layout *)
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
    ("selection-placement", Layout);
    ("selected", Painted); (* folds into state.selected *)
    ("autofocus", Host);
    ("submit-on-enter", Host);
    ("long-press-enabled", Host);
    ("change-enabled", Host);
    ("toggle-enabled", Host);
    ("press-enabled", Host);
    ("submit-enabled", Host);
    ("navigate-enabled", Host);
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
    ("role", Layout);
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
  hidden : int -> bool;              (* host-owned subtree visibility *)
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
    hidden = (fun _ -> false);
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

(* Choice chrome stays beside labels and follows alignment without a label. *)
let leading_box ctx store id r side_logical =
  let side = Float.min (side_logical *. ctx.scale) (Float.min r.w r.h) in
  let has_label =
    match pstr store id "text" with
    | Some text when text <> "" -> true
    | _ -> false
  in
  let x =
    if has_label then r.x
    else
      match pstr store id "main" with
      | Some "center" -> r.x +. ((r.w -. side) /. 2.)
      | Some "end" -> r.x +. r.w -. side
      | _ -> r.x
  in
  rect x (r.y +. ((r.h -. side) /. 2.)) side side

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
  tp_pad_left : float; (* logical px insets *)
  tp_pad_right : float;
  tp_pad_top : float;
  tp_pad_bottom : float;
  tp_top : bool;    (* anchor first line at pad-y instead of centering *)
}

(* Where a kind's own ink sits inside its chrome: labeled controls
   center, fields and rows pad their ink, plain text flows from the
   edge. The text-alignment and padding props win over the table.
   Every text engine feeds this into its pen math so all backends
   place glyphs identically. *)
let text_placement ~layout_padding store id =
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
    | "menu-item" -> (Ta_start, 8., 6., false)
    | "table-cell" | "table-row" -> (Ta_start, 10., 6., false)
    | "step" -> (Ta_center, 8., 4., false)
    | "list-item" -> (Ta_start, 12., 6., false)
    | "text-field" | "secure-field" | "input" | "search-field" -> (Ta_start, 10., 6., false)
    | "select" | "combobox" -> (Ta_start, 12., 8., false)
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
  let leading, trailing =
    if Lui_store.kind store id <> "menu-item" then (0., 0.)
    else
      let zone = 16. +. Option.value ~default:8. (pnum store id "gap") in
      let icon = if pstr store id "icon" = None then 0. else zone in
      if Lui_store.prop store id "selected" = None then (icon, 0.)
      else if pstr store id "selection-placement" = Some "leading" then
        (icon +. zone, 0.)
      else (icon, zone)
  in
  let inset side axis default =
    if not layout_padding
       && (Lui_store.prop store id side <> None
          || Lui_store.prop store id axis <> None
          || Lui_store.prop store id "padding" <> None) then 0.
    else Option.value ~default (pnum store id side)
  in
  { tp_align = align;
    tp_pad_left = inset "padding-left" "padding-horizontal" pad_x +. leading;
    tp_pad_right = inset "padding-right" "padding-horizontal" pad_x +. trailing;
    tp_pad_top = inset "padding-top" "padding-vertical" pad_y;
    tp_pad_bottom = inset "padding-bottom" "padding-vertical" pad_y;
    tp_top = top }

let text_placement_of store id = text_placement ~layout_padding:true store id

(* Flex already adds explicit padding around its measured content box. Only
   implicit control chrome and built-in slots belong in the text measure. *)
let text_measure_placement_of store id = text_placement ~layout_padding:false store id

(* ---------- secure-field masking ---------- *)

(* The glyph a secure field substitutes for every grapheme of its
   text — U+2022 BULLET, the platform password-field convention. *)
let mask_char = "\xe2\x80\xa2"
let mask_char_len = String.length mask_char

(* A compact UAX #29 grapheme-cluster segmenter, engine-free: the
   paint pass must count graphemes to mask a secure field without
   depending on any platform text engine, and the window engines map
   masked caret offsets back through the same boundaries. Rules
   covered: CRxLF, hard breaks around controls, Hangul L/V/T chains,
   Extend/ZWJ joins, SpacingMark and Prepend attachments, emoji ZWJ
   sequences and regional-indicator pairs. A codepoint the tables
   miss lands on [G_other] and starts its own cluster — for masking
   that only means one bullet too many, never a plaintext leak. *)
type gcb =
  | G_other | G_cr | G_lf | G_control | G_extend | G_zwj | G_ri
  | G_prepend | G_spacing | G_extpict | G_l | G_v | G_t | G_lv
  | G_lvt

(* Sorted inclusive codepoint ranges, binary-searched. *)
let in_ranges tbl cp =
  let rec go lo hi =
    if lo > hi then false
    else
      let mid = (lo + hi) / 2 in
      let a, b = tbl.(mid) in
      if cp < a then go lo (mid - 1)
      else if cp > b then go (mid + 1) hi
      else true
  in
  go 0 (Array.length tbl - 1)

let gcb_extend =
  [| (0x0300, 0x036F); (0x0483, 0x0489); (0x0591, 0x05BD); (0x05BF, 0x05BF);
     (0x05C1, 0x05C2); (0x05C4, 0x05C5); (0x05C7, 0x05C7); (0x0610, 0x061A);
     (0x064B, 0x065F); (0x0670, 0x0670); (0x06D6, 0x06DC); (0x06DF, 0x06E4);
     (0x06E7, 0x06E8); (0x06EA, 0x06ED); (0x0711, 0x0711); (0x0730, 0x074A);
     (0x07A6, 0x07B0); (0x07EB, 0x07F3); (0x07FD, 0x07FD); (0x0816, 0x0819);
     (0x081B, 0x0823); (0x0825, 0x0827); (0x0829, 0x082D); (0x0859, 0x085B);
     (0x0898, 0x089F); (0x08CA, 0x0902); (0x093A, 0x093A); (0x093C, 0x093C);
     (0x0941, 0x0948); (0x094D, 0x094D); (0x0951, 0x0957); (0x0962, 0x0963);
     (0x0981, 0x0981); (0x09BC, 0x09BC); (0x09C1, 0x09C4); (0x09CD, 0x09CD);
     (0x09E2, 0x09E3); (0x09FE, 0x09FE); (0x0A01, 0x0A02); (0x0A3C, 0x0A3C);
     (0x0A41, 0x0A42); (0x0A47, 0x0A48); (0x0A4B, 0x0A4D); (0x0A51, 0x0A51);
     (0x0A70, 0x0A71); (0x0A75, 0x0A75); (0x0A81, 0x0A82); (0x0ABC, 0x0ABC);
     (0x0AC1, 0x0AC5); (0x0AC7, 0x0AC8); (0x0ACD, 0x0ACD); (0x0AE2, 0x0AE3);
     (0x0AFA, 0x0AFF); (0x0B01, 0x0B01); (0x0B3C, 0x0B3C); (0x0B3F, 0x0B3F);
     (0x0B41, 0x0B44); (0x0B4D, 0x0B4D); (0x0B55, 0x0B56); (0x0B62, 0x0B63);
     (0x0B82, 0x0B82); (0x0BC0, 0x0BC0); (0x0BCD, 0x0BCD); (0x0C00, 0x0C00);
     (0x0C04, 0x0C04); (0x0C3C, 0x0C3C); (0x0C3E, 0x0C40); (0x0C46, 0x0C48);
     (0x0C4A, 0x0C4D); (0x0C55, 0x0C56); (0x0C62, 0x0C63); (0x0C81, 0x0C81);
     (0x0CBC, 0x0CBC); (0x0CBF, 0x0CBF); (0x0CC6, 0x0CC6); (0x0CCC, 0x0CCD);
     (0x0CE2, 0x0CE3); (0x0D00, 0x0D01); (0x0D3B, 0x0D3C); (0x0D41, 0x0D44);
     (0x0D4D, 0x0D4D); (0x0D62, 0x0D63); (0x0D81, 0x0D81); (0x0DCA, 0x0DCA);
     (0x0DD2, 0x0DD4); (0x0DD6, 0x0DD6); (0x0E31, 0x0E31); (0x0E34, 0x0E3A);
     (0x0E47, 0x0E4E); (0x0EB1, 0x0EB1); (0x0EB4, 0x0EBC); (0x0EC8, 0x0ECE);
     (0x0F18, 0x0F19); (0x0F35, 0x0F35); (0x0F37, 0x0F37); (0x0F39, 0x0F39);
     (0x0F71, 0x0F7E); (0x0F80, 0x0F84); (0x0F86, 0x0F87); (0x0F8D, 0x0F97);
     (0x0F99, 0x0FBC); (0x0FC6, 0x0FC6); (0x102D, 0x1030); (0x1032, 0x1037);
     (0x1039, 0x103A); (0x103D, 0x103E); (0x1058, 0x1059); (0x105E, 0x1060);
     (0x1071, 0x1074); (0x1082, 0x1082); (0x1085, 0x1086); (0x108D, 0x108D);
     (0x109D, 0x109D); (0x135D, 0x135F); (0x1712, 0x1714); (0x1732, 0x1734);
     (0x1752, 0x1753); (0x1772, 0x1773); (0x17B4, 0x17B5); (0x17B7, 0x17BD);
     (0x17C6, 0x17C6); (0x17C9, 0x17D3); (0x17DD, 0x17DD); (0x180B, 0x180D);
     (0x180F, 0x180F); (0x18A9, 0x18A9); (0x1920, 0x1922); (0x1927, 0x1928);
     (0x1932, 0x1932); (0x1939, 0x193B); (0x1A17, 0x1A18); (0x1A1B, 0x1A1B);
     (0x1A56, 0x1A56); (0x1A58, 0x1A5E); (0x1A60, 0x1A60); (0x1A62, 0x1A62);
     (0x1A65, 0x1A6C); (0x1A73, 0x1A7C); (0x1A7F, 0x1A7F); (0x1AB0, 0x1ACE);
     (0x1B00, 0x1B03); (0x1B34, 0x1B34); (0x1B36, 0x1B3A); (0x1B3C, 0x1B3C);
     (0x1B42, 0x1B42); (0x1B6B, 0x1B73); (0x1B80, 0x1B81); (0x1BA2, 0x1BA5);
     (0x1BA8, 0x1BA9); (0x1BAB, 0x1BAD); (0x1BE6, 0x1BE6); (0x1BE8, 0x1BE9);
     (0x1BED, 0x1BED); (0x1BEF, 0x1BF1); (0x1C2C, 0x1C33); (0x1C36, 0x1C37);
     (0x1CD0, 0x1CD2); (0x1CD4, 0x1CE0); (0x1CE2, 0x1CE8); (0x1CED, 0x1CED);
     (0x1CF4, 0x1CF4); (0x1CF7, 0x1CF9); (0x1DC0, 0x1DF9); (0x1DFB, 0x1DFF);
     (0x20D0, 0x20F0); (0x2CEF, 0x2CF1); (0x2D7F, 0x2D7F); (0x2DE0, 0x2DFF);
     (0x302A, 0x302D); (0x3099, 0x309A); (0xA66F, 0xA672); (0xA674, 0xA67D);
     (0xA69E, 0xA69F); (0xA6F0, 0xA6F1); (0xA802, 0xA802); (0xA806, 0xA806);
     (0xA80B, 0xA80B); (0xA825, 0xA826); (0xA82C, 0xA82C); (0xA8C4, 0xA8C5);
     (0xA8E0, 0xA8F1); (0xA8FF, 0xA8FF); (0xA926, 0xA92D); (0xA947, 0xA951);
     (0xA980, 0xA982); (0xA9B3, 0xA9B3); (0xA9B6, 0xA9B9); (0xA9BC, 0xA9BD);
     (0xA9E5, 0xA9E5); (0xAA29, 0xAA2E); (0xAA31, 0xAA32); (0xAA35, 0xAA36);
     (0xAA43, 0xAA43); (0xAA4C, 0xAA4C); (0xAA7C, 0xAA7C); (0xAAB0, 0xAAB0);
     (0xAAB2, 0xAAB4); (0xAAB7, 0xAAB8); (0xAABE, 0xAABF); (0xAAC1, 0xAAC1);
     (0xAAEC, 0xAAED); (0xAAF6, 0xAAF6); (0xABE5, 0xABE5); (0xABE8, 0xABE8);
     (0xABED, 0xABED); (0xFB1E, 0xFB1E); (0xFE00, 0xFE0F); (0xFE20, 0xFE2F);
     (0x101FD, 0x101FD); (0x102E0, 0x102E0); (0x10376, 0x1037A);
     (0x10A01, 0x10A03); (0x10A05, 0x10A06); (0x10A0C, 0x10A0F);
     (0x10A38, 0x10A3A); (0x10A3F, 0x10A3F); (0x10AE5, 0x10AE6);
     (0x10D24, 0x10D27); (0x10EAB, 0x10EAC); (0x10F46, 0x10F50);
     (0x10F82, 0x10F82); (0x11001, 0x11001); (0x11038, 0x11046);
     (0x11070, 0x11070); (0x11073, 0x11074); (0x1107F, 0x1107F);
     (0x110B3, 0x110B6); (0x110B9, 0x110BA); (0x11100, 0x11102);
     (0x11127, 0x1112B); (0x1112D, 0x11134); (0x11173, 0x11173);
     (0x11180, 0x11181); (0x111B6, 0x111BE); (0x111C9, 0x111CC);
     (0x111CF, 0x111CF); (0x1122F, 0x11231); (0x11234, 0x11234);
     (0x11236, 0x11237); (0x1123E, 0x1123E); (0x112DF, 0x112DF);
     (0x1133B, 0x1133C); (0x11340, 0x11340); (0x11366, 0x1136C);
     (0x11370, 0x11374); (0x11438, 0x1143F); (0x11442, 0x11444);
     (0x11446, 0x11446); (0x1145E, 0x1145E); (0x114B3, 0x114B8);
     (0x114BA, 0x114BA); (0x114BF, 0x114C0); (0x114C2, 0x114C3);
     (0x115B2, 0x115B5); (0x115BC, 0x115BD); (0x115BF, 0x115C0);
     (0x115DC, 0x115DD); (0x11633, 0x1163A); (0x1163D, 0x1163D);
     (0x1163F, 0x11640); (0x116AB, 0x116AB); (0x116AD, 0x116AD);
     (0x116B0, 0x116B5); (0x116B7, 0x116B7); (0x1171D, 0x1171F);
     (0x11722, 0x11725); (0x11727, 0x1172B); (0x1182F, 0x11837);
     (0x11839, 0x1183A); (0x1193B, 0x1193C); (0x1193E, 0x1193E);
     (0x11943, 0x11943); (0x119D4, 0x119D7); (0x119DA, 0x119DB);
     (0x119E0, 0x119E0); (0x11A01, 0x11A0A); (0x11A33, 0x11A38);
     (0x11A3B, 0x11A3E); (0x11A47, 0x11A47); (0x11A51, 0x11A56);
     (0x11A59, 0x11A5B); (0x11A8A, 0x11A96); (0x11A98, 0x11A99);
     (0x11C30, 0x11C36); (0x11C38, 0x11C3D); (0x11C3F, 0x11C3F);
     (0x11C92, 0x11CA7); (0x11CAA, 0x11CB0); (0x11CB2, 0x11CB3);
     (0x11CB5, 0x11CB6); (0x11D31, 0x11D36); (0x11D3A, 0x11D3A);
     (0x11D3C, 0x11D3D); (0x11D3F, 0x11D45); (0x11D47, 0x11D47);
     (0x11D90, 0x11D91); (0x11D95, 0x11D95); (0x11D97, 0x11D97);
     (0x11EF3, 0x11EF4); (0x16AF0, 0x16AF4); (0x16B30, 0x16B36);
     (0x16F4F, 0x16F4F); (0x16F8F, 0x16F92); (0x1BC9D, 0x1BC9E);
     (0x1D167, 0x1D169); (0x1D17B, 0x1D182); (0x1D185, 0x1D18B);
     (0x1D1AA, 0x1D1AD); (0x1D242, 0x1D244); (0x1DA00, 0x1DA36);
     (0x1DA3B, 0x1DA6C); (0x1DA75, 0x1DA75); (0x1DA84, 0x1DA84);
     (0x1DA9B, 0x1DA9F); (0x1DAA1, 0x1DAAF); (0x1E000, 0x1E006);
     (0x1E008, 0x1E018); (0x1E01B, 0x1E021); (0x1E023, 0x1E024);
     (0x1E026, 0x1E02A); (0x1E130, 0x1E136); (0x1E2AE, 0x1E2AE);
     (0x1E2EC, 0x1E2EF); (0x1E8D0, 0x1E8D6); (0x1E944, 0x1E94A);
     (0x1F3FB, 0x1F3FF); (0xE0020, 0xE007F); (0xE0100, 0xE01EF) |]

let gcb_spacing =
  [| (0x0903, 0x0903); (0x093B, 0x093B); (0x093E, 0x0940); (0x0949, 0x094C);
     (0x094E, 0x094F); (0x0982, 0x0983); (0x09BE, 0x09C0); (0x09C7, 0x09C8);
     (0x09CB, 0x09CC); (0x09D7, 0x09D7); (0x0A03, 0x0A03); (0x0A3E, 0x0A40);
     (0x0A83, 0x0A83); (0x0ABE, 0x0AC0); (0x0AC9, 0x0AC9); (0x0ACB, 0x0ACC);
     (0x0B02, 0x0B03); (0x0BBE, 0x0BBE); (0x0BC1, 0x0BC2); (0x0BC6, 0x0BC8);
     (0x0BCA, 0x0BCC); (0x0BD7, 0x0BD7); (0x0C01, 0x0C03); (0x0C41, 0x0C44);
     (0x0C82, 0x0C83); (0x0CBE, 0x0CBE); (0x0CC0, 0x0CC4); (0x0CC7, 0x0CC8);
     (0x0CCA, 0x0CCB); (0x0CD5, 0x0CD6); (0x0D02, 0x0D03); (0x0D3E, 0x0D40);
     (0x0D46, 0x0D48); (0x0D4A, 0x0D4C); (0x0D57, 0x0D57); (0x0D82, 0x0D83);
     (0x0DCF, 0x0DD1); (0x0DD8, 0x0DDF); (0x0DF2, 0x0DF3); (0x0F3E, 0x0F3F);
     (0x0F7F, 0x0F7F); (0x102B, 0x102C); (0x1031, 0x1031); (0x1038, 0x1038);
     (0x103B, 0x103C); (0x1056, 0x1057); (0x1062, 0x1064); (0x1067, 0x106D);
     (0x1083, 0x1084); (0x1087, 0x108C); (0x108F, 0x108F); (0x109A, 0x109C);
     (0x17B6, 0x17B6); (0x17BE, 0x17C5); (0x17C7, 0x17C8); (0x1923, 0x1926);
     (0x1929, 0x192B); (0x1930, 0x1931); (0x1933, 0x1938); (0x1A19, 0x1A1A);
     (0x1A55, 0x1A55); (0x1A57, 0x1A57); (0x1A61, 0x1A61); (0x1A63, 0x1A64);
     (0x1A6D, 0x1A72); (0x1B04, 0x1B04); (0x1B35, 0x1B35); (0x1B3B, 0x1B3B);
     (0x1B3D, 0x1B41); (0x1B43, 0x1B44); (0x1B82, 0x1B82); (0x1BA1, 0x1BA1);
     (0x1BA6, 0x1BA7); (0x1BAA, 0x1BAA); (0x1BE7, 0x1BE7); (0x1BEA, 0x1BEC);
     (0x1BEE, 0x1BEE); (0x1BF2, 0x1BF3); (0x1C24, 0x1C2B); (0x1C34, 0x1C35);
     (0x1CE1, 0x1CE1); (0x302E, 0x302F); (0xA823, 0xA824); (0xA827, 0xA827);
     (0xA880, 0xA881); (0xA8B4, 0xA8C3); (0xA952, 0xA953); (0xA983, 0xA983);
     (0xA9B4, 0xA9B5); (0xA9BA, 0xA9BB); (0xA9BE, 0xA9C0); (0xAA2F, 0xAA30);
     (0xAA33, 0xAA34); (0xAA4D, 0xAA4D); (0xAA7B, 0xAA7B); (0xAA7D, 0xAA7D);
     (0xAAEB, 0xAAEB); (0xAAEE, 0xAAEF); (0xAAF5, 0xAAF5); (0xABE3, 0xABE4);
     (0xABE6, 0xABE7); (0xABE9, 0xABEA); (0xABEC, 0xABEC); (0x11000, 0x11000);
     (0x11002, 0x11002); (0x11082, 0x11082); (0x110B0, 0x110B2);
     (0x110B7, 0x110B8); (0x1112C, 0x1112C); (0x11145, 0x11146);
     (0x11182, 0x11182); (0x111B3, 0x111B5); (0x111BF, 0x111C0);
     (0x111CE, 0x111CE); (0x1122C, 0x1122E); (0x11232, 0x11233);
     (0x11235, 0x11235); (0x112E0, 0x112E2); (0x11302, 0x11303);
     (0x1133E, 0x1133F); (0x11341, 0x11344); (0x11347, 0x11348);
     (0x1134D, 0x1134D); (0x11357, 0x11357); (0x11362, 0x11363);
     (0x11435, 0x11437); (0x11440, 0x11441); (0x11445, 0x11445);
     (0x114B0, 0x114B2); (0x114B9, 0x114B9); (0x114BB, 0x114BE);
     (0x114C1, 0x114C1); (0x115AF, 0x115B1); (0x115B8, 0x115BB);
     (0x115BE, 0x115BE); (0x11630, 0x11632); (0x1163B, 0x1163C);
     (0x1163E, 0x1163E); (0x116AC, 0x116AC); (0x116AE, 0x116AF);
     (0x116B6, 0x116B6); (0x11720, 0x11721); (0x11726, 0x11726);
     (0x1182C, 0x1182E); (0x11838, 0x11838); (0x11930, 0x11935);
     (0x11937, 0x11938); (0x1193D, 0x1193D); (0x11940, 0x11940);
     (0x11942, 0x11942); (0x119D1, 0x119D3); (0x119DC, 0x119DF);
     (0x119E4, 0x119E4); (0x11A39, 0x11A39); (0x11A57, 0x11A58);
     (0x11A97, 0x11A97); (0x11C2F, 0x11C2F); (0x11C3E, 0x11C3E);
     (0x11CA9, 0x11CA9); (0x11CB1, 0x11CB1); (0x11CB4, 0x11CB4);
     (0x11D8A, 0x11D8E); (0x11D93, 0x11D94); (0x11D96, 0x11D96);
     (0x11EF5, 0x11EF6); (0x11F03, 0x11F03); (0x11F34, 0x11F3A);
     (0x11F3E, 0x11F3F); (0x11F41, 0x11F41); (0x16F51, 0x16F87);
     (0x16FF0, 0x16FF1); (0x1D165, 0x1D166); (0x1D16D, 0x1D172) |]

let gcb_prepend =
  [| (0x0600, 0x0605); (0x06DD, 0x06DD); (0x070F, 0x070F);
     (0x0890, 0x0891); (0x08E2, 0x08E2); (0x0D4E, 0x0D4E);
     (0x110BD, 0x110BD); (0x110CD, 0x110CD); (0x111C2, 0x111C3);
     (0x1193D, 0x1193D); (0x11941, 0x11941); (0x11A3A, 0x11A3A);
     (0x11A84, 0x11A89); (0x11D46, 0x11D46) |]

(* C0/C1 controls, DEL, soft hyphen, bidi and joiner-adjacent format
   characters — everything that hard-breaks a cluster. *)
let gcb_control =
  [| (0x0000, 0x0009); (0x000B, 0x000C); (0x000E, 0x001F);
     (0x007F, 0x009F); (0x00AD, 0x00AD); (0x061C, 0x061C);
     (0x180E, 0x180E); (0x200B, 0x200C); (0x200E, 0x200F);
     (0x202A, 0x202E); (0x2060, 0x2064); (0x2066, 0x206F);
     (0xFEFF, 0xFEFF); (0xFFF9, 0xFFFB); (0xE0001, 0xE0001);
     (0xE0002, 0xE001F) |]

let gcb_ri = [| (0x1F1E6, 0x1F1FF) |]

(* Extended_Pictographic: the emoji that join through ZWJ. Ranges are
   generous — a stray non-emoji only ever fuses with an explicit ZWJ
   chain, so over-inclusion cannot split a real cluster. *)
let gcb_extpict =
  [| (0x00A9, 0x00A9); (0x00AE, 0x00AE); (0x203C, 0x203C); (0x2049, 0x2049);
     (0x2122, 0x2122); (0x2139, 0x2139); (0x2194, 0x2199); (0x21A9, 0x21AA);
     (0x231A, 0x231B); (0x2328, 0x2328); (0x2388, 0x2388); (0x23CF, 0x23CF);
     (0x23E9, 0x23F3); (0x23F8, 0x23FA); (0x24C2, 0x24C2); (0x25AA, 0x25AB);
     (0x25B6, 0x25B6); (0x25C0, 0x25C0); (0x25FB, 0x25FE); (0x2600, 0x26FF);
     (0x2700, 0x27BF); (0x2934, 0x2935); (0x2B05, 0x2B07); (0x2B1B, 0x2B1C);
     (0x2B50, 0x2B50); (0x2B55, 0x2B55); (0x3030, 0x3030); (0x303D, 0x303D);
     (0x3297, 0x3297); (0x3299, 0x3299); (0x1F000, 0x1F0FF);
     (0x1F10D, 0x1F10F); (0x1F12F, 0x1F12F); (0x1F16C, 0x1F171);
     (0x1F17E, 0x1F17F); (0x1F18E, 0x1F18E); (0x1F191, 0x1F19A);
     (0x1F1AD, 0x1F1E5); (0x1F201, 0x1F20F); (0x1F21A, 0x1F21A);
     (0x1F22F, 0x1F22F); (0x1F232, 0x1F23A); (0x1F23C, 0x1F23F);
     (0x1F249, 0x1FAFF) |]

let gcb_l = [| (0x1100, 0x115F); (0xA960, 0xA97C) |]
let gcb_v = [| (0x1160, 0x11A7); (0xD7B0, 0xD7C6) |]
let gcb_t = [| (0x11A8, 0x11FF); (0xD7CB, 0xD7FB) |]

let gcb_of cp =
  if cp = 0x0D then G_cr
  else if cp = 0x0A then G_lf
  else if cp = 0x200D then G_zwj
  else if cp >= 0xAC00 && cp <= 0xD7A3 then
    if (cp - 0xAC00) mod 28 = 0 then G_lv else G_lvt
  else if in_ranges gcb_l cp then G_l
  else if in_ranges gcb_v cp then G_v
  else if in_ranges gcb_t cp then G_t
  else if in_ranges gcb_ri cp then G_ri
  else if in_ranges gcb_extend cp then G_extend
  else if in_ranges gcb_prepend cp then G_prepend
  else if in_ranges gcb_spacing cp then G_spacing
  else if in_ranges gcb_extpict cp then G_extpict
  else if in_ranges gcb_control cp then G_control
  else G_other

(* The next UTF-8 sequence: (codepoint, index after it). A malformed
   or truncated byte decodes as one U+FFFD unit so the segmenter keeps
   moving on any input a store prop can carry. *)
let utf8_decode s i =
  let n = String.length s in
  let byte k = Char.code s.[k] in
  let cont k = k < n && byte k land 0xC0 = 0x80 in
  let c = byte i in
  if c < 0x80 then (c, i + 1)
  else if c >= 0xC2 && c < 0xE0 && cont (i + 1) then
    (((c land 0x1F) lsl 6) lor (byte (i + 1) land 0x3F), i + 2)
  else if c >= 0xE0 && c < 0xF0 && cont (i + 1) && cont (i + 2) then
    (((c land 0x0F) lsl 12)
     lor ((byte (i + 1) land 0x3F) lsl 6)
     lor (byte (i + 2) land 0x3F),
     i + 3)
  else if c >= 0xF0 && c < 0xF5 && cont (i + 1) && cont (i + 2)
          && cont (i + 3)
  then
    (((c land 0x07) lsl 18)
     lor ((byte (i + 1) land 0x3F) lsl 12)
     lor ((byte (i + 2) land 0x3F) lsl 6)
     lor (byte (i + 3) land 0x3F),
     i + 4)
  else (0xFFFD, i + 1)

(* [grapheme_bounds s] is the sorted array of byte offsets where
   grapheme clusters start or end — the same contract the platform
   engines' [graphemes] carry: it holds [0] and [String.length s], so
   consecutive entries delimit the clusters. *)
let grapheme_bounds s =
  let n = String.length s in
  if n = 0 then [| 0 |]
  else begin
  let acc = ref [ 0 ] in
  let prev = ref G_other in
  (* consecutive regional indicators inside the running cluster — a
     flag forms per pair *)
  let ri_run = ref 0 in
  (* emoji-ZWJ chain state: 1 = suffix "ExtPict Extend*", 2 = that
     chain plus a trailing ZWJ *)
  let ep = ref 0 in
  let i = ref 0 in
  while !i < n do
    let cp, j = utf8_decode s !i in
    let g = gcb_of cp in
    let brk =
      match (!prev, g) with
      | G_cr, G_lf -> false                       (* GB3 *)
      | (G_cr | G_lf | G_control), _ -> true      (* GB4 *)
      | _, (G_cr | G_lf | G_control) -> true      (* GB5 *)
      | G_l, (G_l | G_v | G_lv | G_lvt) -> false  (* GB6 *)
      | (G_lv | G_v), (G_v | G_t) -> false        (* GB7 *)
      | (G_lvt | G_t), G_t -> false               (* GB8 *)
      | _, (G_extend | G_zwj) -> false            (* GB9 *)
      | _, G_spacing -> false                     (* GB9a *)
      | G_prepend, _ -> false                     (* GB9b *)
      | G_zwj, G_extpict when !ep = 2 -> false    (* GB11 *)
      | G_ri, G_ri -> !ri_run mod 2 = 0           (* GB12/13 pairs *)
      | _ -> true                                 (* GB999 *)
    in
    (* the first cluster already opened at [0] in [acc] *)
    if brk && !i > 0 then acc := !i :: !acc;
    (match g with
     | G_ri ->
       ri_run := if !prev = G_ri && not brk then !ri_run + 1 else 1
     | _ -> ri_run := 0);
    (match g with
     | G_extpict -> ep := 1
     | G_extend -> ep := (if !ep = 1 then 1 else 0)
     | G_zwj -> ep := (if !ep = 1 then 2 else 0)
     | _ -> ep := 0);
    prev := g;
    i := j
  done;
  Array.of_list (List.rev (n :: !acc))
  end

(* The masked form of a secure field's text: one bullet per grapheme.
   Masking is idempotent — a bullet is its own cluster — so callers
   may feed it a string the paint pass already masked. *)
let secure_mask s =
  let b = grapheme_bounds s in
  let n = Array.length b - 1 in
  if n <= 0 then ""
  else
    let buf = Buffer.create (n * mask_char_len) in
    for _ = 1 to n do
      Buffer.add_string buf mask_char
    done;
    Buffer.contents buf

(* The byte offset in the real text that answers byte offset [m] in
   its masked form — every bullet spans [mask_char_len] bytes, so a
   hit on the masked layout maps to a grapheme index, and the index
   maps back through the real text's boundaries. *)
let secure_byte_of_masked s m =
  let b = grapheme_bounds s in
  let idx = min (max 0 m / mask_char_len) (Array.length b - 1) in
  b.(idx)

(* The inverse of [secure_byte_of_masked]: the masked-form byte
   offset of real-text byte [i] — the bullet that starts the grapheme
   containing [i]. Lets caret models built on the masked layout take
   and return real-text offsets. *)
let secure_masked_of_byte s i =
  let b = grapheme_bounds s in
  let n = Array.length b in
  let rec go k = if k + 1 < n && b.(k + 1) <= i then go (k + 1) else k in
  (if n = 0 then 0 else go 0) * mask_char_len

let text_ops ?fg ctx store id r alpha ~placeholder_ok =
  let fg =
    match fg with Some c -> c | None -> text_fg ctx store id
  in
  let s =
    match pstr store id "text" with
    | Some s when s <> "" ->
      (* A secure field never hands its real text to the text engine:
         the renderer only ever shapes the bullet mask — one grapheme,
         one bullet. Placeholder and title text are not secrets and
         stay readable. *)
      let s =
        if Lui_store.kind store id = "secure-field" then secure_mask s
        else s
      in
      Some (s, fg)
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

(* Select indicators use the host's existing image decoder, including its
   scale-aware SVG cache. Clip labels before the trailing icon slot. *)
let select_ops ctx store id rs r alpha fg =
  let tp = text_placement_of store id in
  let pad_left = tp.tp_pad_left *. ctx.scale in
  let pad = tp.tp_pad_right *. ctx.scale in
  let _, right, _, left = border_widths ctx store id in
  let size =
    Float.min (16. *. ctx.scale)
      (Float.min r.h (Float.max 0. (r.w -. left -. right -. pad_left -. pad)))
  in
  let label = { r with w = Float.max 0. (r.w -. right -. pad -. size) } in
  let indicator =
    if size <= 0. then []
    else
      let slot =
        rect
          (r.x +. r.w -. right -. pad -. size)
          (r.y +. ((r.h -. size) /. 2.))
          size size
      in
      let logical =
        {
          x = slot.x /. ctx.scale;
          y = slot.y /. ctx.scale;
          w = slot.w /. ctx.scale;
          h = slot.h /. ctx.scale;
        }
      in
      match ctx.hooks.image_in id logical with
      | None -> []
      | Some image ->
          [
            Image
              {
                irect2 = slot;
                iradii = (0., 0., 0., 0.);
                icontinuous = false;
                iimage = image;
                isrc = rect 0. 0. (float image.iw) (float image.ih);
                igrayscale = false;
                iopacity = alpha;
              };
          ]
  in
  box_ops ctx store id rs r alpha
  @ [
      Push_clip
        { crect = label; cradii = (0., 0., 0., 0.); ccontinuous = false };
    ]
  @ text_ops ~fg ctx store id label alpha ~placeholder_ok:true
  @ [ Pop_clip ] @ indicator

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
  let b = leading_box ctx store id r 16. in
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
  let b = leading_box ctx store id r 16. in
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
    let isrc =
      if pstr store id "image-fit" = Some "fill" && r.w > 0. && r.h > 0. then
        let scale = Float.max (r.w /. isrc.w) (r.h /. isrc.h) in
        let width = r.w /. scale and height = r.h /. scale in
        rect (isrc.x +. (isrc.w -. width) /. 2.)
          (isrc.y +. (isrc.h -. height) /. 2.) width height
      else isrc
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
    | _ :: _ when Lui_store.kind store id <> "menu-item" -> []
    | _ ->
      let s = ctx.scale in
      let icon_size = if Lui_store.kind store id = "menu-item" then 16. else 18. in
      let size = Float.min (icon_size *. s) (Float.min r.w r.h) in
      if size <= 0. then []
      else
        let dst =
          match Lui_store.kind store id with
          | "menu-item" ->
            (* The icon follows the optional leading check and outer padding. *)
            let tp = text_placement_of store id in
            let gap = Option.value ~default:8. (pnum store id "gap") in
            rect (r.x +. ((tp.tp_pad_left -. 16. -. gap) *. s))
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

(* A single immutable bitmap is reused across rows and frames. The bounded
   cache also allows theme or display-scale changes without retaining old sizes. *)
let menu_check_cache = ref None

let menu_check_image size c =
  match !menu_check_cache with
  | Some (cached_size, cached_color, image)
    when cached_size = size && cached_color = c ->
      image
  | _ ->
      let distance x y ax ay bx by =
        let dx = bx -. ax and dy = by -. ay in
        let t =
          Float.max 0.
            (Float.min 1.
               ((((x -. ax) *. dx) +. ((y -. ay) *. dy))
               /. ((dx *. dx) +. (dy *. dy))))
        in
        Float.hypot (x -. ax -. (t *. dx)) (y -. ay -. (t *. dy))
      in
      let pixels = Bytes.make (size * size * 4) '\000' in
      let step = 24. /. float size in
      for y = 0 to size - 1 do
        for x = 0 to size - 1 do
          let coverage = ref 0 in
          for sy = 0 to 3 do
            for sx = 0 to 3 do
              let px = (float x +. ((float sx +. 0.5) /. 4.)) *. step in
              let py = (float y +. ((float sy +. 0.5) /. 4.)) *. step in
              if
                Float.min
                  (distance px py 5. 12. 10. 17.)
                  (distance px py 10. 17. 20. 7.)
                <= 1.
              then incr coverage
            done
          done;
          let alpha = ((c.a * !coverage) + 8) / 16 in
          let offset = ((y * size) + x) * 4 in
          Bytes.set pixels offset (Char.chr (((c.r * alpha) + 127) / 255));
          Bytes.set pixels (offset + 1) (Char.chr (((c.g * alpha) + 127) / 255));
          Bytes.set pixels (offset + 2) (Char.chr (((c.b * alpha) + 127) / 255));
          Bytes.set pixels (offset + 3) (Char.chr alpha)
        done
      done;
      let image = new_image ~w:size ~h:size pixels in
      menu_check_cache := Some (size, c, image);
      image

let menu_selection_ops ctx store id r alpha fg =
  if not (pbool store id "selected") then []
  else
    let s = ctx.scale in
    let size = 16. *. s in
    let tp = text_placement_of store id in
    let gap = Option.value ~default:8. (pnum store id "gap") in
    let x =
      if pstr store id "selection-placement" = Some "leading" then
        let icon_zone =
          if pstr store id "icon" = None then 0. else 16. +. gap
        in
        r.x +. ((tp.tp_pad_left -. 16. -. gap -. icon_zone) *. s)
      else r.x +. r.w -. ((tp.tp_pad_right -. gap) *. s)
    in
    let image = menu_check_image (max 1 (int_of_float (Float.ceil size))) fg in
    [
      Image
        {
          irect2 = rect x (r.y +. ((r.h -. size) /. 2.)) size size;
          iradii = (0., 0., 0., 0.);
          icontinuous = false;
          iimage = image;
          isrc = rect 0. 0. (float image.iw) (float image.ih);
          igrayscale = false;
          iopacity = alpha;
        };
    ]

(* Labeled chrome carrying an [icon] prop and no children paints the
   glyph in a side slot — on the web the icon is a flex child sitting
   before ("leading", default) or after ("trailing") the label, so the
   label's rect steps aside by the icon zone (glyph + 6px gap). The
   text engine still applies the kind's own pad inside the shrunken
   rect, keeping the same visual gap. Icon-only nodes keep the
   centered slot from [control_icon_ops]. Like there, the [icon]
   prop gates the image lookup. *)
let labeled_content_ops ctx store id r alpha ~fg ~placeholder_ok =
  (* menu-item owns a fixed leading icon slot: its box branch paints the
     glyph through [control_icon_ops] and [text_placement_of] already
     reserves the slot in the label pad. Painting the side-slot icon here
     as well drew every menu icon twice. *)
  if Lui_store.kind store id = "menu-item" then
    text_ops ~fg ctx store id r alpha ~placeholder_ok
  else
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
        let trailing = pstr store id "icon-placement" = Some "trailing" in
        let pad = (if trailing then tp.tp_pad_right else tp.tp_pad_left) *. s in
        let gap = Option.value ~default:6. (pnum store id "gap") *. s in
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
    @ (if border_styled then []
       else [ hairline r.x (r.y +. r.h -. Float.max 1. (1. *. s)) r.w ])
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
    (* Button-like kinds paint content through labeled_content_ops. *)
    @ (if kind = "number-stepper" then control_icon_ops ctx store id r alpha
       else [])
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

(* Kinds whose own chrome anchors to the viewport rather than the
   node box — the modal scrim fills the frame, not [r]. Their cached
   ops are not translation-invariant, which the retained pass's
   shift fast path needs to know. *)
let viewport_anchored = function
  | "dialog" | "sheet" | "drawer" | "modal" -> true
  | _ -> false

(* Disabled controls dim unless the view already drove an opacity. *)
let disabled_alpha store id st =
  if
    st.disabled
    && not (prop_set store id "disabled-opacity" || prop_set store id "opacity")
  then 0.55
  else 1.

(* ---------- node paint ---------- *)

let menu_kind store id = function
  | "dropdown-menu" | "context-menu" -> true
  | "popover" -> pstr store id "role" = Some "menu"
  | _ -> false

let scroll_kind = function
  | "scroll" | "list" | "virtual-list" -> true
  | _ -> false

let scrollable kind store id =
  scroll_kind kind
  || menu_kind store id kind
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
  (* The resolved display box is edge-snapped ([Lui_scene.rect_snap])
     before it returns — the pixel-snapping contract. Paint, clip,
     the hit-test mirror, scroll extents and damage bounds all consume
     this same snapped geometry, so a fractional layout or a
     scroll-shifted position can never diverge into a 0.5 px
     paint/hit-test mismatch. *)
  let r =
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
  in
  rect_snap r

(* The ctx-taking form {!Lui_retained} calls; the labeled-args one
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

let node_shown store id =
  (match Lui_store.prop store id "visible" with
   | Some (Lui_protocol.BoolValue false) -> false
   | Some (Lui_protocol.StringValue "false") -> false
   | _ -> true)
  && (match pstr store id "display" with Some "none" -> false | _ -> true)

let unboxed store id = pstr store id "display" = Some "contents"

(* The store/paint predicates a spatial index build needs, wired to
   this module's own rules so index bounds always mirror the walk's
   visibility and clip-escape decisions. *)
let spatial_env : Lui_spatial.env =
  { shown = node_shown;
    promotes =
      (fun store id ->
        popup_kind (Lui_store.kind store id) && not (unboxed store id));
    ordered = ordered_children }

(* ---------- shared stacking walk ---------- *)

(* One frame of the tree walk paint and hit-testing share: the node's
   resolved box plus the stacking/clip result both passes agree on —
   z-ordered siblings, promoted popups, display:contents pass-through
   and the ancestor clip it sits inside.

   [f_clip] is the clip context applying to the node (None inside the
   deferred overlay pass — a promoted popup escapes ancestor clips);
   [f_clipped] its painted area (f_rect ∩ f_clip). Children inherit
   [f_clipped] when the node clips, [f_clip] otherwise, and resolve
   their containing block against [f_parent_r]. *)
type frame = {
  f_id : int;
  f_kind : string;
  f_rect : rect;
  f_clip : rect option;
  f_clipped : rect;
  f_clips : bool;
  f_contents : bool;
  f_parent_r : rect;
}

(* What [enter] decides for one node: [b_emit] fires the node's own
   chrome (ops, clip brackets, hit tests); [b_down] walks the
   children; [b_ctx] is the context the subtree and [leave] run under. *)
type 'a branch = {
  b_emit : bool;
  b_down : bool;
  b_ctx : 'a;
}

(* A clip context that misses [viewport] entirely is dead: nothing
   inside it can paint or be hit — except promoted popups, which
   escape to the overlay pass. *)
let clip_dead ~viewport = function
  | Some cr -> rect_empty (rect_intersect cr viewport)
  | None -> false

(* The geometry half of a walk step: resolved box, ancestor-clip
   intersection, own-clip decision and the containing block — shared
   with the retained pass so both agree on where a node sits and what
   it clips to. Returns the node's frame and the clip context its
   children inherit. *)
let frame_of ~scale ~viewport store id kind p parent_r clip =
  let contents = unboxed store id in
  let r = resolve_rect ~scale ~viewport store id kind p parent_r in
  let clipped =
    match clip with
    | Some cr -> rect_intersect r cr
    | None -> r
  in
  let clips_own =
    (not contents) && clips kind store id
    && ((not (rect_empty r))
        || (* An empty split pane still clips: its children's own
              minimum sizes would otherwise paint through it. *)
           (match Lui_store.parent store id with
            | Some pid -> Lui_store.kind store pid = "split"
            | None -> false))
  in
  ( { f_id = id; f_kind = kind; f_rect = r; f_clip = clip;
      f_clipped = clipped; f_clips = clips_own; f_contents = contents;
      f_parent_r = (if contents then parent_r else r) },
    if clips_own then Some clipped else clip )

(* Walk the forest in paint order — z-sorted siblings, popups
   promoted out of their ancestors' clips into a deferred overlay
   pass, display:contents unboxed — carrying [clip] (the accumulated
   ancestor clip) and the caller's context down the tree. [enter]
   fires on every shown node, [leave] closes frames whose own chrome
   emitted, and both receive the context the caller threaded down.
   Inside a dead clip — one that misses [viewport] entirely — the
   walk switches to a ghost pass that skips [enter]/[leave] and every
   node's chrome cost, keeping only the promoted-popup search and the
   [ghost_enter] context update (a popup's alpha and hit flags still
   accumulate its clipped-away ancestors).

   [?spatial] supplies a fresh [Lui_spatial] index plus the query the
   walk serves ([Point] for hit-testing, [Region] for paint culling):
   children whose subtree bound cannot contribute are never entered,
   and wide parents enumerate candidates through the interval index
   instead of scanning every child. Pruning is a strict filter on the
   unindexed walk's visit set — same order, same clip contexts. *)
let walk ?(mounted = fun _ -> None) ?(hidden = fun _ -> false)
    ~scale ~viewport store ~layout ~enter ~ghost_enter ~leave
    ?spatial ctx0 =
  let deferred = Queue.create () in
  (* Virtualized containers walk only their mounted window slice. *)
  let kids id =
    match mounted id with
    | Some ids ->
      z_ordered store (List.filter_map (Lui_store.find_opt store) ids)
    | None -> ordered_children store id
  in
  let dead = clip_dead ~viewport in
  let rec go ctx clip parent_r (n : Lui_store.node) =
    let id = Lui_store.node_id n and kind = Lui_store.node_kind n in
    if not (hidden id) && node_shown store id then
      if popup_kind kind && not (unboxed store id) then
        (* promoted out of the ancestor clips: painted after the whole
           tree with a fresh clip context *)
        Queue.add (fun () -> body ctx None parent_r id kind) deferred
      else if dead clip then ghost ctx clip parent_r n
      else body ctx clip parent_r id kind
  (* The subtree sits entirely inside a dead clip: keep walking only
     far enough to find promoted popups (and their containing blocks),
     skipping every node's enter/chrome cost. *)
  and ghost ctx clip parent_r (n : Lui_store.node) =
    let id = Lui_store.node_id n and kind = Lui_store.node_kind n in
    if not (hidden id) && node_shown store id then
      if popup_kind kind && not (unboxed store id) then
        Queue.add (fun () -> body ctx None parent_r id kind) deferred
      else begin
        let contents = unboxed store id in
        let p = layout id in
        let r = resolve_rect ~scale ~viewport store id kind p parent_r in
        let ctx = ghost_enter ctx id contents in
        let child_parent = if contents then parent_r else r in
        (* The ghost pass owes the query only promoted escapees —
           [keep] answers exactly that via [eb]/[esc]. *)
        List.iter
          (fun cid ->
            match Lui_store.find_opt store cid with
            | Some c -> ghost ctx clip child_parent c
            | None -> ())
          (match mounted id, spatial with
           | Some _, _ -> List.map Lui_store.node_id (kids id)
           | None, None ->
             List.map Lui_store.node_id (ordered_children store id)
           | None, Some (idx, q) -> candidates idx q clip id)
      end
  (* Children of [id] that could contribute to the query under clip
     context [clip]: the interval index for indexed parents, the
     per-child [keep] test otherwise. Returns ids in paint order. *)
  and candidates idx q clip id =
    match Lui_spatial.children idx ~clip q id with
    | Some ids -> ids
    | None ->
      List.filter_map
        (fun c ->
          let cid = Lui_store.node_id c in
          if
            Lui_spatial.keep idx ~clip
              ~esc:
                (popup_kind (Lui_store.node_kind c)
                 && not (unboxed store cid))
              q cid
          then Some cid
          else None)
        (ordered_children store id)
  and body ctx clip parent_r id kind =
    let p = layout id in
    let f, child_clip =
      frame_of ~scale ~viewport store id kind p parent_r clip
    in
    let br = enter ctx f in
    if br.b_down then begin
      (* Mounted virtual-list slices are already window-sized; the
         spatial index only prunes ordinary children. *)
      match mounted id, spatial with
      | Some _, _ -> List.iter (go br.b_ctx child_clip f.f_parent_r) (kids id)
      | None, None ->
        List.iter (go br.b_ctx child_clip f.f_parent_r)
          (ordered_children store id)
      | None, Some (idx, q) ->
        List.iter
          (fun cid ->
            match Lui_store.find_opt store cid with
            | Some c -> go br.b_ctx child_clip f.f_parent_r c
            | None -> ())
          (candidates idx q child_clip id)
    end;
    if br.b_emit then leave br.b_ctx f
  in
  let roots =
    (* [root_ids] folds the whole store — with an index the snapshot
       already knows the roots. *)
    match spatial with
    | None -> Lui_store.root_ids store
    | Some (idx, _) -> Lui_spatial.roots idx
  in
  List.iter
    (fun id ->
       let keep =
         match spatial with
         | None -> true
         | Some (idx, q) ->
           (match Lui_store.find_opt store id with
            | Some n ->
              Lui_spatial.keep idx ~clip:None
                ~esc:
                  (popup_kind (Lui_store.node_kind n)
                   && not (unboxed store id))
                q id
            | None -> false)
       in
       if keep then
         go ctx0 None viewport
           (match Lui_store.find_opt store id with
            | Some n -> n
            | None -> invalid_arg "Lui_paint.walk: root id missing"))
    roots;
  (* Promoted popups drain after the tree — nested popups enqueue
     during the drain and preserve preorder among popups. *)
  while not (Queue.is_empty deferred) do
    (Queue.pop deferred) ()
  done

let emit scene ops = scene.ops <- List.rev_append ops scene.ops
let emit1 scene op = scene.ops <- op :: scene.ops

(* Ops for a single node's own chrome. *)
let paint_own ctx store id st kind r rs alpha =
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
    | "select" | "combobox" -> select_ops ctx store id rs r alpha fg
    | "text-field" | "secure-field" | "input" | "search-field" | "textarea" ->
      box_ops ctx store id rs r alpha
      @ text_ops ~fg ctx store id r alpha ~placeholder_ok:true
    | "menu-item" ->
      box_ops ctx store id rs r alpha
      @ labeled_content_ops ctx store id r alpha ~fg ~placeholder_ok:false
      @ menu_selection_ops ctx store id r alpha fg
    | "button" | "toggle-button" | "toggle" | "menu-trigger"
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

(* Inside a dead clip only the context still matters: a promoted
   popup inherits its clipped-away ancestors' opacity, so the ghost
   walk threads alpha down without resolving chrome. *)
let paint_ghost_enter ctx store alpha id contents =
  if contents then alpha
  else
    let st = effective_state ctx.hooks store id in
    let rs = resolve_style store id st in
    alpha *. rs.rs_opacity *. disabled_alpha store id st

(* A visible node's own chrome: clip bracket, box ops, scrollbar —
   everything except the child walk, which the shared stacking walk
   drives. A node whose painted area misses the frame emits nothing
   but still walks its children: they can escape the box
   (overflow:visible content, absolute/fixed children, promoted
   popups) and cull themselves. The only true subtree cull is the
   walk's dead-clip path — a clip that misses the viewport cannot
   contain output. *)
let paint_enter ctx store scene alpha f =
  let id = f.f_id and kind = f.f_kind in
  let contents = f.f_contents in
  let st = effective_state ctx.hooks store id in
  let rs = resolve_style store id st in
  (* display:contents generates no box, so its opacity and chrome do
     not apply — children paint with the parent's alpha and clip. *)
  let alpha =
    if contents then alpha
    else alpha *. rs.rs_opacity *. disabled_alpha store id st
  in
  (* An alpha-0 subtree emits no ops at all: the raster treats an op
     opacity of 0 as "unset" (opaque), so invisible nodes must be
     culled here rather than painted at opacity 0. *)
  if alpha <= 0. then { b_emit = false; b_down = false; b_ctx = alpha }
  else begin
    (* Node-not-drawn vs subtree-invisible: only the node's own chrome
       is skipped here; the subtree walks on. Zero-size nodes still
       emit — shadows and outlines can paint outside an empty box —
       matching the pre-cull contract that the raster drops empty
       ops. *)
    let node_drawn =
      (not contents)
      && (rect_empty f.f_rect
         || not (rect_empty (rect_intersect f.f_clipped ctx.viewport)))
    in
    if node_drawn then begin
      let own = paint_own ctx store id st kind f.f_rect rs alpha in
      if f.f_clips then begin
        (* Outer shadows escape the node's overflow clip, while ancestor
           clips still constrain them. Inset shadows and content stay inside. *)
        let outer, inside =
          List.partition (function Shadow s -> not s.sinset | _ -> false) own
        in
        emit scene outer;
        emit1 scene
          (Push_clip
             {
               crect = f.f_rect;
               cradii = corners f.f_rect (radii_of ctx store id) false;
               ccontinuous = false;
             });
        emit scene inside
      end
      else emit scene own;
      { b_emit = true; b_down = true; b_ctx = alpha }
    end
    else { b_emit = false; b_down = true; b_ctx = alpha }
  end

let paint_leave ctx store scene alpha f =
  if scrollable f.f_kind store f.f_id && not f.f_contents then
    emit scene (scrollbar_ops ctx store f.f_id f.f_rect alpha);
  if f.f_clips then emit1 scene Pop_clip

(* Full repaint: reset the scene and repaint the whole forest. A
   [?spatial] index fresh for the geometry about to resolve lets the
   walk skip subtrees whose bounds miss the viewport instead of
   visiting every mounted node — see {!Lui_spatial}. *)
let paint ?spatial hooks store scene ~width ~height ~scale ~clear =
  Lui_scene.reset scene ~width ~height ~scale ~clear;
  let ctx =
    { hooks; scale;
      viewport = rect 0. 0. (float width) (float height);
      deferred = Queue.create () }
  in
  walk ~scale ~viewport:ctx.viewport store ~layout:hooks.layout
    ~mounted:hooks.mounted_children
    ~hidden:hooks.hidden
    ~enter:(paint_enter ctx store scene)
    ~ghost_enter:(paint_ghost_enter ctx store)
    ~leave:(paint_leave ctx store scene)
    ?spatial:
      (Option.map (fun i -> (i, Lui_spatial.Region ctx.viewport)) spatial)
    1.;
  (* Extension renderers may enqueue their own deferred work on
     ctx.deferred — drain it after the walk's own popup pass. *)
  while not (Queue.is_empty ctx.deferred) do
    (Queue.pop ctx.deferred) ()
  done;
  scene.ops <- List.rev scene.ops;
  scene.glyphs <- List.rev scene.glyphs;
  scene.wide <- List.rev scene.wide
