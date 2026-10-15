(* End-to-end latency scenarios (plan P0-4): each drives real actions
   through the whole frame path —

     action -> Signal.stabilize -> Lui_runtime patch batch
     -> Lui_host store apply -> Lui_layout -> Lui_paint
     -> Lui_raster damage render + upload -> present

   and reports the plan's named metrics (action_to_patch,
   patch_to_layout, layout_to_scene, scene_to_present,
   dirty_to_present) at p50/p95, plus the signal-stabilize and
   patch-apply sub-spans for attribution.

   Scenario roster is the plan's:

   - typing            TextChanged event -> draft model -> field + summary patch
   - toggle            ToggleChanged event -> checked prop patch
   - hover             PointerEnter/Leave -> hovered model -> background patch
   - blocks-10k-text   one block's text edit inside a 10k keyed list
   - blocks-10k-insert one row inserted mid-list inside the same 10k list
   - vlist-100k-scroll wheel-equivalent scroll frame over a 100k virtual list
   - collapse-expand   subtree mount/unmount through if_ on a bool signal
   - ime-compose       composition-cadence TextChanged updates

   Sizes follow the spec (10k blocks, 100k list); [--small] bounds them
   for the regression suite. *)

open Lui_elements
open Lui_protocol
module H = Harness

type row = {
  scenario : string;
  metric : string;
  value : string;
  unit_ : string;
}

let mrow scenario metric value unit_ = { scenario; metric; value; unit_ }
let ms_row scenario metric ms = mrow scenario metric (Printf.sprintf "%.3f" ms) "ms"
let f2 = Printf.sprintf "%.2f"

(* ---------- app boot + sample collection ---------- *)

let boot_app t model update view =
  let app =
    Lui_app.create
      (H.backend t (generic_profile ()))
      model update view
  in
  ignore (Lui_app.start app);
  ignore (Lui_app.flush app);
  (* One untimed repaint so measured frames start from a steady scene. *)
  ignore (H.run_repaint_frame t ~act:(fun () -> ()));
  app

let collect t app ~warmup ~iters ~act =
  for _ = 1 to warmup do
    ignore (H.run_frame t app ~act:(fun () -> act (-1)))
  done;
  List.init iters (fun i -> H.metrics_of (H.run_frame t app ~act:(fun () -> act i)))

let metric_rows name (samples : H.metrics list) =
  let sel f = H.stats_of (List.map f samples) in
  [
    ms_row name "action_to_patch p50" (sel (fun m -> m.H.action_to_patch)).H.p50;
    ms_row name "action_to_patch p95" (sel (fun m -> m.action_to_patch)).H.p95;
    ms_row name "patch_to_layout p50" (sel (fun m -> m.patch_to_layout)).H.p50;
    ms_row name "patch_to_layout p95" (sel (fun m -> m.patch_to_layout)).H.p95;
    ms_row name "layout_to_scene p50" (sel (fun m -> m.layout_to_scene)).H.p50;
    ms_row name "layout_to_scene p95" (sel (fun m -> m.layout_to_scene)).H.p95;
    ms_row name "scene_to_present p50" (sel (fun m -> m.scene_to_present)).H.p50;
    ms_row name "scene_to_present p95" (sel (fun m -> m.scene_to_present)).H.p95;
    ms_row name "dirty_to_present p50" (sel (fun m -> m.dirty_to_present)).H.p50;
    ms_row name "dirty_to_present p95" (sel (fun m -> m.dirty_to_present)).H.p95;
    ms_row name "signal_stabilize p50" (sel (fun m -> m.signal_stabilize)).H.p50;
    ms_row name "patch_apply p50" (sel (fun m -> m.patch_apply)).H.p50;
    mrow name "patch ops p50"
      (f2 (sel (fun m -> float_of_int m.patch_ops)).p50)
      "ops";
    mrow name "iters" (string_of_int (List.length samples)) "frames";
  ]

(* ---------- typing + IME composition ---------- *)

module Draft = struct
  type model = { draft : string }
  type action = Draft of string

  let initial = { draft = "" }
  let update _model (Draft draft) = { draft }

  let view _ctx model_s send : t =
    column ~gap:4 ~padding:8
      [
        text
          ~value:
            (reactive
               (fun m -> Printf.sprintf "chars:%d" (String.length m.draft))
               model_s)
          [];
        text_field
          ~text:(reactive (fun m -> m.draft) model_s)
          ~placeholder:"type here" ~label:"Draft"
          ~on_input:(on_input send (fun s -> Draft s))
          [];
      ]
end

