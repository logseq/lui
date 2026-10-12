(* Layout glue tests: wire store → flex mirror → scene rects. *)

open Lui_protocol
open Alcotest

let batch ops = { generation = 1; ops }

let apply t ops = Lui_store.apply_batch t (batch ops)

let no_measure _id _w _h = None

let no_measure4 _id _text _w _h = None

let place f id = (f id).Lui_paint.p_rect

let eps = 0.01

let check_rect msg x y w h (r : Lui_scene.rect) =
  check (float eps) (msg ^ ".x") x r.x;
  check (float eps) (msg ^ ".y") y r.y;
  check (float eps) (msg ^ ".w") w r.w;
  check (float eps) (msg ^ ".h") h r.h

let check_some_rect msg x y w h = function
  | Some r -> check_rect msg x y w h r
  | None -> fail (msg ^ ": expected a rect")

(* Column container with padding 10, gap 5, two 20-high children. *)
let test_column_padding_gap () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text); CreateNode (4, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      SetProp (2, PaddingValue, IntValue 10); SetProp (2, Gap, IntValue 5);
      SetProp (3, HeightValue, IntValue 20);
      SetProp (4, HeightValue, IntValue 20) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "child1" 10. 10. 180. 20. (place p 3);
  check_rect "child2" 10. 35. 180. 20. (place p 4)

(* Grid = horizontal flow that wraps: columns=2 → two cells per row. *)
let test_grid_wraps () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Grid);
      CreateNode (3, Text); CreateNode (4, Text); CreateNode (5, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      InsertChild (2, 5, 2);
      SetProp (2, GridColumns, IntValue 2);
      SetProp (3, HeightValue, IntValue 10);
      SetProp (4, HeightValue, IntValue 10);
      SetProp (5, HeightValue, IntValue 10) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "cell1" 0. 0. 100. 10. (place p 3);
  check_rect "cell2" 100. 0. 100. 10. (place p 4);
  check_rect "cell3" 0. 10. 100. 10. (place p 5)

(* Absolute child positioned by inset edges inside its parent. *)
let test_absolute_inset () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column); CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      SetProp (3, Position, StringValue "absolute");
      SetProp (3, InsetTop, FloatValue 7.);
      SetProp (3, InsetLeft, FloatValue 9.);
      SetProp (3, WidthValue, IntValue 30);
      SetProp (3, HeightValue, IntValue 10) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "abs" 9. 7. 30. 10. (place p 3)

(* Text leaf gets a measure callback fed by the injectable fn. *)
let test_text_measured () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Row); CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      SetProp (3, TextValue, StringValue "hello") ];
  let t = Lui_layout.create () in
  let measure id text _w _h =
    if id = 3 && text = "hello" then Some (80., 12.) else None
  in
  Lui_layout.sync ~measure ~width:200. ~height:100. t store;
  check_some_rect "text" 0. 0. 80. 12. (Lui_layout.rect t 3)

(* 'NN%' string lengths resolve against the parent's inner extent. *)
let test_percent_size () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column); CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      SetProp (3, WidthValue, StringValue "50%");
      SetProp (3, HeightValue, IntValue 10) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "half" 0. 0. 100. 10. (place p 3)

(* Column nested inside a row: its children stack, siblings flow right. *)
let test_nested_column_in_row () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Row);
      CreateNode (3, Column); CreateNode (4, Text); CreateNode (5, Text);
      CreateNode (6, Column);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (3, 4, 0);
      InsertChild (3, 5, 1); InsertChild (2, 6, 1);
      SetProp (3, WidthValue, IntValue 40);
      SetProp (4, HeightValue, IntValue 10);
      SetProp (5, HeightValue, IntValue 10);
      SetProp (6, WidthValue, IntValue 30);
      SetProp (6, HeightValue, IntValue 15) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "nested1" 0. 0. 40. 10. (place p 4);
  check_rect "nested2" 0. 10. 40. 10. (place p 5);
  check_rect "sibling" 40. 0. 30. 15. (place p 6)

