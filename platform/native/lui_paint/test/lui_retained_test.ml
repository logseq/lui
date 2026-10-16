open Alcotest
open Lui_scene
open Lui_protocol

let apply t ops = Lui_store.apply_batch t { generation = 1; ops }

(* The text hook appends one glyph per character to whichever scene
   [cur] points at — the same append-then-index discipline the real
   text engine follows, exercising the fragment buffer capture. *)
let text_ops cur _id (r : rect) fg s =
  let scn = !cur in
  let gstart = List.length scn.glyphs in
  String.iter
    (fun _ ->
      scn.glyphs <-
        { gx = r.x; gy = r.y; gw = 4.; gh = 8.; gu = 0; gv = 0;
          guw = 4; gvh = 8; gcolor = fg; gwide = 0; gcolored = false;
          gsubpixel = false; gthin = false }
        :: scn.glyphs)
    s;
  let gend = List.length scn.glyphs in
  if gend = gstart then []
  else
    [ Glyphs
        { gstart; gend; gpaint = Solid; gcolor = fg; gcolor2 = fg;
          ggradient = (0., 0., 0., 0.); gwide2 = 0; gopacity = 1. } ]

let scene () =
  Lui_scene.create
    ~mask_atlas:(Atlas.create ~bpp:1 ~w:64 ~h:64)
    ~color_atlas:(Atlas.create ~bpp:4 ~w:64 ~h:64)

(* ---------- scene comparison ---------- *)

(* [Stdlib.compare] is total across NaN fields — [=] is not. *)
let ceq (a : 'a) (b : 'a) = Stdlib.compare a b = 0

let op_eq a b =
  match (a, b) with
  | Lui_scene.Image a, Lui_scene.Image b ->
    a.iimage.iid = b.iimage.iid && ceq { a with iimage = b.iimage } b
  | a, b -> ceq a b

let glyph_eq (a : glyph) (b : glyph) = ceq a b

let rec list_eq eq xs ys =
  match (xs, ys) with
  | [], [] -> true
  | x :: xs', y :: ys' -> eq x y && list_eq eq xs' ys'
  | _ -> false

let effect_shallow (e : effect_op) =
  (e.ee.ename, e.ee.ebackdrop, e.eblur, Array.to_list e.eparams)

let show_op = function
  | Fill f ->
    Printf.sprintf
      "Fill(%.1f,%.1f,%.1f,%.1f c=%d,%d,%d,%d op=%.2f b=%.0f,%.0f,%.0f,%.0f)"
      f.frect.x f.frect.y f.frect.w f.frect.h
      f.fcolor.r f.fcolor.g f.fcolor.b f.fcolor.a f.fopacity
      (let t, _, _, _ = f.fborder in t)
      (let _, r, _, _ = f.fborder in r)
      (let _, _, b, _ = f.fborder in b)
      (let _, _, _, l = f.fborder in l)
  | Shadow _ -> "Shadow"
  | Glyphs g ->
    Printf.sprintf "Glyphs(%d,%d op=%.3f c=%d,%d,%d,%d)"
      g.gstart g.gend g.gopacity g.gcolor.r g.gcolor.g g.gcolor.b g.gcolor.a
  | Image _ -> "Image"
  | Push_clip c ->
    Printf.sprintf "Push_clip(%.1f,%.1f,%.1f,%.1f)" c.crect.x c.crect.y
      c.crect.w c.crect.h
  | Pop_clip -> "Pop_clip"
  | Effect _ -> "Effect"
  | Hole _ -> "Hole"

let check_scene (a : Lui_scene.t) (b : Lui_scene.t) =
  (if not (list_eq op_eq a.ops b.ops) then begin
     let rec first i xs ys =
       match (xs, ys) with
       | x :: _, y :: _ when not (op_eq x y) ->
         Printf.eprintf "first diff at %d: %s vs %s\n%!" i (show_op x)
           (show_op y)
       | _ :: xs', _ :: ys' -> first (i + 1) xs' ys'
       | [], _ -> Printf.eprintf "kept has %d extra ops\n%!" (List.length ys)
       | _, [] -> Printf.eprintf "full has %d extra ops\n%!" (List.length xs)
     in
     first 0 a.ops b.ops
   end);
  check bool "ops equal" true (list_eq op_eq a.ops b.ops);
  check bool "glyphs equal" true (list_eq glyph_eq a.glyphs b.glyphs);
  check bool "wide equal" true (Stdlib.compare a.wide b.wide = 0);
  check bool "effects equal" true
    (List.map effect_shallow a.effects
     = List.map effect_shallow b.effects)

