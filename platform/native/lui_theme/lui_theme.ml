(* Canonical design tokens for the self-drawn native UI: light and dark
   palettes, spacing/radius/scrollbar metrics, a typography scale with the
   platform font stack, named shadow pairs, and the focus-ring spec.

   The paint layer keeps its own light-token mirror for hosts that supply
   no color resolver (Lui_paint.default_palette); this module is the
   source of truth and its test pins both sides so they cannot drift. *)

type color = Lui_scene.color

let color = Lui_scene.color

type mode =
  | Light
  | Dark

(* ---------- palettes ---------- *)

(* Semantic surface and accent colors. Neutral scale is the shared zinc
   family; accent is blue-600 light / blue-500 dark. Legacy wire names
   (primary/secondary/input/ring/destructive/muted-foreground) alias onto
   the same tokens so existing views keep resolving. *)
let light_tokens : (string * color) list =
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
    (* border mixed 25% / 15% toward text: the neutral edge an unchecked
       control and an off switch track get. *)
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
    (* inverse surfaces: tooltips and toasts flip the polarity. *)
    ("inverse", color 24 24 27 255);
    ("inverse-foreground", color 255 255 255 255) ]

let dark_tokens : (string * color) list =
  [ ("background", color 24 24 27 255);
    ("foreground", color 244 244 245 255);
    ("text", color 244 244 245 255);
    ("text-muted", color 161 161 170 255);
    ("muted-foreground", color 161 161 170 255);
    ("muted", color 39 39 42 255);
    ("surface", color 39 39 42 255);
    ("surface-hover", color 50 50 54 255);
    ("surface-pressed", color 60 60 65 255);
    ("popover", color 39 39 42 255);
    ("card", color 39 39 42 255);
    ("border", color 63 63 70 255);
    ("input", color 63 63 70 255);
    ("control-border", color 108 108 114 255);
    ("switch-track", color 91 91 97 255);
    ("accent", color 59 130 246 255);
    ("accent-hover", color 96 165 250 255);
    ("accent-pressed", color 37 99 235 255);
    ("accent-text", color 255 255 255 255);
    ("primary", color 59 130 246 255);
    ("primary-foreground", color 255 255 255 255);
    ("secondary", color 39 39 42 255);
    ("danger", color 239 68 68 255);
    ("destructive", color 239 68 68 255);
    ("warning", color 245 158 11 255);
    ("success", color 34 197 94 255);
    ("focus", color 96 165 250 153);
    ("ring", color 96 165 250 153);
    ("selection", color 59 130 246 102);
    ("scrollbar-thumb", color 255 255 255 89);
    ("inverse", color 244 244 245 255);
    ("inverse-foreground", color 24 24 27 255) ]

let tokens = function Light -> light_tokens | Dark -> dark_tokens

let color_of mode name = List.assoc_opt name (tokens mode)

(* ---------- metrics ---------- *)

let radius = 6.
let space n = 4. *. n
let control_height = 28.
let control_radius = 6.
let popover_radius = 8.
let tooltip_radius = 5.
let checkbox_radius = 4.

(* Focus ring: a [focus_width] border drawn [focus_offset] outside the
   control's own box, corners grown to match. *)
let focus_width = 2.
let focus_offset = 1.

(* Overlay scrollbar: a slim full-round thumb hugging the clip edge. *)
let scrollbar_width = 6.
let scrollbar_margin = 2.5
let scrollbar_min_thumb = 16.

(* ---------- typography ---------- *)

(* Platform font stack the text engine resolves: system-ui on darwin
   (SF), Segoe UI with Tahoma/Arial fallback on Windows, fontconfig sans
   on Linux. *)
type platform =
  | Darwin
  | Windows
  | Linux

let font_family_for = function
  | Darwin -> "system-ui"
  | Windows -> "Segoe UI"
  | Linux -> "sans"

let font_fallbacks_for = function
  | Darwin -> []
  | Windows -> [ "Tahoma"; "Arial" ]
  | Linux -> []

let font_size_for = function Darwin -> 13. | _ -> 14.

(* Scale in logical px; [base] is the platform default above. *)
let font_xs = 11.
let font_sm = 12.
let font_lg = 16.
let font_xl = 20.
let font_weight_regular = 400
let font_weight_medium = 500
let font_weight_semibold = 600
let line_height = 1.4

(* ---------- shadows ---------- *)

(* Named shadow pairs: a tight ambient occlusion plus a soft key drop —
   the layered look flat single shadows can't reach. Values are logical
   px; paint scales to device px. *)
type shadow_kind =
  | Card
  | Popup
  | Dialog
  | Tooltip
  | Knob
  | Switch_thumb

let shadow mode kind : Lui_paint.shadow_spec list =
  let spec dx dy blur spread a =
    { Lui_paint.dx; dy; blur; spread; scolor = color 0 0 0 a;
      inset = false }
  in
  let dark = mode = Dark in
  match kind with
  | Card -> [ spec 0. 1. 2. 0. (if dark then 100 else 20); spec 0. 4. 10. 0. (if dark then 120 else 15) ]
  | Popup -> [ spec 0. 1. 3. 0. (if dark then 120 else 26); spec 0. 6. 20. 0. (if dark then 160 else 41) ]
  | Dialog -> [ spec 0. 2. 8. 0. (if dark then 120 else 31); spec 0. 10. 30. 0. (if dark then 200 else 76) ]
  | Tooltip -> [ spec 0. 1. 2. 0. (if dark then 100 else 26); spec 0. 2. 8. 0. (if dark then 150 else 51) ]
  | Knob -> [ spec 0. 0.5 1. 0. 20; spec 0. 1.5 7. 0. 26 ]
  | Switch_thumb -> [ spec 0. 1. 3. 0. 64 ]

let shadow_names =
  [ ("card", Card); ("popup", Popup); ("popover", Popup); ("menu", Popup);
    ("dialog", Dialog); ("modal", Dialog); ("tooltip", Tooltip);
    ("toast", Tooltip); ("knob", Knob) ]

(* A shadow_of resolver for host hooks: named specs resolve to the key
   (stronger) layer — CSS props keep working through the paint parser. *)
let shadow_of mode name =
  match List.assoc_opt name shadow_names with
  | Some k -> (match shadow mode k with s :: _ -> Some s | [] -> None)
  | None -> Lui_paint.parse_shadow (color_of mode) name