(* End-to-end: real store, batch ops, run → placements in frame space. *)
let test_run_placements () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text); CreateNode (4, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      SetProp (2, PaddingValue, IntValue 10); SetProp (2, Gap, IntValue 5);
      SetProp (3, HeightValue, IntValue 20);
      SetProp (4, HeightValue, IntValue 20) ];
  let p = Lui_layout.run ~scale:1. store ~measure:no_measure
      ~width:200. ~height:100. in
  check_rect "p3" 10. 10. 180. 20. (place p 3);
  check_rect "p4" 10. 35. 180. 20. (place p 4);
  check (option reject) "p_override" None (p 3).Lui_paint.p_override

(* display:none nodes never reach the mirror. *)
let test_display_none_absent () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text); CreateNode (4, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      SetProp (3, DisplayValue, StringValue "none");
      SetProp (4, HeightValue, IntValue 10) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~width:200. ~height:100. t store;
  check (option reject) "no rect" None (Lui_layout.rect t 3);
  check_some_rect "sibling top" 0. 0. 200. 10. (Lui_layout.rect t 4)

(* Mutation between syncs: dropped node gone, new node laid out. *)
let test_rebuild_after_mutation () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text); CreateNode (4, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      SetProp (3, HeightValue, IntValue 20);
      SetProp (4, HeightValue, IntValue 20) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_some_rect "before" 0. 0. 200. 20. (Lui_layout.rect t 3);
  apply store
    [ DropNode 3; CreateNode (6, Text); InsertChild (2, 6, 0);
      SetProp (6, HeightValue, IntValue 30) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check (option reject) "dropped" None (Lui_layout.rect t 3);
  check_some_rect "new node" 0. 0. 200. 30. (Lui_layout.rect t 6);
  check_some_rect "old sibling shifted" 0. 30. 200. 20. (Lui_layout.rect t 4)

(* Sync over an untouched store is memoized: the measure counter shows
   no rebuild ran. A store mutation or an explicit {!invalidate}
   re-runs layout and measures again. *)
let test_sync_memoized () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Row); CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      SetProp (3, TextValue, StringValue "hello") ];
  let calls = ref 0 in
  let measure _id _text _w _h = incr calls; Some (40., 10.) in
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure ~width:200. ~height:100. t store;
  let first = !calls in
  check bool "measured once" true (first > 0);
  Lui_layout.sync ~measure ~width:200. ~height:100. t store;
  check int "unchanged inputs skip rebuild" first !calls;
  Lui_layout.invalidate t;
  Lui_layout.sync ~measure ~width:200. ~height:100. t store;
  check bool "invalidate forces rebuild" true (!calls > first);
  let after_invalidate = !calls in
  apply store [ SetProp (3, WidthValue, IntValue 30) ];
  Lui_layout.sync ~measure ~width:200. ~height:100. t store;
  check bool "store mutation resyncs" true (!calls > after_invalidate)

(* A paint-only prop change never re-enters the mirror: the store's
   layout revision does not move, so sync stays memoized. *)
