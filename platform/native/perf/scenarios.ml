(* Perf scenarios: each returns markdown rows
   [scenario | metric | value | unit]. Sizes are the spec's: virtual
   list 10k/50k/100k, damage tree 5k, text frame 500 leaves, first
   frame 10k, memory at 100k. *)

open Lui_protocol
module H = Harness

type row = {
  scenario : string;
  metric : string;
  value : string;
  unit_ : string;
}

let row scenario metric value unit_ = { scenario; metric; value; unit_ }
let ms_row scenario metric ms = row scenario metric (Printf.sprintf "%.2f" ms) "ms"
let f2 = Printf.sprintf "%.2f"

(* ---------- patch builders ---------- *)

let row_bg i = if i land 1 = 0 then "#2a2d33" else "#23262b"

(* Mount: root > virtual-list > n list-item rows. The virtual list is
   content-sized like a real scroll container — giving it a definite
   height would make flex shrink every child into the box (browser
   rule in lui_flex) instead of letting them overflow. The viewport
   here is the frame itself, same as a real window. Children are
   inserted at ascending indices — the same op stream a frontend
   emits — so the apply stage reflects the store's real mount cost. *)
let mount_vlist ~n ~item_h =
  let ops =
    ref
      [
        InsertChild (1, 2, 0);
        CreateNode (2, VirtualList);
        CreateNode (1, Root);
      ]
  in
  for i = 0 to n - 1 do
    let id = 10 + i in
    (* Ops are pushed tail-first onto [!ops] so [List.rev] emits
       CreateNode > SetProps > InsertChild. *)
    ops := CreateNode (id, ListItem) :: !ops;
    ops := SetProp (id, HeightValue, FloatValue item_h) :: !ops;
    ops :=
      SetProp (id, TextValue, StringValue (Printf.sprintf "row %d" i))
      :: !ops;
    ops := SetProp (id, BackgroundValue, StringValue (row_bg i)) :: !ops;
    ops := InsertChild (2, id, i) :: !ops
  done;
  { generation = 1; ops = List.rev !ops }

(* Flat tree: root > column > n rows (bg + text + fixed height). *)
let mount_rows ~n ~item_h ~text =
  let ops =
    ref
      [
        InsertChild (1, 2, 0); CreateNode (2, Column); CreateNode (1, Root);
      ]
  in
  for i = 0 to n - 1 do
    let id = 10 + i in
    ops := CreateNode (id, Row) :: !ops;
    ops := SetProp (id, HeightValue, FloatValue item_h) :: !ops;
    ops := SetProp (id, BackgroundValue, StringValue (row_bg i)) :: !ops;
    (match text with
    | Some s -> ops := SetProp (id, TextValue, StringValue s) :: !ops
    | None -> ());
    ops := InsertChild (2, id, i) :: !ops
  done;
  { generation = 1; ops = List.rev !ops }

let mount_texts ~n ~len =
  let body = String.make len 'x' in
  let ops =
    ref
      [
        InsertChild (1, 2, 0); CreateNode (2, Column); CreateNode (1, Root);
      ]
  in
  for i = 0 to n - 1 do
    let id = 10 + i in
    ops := CreateNode (id, Text) :: !ops;
    ops :=
      SetProp
        (id, TextValue, StringValue (Printf.sprintf "%d %s" i body))
      :: !ops;
    ops := InsertChild (2, id, i) :: !ops
  done;
  { generation = 1; ops = List.rev !ops }

(* ---------- scenarios ---------- *)

(* Virtual list: mount n rows, then scroll at a constant velocity for
   [frames] frames. Scrolling shifts children's placements through the
   paint hook (production model) — the store is untouched, so patch
   apply is zero, and the memoized [Lui_layout.sync] returns
   immediately on a scroll frame (the production model too: repaint
   re-syncs every frame, the memo is what makes that cheap). *)
let vlist ~n ~frames ~velocity ~item_h ~width ~height =
  let name = Printf.sprintf "vlist-%dk" (n / 1000) in
  let t = H.create ~width ~height ~scale:1. () in
  let mount = mount_vlist ~n ~item_h in
  let mount_ms = H.apply t mount in
  let mlayout = H.layout t in
  let mpaint = H.paint t in
  let _, mraster = H.raster t in
  let la, pa, ra, ta = (ref [], ref [], ref [], ref []) in
  for f = 1 to frames do
    H.set_scroll t 2 (velocity *. float_of_int f);
    let t0 = H.now () in
    la := H.layout t :: !la;
    pa := H.paint t :: !pa;
    let _, rms = H.raster t in
    ra := rms :: !ra;
    ta := (H.now () -. t0) *. 1000. :: !ta
  done;
  (* The window itself is the viewport: paint culls nodes whose box
     misses the frame, so only the visible window emits ops — count
     children inside it to confirm the cull. *)
  let viewport = Lui_scene.rect 0. 0. (float_of_int width) (float_of_int height) in
  let visible = H.visible_children t ~root:2 ~clip:viewport in
  let ops = H.ops_count t in
  [
    ms_row name "mount patch apply" mount_ms;
    ms_row name "mount layout" mlayout;
    ms_row name "mount paint" mpaint;
    ms_row name "mount raster" mraster;
    ms_row name "frame apply p50" 0.;
    ms_row name "frame layout p50" (H.stats_of !la).p50;
    ms_row name "frame paint p50" (H.stats_of !pa).p50;
    ms_row name "frame raster p50" (H.stats_of !ra).p50;
    ms_row name "frame total p50" (H.stats_of !ta).p50;
    ms_row name "frame total p95" (H.stats_of !ta).p95;
    row name "visible children" (string_of_int visible) "nodes";
    row name "scene ops/frame" (string_of_int ops) "ops";
  ]

(* Damage-limited re-render: flip one node's color inside a 5k-node
   tree; the damage-limited renderer should touch only the flipped
   rect. Reports damaged rect count and limited vs full raster time. *)
let damage ~n ~item_h ~width ~height =
  let name = "damage-5k" in
  let t = H.create ~width ~height ~scale:1. () in
  let mount_ms = H.apply t (mount_rows ~n ~item_h ~text:None) in
  let mlayout = H.layout t in
  let mpaint = H.paint t in
  let _, mraster = H.raster t in
  let flips = 5 in
  let la, ra_l, ra_f, dcount = (ref [], ref [], ref [], ref []) in
  (* The flipped node must sit inside the viewport — paint culls
     children outside it, so an off-screen prop change legitimately
     diffs to nothing. Row index 20 lands mid-window at 20 px rows. *)
  let target = 10 + min 20 (n - 1) in
  for i = 0 to flips - 1 do
    let c = if i land 1 = 0 then "#ff5030" else "#2a2d33" in
    let apply_ms =
      H.apply t
        {
          generation = 2 + i;
          ops = [ SetProp (target, BackgroundValue, StringValue c) ];
        }
    in
    la := apply_ms :: !la;
    ignore (H.paint t);
    let damaged, limited = H.raster t in
    ra_l := limited :: !ra_l;
    dcount := float_of_int (List.length damaged) :: !dcount;
    ra_f := H.raster_full t :: !ra_f
  done;
  [
    ms_row name "mount patch apply" mount_ms;
    ms_row name "mount layout" mlayout;
    ms_row name "mount paint" mpaint;
    ms_row name "mount raster" mraster;
    ms_row name "flip apply p50" (H.stats_of !la).p50;
    ms_row name "damaged raster p50" (H.stats_of !ra_l).p50;
    ms_row name "full raster p50" (H.stats_of !ra_f).p50;
    row name "damaged rects"
      (f2 (H.stats_of !dcount).mean)
      "rects";
  ]

(* Text-heavy frame: 500 text leaves through the glyph-quad engine —
   real per-byte glyph emission and blit, deterministic layout. *)
let text ~n ~len ~width ~height =
  let name = "text-500" in
  let t = H.create ~text_engine:H.Quads ~width ~height ~scale:1. () in
  let mount_ms = H.apply t (mount_texts ~n ~len) in
  let layout_ms = H.layout t in
  let paint_ms = H.paint t in
  let _, raster_ms = H.raster t in
  let glyphs = List.length (H.scene t).glyphs in
  [
    ms_row name "patch apply" mount_ms;
    ms_row name "layout+measure" layout_ms;
    ms_row name "paint+shape" paint_ms;
    ms_row name "raster+blit" raster_ms;
    row name "glyphs" (string_of_int glyphs) "glyphs";
    row name "scene ops" (string_of_int (H.ops_count t)) "ops";
  ]

(* First frame on a 10k-node initial patch: apply through pixels. *)
let first_frame ~n ~item_h ~width ~height =
  let name = "first-frame-10k" in
  let t = H.create ~width ~height ~scale:1. () in
  let t0 = H.now () in
  let apply_ms = H.apply t (mount_rows ~n ~item_h ~text:(Some "row")) in
  let layout_ms = H.layout t in
  let paint_ms = H.paint t in
  let _, raster_ms = H.raster t in
  let total = (H.now () -. t0) *. 1000. in
  [
    ms_row name "patch apply" apply_ms;
    ms_row name "layout" layout_ms;
    ms_row name "paint" paint_ms;
    ms_row name "raster" raster_ms;
    ms_row name "total" total;
  ]

(* RSS across a 100k-node patch: resident set before apply, after
   apply, and after the first full frame. KiB -> MiB. *)
let memory ~n ~item_h ~width ~height =
  let name = "rss-100k" in
  let mb = function
    | Some kb -> Printf.sprintf "%.1f" (float_of_int kb /. 1024.)
    | None -> "n/a"
  in
  let t = H.create ~width ~height ~scale:1. () in
  let batch = mount_vlist ~n ~item_h in
  let before = H.rss_kb () in
  let apply_ms = H.apply t batch in
  let after_apply = H.rss_kb () in
  ignore (H.layout t);
  ignore (H.paint t);
  ignore (H.raster t);
  let after_frame = H.rss_kb () in
  [
    row name "RSS before apply" (mb before) "MiB";
    ms_row name "patch apply" apply_ms;
    row name "RSS after apply" (mb after_apply) "MiB";
    row name "apply delta"
      (match (before, after_apply) with
      | Some b, Some a -> Printf.sprintf "%.1f" (float_of_int (a - b) /. 1024.)
      | _ -> "n/a")
      "MiB";
    row name "RSS after first frame" (mb after_frame) "MiB";
  ]

(* Pointer-event cost over a mounted virtual list: the store is
   static and the hit mirror is resolved once, then every pointer
   event pays one point query. The unindexed path walks the whole
   tree; the spatial index descends only toward the hit band. Also
   reports an indexed static-frame paint — the viewport-cull case the
   same index serves. *)
let hit ~n ~item_h ~width ~height =
  let name = Printf.sprintf "hit-%dk" (n / 1000) in
  let t = H.create ~width ~height ~scale:1. () in
  ignore (H.apply t (mount_vlist ~n ~item_h));
  ignore (H.layout t);
  ignore (H.paint t);
  (* The mirror the window driver's populate fills: resolved rects —
     shifted engine rects here, resolve_rect is identity for these
     plain rows. *)
  let rects = Lui_query.Rects.create () in
  List.iter
    (fun id ->
      match H.rect_of t id with
      | Some r -> Hashtbl.replace rects id r
      | None -> ())
    (Lui_store.preorder (H.store t));
  let idx =
    Lui_spatial.build Lui_paint.spatial_env (H.store t)
      ~rect_of:(Lui_query.Rects.get rects)
  in
  (* Probe points: three depths inside the visible viewport. *)
  let probes =
    [ (float_of_int width *. 0.5, 20.);
      (float_of_int width *. 0.5, float_of_int height *. 0.5);
      (float_of_int width *. 0.9, float_of_int height -. 20.) ]
  in
  let iters = 30 in
  let time_hits spatial =
    let acc = ref [] in
    for _ = 1 to iters do
      let t0 = H.now () in
      List.iter
        (fun (x, y) ->
          ignore (Lui_query.hit_path ?spatial (H.store t) rects ~x ~y))
        probes;
      acc := (H.now () -. t0) *. 1000. :: !acc
    done;
    H.stats_of !acc
  in
  let unindexed = time_hits None in
  let indexed = time_hits (Some idx) in
  (* Static-frame paint with a warm index: what a hover-only repaint
     costs once geometry is already indexed. *)
  let paint_idx =
    let acc = ref [] in
    for _ = 1 to 10 do
      let t0 = H.now () in
      Lui_paint.paint ~spatial:idx (H.paint_hooks t) (H.store t)
        (H.scene t) ~width ~height ~scale:1. ~clear:(Lui_scene.color 0 0 0 0);
      acc := (H.now () -. t0) *. 1000. :: !acc
    done;
    H.stats_of !acc
  in
  [
    ms_row name "hit_path p50" unindexed.p50;
    ms_row name "hit_path p50 indexed" indexed.p50;
    ms_row name "paint static p50 indexed" paint_idx.p50;
    ms_row name "index build"
      (snd
         (H.timed (fun () ->
              ignore
                (Lui_spatial.build Lui_paint.spatial_env (H.store t)
                   ~rect_of:(Lui_query.Rects.get rects)))));
  ]

(* Retained fragments: one visible node's color flips on a static
   n-node tree — the P0-3 acceptance case. The fragment pass re-derives
   only that node; the flat scene materialize still walks ops. *)
let retained ~n ~item_h ~width ~height =
  let name = Printf.sprintf "retained-%dk" (n / 1000) in
  let t = H.create ~width ~height ~scale:1. () in
  ignore (H.apply t (mount_rows ~n ~item_h ~text:(Some "row")));
  ignore (H.layout t);
  ignore (H.paint_retained t);
  let flips = 10 in
  let target = 10 + min 20 (n - 1) in
  let pa, rp = (ref [], ref []) in
  for i = 0 to flips - 1 do
    let c = if i land 1 = 0 then "#ff5030" else "#2a2d33" in
    ignore
      (H.apply t
         { generation = 2 + i;
           ops = [ SetProp (target, BackgroundValue, StringValue c) ] });
    let r0 = H.retained_repaints t in
    pa := H.paint_retained t :: !pa;
    rp := float_of_int (H.retained_repaints t - r0) :: !rp
  done;
  let full = H.paint t in
  [
    ms_row name "full paint (same frame)" full;
    ms_row name "retained paint p50" (H.stats_of !pa).p50;
    ms_row name "retained paint p95" (H.stats_of !pa).p95;
    row name "nodes repainted/frame"
      (f2 (H.stats_of !rp).mean)
      "nodes";
  ]

(* ---------- suite ---------- *)

let default_width = 1280
let default_height = 800

(* [?scale_sizes:false] runs the small variant used by the test suite —
   same code paths, bounded run time. *)
let all ?(scale_sizes = false) () =
  let w, h = (default_width, default_height) in
  let frames, vlists =
    if scale_sizes then (8, [ 10_000 ]) else (30, [ 10_000; 50_000; 100_000 ])
  in
  let n5, n10, ntx, nrss =
    if scale_sizes then (2_000, 2_000, 500, 20_000)
    else (5_000, 10_000, 500, 100_000)
  in
  List.concat
    [
      List.concat
        (List.map
           (fun n ->
             vlist ~n ~frames ~velocity:40. ~item_h:28. ~width:w ~height:h)
           vlists);
      damage ~n:n5 ~item_h:20. ~width:w ~height:h;
      hit ~n:(List.nth vlists (List.length vlists - 1)) ~item_h:28.
        ~width:w ~height:h;
      text ~n:ntx ~len:48 ~width:w ~height:h;
      first_frame ~n:n10 ~item_h:20. ~width:w ~height:h;
      List.concat
        (List.map
           (fun n -> retained ~n ~item_h:20. ~width:w ~height:h)
           (if scale_sizes then [ 10_000 ] else [ 10_000; 100_000 ]));
      memory ~n:nrss ~item_h:28. ~width:w ~height:h;
    ]

let to_markdown rows =
  let b = Buffer.create 4096 in
  Buffer.add_string b "| scenario | metric | value | unit |\n";
  Buffer.add_string b "|---|---|---|---|\n";
  List.iter
    (fun r ->
      Buffer.add_string b
        (Printf.sprintf "| %s | %s | %s | %s |\n" r.scenario r.metric
           r.value r.unit_))
    rows;
  Buffer.contents b