let typing_like ~name ~iters ~width ~height ~text_of_iter =
  let t = H.create ~width ~height ~scale:1. () in
  let t0 = H.now () in
  let app = boot_app t Draft.initial Draft.update Draft.view in
  let mount_ms = (H.now () -. t0) *. 1000. in
  let fid = H.find_kind (H.store t) "text-field" in
  let samples =
    collect t app ~warmup:3 ~iters ~act:(fun i ->
        ignore
          (Lui_app.dispatch_event app (TextChanged (fid, text_of_iter i))))
  in
  ms_row name "mount e2e" mount_ms :: metric_rows name samples

(* One keystroke per frame, like real typing. *)
let typing ~iters ~width ~height =
  typing_like ~name:"typing" ~iters ~width ~height
    ~text_of_iter:(fun i -> Printf.sprintf "the quick brown fox %d" i)

(* IME composition cadence: repeated marked-text updates inside one
   composition, then a commit. Host-side marked-text/caret state is the
   P1-2 protocol's scope; today composition updates reach the app as
   the same TextChanged events, so this measures the OCaml-side cost a
   composition actually pays per update. *)
let ime_compose ~iters ~width ~height =
  let stages = [| "n"; "ni"; "nih"; "niha"; "nihao" |] in
  typing_like ~name:"ime-compose" ~iters ~width ~height
    ~text_of_iter:(fun i ->
      let i = max 0 i in
      if i mod 6 = 5 then "ni hao " ^ string_of_int (i / 6)
      else stages.(i mod 6))

(* ---------- toggle ---------- *)

module Toggle = struct
  type model = { on : bool }
  type action = Flip

  let initial = { on = false }
  let update model Flip = { on = not model.on }

  let view _ctx model_s send : t =
    column ~gap:4 ~padding:8
      [
        toggle ~text:"enabled"
          ~checked:(reactive (fun m -> m.on) model_s)
          ~on_toggle:(press send Flip)
          ~label:"Feature"
          [];
        text
          ~value:(reactive (fun m -> if m.on then "state:on" else "state:off") model_s)
          [];
      ]
end

let toggle_case ~iters ~width ~height =
  let name = "toggle" in
  let t = H.create ~width ~height ~scale:1. () in
  let t0 = H.now () in
  let app = boot_app t Toggle.initial Toggle.update Toggle.view in
  let mount_ms = (H.now () -. t0) *. 1000. in
  let tid = H.find_kind (H.store t) "toggle" in
  let samples =
    collect t app ~warmup:3 ~iters ~act:(fun i ->
        ignore
          (Lui_app.dispatch_event app (ToggleChanged (tid, i land 1 = 0))))
  in
  ms_row name "mount e2e" mount_ms :: metric_rows name samples

(* ---------- hover ---------- *)

module Hover = struct
  type model = { hov : bool }
  type action = Hover of bool

  let initial = { hov = false }
  let update _model (Hover hov) = { hov }

  let view _ctx model_s send : t =
    column ~gap:4 ~padding:8
      [
        button ~text:"target"
          ~background:
            (reactive
               (fun m -> if m.hov then "#3a6ea5" else "#33415c")
               model_s)
          ~on_pointer_enter:(fun _ -> ignore (send (Hover true)))
          ~on_pointer_leave:(fun _ -> ignore (send (Hover false)))
          [];
      ]
end

(* A hover frame both dispatches PointerEnter/Leave (the app sees the
   event, the model flips, a background patch lands) and moves the
   host-side hovered id the paint hooks resolve — the two halves of a
   real hover. *)
let hover ~iters ~width ~height =
  let name = "hover" in
  let t = H.create ~width ~height ~scale:1. () in
  let t0 = H.now () in
  let app = boot_app t Hover.initial Hover.update Hover.view in
  let mount_ms = (H.now () -. t0) *. 1000. in
  let bid = H.find_kind (H.store t) "button" in
  let samples =
    collect t app ~warmup:3 ~iters ~act:(fun i ->
        let enter = i land 1 = 0 in
        H.set_hovered t (if enter then bid else 0);
        ignore
          (Lui_app.dispatch_event app
             (if enter then PointerEnter bid else PointerLeave bid)))
  in
  ms_row name "mount e2e" mount_ms :: metric_rows name samples

(* ---------- 10k blocks: single text edit + insert ---------- *)

