(* SVG subset decoding and CPU rasterization for the native backend.

   [parse] turns SVG source text into a [doc]; [rasterize] flattens it
   into a premultiplied BGRA pixel buffer — the same layout
   [Lui_raster.Image.pix] uses (stride [4 * w], channel order B, G, R,
   A) — so SVG icons and images flow through the existing image paths.
   [to_scene_image] converts such a buffer into a [Lui_scene.image]
   (premultiplied RGBA) for use in [Image] ops, and [render] is the
   parse + rasterize + convert one-shot convenience.

   Supported subset:

   - paths: M L H V C S Q T A Z, relative and absolute, implicit
     repetition and implicit lineto after moveto;
   - shapes: rect (incl. rx/ry), circle, ellipse, line, polyline,
     polygon;
   - structure: g, a, defs, symbol, use (href / xlink:href, symbol
     viewports), nested svg viewports, switch (all children render);
   - transforms: matrix translate scale rotate skewX skewY lists;
   - paint: solid colors (#rgb #rgba #rrggbb #rrggbbaa, rgb()/rgba(),
     named colors, transparent), currentColor, linear and radial
     gradients (any gradientUnits, gradientTransform, spreadMethod,
     stop styles, href chaining), url() with fallback;
   - fill-opacity, stroke-opacity, element and group opacity
     (offscreen-composited), nonzero and evenodd fill rules;
   - strokes: width, linecap butt/round/square, linejoin
     miter/round/bevel, miterlimit, dasharray + dashoffset;
   - clip-path="url(#id)" (userSpaceOnUse and objectBoundingBox,
     clip-rule honored, nested clip paths), mask (luminance and alpha
     mask-types), display=none, visibility;
   - viewBox + preserveAspectRatio (meet / slice / none);
   - presentation attributes and inline [style] declarations, plus
     [<style>] rules with type / .class / #id / descendant / child
     selectors.

   Documented gaps (silently skipped, never an error): text and fonts,
   embedded or referenced raster images, filters, blend modes,
   animation, markers, patterns, foreignObject, unknown elements
   (their children still render). Malformed path data fails [parse];
   malformed numbers in other attributes fall back to the attribute's
   default so lenient real-world files still render.

   Everything here is headless and pure OCaml: no external
   dependencies, no exceptions out of [parse] / [rasterize]. *)

(* A parsed SVG document. *)
type doc

(* Parse SVG source text. Errors are returned, never raised; malformed
   path data is the one hard error (rasterization cannot proceed
   honestly past it). *)
val parse : string -> (doc, string) result

(* The root [viewBox] as (min_x, min_y, width, height), when present
   and well-formed. *)
val view_box : doc -> (float * float * float * float) option

(* The root [width] / [height] attributes in px (unit suffixes
   resolved at 96 dpi), when both are present and well-formed. *)
val intrinsic_size : doc -> (float * float) option

(* Flatten [doc] into a fresh premultiplied BGRA pixel buffer of
   [w] * [h], stride [4 * w]. The root viewBox (or, lacking one, the
   document user space) fits per its preserveAspectRatio — default
   xMidYMid meet. Empty or unpaintable content yields a fully
   transparent buffer; non-positive sizes yield an empty one. *)
val rasterize : doc -> w:int -> h:int -> Bytes.t

(* Wrap a [rasterize]d buffer as a [Lui_scene.image], swapping BGRA to
   the premultiplied RGBA the scene IR stores, so SVG output plugs
   into [Image] ops and color-atlas uploads. *)
val to_scene_image : w:int -> h:int -> Bytes.t -> Lui_scene.image

(* [render src ~w ~h] is [parse] + [rasterize] + [to_scene_image]. *)
val render : string -> w:int -> h:int -> (Lui_scene.image, string) result