(* ---------- driver ----------

   One store, one layout engine, one retained cache. Each frame syncs
   the engine (host contract), hands the moved-rect set to the retained
   pass, and cross-checks it against a full [Lui_paint.paint]. *)
type env = {
  store : Lui_store.t;
  eng : Lui_layout.t;
  rt : Lui_retained.retained;
  cur : Lui_scene.t ref;
  (* The retained pass owns its scene across frames — untouched
     buffers on clean frames are the whole point. *)
  kept : Lui_scene.t;
  state_tbl : (int, Lui_paint.state) Hashtbl.t;
}

let env () =
  { store = Lui_store.create ();
    eng = Lui_layout.create ();
    rt = Lui_retained.create ();
    cur = ref (scene ());
    kept = scene ();
    state_tbl = Hashtbl.create 8 }

let hooks env =
  { Lui_paint.default_hooks with
    text_ops = text_ops env.cur;
    state_of =
      (fun id ->
        match Hashtbl.find_opt env.state_tbl id with
        | Some st -> st
        | None -> Lui_paint.state_neutral);
    shadow_of = Lui_paint.parse_shadows (fun _ -> None) }

let measure _id _text _w _h = Some (40., 16.)

let frame env ?(width = 200) ?(height = 200) () =
  Lui_layout.sync ~scale:1. ~measure ~width:(float_of_int width)
    ~height:(float_of_int height) env.eng env.store;
  let moved = Lui_layout.take_rect_changes env.eng in
  let h = { (hooks env) with layout = Lui_layout.layout_hook env.eng } in
  let full = scene () in
  env.cur := full;
  Lui_paint.paint h env.store full ~width ~height ~scale:1.
    ~clear:(color 0 0 0 0);
  env.cur := env.kept;
  Lui_retained.paint_retained env.rt h env.store env.kept ~moved ~width
    ~height ~scale:1. ~clear:(color 0 0 0 0) ();
  check_scene full env.kept

let build_rows env n =
  let ops =
    CreateNode (1, Column)
    :: List.concat_map
         (fun i ->
           let id = i + 2 in
           [ CreateNode (id, Button);
             SetProp (id, TextValue, StringValue (Printf.sprintf "row %d" i));
             SetProp (id, BackgroundValue, StringValue "#112233");
             InsertChild (1, id, i) ])
         (List.init n Fun.id)
  in
  apply env.store ops

let test_fragment_lookup_allocation () =
  let retained = Lui_retained.create () in
  let originals = Array.init 1000 (fun id -> Lui_retained.frag_of retained id) in
  let identities_match = ref true in
  let before = Gc.allocated_bytes () in
  for _ = 1 to 100 do
    Array.iteri
      (fun id expected ->
        if Lui_retained.frag_of retained id != expected then identities_match := false)
      originals
  done;
  let allocated = (Gc.allocated_bytes () -. before) /. 100. in
  check bool "Existing fragments preserve physical identity" true !identities_match;
  Printf.printf "Retained 1000-fragment lookup allocated %.0f bytes/pass\n%!" allocated;
  check bool "Looking up live paint fragments allocates wrappers" true (allocated < 4096.)

let test_static_frame () =
  let env = env () in
  build_rows env 10;
  frame env ();
  let v0 = Lui_retained.stat_visits env.rt
  and r0 = Lui_retained.stat_repaints env.rt in
  frame env ();
  frame env ();
  check int "no visits" 0 (Lui_retained.stat_visits env.rt - v0);
  check int "no repaints" 0 (Lui_retained.stat_repaints env.rt - r0)

let test_single_paint_update () =
  let env = env () in
  build_rows env 20;
  frame env ();
  let r0 = Lui_retained.stat_repaints env.rt in
  apply env.store
    [ SetProp (7, BackgroundValue, StringValue "#ff0000") ];
  frame env ();
  check int "one repaint" 1
    (Lui_retained.stat_repaints env.rt - r0)

