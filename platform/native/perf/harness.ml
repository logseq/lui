(* Headless perf harness: the same store -> layout -> paint -> raster
   pipeline the window backend runs (see platform/native/lui_window),
   with each stage driven and timed individually so a frame's cost can
   be attributed.

   Fidelity notes, mirroring platform/native/e2e:

   - Text is the deterministic stub measure (8 device px per byte, 16
     px line) unless the glyph-quad engine below is selected — real
     shaping is platform-bound, so measurements stay reproducible.
   - Scrolling is modelled exactly like the window driver: ancestor
     scroll offsets are summed and subtracted from each node's engine
     rect inside the paint [layout] hook — a scroll frame costs a
     paint + raster pass over the unchanged store, not a patch.
     [Lui_layout.sync] is called every frame because that is what
     [Lui_host.repaint] does in production; the memo makes the call
     free when the store revision and frame inputs are unchanged.
   - Raster uses [Lui_raster.Renderer], the damage-limited renderer a
     real window drives; the full-frame [Lui_raster.render] is kept
     alongside for before/after damage comparisons.
   - One worker throughout ([~workers:1]): deterministic single-core
     numbers like the gallery runner. *)

open Lui_scene

(* ---------- timing + samples ---------- *)

let now () = Unix.gettimeofday ()

let timed f =
  let t0 = now () in
  let r = f () in
  (r, (now () -. t0) *. 1000.)

type stats = {
  n : int;
  mean : float;
  p50 : float;
  p95 : float;
  min : float;
  max : float;
}

let stats_of samples =
  let a = Array.of_list samples in
  Array.sort Float.compare a;
  let n = Array.length a in
  let mean =
    if n = 0 then 0. else Array.fold_left ( +. ) 0. a /. float_of_int n
  in
  let pct p =
    if n = 0 then 0.
    else a.(min (n - 1) (int_of_float (p *. float_of_int (n - 1) +. 0.5)))
  in
  {
    n;
    mean;
    p50 = pct 0.5;
    p95 = pct 0.95;
    min = (if n = 0 then 0. else a.(0));
    max = (if n = 0 then 0. else a.(n - 1));
  }

(* ---------- harness ---------- *)

