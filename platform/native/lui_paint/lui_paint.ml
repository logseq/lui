(* Node → scene translation: the paint pass.

   Walks the retained store and emits Lui_scene ops for every visible
   node, using the rects the layout pass computed. Extension nodes are
   painted by registered extension renderers, keeping the kernel closed
   while staying open to any app's own kinds. *)

open Lui_scene

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

(* ---------- context ---------- *)

(* Host-injected lookups so paint stays platform-free. *)
type hooks = {
  color_of : string -> color option; (* theme/resource name → color *)
  layout : int -> rect;              (* node id → device-px rect *)
  text_ops : int -> rect -> color -> string -> op list; (* text engine *)
  image_of : int -> image option;    (* node id → decoded image *)
  shadow_of : string -> shadow_spec option;
}

and shadow_spec = {
  dx : float; dy : float; blur : float; scolor : color; inset : bool;
}

type extension_renderer = {
  paint : hooks -> Lui_store.t -> Lui_store.node -> rect -> op list;
}

let extension_renderers : (string, extension_renderer) Hashtbl.t =
  Hashtbl.create 8

let register_extension ~identifier renderer =
  Hashtbl.replace extension_renderers identifier renderer

(* ---------- prop helpers ---------- *)

let pstr store id name = Lui_store.string_prop store id name
let pfloat store id name = Lui_store.float_prop store id name

let pcolor hooks store id name =
  match Lui_store.string_prop store id name with
  | None -> None
  | Some s -> (
    match color_of_hex s with
    | Some c -> Some c
    | None -> hooks.color_of s)

let pfloats store id name =
  match pstr store id name with
  | None -> []
  | Some s ->
    String.split_on_char ' ' s
    |> List.filter_map (fun tok -> float_of_string_opt (String.trim tok))

(* Edges: "all" | "v h" | "t r b l" — CSS shorthand order. *)
let edges_of_floats = function
  | [a] -> (a, a, a, a)
  | [v; h] -> (v, h, v, h)
  | [t; r; b; l] -> (t, r, b, l)
  | _ -> (0., 0., 0., 0.)

let opacity store id =
  match pfloat store id "opacity" with
  | Some f -> Float.max 0. (Float.min 1. f)
  | None -> 1.

let visible store id =
  (match Lui_store.prop store id "visible" with
   | Some (Lui_protocol.BoolValue false) -> false
   | Some (Lui_protocol.StringValue "false") -> false
   | _ -> true)
  && (match pstr store id "display" with Some "none" -> false | _ -> true)

(* ---------- node paint ---------- *)

(* Corner radii from the corner-radius shorthand (CSS order t r b l
   maps to corners tl tr br bl). *)
let radii_of store id =
  match pfloats store id "corner-radius" with
  | [] -> (0., 0., 0., 0.)
  | l -> edges_of_floats l

(* Ops drawn for the node's own box decoration. *)
let box_ops hooks store id r =
  let radii = radii_of store id in
  let bw = match pfloats store id "border-width" with
    | [] -> (0., 0., 0., 0.) | l -> edges_of_floats l
  in
  let ops = ref [] in
  (match pstr store id "shadow" with
   | Some s -> (
     match hooks.shadow_of s with
     | Some spec ->
       ops :=
         Shadow
           { srect = { r with x = r.x +. spec.dx; y = r.y +. spec.dy };
             sradii = corners r radii false;
             scontinuous = false; scolor = spec.scolor; sblur = spec.blur;
             sinset = spec.inset; scast = r; scast_radii = radii;
             scast_continuous = false; swide = 0; sopacity = 1. }
         :: !ops
     | None -> ())
   | None -> ());
  let bg = pcolor hooks store id "background" in
  let bcol = pcolor hooks store id "border-color" in
  (match (bg, bcol, has_border bw) with
   | None, None, _ -> ()
   | None, Some _, false -> ()
   | _ ->
     let c = match bg with Some c -> c | None -> color 0 0 0 0 in
     let bc = match bcol with Some c -> c | None -> color 0 0 0 0 in
     ops :=
       Fill
         { frect = r;
           fradii = corners r radii false;
           fcontinuous = false; fcolor = c; fpaint = Solid;
           fcolor2 = c; fgradient = (0., 0., 0., 0.); fborder = bw;
           fborder_color = bc; fdashed = false; fwide = 0;
           fopacity = opacity store id }
       :: !ops);
  List.rev !ops

let rec paint_node hooks store scene id =
  if visible store id then (
    let r = hooks.layout id in
    let kind = Lui_store.kind store id in
    let clip_overflow =
      match pstr store id "overflow" with
      | Some ("hidden" | "scroll" | "auto" | "clip") -> true
      | _ -> kind = "scroll" || kind = "list" || kind = "virtual-list"
    in
    if clip_overflow && not (rect_empty r) then
      scene.ops <-
        Push_clip { crect = r; cradii = (0., 0., 0., 0.); ccontinuous = false }
        :: scene.ops;
    let own_ops = paint_own hooks store id kind r in
    scene.ops <- List.rev own_ops @ scene.ops;
    List.iter
      (fun c -> paint_node hooks store scene (Lui_store.node_id c))
      (Lui_store.children store id);
    if clip_overflow && not (rect_empty r) then scene.ops <- Pop_clip :: scene.ops)

(* Ops for a single node. *)
and paint_own hooks store id kind r =
  match kind with
  | "text" | "label" | "heading" | "paragraph" | "br" -> (
    let fg =
      match pcolor hooks store id "foreground" with
      | Some c -> c
      | None -> color 0 0 0 255
    in
    match pstr store id "text" with
    | Some s when s <> "" -> hooks.text_ops id r fg s
    | _ -> [])
  | "image" | "file-image" | "media-surface" -> (
    match hooks.image_of id with
    | Some img ->
      box_ops hooks store id r
      @ [ Image { irect2 = r; iradii = (0., 0., 0., 0.); icontinuous = false;
                  iimage = img; isrc = { x = 0.; y = 0.; w = float img.iw; h = float img.ih };
                  igrayscale = false; iopacity = opacity store id } ]
    | None -> box_ops hooks store id r)
  | kind -> (
    match String.index_opt kind ':' with
    | Some _ when String.length kind > 10 && String.sub kind 0 10 = "extension:" -> (
      let identifier = String.sub kind 10 (String.length kind - 10) in
      match Hashtbl.find_opt extension_renderers identifier with
      | Some renderer -> renderer.paint hooks store (Option.get (Lui_store.find_opt store id)) r
      | None -> box_ops hooks store id r)
    | _ -> box_ops hooks store id r)

(* Full repaint: reset the scene and repaint the whole forest. *)
let paint hooks store scene ~width ~height ~scale ~clear =
  Lui_scene.reset scene ~width ~height ~scale ~clear;
  List.iter (paint_node hooks store scene) (Lui_store.root_ids store);
  scene.ops <- List.rev scene.ops