(* A geometry-only shift translates cached fragments instead of
   re-planning: one row's height change moves every sibling below it
   plus the column itself — only those two may hard-repaint. The tall
   viewport keeps every row onscreen: C4 lets an offscreen node's
   children escape, so offscreen siblings must re-derive rather than
   cull — only drawn fragments can take the pure-translation path. *)
let test_geom_shift_translates () =
  let env = env () in
  build_rows env 20;
  frame env ~height:720 ();
  let r0 = Lui_retained.stat_repaints env.rt in
  apply env.store [ SetProp (3, HeightValue, FloatValue 40.) ];
  frame env ~height:720 ();
  check bool "shifted siblings translated" true
    (Lui_retained.stat_repaints env.rt - r0 <= 3)

let test_semantics_only_skips () =
  let env = env () in
  build_rows env 5;
  frame env ();
  let v0 = Lui_retained.stat_visits env.rt in
  apply env.store
    [ SetProp (3, AccessibilityLabel, StringValue "third") ];
  frame env ();
  check int "no visits" 0 (Lui_retained.stat_visits env.rt - v0)

let test_text_edit () =
  let env = env () in
  build_rows env 8;
  frame env ();
  apply env.store [ SetProp (4, TextValue, StringValue "renamed") ];
  frame env ()

let test_insert_remove () =
  let env = env () in
  build_rows env 6;
  frame env ();
  apply env.store
    [ CreateNode (100, Text);
      SetProp (100, TextValue, StringValue "inserted");
      InsertChild (1, 100, 2) ];
  frame env ();
  apply env.store [ RemoveChild (1, 4) ];
  frame env ();
  apply env.store [ RemoveChild (1, 100) ];
  frame env ()

let test_move_child () =
  let env = env () in
  build_rows env 6;
  frame env ();
  apply env.store [ MoveChild (1, 6, 0) ];
  frame env ()

let test_zindex () =
  let env = env () in
  build_rows env 4;
  frame env ();
  apply env.store [ SetProp (4, ZIndex, IntValue 5) ];
  frame env ();
  apply env.store [ SetProp (4, ZIndex, IntValue 0) ];
  frame env ()

let test_display_none_cycle () =
  let env = env () in
  build_rows env 5;
  frame env ();
  apply env.store [ SetProp (4, DisplayValue, StringValue "none") ];
  frame env ();
  apply env.store [ RemoveProp (4, DisplayValue) ];
  frame env ()

let test_display_contents () =
  let env = env () in
  build_rows env 3;
  apply env.store
    [ CreateNode (50, ViewThatFits);
      SetProp (50, DisplayValue, StringValue "contents");
      InsertChild (1, 50, 1);
      CreateNode (51, Text);
      SetProp (51, TextValue, StringValue "lifted");
      InsertChild (50, 51, 0) ];
  frame env ();
  apply env.store [ SetProp (51, TextValue, StringValue "still lifted") ];
  frame env ()

let test_opacity_cascade () =
  let env = env () in
  build_rows env 4;
  frame env ();
  apply env.store [ SetProp (1, Opacity, FloatValue 0.5) ];
  frame env ();
  apply env.store [ SetProp (1, Opacity, FloatValue 1.) ];
  frame env ()

let test_popup_deferred () =
  let env = env () in
  build_rows env 3;
  apply env.store
    [ CreateNode (60, ContextMenu);
      CreateNode (61, MenuItem);
      SetProp (61, TextValue, StringValue "item");
      InsertChild (60, 61, 0);
      InsertChild (1, 60, 1) ];
  frame env ();
  apply env.store [ SetProp (61, TextValue, StringValue "item!") ];
  frame env ()