module Blocks = struct
  type block = {
    bid : int;
    txt : string;
  }

  type model = { blocks : block list }

  type action =
    | Edit of int * string
    | Insert of int * int * string (* position, fresh id, text *)

  let make n =
    {
      blocks =
        List.init n (fun i ->
            { bid = i; txt = Printf.sprintf "block %d content" i });
    }

  let update model = function
    | Edit (k, s) ->
      {
        blocks =
          List.map
            (* Unchanged blocks keep their record identity: keyed sees
               them as [==] and only the edited item republishes. *)
            (fun b -> if b.bid = k then { b with txt = s } else b)
            model.blocks;
      }
    | Insert (pos, id, s) ->
      let rec go i = function
        | bs when i <= 0 -> { bid = id; txt = s } :: bs
        | [] -> [ { bid = id; txt = s } ]
        | b :: rest -> b :: go (i - 1) rest
      in
      { blocks = go pos model.blocks }

  let view _ctx model_s _send : t =
    scroll
      [
        keyed
          ~source:(reactive (fun m -> m.blocks) model_s)
          ~key:(fun b -> b.bid)
          ~cmp:Int.compare
          ~mount:(fun item_s ->
            row ~height:20
              [ text ~value:(reactive (fun b -> b.txt) item_s) [] ]);
      ]
end

(* One boot, two measured phases on the same 10k list. *)
let blocks ~n ~iters ~width ~height =
  let t = H.create ~width ~height ~scale:1. () in
  let t0 = H.now () in
  let app = boot_app t (Blocks.make n) Blocks.update Blocks.view in
  let mount_ms = (H.now () -. t0) *. 1000. in
  let target = n / 2 in
  let edit_samples =
    collect t app ~warmup:2 ~iters ~act:(fun i ->
        ignore
          (Lui_app.send app
             (Blocks.Edit (target, Printf.sprintf "edited text %d" i))))
  in
  let fresh_id = ref n in
  let insert_pos = ref (n / 4) in
  let insert_samples =
    collect t app ~warmup:2 ~iters ~act:(fun i ->
        incr fresh_id;
        let id = !fresh_id in
        let pos = min !insert_pos (n + max 0 i) in
        incr insert_pos;
        ignore
          (Lui_app.send app
             (Blocks.Insert (pos, id, Printf.sprintf "inserted %d" i))))
  in
  let name_edit = Printf.sprintf "blocks-%dk-text" (n / 1000) in
  let name_ins = Printf.sprintf "blocks-%dk-insert" (n / 1000) in
  (ms_row name_edit "mount e2e" mount_ms :: metric_rows name_edit edit_samples)
  @ metric_rows name_ins insert_samples

(* ---------- 100k virtual list scroll ---------- *)

(* The same mount op stream the frontend emits (see
   platform/native/perf/scenarios.ml — kept in sync deliberately so the
   two harnesses measure the same tree): root > virtual-list > n
   list-items, content-sized so children overflow the viewport. *)
let mount_vlist ~n ~item_h =
  let row_bg i = if i land 1 = 0 then "#2a2d33" else "#23262b" in
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
    ops := CreateNode (id, ListItem) :: !ops;
    ops := SetProp (id, HeightValue, FloatValue item_h) :: !ops;
    ops :=
      SetProp (id, TextValue, StringValue (Printf.sprintf "row %d" i))
      :: !ops;
    ops := SetProp (id, BackgroundValue, StringValue (row_bg i)) :: !ops;
    ops := InsertChild (2, id, i) :: !ops
  done;
  { generation = 1; ops = List.rev !ops }

(* Wheel-equivalent scroll: the production model keeps scroll offsets
   host-side, so a scroll frame emits no patch — the action timestamp
   lands on the offset update and the patch stages collapse to ~0,
   which is exactly what a driver measures on these frames. *)
let vlist_scroll ~n ~frames ~velocity ~item_h ~width ~height =
  let name = Printf.sprintf "vlist-%dk-scroll" (n / 1000) in
  let t = H.create ~width ~height ~scale:1. () in
  let t0 = H.now () in
  ignore (H.apply t (mount_vlist ~n ~item_h));
  let mount_apply_ms = (H.now () -. t0) *. 1000. in
  ignore (H.run_repaint_frame t ~act:(fun () -> ()));
  let samples =
    List.init frames (fun i ->
        H.metrics_of
          (H.run_repaint_frame t ~act:(fun () ->
               H.set_scroll t 2 (velocity *. float_of_int (i + 1)))))
  in
  ms_row name "mount patch apply" mount_apply_ms :: metric_rows name samples

(* ---------- mount patch apply: the P1-4 transport comparison ---------- *)

