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
         test_case "frame grows" `Quick test_frame_grows_to_content;
         test_case "popup centered" `Quick test_popup_default_centered;
         test_case "root popup" `Quick test_root_popup_centered_in_frame;
         test_case "menu panel" `Quick test_menu_panel;
         test_case "ac row" `Quick test_ac_row ]) ]