let test_popup_motion_buffers () =
  let env = env () in
  apply env.store
    [
      CreateNode (1, Column);
      CreateNode (60, Dialog);
      InsertChild (1, 60, 0);
      CreateNode (61, Text);
      SetProp (61, TextValue, StringValue "dialog");
      InsertChild (60, 61, 0);
      CreateNode (62, Popover);
      InsertChild (60, 62, 1);
      CreateNode (63, Text);
      SetProp (63, TextValue, StringValue "menu");
      InsertChild (62, 63, 0);
    ];
  let paint now =
    ignore (Lui_retained.tick env.rt ~now);
    Lui_layout.sync ~scale:1. ~measure ~width:200. ~height:200. env.eng
      env.store;
    let moved = Lui_layout.take_rect_changes env.eng in
    let h = { (hooks env) with layout = Lui_layout.layout_hook env.eng } in
    env.cur := env.kept;
    Lui_retained.paint_retained env.rt h env.store env.kept ~moved ~width:200
      ~height:200 ~scale:1. ~clear:(color 0 0 0 0) ();
    List.iter
      (function
        | Glyphs g ->
            check bool "animated glyph references remain in range" true
              (g.gstart >= 0 && g.gend <= List.length env.kept.glyphs)
        | _ -> ())
      env.kept.ops
  in
  paint 0.;
  let planned = Lui_retained.stat_repaints env.rt in
  paint 0.075;
  check int "motion reuses the painted fragments" planned
    (Lui_retained.stat_repaints env.rt);
  check bool "nested glyphs fade" true
    (List.exists
       (function Glyphs g -> g.gopacity > 0. && g.gopacity < 1. | _ -> false)
       env.kept.ops);
  paint 0.25;
  frame env ();
  apply env.store [ DetachSubtree 60 ];
  paint 0.25;
  check bool "removed nested surface retains text during exit" true
    (env.kept.glyphs <> []);
  paint 0.5;
  frame env ();
  check bool "exit releases glyph buffers" true (env.kept.glyphs = []);
  check bool "all popup motion is settled" false (Lui_retained.animating env.rt)

let test_state_hint () =
  let env = env () in
  build_rows env 5;
  frame env ();
  Hashtbl.replace env.state_tbl 4
    { Lui_paint.state_neutral with hovered = true };
  let hints = Hashtbl.create 4 in
  Hashtbl.replace hints 4 ();
  Lui_layout.sync ~scale:1. ~measure ~width:200. ~height:200. env.eng
    env.store;
  let h = { (hooks env) with layout = Lui_layout.layout_hook env.eng } in
  let full = scene () in
  env.cur := full;
  Lui_paint.paint h env.store full ~width:200 ~height:200 ~scale:1.
    ~clear:(color 0 0 0 0);
  env.cur := env.kept;
  Lui_retained.paint_retained env.rt h env.store env.kept ~hints ~width:200
    ~height:200 ~scale:1. ~clear:(color 0 0 0 0) ();
  check_scene full env.kept

let test_drop_subtree () =
  let env = env () in
  build_rows env 6;
  frame env ();
  apply env.store [ DropNode 1 ];
  frame env ();
  (* A second clean frame must preserve the empty forest. *)
  frame env ()

let test_disposed_fragments () =
  List.iter (fun painted ->
    let env = env () in
    apply env.store [CreateNode (1, Column)];
    frame env ();
    let baseline = (Gc.stat ()).live_words in
    for turn=0 to 99 do
      let parent=1000+turn*4 in
      apply env.store [CreateNode (parent,Column); InsertChild (1,parent,0);
        CreateNode (parent+1,Column); InsertChild (parent,parent+1,0);
        CreateNode (parent+2,Button); SetProp (parent+2,TextValue,StringValue "temporary");
        InsertChild (parent+1,parent+2,0);
        CreateNode (parent+3,Button); InsertChild (parent,parent+3,1)];
      if painted then frame env ();
      (* Native viewport teardown can dispose an inner scope and then its
         enclosing row before the next materialization. *)
      apply env.store [RemoveChild (parent,parent+1); DetachSubtree (parent+1);
        DetachSubtree parent];
      frame env ()
    done;
    Gc.full_major (); Gc.full_major ();
    let retained = ((Gc.stat ()).live_words-baseline)*(Sys.word_size/8) in
    Printf.printf "Disposed paint fragments (painted=%b): fragments=%d parents=%d retained=%d bytes\n%!"
      painted (Hashtbl.length env.rt.frags) (Hashtbl.length env.rt.fparent) retained;
    check bool "Disposed viewport rows retain paint fragments"
      true (Hashtbl.length env.rt.frags <= Lui_store.node_count env.store);
    check bool "Disposed viewport rows retain paint parent links"
      true (Hashtbl.length env.rt.fparent <= Lui_store.node_count env.store);
    check bool "Disposed viewport rows retain virtual paint windows"
      true (Hashtbl.length env.rt.vwin <= Lui_store.node_count env.store);
    check bool "Disposed rows retain pending paint work"
      true (Hashtbl.length env.rt.pend_segs=0 && Hashtbl.length env.rt.pend_kids=0)
  ) [false;true]