type t = {
  host : Lui_host.t; (* store + scene + apply_batch, no engine of its own *)
  engine : Lui_layout.t; (* this harness's own flex mirror *)
  scroll : (int, float) Hashtbl.t; (* node id -> scroll offset, device px *)
  renderer : Lui_raster.Renderer.t;
  mutable hooks : Lui_paint.hooks;
  retained : Lui_retained.retained;
  gcount : int ref; (* glyph records appended this paint (Quads engine) *)
  rev_glyphs : bool; (* Quads prepends records; [paint] unreverses once *)
  width : int;
  height : int;
  scale : float;
}

let store t = Lui_host.store t.host
let scene t = Lui_host.scene t.host
let engine t = t.engine

(* Deterministic measure shared by both text engines: 8 device px per
   byte, 16 px tall — the e2e contract. *)
let measure _id text _offered_w _offered_h =
  Some (8. *. float_of_int (String.length text), 16.)

(* Stub text engine: one [Glyphs] op per call, but an empty range —
   the stub appends no glyph records, and [Damage.update]'s op diff
   indexes [gstart..gend] into the glyphs array without clamping, so
   [gend] must stay inside what was appended. Paint still pays the op
   emission; raster has nothing to blit. *)
let stub_text_ops _id _r c _s =
  [
    Glyphs
      {
        gstart = 0;
        gend = 0;
        gpaint = Solid;
        gcolor = c;
        gcolor2 = c;
        ggradient = (0., 0., 0., 0.);
        gwide2 = 0;
        gopacity = 1.;
      };
  ]

(* Glyph-quad text engine: every byte becomes one 8x16 glyph record
   pointing at a shared mask-atlas slot, so paint and raster do real
   per-byte emission and blit work without a platform font stack. *)
type glyph_src = { slot : int * int * int * int } (* gu, gv, w, h *)

let glyph_slot scene =
  let a = scene.mask_atlas in
  match Atlas.alloc_last a 8 16 with
  | None -> None
  | Some (x, y) ->
    for row = 0 to 15 do
      Bytes.fill a.pix ((y + row) * a.w + x) 8 '\255'
    done;
    Some { slot = (x, y, 8, 16) }

(* Records are accumulated reversed ([rev_append] onto the head) so
   appending n glyphs is O(n) per call instead of O(total) — [paint]
   reverses the list once afterwards, and [gcount] tracks each call's
   start index into the final order. *)
let quad_text_ops gcount scene slot _id r c s =
  let gu, gv, gw, gh = slot.slot in
  let gstart = !gcount in
  let n = String.length s in
  let mine =
    List.init n (fun i ->
        {
          gx = r.x +. (float_of_int i *. 8.);
          gy = r.y;
          gw = float_of_int gw;
          gh = float_of_int gh;
          gu;
          gv;
          guw = gw;
          gvh = gh;
          gcolor = c;
          gwide = 0;
          gcolored = false;
          gsubpixel = false;
          gthin = false;
        })
  in
  gcount := gstart + n;
  scene.glyphs <- List.rev_append mine scene.glyphs;
  [
    Glyphs
      {
        gstart;
        gend = !gcount;
        gpaint = Solid;
        gcolor = c;
        gcolor2 = c;
        ggradient = (0., 0., 0., 0.);
        gwide2 = 0;
        gopacity = 1.;
      };
  ]

type text_engine = Stub | Quads

let create ?(text_engine = Stub) ~width ~height ~scale () =
  (* Scenarios share the process heap: garbage owed by an earlier
     scenario's mounts is otherwise collected inside the next
     scenario's timed stages. Force a full collection up front so each
     stage measures its own work. *)
  Gc.full_major ();
  let engine = Lui_layout.create () in
  let hooks = { Lui_paint.default_hooks with text_ops = stub_text_ops } in
  (* The host holds the store and scene; this harness drives layout,
     paint and raster itself so each stage can be timed — the renderer
     slot is a never-called sink. *)
  let host =
    Lui_host.create ~hooks ~measure
      ~renderer:{ render = (fun _ -> Bytes.empty); name = "perf-sink" }
      ~width ~height ~scale ()
  in
  let gcount = ref 0 in
  let t =
    {
      host;
      engine;
      scroll = Hashtbl.create 8;
      renderer = Lui_raster.Renderer.create ();
      hooks;
      retained = Lui_retained.create ();
      gcount;
      rev_glyphs = (text_engine = Quads);
      width;
      height;
      scale;
    }
  in
  (match text_engine with
  | Stub -> ()
  | Quads -> (
    match glyph_slot (scene t) with
    | None -> failwith "glyph atlas alloc failed"
    | Some slot ->
      t.hooks <-
        { t.hooks with text_ops = quad_text_ops gcount (scene t) slot }));
  t

(* Total ancestor scroll shift for a node — the same composition the
   window driver applies to engine rects ([scroll_shift_of] in
   platform/native/lui_window/main.ml). *)
let scroll_shift t id =
  let rec sum aid acc =
    let off =
      match Hashtbl.find_opt t.scroll aid with Some v -> v | None -> 0.
    in
    match Lui_store.parent (store t) aid with
    | Some p -> sum p (acc +. off)
    | None -> acc +. off
  in
  match Lui_store.parent (store t) id with
  | Some p -> sum p 0.
  | None -> 0.

let set_scroll t id off = Hashtbl.replace t.scroll id off

(* Anchor correction, the way the window driver applies it in
   populate: measurement drift folds back into the scroll offset so
   the top row keeps its screen position. *)
let apply_vlist_drift t id =
  let d = Lui_layout.virtual_take_drift t.engine id in
  if Float.abs d > 0.001 then
    set_scroll t id
      (Option.value ~default:0. (Hashtbl.find_opt t.scroll id) +. d)

(* Engine rect shifted by ancestor scroll offsets — what paint and hit
   tests see. *)
let rect_of t id =
  match Lui_layout.rect t.engine id with
  | None -> None
  | Some r -> Some { r with y = r.y -. scroll_shift t id }

(* Direct children of [root] whose shifted rect intersects [clip]:
   the rows a viewport actually covers. *)
let visible_children t ~root ~clip =
  Lui_store.child_ids (store t) root
  |> List.fold_left
       (fun n id ->
         match rect_of t id with
         | Some r
           when (not (rect_empty r)) && not (rect_empty (rect_intersect r clip)) ->
           n + 1
         | _ -> n)
       0

let paint_hooks t =
  let mounted_children = Lui_layout.mounted_children t.engine in
  if Hashtbl.length t.scroll = 0 then
    { t.hooks with
      layout = Lui_layout.layout_hook t.engine;
      mounted_children }
  else
    {
      t.hooks with
      mounted_children;
      layout =
        (fun id ->
          let p = Lui_layout.layout_hook t.engine id in
          let sy = scroll_shift t id in
          if sy = 0. then p
          else
            Lui_paint.placement_of_rect
              { p.p_rect with y = p.p_rect.y -. sy });
    }

(* Virtual-list viewport feed, same composition the window driver
   makes: the container's scroll offset plus how far the frame clip
   has scrolled into its shifted box. *)
let vport_of t id =
  if Lui_store.kind (store t) id <> "virtual-list" then None
  else begin
    let er =
      match Lui_layout.rect t.engine id with
      | Some r -> r
      | None -> rect 0. 0. 0. 0.
    in
    let shifted = { er with y = er.y -. scroll_shift t id } in
    let clip =
      rect_intersect shifted
        (rect 0. 0. (float_of_int t.width) (float_of_int t.height))
    in
    Some
      ( Option.value ~default:0. (Hashtbl.find_opt t.scroll id)
        +. Float.max 0. (clip.y -. shifted.y),
        Float.max 0. clip.h )
  end

(* Mounted window [first, last) and mounted row count for a virtual
   list id — the structural bound the scenarios assert. *)
let mounted_range t id = Lui_layout.mounted_range t.engine id
let mounted_count t id = Lui_layout.mounted_count t.engine id

(* ---------- timed stages (each returns elapsed ms) ---------- *)

let apply t batch =
  snd (timed (fun () -> ignore (Lui_host.apply_batch t.host batch)))

let layout t =
  snd
    (timed (fun () ->
         Lui_layout.sync ~scale:t.scale ~measure ~vport:(vport_of t)
           ~width:(float_of_int t.width)
           ~height:(float_of_int t.height) t.engine (store t)))

let paint t =
  t.gcount := 0;
  let ms =
    snd
      (timed (fun () ->
           Lui_paint.paint (paint_hooks t) (store t) (scene t)
             ~width:t.width ~height:t.height ~scale:t.scale
             ~clear:(color 0 0 0 0)))
  in
  if t.rev_glyphs then
    (scene t).glyphs <- List.rev (scene t).glyphs;
  ms

(* Damage-limited raster (production path): returns the damaged rect
   list plus elapsed ms. *)
let raster t = timed (fun () -> Lui_raster.Renderer.render ~workers:1 t.renderer (scene t))

(* Full-scene raster, no damage bookkeeping — the comparison point. *)
let raster_full t =
  snd (timed (fun () -> ignore (Lui_raster.render ~workers:1 ~scene:(scene t) ())))

let ops_count t = List.length (scene t).ops

(* Retained fragment pass — same frame inputs as {!paint}, driven the
   way [Lui_host.repaint] wires it: engine rect changes as [~moved]. *)
let paint_retained t =
  snd
    (timed (fun () ->
         Lui_retained.paint_retained t.retained (paint_hooks t) (store t)
           (scene t) ~moved:(Lui_layout.take_rect_changes t.engine)
           ~width:t.width ~height:t.height ~scale:t.scale
           ~clear:(color 0 0 0 0) ()))

let retained_repaints t = Lui_retained.stat_repaints t.retained
let retained_visits t = Lui_retained.stat_visits t.retained

(* ---------- resident memory ---------- *)

(* Current RSS in KiB: /proc on Linux, `ps` elsewhere (macOS/BSD).
   [None] when neither is readable — callers print n/a. *)
let rss_kb () =
  let from_proc () =
    if not (Sys.file_exists "/proc/self/status") then None
    else
      let ic = open_in "/proc/self/status" in
      let rec loop () =
        match input_line ic with
        | line
          when String.length line > 6
               && String.sub line 0 6 = "VmRSS:" -> (
          let v = String.trim (String.sub line 6 (String.length line - 6)) in
          let kb = int_of_string (List.hd (String.split_on_char ' ' (String.trim v))) in
          close_in_noerr ic;
          Some kb)
        | _ -> loop ()
        | exception End_of_file ->
          close_in_noerr ic;
          None
      in
      loop ()
  in
  let from_ps () =
    let ic =
      Unix.open_process_in
        (Printf.sprintf "ps -o rss= -p %d" (Unix.getpid ()))
    in
    match input_line ic with
    | line ->
      let st = Unix.close_process_in ic in
      (match st with
      | Unix.WEXITED 0 -> (
        try Some (int_of_string (String.trim line)) with _ -> None)
      | _ -> None)
    | exception _ -> None
  in
  match from_proc () with Some _ as r -> r | None -> from_ps ()