(* The big-mount apply this milestone is about: the same mount batch
   delivered to a fresh store through each transport, timing the whole
   apply path — [Wire] prices patch -> encode -> decode -> apply (what
   a bridged host pays), [In_process] prices apply alone (what a
   same-process backend pays). A fresh store per sample keeps every
   iteration at full mount cost; encode of the same batch repeats
   inside [Wire], so the delta is the serialization work itself. *)
let mount_apply ~n ~iters ~item_h =
  let batch = mount_vlist ~n ~item_h in
  List.concat_map
    (fun transport ->
      let name =
        Printf.sprintf "mount-apply-%dk-%s" (n / 1000)
          (match transport with
          | Lui_wire.In_process -> "in-process"
          | Lui_wire.Wire -> "wire")
      in
      let samples =
        List.init iters (fun _ ->
            let store = Lui_store.create () in
            let t0 = H.now () in
            Lui_store.apply_batch store (Lui_wire.transcode transport batch);
            (H.now () -. t0) *. 1000.)
      in
      let s = H.stats_of samples in
      [
        ms_row name "patch apply p50" s.H.p50;
        ms_row name "patch apply p95" s.H.p95;
        ms_row name "patch apply mean" s.H.mean;
        mrow name "patch ops"
          (string_of_int (List.length batch.ops)) "ops";
      ])
    [ Lui_wire.In_process; Lui_wire.Wire ]

(* ---------- collapse / expand subtree ---------- *)

module Tree = struct
  type model = { open_ : bool }
  type action = Toggle

  let initial = { open_ = true }
  let update model Toggle = { open_ = not model.open_ }

  let view kids _ctx model_s send : t =
    column ~gap:0 ~padding:4
      [
        button
          ~text:
            (reactive
               (fun m -> (if m.open_ then "v " else "> ") ^ "section")
               model_s)
          ~on_press:(press send Toggle)
          [];
        if_
          ~test:(reactive (fun m -> m.open_) model_s)
          (column ~gap:0
             (List.init kids (fun i ->
                  row ~height:18
                    [
                      text
                        ~value:(Printf.sprintf "child row %d" i)
                        ~margin_left:16
                        [];
                    ])));
      ]
end

let collapse_expand ~kids ~iters ~width ~height =
  let name = "collapse-expand" in
  let t = H.create ~width ~height ~scale:1. () in
  let t0 = H.now () in
  let app = boot_app t Tree.initial Tree.update (Tree.view kids) in
  let mount_ms = (H.now () -. t0) *. 1000. in
  let samples =
    collect t app ~warmup:2 ~iters ~act:(fun _i ->
        ignore (Lui_app.send app Tree.Toggle))
  in
  ms_row name "mount e2e" mount_ms :: metric_rows name samples

(* ---------- suite ---------- *)

let default_width = 1280
let default_height = 800

(* [?scale_sizes:false] runs the reduced variant the regression suite
   uses — same code paths, bounded run time. *)
let all ?(scale_sizes = false) () =
  let w, h = (default_width, default_height) in
  if scale_sizes then
    List.concat
      [
        typing ~iters:24 ~width:w ~height:h;
        toggle_case ~iters:24 ~width:w ~height:h;
        hover ~iters:24 ~width:w ~height:h;
        blocks ~n:2_000 ~iters:12 ~width:w ~height:h;
        vlist_scroll ~n:10_000 ~frames:12 ~velocity:40. ~item_h:28.
          ~width:w ~height:h;
        mount_apply ~n:10_000 ~iters:5 ~item_h:28.;
        collapse_expand ~kids:80 ~iters:16 ~width:w ~height:h;
        ime_compose ~iters:24 ~width:w ~height:h;
      ]
  else
    List.concat
      [
        typing ~iters:60 ~width:w ~height:h;
        toggle_case ~iters:60 ~width:w ~height:h;
        hover ~iters:60 ~width:w ~height:h;
        blocks ~n:10_000 ~iters:30 ~width:w ~height:h;
        vlist_scroll ~n:100_000 ~frames:30 ~velocity:40. ~item_h:28.
          ~width:w ~height:h;
        mount_apply ~n:100_000 ~iters:5 ~item_h:28.;
        collapse_expand ~kids:200 ~iters:40 ~width:w ~height:h;
        ime_compose ~iters:60 ~width:w ~height:h;
      ]

let to_markdown rows =
  let b = Buffer.create 8192 in
  Buffer.add_string b "| scenario | metric | value | unit |\n";
  Buffer.add_string b "|---|---|---|---|\n";
  List.iter
    (fun r ->
      Buffer.add_string b
        (Printf.sprintf "| %s | %s | %s | %s |\n" r.scenario r.metric
           r.value r.unit_))
    rows;
  Buffer.contents b