let test_paint_prop_skips_layout () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Row); CreateNode (3, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      SetProp (3, TextValue, StringValue "hi");
      SetProp (3, WidthValue, IntValue 200);
      SetProp (3, HeightValue, IntValue 10) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~width:200. ~height:100. t store;
  check int "first sync builds" 1 (Lui_layout.stat_syncs t);
  apply store [ SetProp (3, BackgroundValue, StringValue "#ff0000") ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check int "paint-only prop skips rebuild" 1 (Lui_layout.stat_syncs t);
  check_some_rect "rect intact" 0. 0. 200. 10. (Lui_layout.rect t 3);
  apply store [ SetProp (3, WidthValue, IntValue 30) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check int "layout prop resyncs" 2 (Lui_layout.stat_syncs t)

(* Grid cells subtract the gap share: columns=2 + gap 10 in a 200-wide
   frame gives two 95-wide cells per row, not one. *)
let test_grid_gap_fits_columns () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Grid);
      CreateNode (3, Text); CreateNode (4, Text);
      CreateNode (5, Text); CreateNode (6, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      InsertChild (2, 5, 2); InsertChild (2, 6, 3);
      SetProp (2, GridColumns, IntValue 2);
      SetProp (2, Gap, IntValue 10);
      SetProp (3, HeightValue, IntValue 10);
      SetProp (4, HeightValue, IntValue 10);
      SetProp (5, HeightValue, IntValue 10);
      SetProp (6, HeightValue, IntValue 10) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "cell1" 0. 0. 95. 10. (place p 3);
  check_rect "cell2" 105. 0. 95. 10. (place p 4);
  check_rect "cell3" 0. 20. 95. 10. (place p 5);
  check_rect "cell4" 105. 20. 95. 10. (place p 6)

(* Content taller than the offered frame grows the frame instead of
   being compressed or cut; content_extent reports it. *)
let test_frame_grows_to_content () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text); CreateNode (4, Text); CreateNode (5, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      InsertChild (2, 5, 2);
      SetProp (3, HeightValue, IntValue 100);
      SetProp (4, HeightValue, IntValue 100);
      SetProp (5, HeightValue, IntValue 100) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:200. ~height:100. t store;
  check_some_rect "third row uncut" 0. 200. 200. 100. (Lui_layout.rect t 5);
  let ew, eh = Lui_layout.content_extent t in
  check (float eps) "extent w" 200. ew;
  check (float eps) "extent h" 300. eh

(* A popup-family node with no positioning props centers in its
   containing block; explicit insets still win. *)
let test_popup_default_centered () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Dialog); CreateNode (4, Dialog);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      SetProp (2, WidthValue, IntValue 200);
      SetProp (2, HeightValue, IntValue 100);
      SetProp (3, WidthValue, IntValue 40);
      SetProp (3, HeightValue, IntValue 20);
      SetProp (4, Position, StringValue "absolute");
      SetProp (4, InsetLeft, FloatValue 5.);
      SetProp (4, InsetTop, FloatValue 6.);
      SetProp (4, WidthValue, IntValue 40);
      SetProp (4, HeightValue, IntValue 20) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "default centered" 80. 40. 40. 20. (place p 3);
  check_rect "explicit inset" 5. 6. 40. 20. (place p 4)

(* A store-root popup centers in the offered frame extent. *)
let test_root_popup_centered_in_frame () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Dialog);
      InsertChild (1, 2, 0);
      SetProp (2, WidthValue, IntValue 50);
      SetProp (2, HeightValue, IntValue 30) ];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  check_rect "root popup" 75. 35. 50. 30. (place p 2)

(* A menu-trigger's dropdown panel: hidden until opened, then anchored
   below the trigger with its items stacked inside. *)
let test_menu_panel () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Toolbar);
      CreateNode (3, MenuTrigger); CreateNode (4, DropdownMenu);
      CreateNode (5, MenuItem); CreateNode (6, MenuItem);
      CreateNode (7, MenuItem);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0);
      InsertChild (3, 4, 0);
      InsertChild (4, 5, 0); InsertChild (4, 6, 1);
      InsertChild (4, 7, 2);
      SetProp (3, TextValue, StringValue "File");
      SetProp (3, HeightValue, IntValue 20);
      SetProp (5, TextValue, StringValue "open");
      SetProp (6, TextValue, StringValue "new item");
      SetProp (7, TextValue, StringValue "close") ];
  let open_ = ref 0 in
  let h id =
    (match Lui_store.kind store id with
     | "dropdown-menu" | "context-menu" -> (
       match Lui_store.parent store id with
       | Some p -> Lui_store.kind store p = "menu-trigger" && id <> !open_
       | None -> false)
     | _ -> false)
  in
  let p = Lui_layout.run ~hidden:h store ~measure:no_measure ~width:200. ~height:100. in
  check (float eps) "panel hidden" 0. (place p 4).w;
  open_ := 4;
  (* The frame must leave room for the open panel below the trigger —
     viewport clamping otherwise pulls it up to stay on-screen. *)
  let p = Lui_layout.run ~hidden:h store ~measure:(fun _ _ _ -> Some (30., 10.)) ~width:200. ~height:400. in
  let trig = place p 3 and panel = place p 4 in
  (* anchored default: side below, 4pt offset *)
  check (float eps) "panel below" (trig.y +. trig.h +. 4.) panel.y;
  (* menu-item carries the 2rem min-height contract, so the measured
     10px text grows to a 32px row. *)
  check_rect "item1" panel.x panel.y panel.w 32. (place p 5);
  check_rect "item3" panel.x (panel.y +. 64.) panel.w 32. (place p 7)


(* AC menu row: scroll > column > wrap > horizontal extension row >
   grow box > box > row > icon + text — the slash popup shape. *)