let test_removed_paint_hints () =
  let env = env () in
  build_rows env 4;
  frame env ();
  apply env.store [DetachSubtree 1];
  let moved=Hashtbl.create 4 and hints=Hashtbl.create 4 in
  for id=1 to 5 do Hashtbl.add moved id (); Hashtbl.add hints id () done;
  let h=hooks env in
  Lui_retained.paint_retained env.rt h env.store env.kept ~moved ~hints
    ~width:200 ~height:200 ~scale:1. ~clear:(color 0 0 0 0) ();
  check int "Deleted geometry and hover hints recreate paint resources"
    0 (Hashtbl.length env.rt.frags);
  check int "Deleted geometry leaves parent links" 0 (Hashtbl.length env.rt.fparent);
  apply env.store [CreateNode (1,Column); CreateNode (2,Button);
    SetProp (2,TextValue,StringValue "replacement"); InsertChild (1,2,0)];
  frame env ();
  Lui_retained.invalidate env.rt;
  frame env ();
  check bool "Invalidation retains obsolete parent links"
    true (Hashtbl.length env.rt.fparent <= Lui_store.node_count env.store)


(* Wide-child removals: 250 removed children land on the root list
   and re-emit there — one repaint per moved id, never a rebuild per
   removed child. *)
let test_wide_removal () =
  let env = env () in
  build_rows env 300;
  frame env ();
  let r0 = Lui_retained.stat_repaints env.rt in
  for id = 2 to 250 do
    apply env.store [ RemoveChild (1, id) ]
  done;
  frame env ();
  check bool "bounded repaints" true
    (Lui_retained.stat_repaints env.rt - r0 < 320)

