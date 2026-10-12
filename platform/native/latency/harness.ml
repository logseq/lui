(* End-to-end latency harness: one action through the whole pipeline a
   real frame crosses —

     action dispatch
     -> Signal.stabilize      (reducer + view recompute -> queued ops)
     -> patch batch generated (Lui_runtime.flush -> backend.apply_batch)
     -> backend applied       (Lui_store.apply_batch)
     -> layout done           (Lui_layout.sync)
     -> scene ready           (Lui_paint.paint -> Lui_scene ops)
     -> present submitted     (Lui_raster.Renderer.render + damage upload)
     -> frame presented       (swap; immediate headless)

   Every timestamp is taken by the harness around public calls — no
   production instrumentation is added, so there is nothing to disable
   and zero overhead when the bench is not running. The frontend half
   is a real [Lui_app] (scheduler + runtime + reducer + view); the
   backend half is the same store -> layout -> paint -> raster +
   damage-upload path the window driver runs (platform/native/lui_window,
   [cpu_renderer]: Renderer.render -> per-rect update -> present).

   Fidelity notes, mirroring platform/native/perf + e2e:

   - Text is the deterministic stub measure (8 device px per byte, 16
     px line): real shaping is platform-bound, so measurements stay
     reproducible.
   - [Signal.stabilize] is driven explicitly before [Lui_app.flush] so
     the signal/render pass is timestamped separately from batch
     assembly; flush's own stabilize call then observes a settled
     graph, exactly the work split a driver sees when it flushes after
     dispatching an event.
   - "patch generated" is stamped at the backend's apply_batch entry —
     the batch literally exists in hand; "backend applied" is stamped
     when [Lui_host.apply_batch] returns (store mirror committed).
   - Present is the CPU path the window driver uses: damage-limited
     [Lui_raster.Renderer.render] followed by an upload of each damaged
     rect's rows into a standing framebuffer — what [Lui_blit.update]
     does into the SDL texture — then a swap that returns immediately
     (no vsync headless).
   - One worker throughout ([~workers:1]): deterministic single-core
     numbers like the perf runner.
   - [create] runs [Gc.full_major] first: scenarios share the process
     heap, so garbage owed by an earlier scenario's mounts would
     otherwise be collected inside the next scenario's timed stages. *)

open Lui_scene

(* ---------- timing + samples ---------- *)

let now () = Unix.gettimeofday ()

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

(* ---------- frame timestamps ---------- *)

(* One timestamp per pipeline stage, seconds since epoch. Stages a
   frame does not cross (a scroll frame emits no patch) collapse onto
   the previous stamp: their deltas contribute ~0, which is the honest
   cost of that stage for that frame. *)
type stamps = {
  action : float;          (* event/action handed to the app *)
  stabilized : float;      (* Signal graph settled, ops queued *)
  patch_generated : float; (* backend.apply_batch entered *)
  backend_applied : float; (* store mirror committed *)
  layout_done : float;     (* Lui_layout.sync returned *)
  scene_ready : float;     (* Lui_paint.paint filled the scene *)
  present_submitted : float; (* raster + damage upload issued *)
  presented : float;       (* swap returned *)
  patch_ops : int;         (* ops in the flushed batch (0 = no batch) *)
}

(* The plan's named metrics, derived from the stamps above (ms). *)
type metrics = {
  action_to_patch : float;
  patch_to_layout : float;
  layout_to_scene : float;
  scene_to_present : float;
  dirty_to_present : float;
  (* Sub-spans kept for attribution inside the headline metrics. *)
  signal_stabilize : float;  (* action -> stabilized *)
  patch_apply : float;       (* patch generated -> backend applied *)
  patch_ops : int;
}

let metrics_of s =
  let ms a b = (b -. a) *. 1000. in
  {
    action_to_patch = ms s.action s.patch_generated;
    patch_to_layout = ms s.patch_generated s.layout_done;
    layout_to_scene = ms s.layout_done s.scene_ready;
    scene_to_present = ms s.scene_ready s.present_submitted;
    dirty_to_present = ms s.action s.presented;
    signal_stabilize = ms s.action s.stabilized;
    patch_apply = ms s.patch_generated s.backend_applied;
    patch_ops = s.patch_ops;
  }

(* ---------- harness ---------- *)

type t = {
  host : Lui_host.t; (* store + scene + apply_batch, no engine of its own *)
  engine : Lui_layout.t;
  renderer : Lui_raster.Renderer.t;
  screen : Bytes.t; (* present target the damage upload blits into *)
  hooks : Lui_paint.hooks;
  scroll : (int, float) Hashtbl.t; (* host-side scroll offsets (production model) *)
  mutable hovered : int; (* node id the state_of hook reports hovered *)
  mutable batch_in : float; (* apply_batch entry stamp *)
  mutable batch_out : float; (* apply_batch exit stamp *)
  mutable batch_seen : bool;
  mutable batch_ops : int;
  transport : Lui_wire.transport; (* how batches reach the store apply *)
  width : int;
  height : int;
  scale : float;
}

let store t = Lui_host.store t.host
let scene t = Lui_host.scene t.host

(* [~transport] picks the delivery path at the backend seam (P1-4):
   [In_process] hands the batch over as a value (production), [Wire]
   routes it through encode -> decode first — what a bridged host
   pays — so scenarios can run and measure both. *)
let apply ?(transport = Lui_wire.In_process) t batch =
  Lui_host.apply_batch t.host (Lui_wire.transcode transport batch)
let set_hovered t id = t.hovered <- id

(* Deterministic measure: 8 device px per byte, 16 px tall — the
   e2e/perf contract. *)
let measure _id text _offered_w _offered_h =
  Some (8. *. float_of_int (String.length text), 16.)

(* Stub text engine: one [Glyphs] op per call with an empty range —
   see the note in platform/native/perf/harness.ml about [gend]. *)
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

let create ?(transport = Lui_wire.In_process) ~width ~height ~scale () =
  Gc.full_major ();
  (* The host's own hook/renderer slots are never exercised — the
     harness drives layout, paint and raster itself so each stage can
     be timestamped (same split as platform/native/perf). *)
  let t =
    {
      host =
        Lui_host.create ~hooks:Lui_paint.default_hooks ~measure
          ~renderer:{ render = (fun _ -> Bytes.empty); name = "latency-sink" }
          ~width ~height ~scale ();
      engine = Lui_layout.create ();
      renderer = Lui_raster.Renderer.create ();
      screen = Bytes.make (width * height * 4) '\000';
      hooks =
        { Lui_paint.default_hooks with text_ops = stub_text_ops };
      scroll = Hashtbl.create 8;
      hovered = 0;
      batch_in = 0.;
      batch_out = 0.;
      batch_seen = false;
      batch_ops = 0;
      transport;
      width;
      height;
      scale;
    }
  in
  t

(* The backend record Lui_app.create consumes: stamps the batch on the
   way into the real store apply, so "patch generated" and "backend
   applied" split inside one flush without touching the runtime. *)
let backend t profile =
  {
    Lui_protocol.backend_profile = profile;
    apply_batch =
      (fun batch ->
        t.batch_in <- now ();
        t.batch_seen <- true;
        t.batch_ops <- List.length batch.Lui_protocol.ops;
        (* The transport's transcoding is part of "backend applied": a
           wire-mode frame prices encode -> decode -> store apply. *)
        let ok =
          Lui_host.apply_batch t.host
            (Lui_wire.transcode t.transport batch)
        in
        t.batch_out <- now ();
        ok);
  }

(* Total ancestor scroll shift for a node — the same composition the
   window driver applies to engine rects. *)
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

let paint_hooks t =
  let hooks =
    {
      t.hooks with
      state_of =
        (fun id ->
          if id = t.hovered then
            { Lui_paint.state_neutral with hovered = true }
          else Lui_paint.state_neutral);
    }
  in
  if Hashtbl.length t.scroll = 0 then
    { hooks with layout = Lui_layout.layout_hook t.engine }
  else
    {
      hooks with
      layout =
        (fun id ->
          let p = Lui_layout.layout_hook t.engine id in
          let sy = scroll_shift t id in
          if sy = 0. then p
          else
            Lui_paint.placement_of_rect
              { p.p_rect with y = p.p_rect.y -. sy });
    }

(* Damage upload + swap: what the window's CPU rung does inside its
   render callback (Lui_blit.update per damaged rect, then present).
   Rows of each damaged rect are copied from the raster image into the
   standing screen framebuffer. *)
let upload_damage t img dirty =
  let stride = img.Lui_raster.Image.stride in
  List.iter
    (fun (r : Lui_scene.irect) ->
      let w = r.x1 - r.x0 in
      if w > 0 then
        for y = r.y0 to r.y1 - 1 do
          let off = (y * stride) + (r.x0 * 4) in
          Bytes.blit img.Lui_raster.Image.pix off t.screen off (w * 4)
        done)
    dirty

(* Backend half of a frame, shared by app-driven and store-driven
   scenarios: layout -> paint -> raster + upload -> swap. [t0] is the
   earliest stamp the frame already has; the returned record's earlier
   fields are back-filled by the caller. *)
let repaint t s =
  Lui_layout.sync ~scale:t.scale ~measure
    ~width:(float_of_int t.width)
    ~height:(float_of_int t.height) t.engine (store t);
  let layout_done = now () in
  Lui_paint.paint (paint_hooks t) (store t) (scene t)
    ~width:t.width ~height:t.height ~scale:t.scale
    ~clear:(color 0 0 0 0);
  let scene_ready = now () in
  let dirty = Lui_raster.Renderer.render ~workers:1 t.renderer (scene t) in
  let img = Lui_raster.Renderer.image t.renderer in
  upload_damage t img dirty;
  let present_submitted = now () in
  (* The swap returns immediately headless — no vsync to wait on. *)
  let presented = now () in
  {
    s with
    layout_done;
    scene_ready;
    present_submitted;
    presented;
  }

(* Full e2e frame through a real app: [act] hands the action over
   (send or dispatch_event), signal stabilization recomputes the view,
   flush emits the batch through the stamping backend, then the
   backend half runs. *)
let run_frame t app ~act =
  let action = now () in
  act ();
  Signal.stabilize app.Lui_app.app_scheduler;
  let stabilized = now () in
  t.batch_seen <- false;
  t.batch_ops <- 0;
  ignore (Lui_app.flush app);
  (* A frame with no batch (dispatch swallowed, unchanged signal)
     collapses the patch stamps onto the flush boundary: their deltas
     then read ~0, the true cost of that stage for the frame. *)
  let patch_generated, backend_applied, patch_ops =
    if t.batch_seen then (t.batch_in, t.batch_out, t.batch_ops)
    else
      let ts = now () in
      (ts, ts, 0)
  in
  repaint t
    {
      action;
      stabilized;
      patch_generated;
      backend_applied;
      layout_done = 0.;
      scene_ready = 0.;
      present_submitted = 0.;
      presented = 0.;
      patch_ops;
    }

(* Store-driven frame (scroll): no app, no patch — the production
   scroll model where the offset lives host-side and a frame costs a
   repaint over an unchanged store. The patch stamps collapse onto the
   action stamp. *)
let run_repaint_frame t ~act =
  let action = now () in
  act ();
  repaint t
    {
      action;
      stabilized = action;
      patch_generated = action;
      backend_applied = action;
      layout_done = 0.;
      scene_ready = 0.;
      present_submitted = 0.;
      presented = 0.;
      patch_ops = 0;
    }

(* Store traversal helpers for locating nodes the app mounted. *)
let nodes_of_kind store kind =
  List.filter_map
    (fun n ->
      if Lui_store.node_kind n = kind then Some (Lui_store.node_id n)
      else None)
    (Lui_store.all_nodes store)

let find_kind store kind =
  match nodes_of_kind store kind with
  | id :: _ -> id
  | [] -> invalid_arg ("latency: no node of kind " ^ kind)