let test_ac_row () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Scroll); CreateNode (3, Column);
      CreateNode (4, Box); CreateExtension (5, "logseq-a", "");
      CreateNode (6, Box); CreateNode (7, Box); CreateNode (8, Row);
      CreateNode (9, Icon); CreateNode (10, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (3, 4, 0);
      InsertChild (4, 5, 0); InsertChild (5, 6, 0); InsertChild (6, 7, 0);
      InsertChild (7, 8, 0); InsertChild (8, 9, 0); InsertChild (8, 10, 1);
      SetProp (5, OrientationValue, StringValue "horizontal");
      SetProp (10, TextValue, StringValue "Query") ];
  let p =
    Lui_layout.run store
      ~measure:(fun id _ _ ->
        (match Lui_store.string_prop store id "text" with
         | Some _ -> Some (30., 10.)
         | None -> None))
      ~width:200. ~height:100.
  in
  check (float eps) "text h" 10. (place p 10).h;
  check (float eps) "wrap h" 10. (place p 4).h

(* ---------- virtual lists ---------- *)

(* root > virtual-list(2) > n 20-px rows keyed "row-i". *)
let vlist_store ?(item_h = 20.) ~n () =
  let store = Lui_store.create () in
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
      :: SetProp (id, HeightValue, FloatValue item_h)
      :: CreateNode (id, ListItem)
      :: !ops
  done;
  Lui_store.apply_batch store { generation = 1; ops = List.rev !ops };
  store

let vport y h id = if id = 2 then Some (y, h) else None

(* The mounted window is the fed viewport plus overscan — 1000 logical
   rows never materialize more than a couple dozen. *)
let test_vlist_window_mounts_slice () =
  let store = vlist_store ~n:1000 () in
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 0. 200.) t store;
  let f, l = Option.get (Lui_layout.mounted_range t 2) in
  check int "first" 0 f;
  (* 200px viewport over 20px rows = 10 rows (+1 touching) and 4
     overscan past the end *)
  check int "last" 15 l;
  check bool "mounted bounded" true
    (Lui_layout.mounted_count t 2 <= 15);
  check int "one vlist" 1 (List.length (Lui_layout.vlists t));
  (* the list claims the full virtual extent as its frame height *)
  check (float eps) "extent" 20000.
    (Option.get (Lui_layout.virtual_extent t 2));
  check_some_rect "vlist" 0. 0. 100. 20000. (Lui_layout.rect t 2);
  (* mounted rows sit at model positions *)
  check_some_rect "row0" 0. 0. 100. 20. (Lui_layout.rect t 10);
  check_some_rect "row5" 0. 100. 100. 20. (Lui_layout.rect t 15);
  (* unmounted rows have no rect *)
  check bool "unmounted no rect" true
    (Lui_layout.rect t (10 + 500) = None)

(* A memo-hit sync only remounts the window that slid — same store
   revision, no mirror rebuild, just a different fed viewport. *)
let test_vlist_window_moves () =
  let store = vlist_store ~n:1000 () in
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 0. 200.) t store;
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 500. 200.) t store;
  let f, l = Option.get (Lui_layout.mounted_range t 2) in
  (* [420,780) over 20px rows: items 21..39 *)
  check int "first" 21 f;
  check int "last" 40 l;
  check bool "mounted bounded" true
    (Lui_layout.mounted_count t 2 <= 19);
  check_some_rect "row30" 0. 600. 100. 20. (Lui_layout.rect t 40);
  check bool "before window" true (Lui_layout.rect t 30 = None);
  check bool "after window" true (Lui_layout.rect t 50 = None);
  (* scroll-to-item reaches unmounted rows through the model *)
  check (option int) "key" (Some 30)
    (Lui_layout.virtual_index_of_key t store 2 "row-30");
  check_some_rect "item500" 0. 10000. 100. 20.
    (Lui_layout.virtual_item_rect t 2 ~index:500)

(* Measured extents: a row taller than the estimate refines the model
   once mounted, and the total reflects measured + estimated parts. *)
