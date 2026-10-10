(* Headless e2e harness for the native backend: a Lui_host wired to a
   stub renderer that records every display list it is asked to draw,
   plus deterministic stubs for the layout, text, color, image and
   shadow hooks — enough to assert scene ops without a window or a
   real renderer. *)

open Lui_scene

let frame_w = 320
let frame_h = 240
let row_h = 24.

(* What the stub renderer recorded on its last render call. *)
type captured = {
  mutable ops : op list;
  mutable frames : int;
  mutable bytes : int;
}

type t = {
  host : Lui_host.t;
  cap : captured;
  rects : (int, rect) Hashtbl.t;
}

let host t = t.host
let cap t = t.cap
let store t = Lui_host.store t.host
let scene t = Lui_host.scene t.host
let backend t profile = Lui_host.backend t.host profile
let wants_repaint t = Lui_host.wants_repaint t.host
let apply_batch t batch = Lui_host.apply_batch t.host batch
let resize t ~width ~height ~scale = Lui_host.resize t.host ~width ~height ~scale

(* Vertical-stack layout: each node gets a 304x20 row in store preorder,
   so reparenting or reordering children moves its scene rect. *)
let refresh_layout t =
  Hashtbl.reset t.rects;
  List.iteri
    (fun i id ->
       Hashtbl.replace t.rects id (rect 8. (float i *. row_h) 304. 20.))
    (Lui_store.preorder (store t))

let rect_of t id =
  match Hashtbl.find_opt t.rects id with
  | Some r -> r
  | None -> rect 0. 0. 0. 0.

(* Repaint through the real paint pass; returns the ops the stub
   renderer recorded. *)
let repaint t =
  refresh_layout t;
  ignore (Lui_host.repaint t.host);
  t.cap.ops

(* The stub renderer records the display list and reports a zeroed
   premultiplied-BGRA buffer sized to the frame. *)
let stub_renderer cap =
  { Lui_host.render =
      (fun scene ->
        cap.ops <- scene.Lui_scene.ops;
        cap.frames <- cap.frames + 1;
        let b = Bytes.make (scene.width * scene.height * 4) '\000' in
        cap.bytes <- Bytes.length b;
        b);
    name = "stub" }

let test_image = new_image ~w:2 ~h:2 (Bytes.make 16 '\255')

(* Stub text engine: one Glyphs op per call, [gend] carrying the string
   length so tests can correlate ops with text nodes. *)
let stub_text_ops _id _r c s =
  [ Glyphs
      { gstart = 0; gend = String.length s; gpaint = Solid;
        gcolor = c; gcolor2 = c; ggradient = (0., 0., 0., 0.);
        gwide2 = 0; gopacity = 1. } ]

let create ?(width = frame_w) ?(height = frame_h) () =
  let cap = { ops = []; frames = 0; bytes = 0 } in
  let rects = Hashtbl.create 32 in
  let layout id =
    match Hashtbl.find_opt rects id with
    | Some r -> r
    | None -> rect 0. 0. 0. 0.
  in
  let hooks =
    { Lui_paint.color_of =
        (fun name ->
          match name with
          | "accent" -> Some (color 10 20 30 255)
          | _ -> None);
      layout;
      text_ops = stub_text_ops;
      image_of = (fun _id -> Some test_image);
      shadow_of =
        (fun name ->
          match name with
          | "card" ->
            Some
              { dx = 0.; dy = 2.; blur = 6.;
                scolor = color 0 0 0 80; inset = false }
          | _ -> None) }
  in
  { host =
      Lui_host.create ~hooks ~renderer:(stub_renderer cap)
        ~width ~height ~scale:1. ();
    cap;
    rects }

(* ---------- assertion helpers ---------- *)

let op_name = function
  | Fill _ -> "fill"
  | Shadow _ -> "shadow"
  | Glyphs _ -> "glyphs"
  | Image _ -> "image"
  | Push_clip _ -> "push_clip"
  | Pop_clip -> "pop_clip"
  | Effect _ -> "effect"
  | Hole _ -> "hole"

let op_names ops = List.map op_name ops

let kind_nodes store kind =
  List.filter_map
    (fun n ->
      if Lui_store.node_kind n = kind then Some (Lui_store.node_id n)
      else None)
    (Lui_store.all_nodes store)

let find_text_id store kind text =
  match
    List.find_opt
      (fun n ->
        Lui_store.node_kind n = kind
        && Lui_store.node_prop n "text" = Some (Lui_protocol.StringValue text))
      (Lui_store.all_nodes store)
  with
  | Some n -> Some (Lui_store.node_id n)
  | None -> None

let text_prop store id =
  match Lui_store.prop store id "text" with
  | Some (Lui_protocol.StringValue s) -> s
  | _ -> ""
