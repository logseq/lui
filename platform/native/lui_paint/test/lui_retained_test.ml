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
    Printf.sprintf "Fill(%.1f,%.1f,%.1f,%.1f)" f.frect.x f.frect.y
      f.frect.w f.frect.h
  | Shadow _ -> "Shadow"
  | Glyphs g -> Printf.sprintf "Glyphs(%d,%d)" g.gstart g.gend
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
   plus the column itself — only those two may hard-repaint. *)
let test_geom_shift_translates () =
  let env = env () in
  build_rows env 20;
  frame env ();
  let r0 = Lui_retained.stat_repaints env.rt in
  apply env.store [ SetProp (3, HeightValue, FloatValue 40.) ];
  frame env ();
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
  (* store still carries the orphaned children as roots *)
  frame env ()

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

(* Deterministic random op sequences: every frame cross-checks the
   retained scene against a full repaint. *)
let test_random_equivalence () =
  let env = env () in
  let rand = Random.State.make [| 0xC0FFEE |] in
  let next_id = ref 100 in
  let kinds =
    [| Column; Row; Text; Button; Scroll; ViewThatFits; Label; Kbd |]
  in
  let paint_props =
    [| BackgroundValue; ForegroundValue; CornerRadius; Shadow;
      HoverBackground; BorderWidth; BorderColorValue |]
  in
  let layout_props =
    [| WidthValue; HeightValue; PaddingValue; Gap; MarginValue |]
  in
  let colors = [| "#ff0000"; "#00ff00"; "#0000ff"; "#11223344" |] in
  let pick a = a.(Random.State.int rand (Array.length a)) in
  let live = ref [ 1 ] in
  let kids_of id = Lui_store.child_ids env.store id in
  let rand_live () = pick (Array.of_list !live) in
  let rand_op () =
    match Random.State.int rand 10 with
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
      let p = rand_live () in
      match kids_of p with
      | [] -> []
      | kids ->
        let c = pick (Array.of_list kids) in
        let n = List.length (kids_of p) in
        [ MoveChild (p, c, Random.State.int rand n) ])
    | 3 ->
      [ SetProp (rand_live (), pick paint_props, StringValue (pick colors)) ]
    | 4 ->
      [ SetProp
          (rand_live (), pick layout_props,
            FloatValue (float_of_int (Random.State.int rand 60))) ]
    | 5 ->
      [ SetProp
            (rand_live (), Opacity,
              FloatValue (Random.State.float rand 1.)) ]
    | 6 ->
      [ SetProp
            ( rand_live (),
              DisplayValue,
              StringValue (if Random.State.bool rand then "none" else "contents") ) ]
    | 7 ->
      [ SetProp
            ( rand_live (),
              Visible,
              BoolValue (Random.State.bool rand) ) ]
    | 8 ->
      [ SetProp (rand_live (), ZIndex, IntValue (Random.State.int rand 4)) ]
    | _ ->
      [ SetProp (rand_live (), TextValue, StringValue (pick colors)) ]
  in
  apply env.store [ CreateNode (1, Column) ];
  for _step = 1 to 60 do
    let ops =
      List.concat_map (fun _ -> rand_op ()) (List.init 4 Fun.id)
    in
    if ops <> [] then apply env.store ops;
    frame env ()
  done

let () =
  run "lui_retained"
    [ ( "fragments",
        [ test_case "static frame" `Quick test_static_frame;
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
          test_case "state hint" `Quick test_state_hint;
          test_case "drop subtree" `Quick test_drop_subtree;
          test_case "wide removal" `Quick test_wide_removal;
          test_case "random equivalence" `Quick test_random_equivalence ] ) ]