let test_vlist_measured_extents () =
  let store = Lui_store.create () in
  let ops =
    ref
      [ InsertChild (1, 2, 0); CreateNode (2, VirtualList);
        CreateNode (1, Root) ]
  in
  for i = 0 to 99 do
    let id = 10 + i in
    ops :=
      InsertChild (2, id, i)
      :: SetProp (id, HeightValue, FloatValue (if i = 0 then 100. else 20.))
      :: CreateNode (id, ListItem)
      :: !ops
  done;
  Lui_store.apply_batch store { generation = 1; ops = List.rev !ops };
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 0. 200.) t store;
  (* Estimate = first child's height (100) → the initial window is
     [0,600) → rows 0..6; mounting them measures rows 1-6 at 20, so
     the post-patch remount reaches further down the shrunk strides:
     rows 0..10. Total = 100 + 10*20 + 89*100 estimated. *)
  let f, l = Option.get (Lui_layout.mounted_range t 2) in
  check int "first" 0 f;
  check int "last" 11 l;
  check (float eps) "extent" 9200.
    (Option.get (Lui_layout.virtual_extent t 2));
  (* row 1 sits right after the 100px row 0 *)
  check_some_rect "row1" 0. 100. 100. 20. (Lui_layout.rect t 11)

(* A gap between rows participates in the stride: positions and the
   total both include it. *)
let test_vlist_gap () =
  let store = vlist_store ~n:100 () in
  apply store [ SetProp (2, Gap, IntValue 10) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 0. 200.) t store;
  (* 100 rows * 20 + 99 gaps * 10 = 2990 *)
  check (float eps) "extent" 2990.
    (Option.get (Lui_layout.virtual_extent t 2));
  check_some_rect "row2" 0. 60. 100. 20. (Lui_layout.rect t 12)

(* No vport → the list is unwindowed and mounts every row (the legacy
   behavior hosts without a viewport feed keep). *)
let test_vlist_unwindowed () =
  let store = vlist_store ~n:50 () in
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800. t store;
  let f, l = Option.get (Lui_layout.mounted_range t 2) in
  check int "all" 50 (l - f);
  check int "mounted" 50 (Lui_layout.mounted_count t 2);
  check_some_rect "row49" 0. 980. 100. 20. (Lui_layout.rect t 59)

(* Pixel snapping contract: at a fractional backing scale the exported
   rects land on device-pixel edges, and siblings stacked without a
   gap share their boundary exactly — the same snapped geometry feeds
   paint, hit-test and scroll extents. *)
let test_snapped_edges () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Text); CreateNode (4, Text);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 4, 1);
      SetProp (2, PaddingValue, IntValue 3);
      SetProp (3, HeightValue, IntValue 20);
      SetProp (4, HeightValue, IntValue 20) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~scale:1.5 ~width:200. ~height:100. t store;
  let r3 = Option.get (Lui_layout.rect t 3)
  and r4 = Option.get (Lui_layout.rect t 4) in
  let aligned (r : Lui_scene.rect) =
    r.x = Float.round r.x && r.y = Float.round r.y
    && r.w = Float.round r.w && r.h = Float.round r.h
  in
  check bool "child1 aligned" true (aligned r3);
  check bool "child2 aligned" true (aligned r4);
  (* pad 3 logical = 4.5 device: first child spans 4.5..195.5 and
     snaps to 5..196 (w 191); its bottom 34.5 snaps to 35, which the
     second child shares exactly. *)
  check_rect "child1" 5. 5. 191. 30. r3;
  check_rect "child2 shared edge" 5. 35. 191. 30. r4

(* ---------- incremental mirror ---------- *)

let rect_or_zero t id =
  Option.value ~default:(Lui_scene.rect 0. 0. 0. 0.)
    (Lui_layout.rect t id)

(* Differential oracle: the persistent mirror must produce the same
   rects as a wholesale rebuild of the same store state. *)
let check_equiv msg store t =
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:100. in
  List.iter
    (fun id ->
      let expect = (p id).Lui_paint.p_rect in
      let got = rect_or_zero t id in
      check_rect (Printf.sprintf "%s #%d" msg id) expect.x expect.y
        expect.w expect.h got)
    (Lui_store.preorder store)

(* A journal replay through moves, toggles, drops and prop churn keeps
   the mirror identical to a rebuild at every step. *)