(* A virtual list under retained paint: both walks enumerate the
   mounted window slice, and a scroll-driven remount must rebuild the
   list's kids list — never replaying pieces of rows that slid out. *)
let vlist_store env ~n =
  let ops =
    ref
      [ InsertChild (1, 2, 0); CreateNode (2, VirtualList);
        CreateNode (1, Root) ]
  in
  for i = 0 to n - 1 do
    let id = 10 + i in
    ops :=
      InsertChild (2, id, i)
      :: SetProp (id, KeyValue, StringValue (Printf.sprintf "row-%d" i))
      :: SetProp (id, HeightValue, FloatValue 20.)
      :: SetProp (id, BackgroundValue, StringValue "#112233")
      :: CreateNode (id, ListItem)
      :: !ops
  done;
  apply env.store (List.rev !ops)

let vframe env ~vport =
  Lui_layout.sync ~scale:1. ~measure ~width:200. ~height:200. ~vport
    env.eng env.store;
  let moved = Lui_layout.take_rect_changes env.eng in
  let h =
    { (hooks env) with
      layout = Lui_layout.layout_hook env.eng;
      mounted_children = Lui_layout.mounted_children env.eng }
  in
  let full = scene () in
  env.cur := full;
  Lui_paint.paint h env.store full ~width:200 ~height:200 ~scale:1.
    ~clear:(color 0 0 0 0);
  env.cur := env.kept;
  Lui_retained.paint_retained env.rt h env.store env.kept ~moved
    ~vlists:(Lui_layout.vlists env.eng) ~width:200 ~height:200 ~scale:1.
    ~clear:(color 0 0 0 0) ();
  check_scene full env.kept

let test_vlist_scroll () =
  let env = env () in
  vlist_store env ~n:1000;
  let vport y h id = if id = 2 then Some (y, h) else None in
  vframe env ~vport:(vport 0. 200.);
  (* Each scroll remounts a different window; the retained scene must
     equal a fresh full paint on every frame, back-scrolls included. *)
  vframe env ~vport:(vport 500. 200.);
  vframe env ~vport:(vport 9500. 200.);
  vframe env ~vport:(vport 0. 200.)

(* Deterministic random op sequences: every frame cross-checks the
   retained scene against a full repaint. Covers stacking (z-index),
   promoted popups (incl. nested and clip-escaping), clip culling
   (scroll/overflow containers pushed offscreen), display:contents
   pass-through, hidden subtrees, reparenting and prop removal. *)
let test_random_equivalence () =
  let run_seed seed =
    let env = env () in
    let rand = Random.State.make seed in
    let next_id = ref 100 in
    let kinds =
      [| Column; Row; Text; Button; Scroll; ViewThatFits; Label; Kbd;
        Stack; Overlay; ContextMenu; Tooltip; Popover; Dialog;
        MenuItem |]
    in
    let paint_props =
      [| BackgroundValue; ForegroundValue; CornerRadius; Shadow;
        HoverBackground; BorderWidth; BorderColorValue |]
    in
    (* Sizes reach well past the 200px viewport so subtrees land
       partly or wholly offscreen and clip contexts die. *)
    let layout_props =
      [| WidthValue; HeightValue; PaddingValue; Gap; MarginValue |]
    in
    let colors = [| "#ff0000"; "#00ff00"; "#0000ff"; "#11223344" |] in
    let removable_props =
      [| DisplayValue; Position; ZIndex; Overflow; Opacity; Visible |]
    in
    let pick a = a.(Random.State.int rand (Array.length a)) in
    let live = ref [ 1 ] in
    let kids_of id = Lui_store.child_ids env.store id in
    let rand_live () = pick (Array.of_list !live) in
    let is_ancestor anc id =
      let rec go cur =
        match Lui_store.parent env.store cur with
        | Some p -> p = anc || go p
        | None -> false
      in
      go id
    in
    let rand_op () =
      match Random.State.int rand 14 with
      | 0 -> (
        incr next_id;
        let id = !next_id in
        let p = rand_live () in
        live := id :: !live;
        let n = List.length (kids_of p) in
        [ CreateNode (id, pick kinds);
          SetProp (id, TextValue, StringValue (Printf.sprintf "n%d" id));
          InsertChild (p, id, Random.State.int rand (n + 1)) ])
      | 1 -> (
        let p = rand_live () in
        match kids_of p with
        | [] -> []
        | kids ->
          let c = pick (Array.of_list kids) in
          [ RemoveChild (p, c) ])
      | 2 -> (
        (* Reparent an existing subtree — the child's paint context
           (containing block, alpha, clip) changes wholesale. *)
        let p = rand_live () in
        match kids_of p with
        | [] -> []
        | kids -> (
          let c = pick (Array.of_list kids) in
          let np = rand_live () in
          if np = c || is_ancestor c np then []
          else
            let n = List.length (kids_of np) in
            [ RemoveChild (p, c);
              InsertChild (np, c, Random.State.int rand (n + 1)) ]))
      | 3 -> (
        let p = rand_live () in
        match kids_of p with
        | [] -> []
        | kids ->
          let c = pick (Array.of_list kids) in
          let n = List.length (kids_of p) in
          [ MoveChild (p, c, Random.State.int rand n) ])
      | 4 ->
        [ SetProp
            (rand_live (), pick paint_props, StringValue (pick colors)) ]
      | 5 ->
        [ SetProp
            (rand_live (), pick layout_props,
              FloatValue (float_of_int (Random.State.int rand 400))) ]
      | 6 ->
        [ SetProp
            ( rand_live (),
              Opacity,
              FloatValue (Random.State.float rand 1.)) ]
      | 7 ->
        [ SetProp
            ( rand_live (),
              DisplayValue,
              StringValue
                (if Random.State.bool rand then "none" else "contents") ) ]
      | 8 ->
        [ SetProp
            ( rand_live (),
              Visible,
              BoolValue (Random.State.bool rand) ) ]
      | 9 ->
        [ SetProp (rand_live (), ZIndex, IntValue (Random.State.int rand 4)) ]
      | 10 ->
        [ SetProp
            ( rand_live (),
              Overflow,
              StringValue (pick [| "hidden"; "auto"; "visible" |]) ) ]
      | 11 -> (
        (* Out-of-viewport placement: absolute/fixed offsets and popup
           x/y land nodes outside the 200px frame. *)
        let id = rand_live () in
        match Random.State.int rand 3 with
        | 0 ->
          [ SetProp (id, Position, StringValue (pick [| "absolute"; "fixed"; "relative" |]));
            SetProp
              ( id,
                pick [| Inset; InsetTop; InsetLeft |],
                FloatValue (float_of_int (Random.State.int rand 500 - 100)) ) ]
        | 1 ->
          [ SetProp (id, PopupX, FloatValue (float_of_int (Random.State.int rand 500 - 100)));
            SetProp (id, PopupY, FloatValue (float_of_int (Random.State.int rand 500 - 100))) ]
        | _ ->
          [ RemoveProp (id, Position) ])
      | 12 ->
        [ RemoveProp (rand_live (), pick removable_props) ]
      | _ ->
        [ SetProp (rand_live (), TextValue, StringValue (pick colors)) ]
    in
    apply env.store [ CreateNode (1, Column) ];
    (* Each generated op group applies immediately: the reparent
       acyclicity check and live-node picks in [rand_op] must see the
       store the earlier ops produced, not the frame's stale start
       state. *)
    for _ = 1 to 100 do
      for _ = 1 to 5 do
        let ops = rand_op () in
        if ops <> [] then apply env.store ops
      done;
      frame env ()
    done
  in
  List.iter run_seed
    [ [| 0x5EED; 0xBEEF |]; [| 1; 0xC0FFEE |]; [| 33; 7 |]; [| 104; 42 |] ]

(* A batch larger than the store journal (8192 ops) truncates the retained
   cursor; the wholesale resync must re-derive every kid list, not
   paint childless roots (an empty frame). *)
let test_journal_overflow_resync () =
  let env = env () in
  build_rows env 4;
  frame env ();
  let ops =
    List.concat_map
      (fun i ->
        let id = 1000 + i in
        [ CreateNode (id, Button);
          SetProp (id, TextValue, StringValue "x");
          InsertChild (1, id, 4 + i) ])
      (List.init 5000 Fun.id)
  in
  apply env.store ops;
  frame env ~height:720 ();
  check bool "frame not empty" true (env.kept.ops <> [])

(* Same for an explicit wholesale invalidation (theme swap). *)
let test_invalidate_rebuilds_kids () =
  let env = env () in
  build_rows env 6;
  frame env ();
  Lui_retained.invalidate env.rt;
  frame env ();
  check bool "frame not empty" true (env.kept.ops <> [])

let () =
  run "lui_retained"
    [ ( "fragments",
        [ test_case "fragment lookup allocation" `Quick test_fragment_lookup_allocation;
          test_case "static frame" `Quick test_static_frame;
          test_case "single paint update" `Quick test_single_paint_update;
          test_case "geom shift translates" `Quick test_geom_shift_translates;
          test_case "semantics-only skips" `Quick test_semantics_only_skips;
          test_case "text edit" `Quick test_text_edit;
          test_case "insert/remove" `Quick test_insert_remove;
          test_case "move child" `Quick test_move_child;
          test_case "z-index" `Quick test_zindex;
          test_case "display none cycle" `Quick test_display_none_cycle;
          test_case "display contents" `Quick test_display_contents;
          test_case "opacity cascade" `Quick test_opacity_cascade;
          test_case "popup deferred" `Quick test_popup_deferred;
          test_case "popup motion buffers" `Quick test_popup_motion_buffers;
          test_case "state hint" `Quick test_state_hint;
          test_case "drop subtree" `Quick test_drop_subtree;
          test_case "disposed fragments" `Quick test_disposed_fragments;
          test_case "removed paint hints" `Quick test_removed_paint_hints;
          test_case "wide removal" `Quick test_wide_removal;
          test_case "vlist scroll" `Quick test_vlist_scroll;
          test_case "random equivalence" `Quick test_random_equivalence;
          test_case "journal overflow resync" `Quick test_journal_overflow_resync;
          test_case "invalidate rebuilds kids" `Quick test_invalidate_rebuilds_kids ] ) ]