let test_incremental_equivalence () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Column);
      CreateNode (3, Row); CreateNode (4, Text); CreateNode (5, Text);
      CreateNode (6, Text); CreateNode (7, Column);
      InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 7, 1);
      InsertChild (3, 4, 0); InsertChild (3, 5, 1); InsertChild (7, 6, 0);
      SetProp (4, WidthValue, IntValue 20); SetProp (4, HeightValue, IntValue 10);
      SetProp (5, WidthValue, IntValue 30); SetProp (5, HeightValue, IntValue 10);
      SetProp (6, WidthValue, IntValue 40); SetProp (6, HeightValue, IntValue 10);
      SetProp (3, Gap, IntValue 5) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "init" store t;
  (* Move a leaf across parents — reuse, not rebuild. *)
  apply store [ MoveChild (7, 4, 0) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "move across" store t;
  check bool "incremental path" true (Lui_layout.stat_steps t > 0);
  (* Same-parent reorder. *)
  apply store [ MoveChild (7, 4, 1) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "reorder" store t;
  (* display:none then back. *)
  apply store [ SetProp (6, DisplayValue, StringValue "none") ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "hidden" store t;
  apply store [ RemoveProp (6, DisplayValue) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "reshown" store t;
  (* RemoveChild leaves a root. *)
  apply store [ RemoveChild (3, 5) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "detached root" store t;
  apply store [ InsertChild (2, 5, 0) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "reattached" store t;
  (* Drop a whole subtree. *)
  apply store [ DropNode 7 ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "dropped subtree" store t;
  (* Layout prop on a survivor. *)
  apply store [ SetProp (5, HeightValue, IntValue 42) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "restyle" store t

(* Deterministic op fuzz: leaf props, reorders, cross-parent moves,
   display toggles and drops keep the mirror rebuild-equivalent. *)
let test_incremental_random () =
  let store = Lui_store.create () in
  let leaves = List.init 10 (fun i -> 10 + i) in
  apply store
    ([ CreateNode (1, Root); CreateNode (2, Column); CreateNode (3, Row);
       InsertChild (1, 2, 0); InsertChild (1, 3, 1) ]
     @ List.concat_map
         (fun i ->
           [ CreateNode (10 + i, Text);
             InsertChild ((if i mod 2 = 0 then 2 else 3), 10 + i, i / 2);
             SetProp (10 + i, WidthValue, IntValue (10 + i));
             SetProp (10 + i, HeightValue, IntValue 10) ])
         leaves);
  let t = Lui_layout.create () in
  Lui_layout.sync ~width:200. ~height:100. t store;
  let st = Random.State.make [| 42 |] in
  let pick l = List.nth l (Random.State.int st (List.length l)) in
  for round = 1 to 80 do
    let ops =
      List.init (1 + Random.State.int st 3) (fun _ ->
        let leaf = pick leaves in
        match Random.State.int st 6 with
        | 0 -> SetProp (leaf, WidthValue, IntValue (5 + Random.State.int st 60))
        | 1 -> SetProp (leaf, HeightValue, IntValue (5 + Random.State.int st 40))
        | 2 -> (
          match Lui_store.parent store leaf with
          | Some p -> MoveChild (p, leaf, Random.State.int st 3)
          | None -> SetProp (leaf, PaddingValue, IntValue 0))
        | 3 -> InsertChild ((if Random.State.bool st then 2 else 3), leaf,
                            Random.State.int st 3)
        | 4 ->
          if Lui_store.string_prop store leaf "display" = Some "none"
          then RemoveProp (leaf, DisplayValue)
          else SetProp (leaf, DisplayValue, StringValue "none")
        | _ -> SetProp ((if Random.State.bool st then 2 else 3), Gap,
                        IntValue (Random.State.int st 8)))
    in
    apply store ops;
    Lui_layout.sync ~width:200. ~height:100. t store;
    check_equiv (Printf.sprintf "round %d" round) store t
  done

(* Two store roots: growth under the first shifts the second — the
   scoped rect refresh must cover the moved sibling root's subtree. *)
let test_incremental_root_shift () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Root);
      CreateNode (3, Text); CreateNode (4, Text);
      InsertChild (1, 3, 0); InsertChild (2, 4, 0);
      SetProp (3, HeightValue, IntValue 10);
      SetProp (4, HeightValue, IntValue 10) ];
  let t = Lui_layout.create () in
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "roots init" store t;
  apply store [ SetProp (3, HeightValue, IntValue 40) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "root shifted" store t

(* A 10k-sibling tree stays incremental: one text prop edit replays
   through the journal and relayouts only the dirty path, well under
   the cost of a full mirror rebuild. *)
let test_incremental_large_tree () =
  let store = Lui_store.create () in
  apply store
    ([ CreateNode (1, Root); CreateNode (2, Column); InsertChild (1, 2, 0) ]
     @ List.concat_map
         (fun i ->
           [ CreateNode (10 + i, Text);
             InsertChild (2, 10 + i, i);
             SetProp (10 + i, HeightValue, IntValue 1) ])
         (List.init 10_000 Fun.id));
  let t = Lui_layout.create () in
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "big init" store t;
  let before_steps = Lui_layout.stat_steps t in
  let t0 = Sys.time () in
  apply store [ SetProp (5_000, TextValue, StringValue "x") ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  let dt = Sys.time () -. t0 in
  check bool "journal path" true (Lui_layout.stat_steps t > before_steps);
  check_equiv "big restyle" store t;
  check bool "fast incremental" true (dt < 0.5)

(* Journal ops that land inside a virtual list resync its side forest
   instead of rebuilding the mirror — composed row rects still match a
   fresh full layout of the same store. *)
let test_vlist_incremental_child () =
  let store = vlist_store ~n:30 () in
  let t = Lui_layout.create () in
  (* Frame and measure inputs match [check_equiv]'s oracle exactly —
     no vport, so the whole list mounts like an ordinary column. *)
  Lui_layout.sync ~width:200. ~height:100. t store;
  check int "mounted all" 30 (Lui_layout.mounted_count t 2);
  (* Layout prop on a mounted row replays through the journal. *)
  apply store [ SetProp (15, HeightValue, IntValue 60) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check bool "incremental path" true (Lui_layout.stat_steps t > 0);
  check_equiv "row resized" store t;
  (* A structural op under the list: a new row splices in. *)
  apply store
    [ CreateNode (200, ListItem); InsertChild (2, 200, 3);
      SetProp (200, HeightValue, IntValue 25) ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "row inserted" store t;
  (* And one removed again, then dropped. *)
  apply store [ RemoveChild (2, 12); DropNode 12 ];
  Lui_layout.sync ~width:200. ~height:100. t store;
  check_equiv "row dropped" store t

let () =
  run "lui_layout"
    [ ("layout",
       [ test_case "column padding/gap" `Quick test_column_padding_gap;
         test_case "grid wraps" `Quick test_grid_wraps;
         test_case "grid gap fits" `Quick test_grid_gap_fits_columns;
         test_case "absolute inset" `Quick test_absolute_inset;
         test_case "text measured" `Quick test_text_measured;
         test_case "percent size" `Quick test_percent_size;
         test_case "column in row" `Quick test_nested_column_in_row;
         test_case "run placements" `Quick test_run_placements;
         test_case "display none" `Quick test_display_none_absent;
         test_case "rebuild" `Quick test_rebuild_after_mutation;
         test_case "sync memoized" `Quick test_sync_memoized;
         test_case "paint prop skips layout" `Quick test_paint_prop_skips_layout;
         test_case "frame grows" `Quick test_frame_grows_to_content;
         test_case "popup centered" `Quick test_popup_default_centered;
         test_case "root popup" `Quick test_root_popup_centered_in_frame;
         test_case "menu panel" `Quick test_menu_panel;
         test_case "ac row" `Quick test_ac_row;
         test_case "vlist window" `Quick test_vlist_window_mounts_slice;
         test_case "vlist window moves" `Quick test_vlist_window_moves;
         test_case "vlist measured" `Quick test_vlist_measured_extents;
         test_case "vlist gap" `Quick test_vlist_gap;
         test_case "vlist unwindowed" `Quick test_vlist_unwindowed;
         test_case "vlist incremental child" `Quick
           test_vlist_incremental_child;
         test_case "snapped edges" `Quick test_snapped_edges;
         test_case "incremental equivalence" `Quick
           test_incremental_equivalence;
         test_case "incremental random" `Quick test_incremental_random;
         test_case "incremental root shift" `Quick
           test_incremental_root_shift;
         test_case "incremental large tree" `Quick
           test_incremental_large_tree ]) ]
