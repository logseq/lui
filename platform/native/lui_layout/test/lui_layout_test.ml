(* Layout glue tests: wire store → flex mirror → scene rects. *)

open Lui_protocol
open Alcotest

let batch ops = { generation = 1; ops }

let apply t ops = Lui_store.apply_batch t (batch ops)

let no_measure _id _w _h = None

let no_measure4 _id _text _w _h = None

let () = match Sys.getenv_opt "LUI_LAYOUT_TRACE_REPLAY" with
  | None -> ()
  | Some path ->
    let layout = Lui_layout.create () in
    let hidden_nodes = Hashtbl.create 16 in
    let hidden id = Hashtbl.mem hidden_nodes id in
    In_channel.with_open_bin path (fun channel ->
      let frame = ref 0 in
      let rec replay () = match (Marshal.from_channel channel :
          Lui_store.t * float * float * float * int list * (float * float) option) with
        | store,width,height,scale,hidden_ids,anchor ->
          incr frame;
          Hashtbl.reset hidden_nodes;
          List.iter (fun id -> Hashtbl.add hidden_nodes id ()) hidden_ids;
          Printf.printf "trace frame=%d nodes=%d\n%!" !frame (Lui_store.node_count store);
          Lui_layout.sync ~scale ~hidden ?ctx_anchor:anchor ~width ~height layout store;
          replay ()
        | exception End_of_file -> () in
      replay ())

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

let test_picker_intrinsic_width () =
  List.iter
    (fun scale ->
      List.iter
        (fun kind ->
          List.iter
            (fun padding ->
              List.iter
                (fun gap ->
                  let store = Lui_store.create () in
                  apply store
                    ([
                       CreateNode (1, Root);
                       CreateNode (2, Row);
                       CreateNode (3, kind);
                       InsertChild (1, 2, 0);
                       InsertChild (2, 3, 0);
                       SetProp (3, TextValue, StringValue "Descending");
                       SetProp (3, PaddingHorizontal, IntValue padding);
                     ]
                    @ Option.fold ~none:[]
                        ~some:(fun value ->
                          [ SetProp (3, Gap, IntValue value) ])
                        gap);
                  let layout = Lui_layout.create () in
                  Lui_layout.sync ~scale ~width:(500. *. scale)
                    ~height:(100. *. scale)
                    ~measure:(fun _ _ _ _ -> Some (80. *. scale, 20. *. scale))
                    layout store;
                  let r = Option.get (Lui_layout.rect layout 3) in
                  let tp = Lui_paint.text_placement_of store 3 in
                  let label_end = r.x +. ((tp.tp_pad_left +. 80.) *. scale) in
                  let indicator_start =
                    r.x +. r.w -. ((tp.tp_pad_right +. 16.) *. scale)
                  in
                  let gap = float_of_int (Option.value gap ~default:8) in
                  check bool
                    "picker width reserves the indicator and requested label \
                     gap"
                    true
                    (indicator_start -. label_end >= (gap *. scale) -. 1.);
                  check (float 1.) "picker does not reserve a second indicator"
                    ((80. +. 16. +. gap +. (2. *. float_of_int padding))
                    *. scale)
                    r.w)
                [ None; Some 0; Some 4; Some 16 ])
            [ 0; 8; 20 ])
        [ Select; Combobox ])
    [ 1.; 2. ]

let test_button_icon_gap () =
  List.iter (fun scale -> List.iter (fun gap ->
    let store = Lui_store.create () in
    apply store ([CreateNode (1,Root);CreateNode (2,Row);CreateNode (3,Button);
      InsertChild (1,2,0);InsertChild (2,3,0);
      SetProp (3,TextValue,StringValue "Add property");
      SetProp (3,InlineIconName,StringValue "plus");
      SetProp (3,PaddingHorizontal,IntValue 12)]
      @ Option.fold ~none:[] ~some:(fun value -> [SetProp (3,Gap,IntValue value)]) gap);
    let layout = Lui_layout.create () in
    Lui_layout.sync ~scale ~width:(500.*.scale) ~height:(100.*.scale)
      ~measure:(fun _ _ _ _ -> Some (80.*.scale,20.*.scale)) layout store;
    let r = Option.get (Lui_layout.rect layout 3) in
    check (float 0.1) "button reserves its label, icon, requested gap and padding"
      ((80.+.16.+.float_of_int (Option.value gap ~default:6)+.24.)*.scale) r.w)
    [None;Some 0;Some 4;Some 16]) [1.;2.]

let test_list_item_content_flow () =
  List.iter
    (fun scale ->
      let store = Lui_store.create () and layout = Lui_layout.create () in
      apply store
        [
          CreateNode (1, Root);
          CreateNode (2, ListItem);
          CreateNode (3, Box);
          CreateNode (4, Box);
          InsertChild (1, 2, 0);
          InsertChild (2, 3, 0);
          InsertChild (2, 4, 1);
          SetProp (2, WidthValue, IntValue 100);
          SetProp (2, HeightValue, IntValue 40);
          SetProp (2, PaddingValue, IntValue 0);
          SetProp (3, WidthValue, IntValue 10);
          SetProp (3, HeightValue, IntValue 10);
          SetProp (4, WidthValue, IntValue 20);
          SetProp (4, HeightValue, IntValue 20);
        ];
      let expect x1 y1 x2 y2 =
        Lui_layout.sync ~scale ~width:(200. *. scale) ~height:(80. *. scale)
          layout store;
        let item = Option.get (Lui_layout.rect layout 2) in
        let child id x y w h =
          check_some_rect "list item child"
            (item.x +. (x *. scale))
            (item.y +. (y *. scale))
            (w *. scale) (h *. scale)
            (Lui_layout.rect layout id)
        in
        child 3 x1 y1 10. 10.;
        child 4 x2 y2 20. 20.
      in
      expect 0. 15. 18. 10.;
      apply store
        [
          SetProp (2, MainAlignment, StringValue "end");
          SetProp (2, CrossAlignment, StringValue "start");
        ];
      expect 62. 0. 80. 0.;
      apply store [ SetProp (2, WidthValue, IntValue 160) ];
      expect 122. 0. 140. 0.;
      apply store
        [ RemoveProp (2, CrossAlignment); RemoveProp (2, MainAlignment) ];
      expect 0. 15. 18. 10.)
    [ 1.; 2. ]

let test_padding_edges () =
  let property name =
    match
      List.find_opt
        (fun p -> Lui_wire_schema.property_name p = name)
        Lui_wire_schema.all_properties
    with
    | Some p -> p
    | None -> fail ("Missing typed property: " ^ name)
  in
  let top = property "padding-top"
  and right = property "padding-right"
  and bottom = property "padding-bottom"
  and left = property "padding-left" in
  List.iter
    (fun scale ->
      let store = Lui_store.create () and layout = Lui_layout.create () in
      apply store
        [
          CreateNode (1, Root);
          CreateNode (2, Column);
          CreateNode (3, Box);
          InsertChild (1, 2, 0);
          InsertChild (2, 3, 0);
          SetProp (2, WidthValue, IntValue 100);
          SetProp (2, HeightValue, IntValue 80);
          SetProp (2, PaddingValue, IntValue 5);
          SetProp (2, PaddingHorizontal, IntValue 10);
          SetProp (2, PaddingVertical, IntValue 6);
          SetProp (3, GrowValue, FloatValue 1.);
        ];
      let expect label l t r b =
        Lui_layout.sync ~scale ~width:(200. *. scale) ~height:(120. *. scale)
          layout store;
        check_some_rect label (l *. scale) (t *. scale)
          ((100. -. l -. r) *. scale)
          ((80. -. t -. b) *. scale)
          (Lui_layout.rect layout 3)
      in
      expect "axis padding" 10. 6. 10. 6.;
      apply store
        [
          SetProp (2, left, IntValue 28);
          SetProp (2, right, IntValue 8);
          SetProp (2, top, IntValue 3);
          SetProp (2, bottom, IntValue 9);
        ];
      expect "sides override axes" 28. 3. 8. 9.;
      apply store
        [ SetProp (2, left, IntValue 0); SetProp (2, bottom, IntValue 0) ];
      expect "zero side padding invalidates retained layout" 0. 3. 8. 0.;
      apply store
        [
          RemoveProp (2, left);
          RemoveProp (2, right);
          RemoveProp (2, top);
          RemoveProp (2, bottom);
        ];
      expect "removing sides restores axes" 10. 6. 10. 6.;
      apply store
        [ RemoveProp (2, PaddingHorizontal); RemoveProp (2, PaddingVertical) ];
      expect "removing axes restores uniform padding" 5. 5. 5. 5.)
    [ 1.; 2. ]

let test_absolute_cross_alignment () =
  List.iter
    (fun scale ->
      List.iter
        (fun kind ->
          List.iter
            (fun intrinsic ->
              let store = Lui_store.create ()
              and layout = Lui_layout.create () in
              let cross_size = if kind = Row then HeightValue else WidthValue in
              let leading = if kind = Row then InsetTop else InsetLeft in
              let trailing = if kind = Row then InsetBottom else InsetRight in
              apply store
                ([
                   CreateNode (1, Root);
                   CreateNode (2, kind);
                   CreateNode (3, Box);
                   CreateNode (4, Box);
                   CreateNode (5, Box);
                   InsertChild (1, 2, 0);
                   InsertChild (2, 3, 0);
                   InsertChild (2, 4, 1);
                   InsertChild (4, 5, 0);
                   SetProp (2, WidthValue, IntValue 100);
                   SetProp (2, HeightValue, IntValue 80);
                   SetProp (2, PaddingHorizontal, IntValue 10);
                   SetProp (2, PaddingVertical, IntValue 6);
                   SetProp (2, BorderWidth, IntValue 2);
                   SetProp (3, WidthValue, IntValue 30);
                   SetProp (3, HeightValue, IntValue 20);
                   SetProp (4, Position, StringValue "absolute");
                   SetProp (5, WidthValue, IntValue 20);
                   SetProp (5, HeightValue, IntValue 10);
                 ]
                @
                if intrinsic then []
                else
                  [
                    SetProp (4, WidthValue, IntValue 20);
                    SetProp (4, HeightValue, IntValue 10);
                  ]);
              let expect label value =
                Lui_layout.sync ~scale ~width:(200. *. scale)
                  ~height:(160. *. scale) layout store;
                let child = Option.get (Lui_layout.rect layout 4) in
                let actual = if kind = Row then child.y else child.x in
                check (float eps) label (value *. scale) actual
              in
              let origin, available, extent =
                if kind = Row then (8., 64., 10.) else (12., 76., 20.)
              in
              List.iter
                (fun (align, offset) ->
                  apply store [ SetProp (2, CrossAlignment, StringValue align) ];
                  expect "absolute static cross alignment" (origin +. offset))
                [
                  ("start", 0.);
                  ("stretch", 0.);
                  ("center", (available -. extent) /. 2.);
                  ("end", available -. extent);
                ];
              apply store [ SetProp (2, CrossAlignment, StringValue "center") ];
              apply store [ SetProp (4, leading, FloatValue 4.) ];
              expect "leading inset overrides alignment" 6.;
              apply store
                [
                  RemoveProp (4, leading); SetProp (4, trailing, FloatValue 4.);
                ];
              expect "trailing inset overrides alignment"
                ((if kind = Row then 80. else 100.) -. 6. -. extent);
              apply store
                [
                  RemoveProp (4, trailing); SetProp (2, cross_size, IntValue 120);
                ];
              expect "resize recomputes static alignment"
                ((120. -. extent) /. 2.);
              let cross_before, cross_after, delta =
                if kind = Row then (PaddingTop, PaddingBottom, 8.)
                else (PaddingLeft, PaddingRight, 20.)
              in
              apply store
                [
                  SetProp
                    (2, cross_before, IntValue (if kind = Row then 10 else 28));
                  SetProp
                    (2, cross_after, IntValue (if kind = Row then 2 else 8));
                ];
              expect "static alignment uses asymmetric content edges"
                ((120. -. extent +. delta) /. 2.);
              if not intrinsic then begin
                apply store [ SetProp (4, cross_size, IntValue 200) ];
                expect "oversized absolute content retains center alignment"
                  ((120. -. 200. +. delta) /. 2.)
              end)
            [ false; true ])
        [ Row; Column ])
    [ 1.; 2. ]

let test_border_box_layout () =
  List.iter
    (fun scale ->
      let store = Lui_store.create () and layout = Lui_layout.create () in
      apply store
        [
          CreateNode (1, Root);
          CreateNode (2, Column);
          CreateNode (3, Box);
          InsertChild (1, 2, 0);
          InsertChild (2, 3, 0);
          SetProp (2, WidthValue, IntValue 100);
          SetProp (2, HeightValue, IntValue 80);
          SetProp (2, PaddingValue, IntValue 5);
          SetProp (3, GrowValue, FloatValue 1.);
        ];
      let sync () =
        Lui_layout.sync ~scale ~width:(200. *. scale) ~height:(120. *. scale)
          layout store
      in
      let expect label (top, right, bottom, left) =
        sync ();
        (* Exported geometry snaps edges to physical pixels. *)
        let x = Float.round ((5. +. left) *. scale) in
        let y = Float.round ((5. +. top) *. scale) in
        check_some_rect label x y
          (Float.round ((95. -. right) *. scale) -. x)
          (Float.round ((75. -. bottom) *. scale) -. y)
          (Lui_layout.rect layout 3)
      in
      List.iter
        (fun (value, edges) ->
          apply store [ SetProp (2, BorderWidth, value) ];
          expect "border insets the child" edges)
        [
          (IntValue 3, (3., 3., 3., 3.));
          (FloatValue 1.5, (1.5, 1.5, 1.5, 1.5));
          (StringValue "1 2 3 4", (1., 2., 3., 4.));
          (IntValue 6, (6., 6., 6., 6.));
          (IntValue 0, (0., 0., 0., 0.));
        ];
      let revision = Lui_store.layout_rev store in
      apply store [ SetProp (2, BorderColorValue, StringValue "red") ];
      check int "border color remains paint-only" revision
        (Lui_store.layout_rev store))
    [ 1.; 2. ]

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

(* Dialog width caps also respect the viewport during repeated resize. *)
let test_dialog_viewport_width () =
  List.iter
    (fun scale ->
      List.iter
        (fun (declared, explicit_width) ->
          let store = Lui_store.create () and layout = Lui_layout.create () in
          apply store
            ([
               CreateNode (1, Root);
               CreateNode (2, Dialog);
               CreateNode (3, Box);
               InsertChild (1, 2, 0);
               InsertChild (2, 3, 0);
               SetProp (3, WidthValue, IntValue 1400);
               SetProp (3, HeightValue, IntValue 100);
             ]
            @ (match explicit_width with
              | None -> []
              | Some width -> [ SetProp (2, WidthValue, IntValue width) ])
            @
            match declared with
            | None -> []
            | Some cap -> [ SetProp (2, MaxWidth, IntValue cap) ]);
          List.iter
            (fun width ->
              Lui_layout.sync ~scale ~width:(width *. scale)
                ~height:(600. *. scale) layout store;
              let r = Option.get (Lui_layout.rect layout 2) in
              let cap =
                match declared with
                | Some cap -> float_of_int cap
                | None -> (
                    match explicit_width with
                    | Some size -> float_of_int size
                    | None -> if width >= 1024. then 768. else 672.)
              in
              let expected = Float.min cap (width -. 32.) *. scale in
              check (float eps)
                "dialog width respects its declared cap and available viewport"
                expected r.w;
              check (float eps) "bounded dialog stays centered"
                (((width *. scale) -. expected) /. 2.)
                r.x)
            [ 1440.; 600.; 800.; 1440. ])
        [
          (None, None);
          (Some 768, None);
          (Some 1246, None);
          (Some 400, None);
          (None, Some 898);
        ])
    [ 1.; 2. ]

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

let test_popup_collision_flip () =
  let store = Lui_store.create () in
  apply store
    [ CreateNode (1, Root); CreateNode (2, Popover);
      InsertChild (1, 2, 0);
      SetProp (2, WidthValue, IntValue 60);
      SetProp (2, HeightValue, IntValue 40);
      SetProp (2, AnchorOffset, FloatValue 4.) ];
  let check_at ~scale side x y expected_x expected_y =
    apply store [SetProp (2, AnchorValue, StringValue side);
      SetProp (2, PopupX, FloatValue x); SetProp (2, PopupY, FloatValue y)];
    let p = Lui_layout.run ~scale store ~measure:no_measure
      ~width:(200. *. scale) ~height:(160. *. scale) in
    check_rect (side ^ " popup") (expected_x *. scale) (expected_y *. scale)
      (60. *. scale) (40. *. scale) (place p 2)
  in
  List.iter (fun scale ->
    check_at ~scale "below" 80. 140. 80. 96.;
    check_at ~scale "above" 80. 20. 80. 24.;
    check_at ~scale "right" 180. 60. 116. 60.;
    check_at ~scale "left" 20. 60. 24. 60.;
    check_at ~scale "below" 80. 40. 80. 44.;
    check_at ~scale "above" 80. 100. 80. 56.;
    check_at ~scale "right" 80. 60. 84. 60.;
    check_at ~scale "left" 100. 60. 36. 60.;
    (* Cross-axis overflow shifts without changing the preferred side. *)
    check_at ~scale "below" 190. 40. 140. 44.) [1.; 2.];
  (* Neither side fits: use the side with more room, then clamp. *)
  apply store [SetProp (2, HeightValue, IntValue 140);
    SetProp (2, PopupY, FloatValue 100.)];
  let p = Lui_layout.run store ~measure:no_measure ~width:200. ~height:160. in
  check_rect "oversized popup stays in frame" 140. 0. 60. 140. (place p 2)

let test_popup_inside_centered_dialog () =
  List.iter (fun scale ->
    let store=Lui_store.create () and layout=Lui_layout.create () in
    apply store [CreateNode (1,Root);CreateNode (2,Dialog);CreateNode (3,Column);
      CreateNode (4,Spacer);CreateNode (5,Box);InsertChild (1,2,0);
      InsertChild (2,3,0);InsertChild (3,4,0);InsertChild (3,5,1);
      SetProp (2,WidthValue,IntValue 600);SetProp (2,HeightValue,IntValue 400);
      SetProp (2,PaddingValue,IntValue 24);SetProp (4,HeightValue,IntValue 100);
      SetProp (5,WidthValue,IntValue 200);SetProp (5,HeightValue,IntValue 32)];
    let sync width height = Lui_layout.sync ~scale ~width:(width*.scale)
      ~height:(height*.scale) layout store in
    sync 800. 600.;
    apply store [CreateNode (6,DropdownMenu);InsertChild (5,6,0);
      SetProp (6,WidthValue,IntValue 180);SetProp (6,HeightValue,IntValue 120);
      SetProp (6,AnchorValue,StringValue "below")];
    sync 800. 600.;
    let rect id=Option.get (Lui_layout.rect layout id) in
    let anchor=rect 5 and popup=rect 6 in
    check (float eps) "nested popup follows final trigger x" anchor.x popup.x;
    check (float eps) "nested popup follows final trigger y"
      (anchor.y+.anchor.h+.4.*.scale) popup.y;
    apply store [SetProp (6,HeightValue,IntValue 500)];
    sync 800. 600.;
    let popup=rect 6 in
    check bool "nested tall popup stays in viewport" true
      (popup.y>=0. && popup.y+.popup.h<=600.*.scale+.eps);
    sync 640. 480.;
    let popup=rect 6 in
    check bool "nested popup remains bounded after resize" true
      (popup.x>=0. && popup.y>=0. && popup.x+.popup.w<=640.*.scale+.eps
       && popup.y+.popup.h<=480.*.scale+.eps);
    Lui_layout.invalidate layout;
    sync 640. 480.;
    let popup=rect 6 in
    check bool "nested popup remains bounded after rebuilding the open tree" true
      (popup.x>=0. && popup.y>=0. && popup.x+.popup.w<=640.*.scale+.eps
       && popup.y+.popup.h<=480.*.scale+.eps)) [1.;2.]

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

(* The mounted window's store ids — what paint and hit-test slice to. *)
let test_vlist_mounted_children () =
  let store = vlist_store ~n:1000 () in
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 500. 200.) t store;
  let f, l = Option.get (Lui_layout.mounted_range t 2) in
  let ids = Option.get (Lui_layout.mounted_children t 2) in
  check int "window size" (l - f) (List.length ids);
  check int "first id" (10 + f) (List.hd ids);
  check int "last id" (10 + l - 1) (List.nth ids (l - f - 1))

(* Variable heights settle through measured extents: overscan rows
   above the anchor that differ from the estimate shift the prefix
   sums — the drift the scroller folds back into the offset so the
   anchored row does not visibly jump. *)
let test_vlist_anchor_drift () =
  let store = Lui_store.create () in
  let ops =
    ref
      [ InsertChild (1, 2, 0);
        SetProp
          (2, DataAttrs,
            StringValue
              (Lui_protocol.data_attrs_encode
                 [ ("data-item-extent", "20") ]));
        CreateNode (2, VirtualList); CreateNode (1, Root) ]
  in
  for i = 0 to 99 do
    let id = 10 + i in
    (* Rows 46-49 are really 60 px against the 20-px estimate. *)
    ops :=
      InsertChild (2, id, i)
      :: SetProp
           (id, HeightValue,
             FloatValue (if i >= 46 && i < 50 then 60. else 20.))
      :: CreateNode (id, ListItem) :: !ops
  done;
  Lui_store.apply_batch store { generation = 1; ops = List.rev !ops };
  let t = Lui_layout.create () in
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 0. 300.) t store;
  (* Anchor is item 0 — nothing above it can move. *)
  check (float eps) "no drift at top" 0.
    (Lui_layout.virtual_take_drift t 2);
  (* Jump mid-list: rows 46-49 mount in the overscan band and measure
     60 instead of the 20 estimate — prefix(anchor=50) grew by 160. *)
  Lui_layout.sync ~measure:no_measure4 ~width:100. ~height:800.
    ~vport:(vport 1000. 300.) t store;
  check (float eps) "drift" 160. (Lui_layout.virtual_take_drift t 2);
  (* consume-on-read *)
  check (float eps) "consumed" 0. (Lui_layout.virtual_take_drift t 2);
  (* the model reports corrected positions: item 50 sits at
     46*20 + 4*60 = 1160 *)
  check_some_rect "item50" 0. 1160. 100. 20.
    (Lui_layout.virtual_item_rect t 2 ~index:50)

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

let test_child_restyle_allocation () =
  let allocation count =
    let store = Lui_store.create () in
    apply store ([CreateNode (1, Root); CreateNode (2, Grid);
      InsertChild (1, 2, 0); SetProp (2, GridColumns, IntValue 2)] @
      List.concat_map (fun i -> [CreateNode (i+10, Text);
        InsertChild (2, i+10, i); SetProp (i+10, HeightValue, IntValue 10)])
        (List.init count Fun.id));
    let layout = Lui_layout.create () in
    let sync () = Lui_layout.sync ~width:200. ~height:100. layout store in
    sync ();
    let change columns = apply store [SetProp (2, GridColumns, IntValue columns)]; sync () in
    change 3; change 2;
    let before = Gc.allocated_bytes () in
    for step=1 to 4 do change (if step mod 2=0 then 2 else 3) done;
    let bytes = (Gc.allocated_bytes () -. before) /. 4. in
    check bool "Restyling retains incremental replay" true (Lui_layout.stat_steps layout >= 6);
    check_some_rect "First grid cell keeps its width" 0. 0. 100. 10.
      (Lui_layout.rect layout 10);
    bytes
  in
  let small = allocation 64 and large = allocation 1024 in
  Printf.printf "Child restyle allocation: 64=%.0f, 1024=%.0f bytes/update\n%!" small large;
  check bool "Restyling 16 times as many children exceeds 1.3 times linear allocation" true
    (large <= small *. 16. *. 1.3)

let test_child_restyle_produced_order () =
  let store = Lui_store.create () in
  apply store [CreateNode (1, Root); CreateNode (2, Overlay);
    CreateNode (3, Text); CreateNode (4, Box); CreateNode (5, Text);
    CreateNode (6, Box); CreateNode (7, Text); CreateNode (8, Box);
    CreateNode (9, Text); CreateNode (10, Text);
    InsertChild (1,2,0); InsertChild (2,3,0); InsertChild (2,4,1);
    InsertChild (4,5,0); InsertChild (4,6,1); InsertChild (6,7,0);
    InsertChild (2,8,2); InsertChild (8,9,0); InsertChild (2,10,3);
    SetProp (4,DisplayValue,StringValue "contents");
    SetProp (6,DisplayValue,StringValue "contents");
    SetProp (8,DisplayValue,StringValue "none");
    SetProp (3,WidthValue,IntValue 40); SetProp (3,HeightValue,IntValue 20);
    SetProp (5,HeightValue,IntValue 10); SetProp (7,HeightValue,IntValue 15);
    SetProp (9,HeightValue,IntValue 30); SetProp (10,HeightValue,IntValue 25)];
  let layout = Lui_layout.create () in
  let verify ops =
    apply store ops;
    Lui_layout.sync ~width:200. ~height:100. layout store;
    check_equiv "Produced child restyle" store layout
  in
  List.iter verify [ [];
    [SetProp (4,ProgressValue,IntValue 1)];
    [SetProp (6,ProgressValue,IntValue 2)];
    [MoveChild (2,4,0)];
    [MoveChild (4,5,1)];
    [SetProp (8,DisplayValue,StringValue "contents"); MoveChild (2,8,0)];
    [SetProp (4,ProgressValue,IntValue 3)];
    [SetProp (4,DisplayValue,StringValue "none")];
    [RemoveProp (4,DisplayValue)];
    [SetProp (4,DisplayValue,StringValue "contents")];
    [SetProp (2,ProgressValue,IntValue 4)] ]

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

let test_resize_retains_measurements () =
  let store = Lui_store.create () in
  apply store [CreateNode (1, Column); SetProp (1, HeightViewport, FloatValue 1.)];
  for index = 0 to 99 do
    let id = index + 2 in
    apply store [CreateNode (id, Text); InsertChild (1,id,index);
      SetProp (id, WidthValue, IntValue 100); SetProp (id, TextValue, StringValue "hello")]
  done;
  let measured = ref 0 in
  let measure _ _ _ _ = incr measured; Some (100.,20.) in
  let layout = Lui_layout.create () in
  Lui_layout.sync ~measure ~width:400. ~height:800. layout store;
  measured := 0;
  Lui_layout.sync ~measure ~width:500. ~height:700. layout store;
  check int "Fixed-width text is remeasured during viewport resize" 0 !measured;
  check_some_rect "Viewport-height root" 0. 0. 500. 700. (Lui_layout.rect layout 1);
  let fresh = Lui_layout.create () in
  Lui_layout.sync ~measure ~width:500. ~height:700. fresh store;
  for id = 1 to 101 do
    check (option (of_pp (fun formatter rect -> Format.fprintf formatter "%g,%g %gx%g" rect.Lui_scene.x rect.y rect.w rect.h))) "Resize geometry differs from fresh layout"
      (Lui_layout.rect fresh id) (Lui_layout.rect layout id)
  done

let test_deep_rect_refresh_budget () =
  let store = Lui_store.create () in
  Lui_store.apply_op store (CreateNode (1, Column));
  let next = ref 2 and last = ref 0 in
  for branch = 0 to 127 do
    let parent = ref 1 in
    for depth = 0 to 32 do
      let id = !next in incr next;
      Lui_store.apply_op store (CreateNode (id, Column));
      Lui_store.apply_op store (InsertChild (!parent,id,if depth=0 then branch else 0));
      parent := id;
      if depth=32 then begin
        Lui_store.apply_op store (SetProp (id,HeightValue,IntValue 1)); last := id
      end
    done
  done;
  let layout = Lui_layout.create () in
  Lui_layout.sync ~width:1000. ~height:600. layout store;
  Lui_store.apply_op store (SetProp (1,MarginTop,IntValue 1));
  Gc.full_major ();
  let before = Gc.allocated_bytes () in
  Lui_layout.sync ~width:1000. ~height:600. layout store;
  let allocated = Gc.allocated_bytes () -. before in
  check bool (Printf.sprintf "deep absolute geometry refresh allocates %.0f bytes" allocated)
    true (allocated < 2097152.);
  check_some_rect "last leaf follows ancestor offset" 0. 128. 1000. 1.
    (Lui_layout.rect layout !last);
  Lui_store.apply_op store (SetProp (!last,HeightValue,IntValue 2));
  Lui_layout.sync ~width:1000. ~height:600. layout store;
  check_some_rect "scoped refresh follows current ancestry" 0. 128. 1000. 2.
    (Lui_layout.rect layout !last)

let test_created_subtree_mirrored_once () =
  let store = Lui_store.create () and layout = Lui_layout.create () in
  apply store [CreateNode (1,Column)];
  Lui_layout.sync ~width:200. ~height:100. layout store;
  let ops = ref [] in
  for id = 2 to 81 do
    ops := InsertChild (id-1,id,0)
      :: SetProp (id,MarginTop,IntValue 0) :: SetProp (id,MarginBottom,IntValue 0)
      :: SetProp (id,PaddingValue,IntValue 0) :: SetProp (id,WidthValue,IntValue 200)
      :: SetProp (id,Gap,IntValue 0) :: CreateNode (id,Column) :: !ops
  done;
  apply store (List.rev !ops @ [SetProp (81,HeightValue,IntValue 10)]);
  let before = Gc.allocated_bytes () in
  Lui_layout.sync ~width:200. ~height:100. layout store;
  let allocated = Gc.allocated_bytes () -. before in
  Printf.printf "created subtree allocated %.0f bytes\n%!" allocated;
  check bool "A new subtree must not be mirrored again for each descendant create"
    true (allocated < 1500000.);
  check_some_rect "new leaf" 0. 0. 200. 10. (Lui_layout.rect layout 81);
  check_equiv "new subtree" store layout

let test_created_identity_reuse () =
  let store = Lui_store.create () and layout = Lui_layout.create () in
  let settle message ops =
    apply store ops;
    Lui_layout.sync ~width:200. ~height:100. layout store;
    check_equiv message store layout in
  settle "initial" [CreateNode (1,Column); CreateNode (2,Column); CreateNode (3,Text);
    CreateNode (4,Text); InsertChild (1,2,0); InsertChild (2,3,0); InsertChild (2,4,1)];
  settle "replace parent identity" [DropNode 2; CreateNode (2,Column);
    CreateNode (3,Text); InsertChild (1,2,0); InsertChild (2,3,0);
    SetProp (3,HeightValue,IntValue 20)];
  check (option reject) "old descendants released" None (Lui_layout.rect layout 4);
  settle "replace attached child identity" [CreateNode (3,Text);
    SetProp (3,HeightValue,IntValue 30); InsertChild (2,3,0)];
  settle "drop then recreate newly inserted identity" [CreateNode (5,Column);
    InsertChild (1,5,1); DropNode 5; CreateNode (5,Text);
    SetProp (5,HeightValue,IntValue 15)];
  settle "created subtree disappears in batch" [CreateNode (6,Column);
    CreateNode (7,Text); InsertChild (1,6,1); InsertChild (6,7,0); DetachSubtree 6];
  List.iter (fun id -> check (option reject) "transient descendants released" None
    (Lui_layout.rect layout id)) [6;7]

let test_updates_before_subtree_disposal () =
  let store = Lui_store.create () and layout = Lui_layout.create () in
  apply store [CreateNode (1,Column); CreateNode (2,Column); CreateNode (3,Column);
    CreateNode (4,Text); InsertChild (1,2,0); InsertChild (2,3,0); InsertChild (3,4,0)];
  Lui_layout.sync ~width:200. ~height:100. layout store;
  (* A queued property update remains valid in the wire transaction even
     when a later scope disposal removes its target and descendants. *)
  apply store [SetProp (3,Gap,IntValue 8); SetExtensionProp (3,"height",StringValue "40");
    DetachSubtree 2];
  Lui_layout.sync ~width:200. ~height:100. layout store;
  Lui_layout.sync ~width:180. ~height:100. layout store;
  Lui_layout.sync ~width:200. ~height:100. layout store;
  check_equiv "queued update then disposal" store layout;
  List.iter (fun id -> check (option reject) "disposed descendant geometry" None
    (Lui_layout.rect layout id)) [2;3;4]

let test_transient_links_before_disposal () =
  let store = Lui_store.create () and layout = Lui_layout.create () in
  let settle message ops =
    apply store ops;
    Lui_layout.sync ~width:200. ~height:100. layout store;
    Lui_layout.sync ~width:180. ~height:100. layout store;
    Lui_layout.sync ~width:200. ~height:100. layout store;
    check_equiv message store layout in
  settle "initial" [CreateNode (1,Column); CreateNode (2,Column);
    InsertChild (1,2,0)];
  settle "transient editor subtree" [CreateNode (3,Column); CreateNode (4,Column);
    CreateNode (5,Text); InsertChild (2,3,0); InsertChild (3,4,0);
    InsertChild (4,5,0); DetachSubtree 3];
  settle "insert inside disposed owner" [CreateNode (6,Column); InsertChild (2,6,0)];
  settle "queued child inside disposed owner" [CreateNode (7,Column); CreateNode (8,Text);
    InsertChild (6,7,0); InsertChild (7,8,0); DetachSubtree 6];
  settle "reparent final child" [CreateNode (9,Column); CreateNode (10,Text);
    InsertChild (2,9,0); InsertChild (9,10,0); MoveChild (1,10,1); DetachSubtree 9];
  settle "remove and reinsert live child" [RemoveChild (1,10); InsertChild (1,10,0)];
  settle "discard old position before final move" [CreateNode (11,Column);
    InsertChild (2,11,0); MoveChild (11,10,0); MoveChild (1,10,1); DetachSubtree 11]

let test_nested_disposal_purges_geometry () =
  let store = Lui_store.create () in
  apply store [CreateNode (1,Column); CreateNode (2,Column); CreateNode (3,Column);
    CreateNode (4,Text); CreateNode (5,Text); InsertChild (1,2,0); InsertChild (1,3,1);
    InsertChild (2,4,0); InsertChild (3,5,0);
    SetProp (4,HeightValue,IntValue 10); SetProp (5,HeightValue,IntValue 10)];
  let layout = Lui_layout.create () in
  Lui_layout.sync ~width:100. ~height:40. layout store;
  (* Scope disposal can drop one child before dropping its enclosing root
     in the same batch. The mirror must retain the other child until purge. *)
  apply store [DetachSubtree 2; DetachSubtree 1];
  Lui_layout.sync ~width:100. ~height:40. layout store;
  for id = 1 to 5 do
    check (option reject) "disposed geometry is released" None (Lui_layout.rect layout id)
  done;
  apply store [CreateNode (6,Text); SetProp (6,HeightValue,IntValue 20)];
  Lui_layout.sync ~width:100. ~height:40. layout store;
  check_some_rect "subsequent root fills frame" 0. 0. 100. 40. (Lui_layout.rect layout 6)

let test_fractional_ancestor_offsets () =
  let store = Lui_store.create () in
  apply store [CreateNode (1,Column);CreateNode (2,Column);CreateNode (3,Column);
    InsertChild (1,2,0);InsertChild (2,3,0);
    SetProp (1,MarginLeft,FloatValue 0.3);SetProp (2,MarginLeft,FloatValue 0.3);
    SetProp (3,MarginLeft,FloatValue 0.3);SetProp (3,WidthValue,IntValue 40);
    SetProp (3,HeightValue,IntValue 10)];
  let layout = Lui_layout.create () in
  Lui_layout.sync ~width:100. ~height:40. layout store;
  check_some_rect "ancestors stay unsnapped" 1. 0. 40. 10. (Lui_layout.rect layout 3);
  apply store [SetProp (2,MarginLeft,FloatValue 0.9)];
  Lui_layout.sync ~width:100. ~height:40. layout store;
  check_some_rect "fractional ancestor update" 2. 0. 40. 10. (Lui_layout.rect layout 3)

let test_split_gap_fraction () =
  let store = Lui_store.create () in
  apply store
    [
      CreateNode (1, Split);
      CreateNode (2, Column);
      CreateNode (3, Column);
      SetProp (1, Gap, IntValue 3);
      InsertChild (1, 2, 0);
      InsertChild (1, 3, 1);
    ];
  let layout = Lui_layout.create () in
  List.iter
    (fun scale ->
      List.iter
        (fun value ->
          apply store [ SetProp (1, ProgressValue, FloatValue value) ];
          Lui_layout.sync ~scale ~width:1000. ~height:400. layout store;
          let first = Option.get (Lui_layout.rect layout 2)
          and second = Option.get (Lui_layout.rect layout 3) in
          let available = 1000. -. (3. *. scale) in
          check (float 0.6) "first pane uses the track excluding its divider"
            (available *. value) first.w;
          check (float 0.6) "second pane uses the remaining track"
            (available *. (1. -. value))
            second.w;
          check (float 0.6) "divider keeps its logical width" (3. *. scale)
            (second.x -. first.x -. first.w))
        [ 0.; 0.25; 0.7; 1. ])
    [ 1.; 2. ]

let test_split_first_width () =
  let properties = Property_map.singleton FirstPaneWidth (FloatValue 246.) in
  check bool "pixel sizing is valid" true (node_properties_supported Split properties);
  check bool "fraction and pixel sizing are mutually exclusive" false
    (node_properties_supported Split (Property_map.add ProgressValue (FloatValue 0.5) properties));
  List.iter (fun scale -> List.iter (fun viewport -> List.iter (fun width ->
    let store = Lui_store.create () in
    apply store [CreateNode (1,Split);CreateNode (2,Column);CreateNode (3,Column);
      SetProp (1,Gap,IntValue 3);SetProp (1,FirstPaneWidth,FloatValue width);
      SetProp (2,MinWidth,IntValue 240);InsertChild (1,2,0);InsertChild (1,3,1)];
    let layout = Lui_layout.create () in
    Lui_layout.sync ~scale ~width:(viewport*.scale) ~height:(300.*.scale) layout store;
    let first = Option.get (Lui_layout.rect layout 2)
    and second = Option.get (Lui_layout.rect layout 3) in
    check (float 0.6) "pixel pane stays fixed while its owner resizes" (width*.scale) first.w;
    check (float 0.6) "the other pane takes the divider-free remainder"
      ((viewport-.width-.3.)*.scale) second.w)
      [0.;246.;300.]) [640.;1000.;1440.]) [1.;2.]

let test_select_menu_alignment () =
  List.iter
    (fun scale ->
      List.iter
        (fun (selected, unavailable, expected) ->
          let store = Lui_store.create () and layout = Lui_layout.create () in
          apply store
            [
              CreateNode (1, Root);
              CreateNode (2, Dialog);
              CreateNode (3, Box);
              CreateNode (4, Select);
              CreateNode (5, DropdownMenu);
              InsertChild (1, 2, 0);
              InsertChild (2, 3, 0);
              InsertChild (3, 4, 0);
              InsertChild (3, 5, 1);
              SetProp (2, WidthValue, IntValue 400);
              SetProp (2, HeightValue, IntValue 300);
              SetProp (2, PaddingValue, IntValue 32);
              SetProp (3, WidthValue, IntValue 256);
              SetProp (3, HeightValue, IntValue 32);
              SetProp (4, WidthValue, IntValue 256);
              SetProp (4, HeightValue, IntValue 32);
              SetProp (5, WidthValue, IntValue 190);
              SetProp (5, PaddingValue, IntValue 4);
              SetProp (5, BorderWidth, IntValue 1);
              SetProp (5, AnchorValue, StringValue "below");
            ];
          for index = 0 to 3 do
            let id = index + 6 in
            apply store
              [
                CreateNode (id, MenuItem);
                InsertChild (5, id, index);
                SetProp (id, HeightValue, IntValue 32);
                SetProp (id, Selected, BoolValue (Some index = selected));
                SetProp (id, SelectionPlacementValue, StringValue "leading");
              ]
          done;
          Option.iter
            (fun (property, value) ->
              apply store [ SetProp (7, property, value) ])
            unavailable;
          let rect id = Option.get (Lui_layout.rect layout id) in
          let sync width height =
            Lui_layout.sync ~scale ~width:(width *. scale)
              ~height:(height *. scale) layout store
          in
          let label id =
            let r = rect id and p = Lui_paint.text_placement_of store id in
            ( r.x +. (p.tp_pad_left *. scale),
              r.y
              +. ((r.h +. ((p.tp_pad_top -. p.tp_pad_bottom) *. scale)) /. 2.)
            )
          in
          let aligned () =
            let tx, ty = label 4 and ix, iy = label (6 + expected) in
            check (float 0.6) "selected label aligns with the trigger" tx ix;
            check (float 0.6) "selected row centers on the trigger" ty iy
          in
          sync 800. 600.;
          aligned ();
          sync 1000. 700.;
          aligned ();
          Lui_layout.invalidate layout;
          sync 1000. 700.;
          aligned ();
          (* Keep the trigger at the viewport edge after the dialog's inset
             clamp. Overlapping selection alignment cannot fit here. *)
          apply store [SetProp (3, MarginLeft, IntValue (-32))];
          sync 400. 320.;
          let popup = rect 5 in
          check bool "small viewport retains accessible menu bounds" true
            (popup.x >= 0. && popup.y >= 0.
            && popup.x +. popup.w <= 400. *. scale
            && popup.y +. popup.h <= 320. *. scale);
          check (float eps) "edge collision keeps below-trigger placement"
            ((rect 4).y +. (rect 4).h +. (4. *. scale))
            popup.y;
          apply store
            [
              SetProp (5, Position, StringValue "fixed");
              SetProp (5, PopupX, FloatValue 100.);
              SetProp (5, PopupY, FloatValue 200.);
            ];
          sync 1000. 700.;
          check (float eps) "explicit point keeps ordinary placement"
            (204. *. scale) (rect 5).y)
        [
          (None, None, 0);
          (Some 0, None, 0);
          (Some 1, None, 1);
          (Some 3, None, 3);
          (Some 1, Some (Enabled, BoolValue false), 0);
        ])
    [ 1.; 2. ]

let test_menu_height_cap () =
  List.iter
    (fun scale ->
      List.iter
        (fun (kind, props) ->
          List.iter
            (fun (maximum, available) ->
              let store = Lui_store.create ()
              and layout = Lui_layout.create () in
              apply store
                [
                  CreateNode (1, Root);
                  CreateNode (2, kind);
                  InsertChild (1, 2, 0);
                  SetProp (2, WidthValue, IntValue 200);
                  SetProp (2, AnchorValue, StringValue "below");
                ];
              apply store props;
              Option.iter
                (fun value ->
                  apply store [ SetProp (2, MaxHeight, IntValue value) ])
                maximum;
              Option.iter
                (fun value ->
                  apply store [ SetProp (2, AvailableHeight, FloatValue value) ])
                available;
              for index = 0 to 29 do
                let id = index + 3 in
                apply store
                  [
                    CreateNode (id, MenuItem);
                    InsertChild (2, id, index);
                    SetProp (id, HeightValue, IntValue 32);
                  ]
              done;
              List.iter
                (fun height ->
                  Lui_layout.sync ~scale ~width:(640. *. scale)
                    ~height:(height *. scale) layout store;
                  let popup = Option.get (Lui_layout.rect layout 2) in
                  let limit =
                    float_of_int (Option.value ~default:288 maximum)
                  in
                  let limit =
                    Float.min limit (Option.value ~default:limit available)
                  in
                  check (float eps) "menu height follows its cap and viewport"
                    (Float.min limit (height -. 16.) *. scale)
                    popup.h;
                  check bool "menu stays within the viewport" true
                    (popup.y >= 0. && popup.y +. popup.h <= height *. scale);
                  let first = Option.get (Lui_layout.rect layout 3)
                  and last = Option.get (Lui_layout.rect layout 32) in
                  check (float eps) "constrained menu rows retain their height"
                    (32. *. scale) first.h;
                  check bool "overflow remains available for scrolling" true
                    (last.y +. last.h > popup.y +. popup.h))
                [ 932.; 180.; 600. ])
            [
              (None, None); (Some 128, None); (Some 480, None); (None, Some 96.);
            ])
        [
          (DropdownMenu, []);
          (ContextMenu, []);
          (Popover, [ SetProp (2, RoleValue, StringValue "menu") ]);
        ])
    [ 1.; 2. ]

let test_popover_available_height () =
  List.iter
    (fun scale ->
      let store = Lui_store.create () and layout = Lui_layout.create () in
      apply store
        [
          CreateNode (1, Root);
          CreateNode (2, Popover);
          InsertChild (1, 2, 0);
          SetProp (2, WidthValue, IntValue 200);
          SetProp (2, PopupX, FloatValue 100.);
          SetProp (2, PopupY, FloatValue 40.);
          SetProp (2, AvailableHeight, FloatValue 96.);
        ];
      for index = 0 to 29 do
        let id = index + 3 in
        apply store
          [
            CreateNode (id, Box);
            InsertChild (2, id, index);
            SetProp (id, HeightValue, IntValue 32);
          ]
      done;
      let size height expected =
        Lui_layout.sync ~scale ~width:(640. *. scale) ~height:(height *. scale)
          layout store;
        let popup = Option.get (Lui_layout.rect layout 2) in
        check (float eps) "non-menu popover honors available height"
          (expected *. scale) popup.h;
        check bool "non-menu popover stays in the viewport" true
          (popup.y >= 0. && popup.y +. popup.h <= height *. scale)
      in
      size 932. 96.;
      size 64. 64.;
      size 600. 96.;
      apply store [ SetProp (2, MaxHeight, IntValue 64) ];
      size 600. 64.;
      apply store [ SetProp (2, AvailableHeight, FloatValue 32.) ];
      size 600. 32.)
    [ 1.; 2. ]

let test_anchored_popover_side_height () =
  List.iter
    (fun scale ->
      let store = Lui_store.create () and layout = Lui_layout.create () in
      apply store
        [
          CreateNode (1, Root);
          CreateNode (2, Box);
          CreateNode (3, Popover);
          InsertChild (1, 2, 0);
          InsertChild (2, 3, 0);
          SetProp (2, WidthValue, IntValue 120);
          SetProp (2, HeightValue, IntValue 32);
          SetProp (2, MarginLeft, IntValue 64);
          SetProp (2, MarginTop, IntValue 96);
          SetProp (3, WidthValue, IntValue 226);
          SetProp (3, MaxHeight, IntValue 288);
          SetProp (3, AnchorValue, StringValue "below");
        ];
      for index = 0 to 29 do
        let id = index + 4 in
        apply store
          [
            CreateNode (id, Box);
            InsertChild (3, id, index);
            SetProp (id, HeightValue, IntValue 32);
          ]
      done;
      List.iter
        (fun (height, y, h) ->
          Lui_layout.sync ~scale ~width:(640. *. scale)
            ~height:(height *. scale) layout store;
          let popup = Option.get (Lui_layout.rect layout 3) in
          check (float eps) "anchored popover retains its trigger edge"
            (64. *. scale) popup.x;
          check (float eps) "anchored popover fits its resolved side"
            (h *. scale) popup.h;
          check (float eps) "anchored popover does not cover its trigger"
            (y *. scale) popup.y)
        [
          (932., 132., 288.);
          (329., 132., 189.);
          (220., 8., 84.);
          (932., 132., 288.);
        ])
    [ 1.; 2. ]

let test_menu_role_layout () =
  let store = Lui_store.create () and layout = Lui_layout.create () in
  apply store
    [
      CreateNode (1, Root);
      CreateNode (2, Popover);
      InsertChild (1, 2, 0);
      SetProp (2, WidthValue, IntValue 200);
    ];
  for index = 0 to 29 do
    let id = index + 3 in
    apply store
      [
        CreateNode (id, MenuItem);
        InsertChild (2, id, index);
        SetProp (id, HeightValue, IntValue 32);
      ]
  done;
  let height () =
    Lui_layout.sync ~width:640. ~height:932. layout store;
    (Option.get (Lui_layout.rect layout 2)).h
  in
  check (float eps) "ordinary popovers retain their content height" 932.
    (height ());
  apply store [ SetProp (2, RoleValue, StringValue "menu") ];
  check (float eps) "adding menu semantics invalidates height" 288. (height ());
  apply store [ SetProp (2, RoleValue, StringValue "") ];
  check (float eps) "removing menu semantics restores content height" 932.
    (height ())

let test_button_custom_content () =
  List.iter (fun scale ->
      let store = Lui_store.create () and layout = Lui_layout.create () in
      apply store
        [ CreateNode (1, Root); CreateNode (2, Row);
          CreateNode (3, Button); CreateNode (4, Row); CreateNode (5, Box);
          CreateNode (6, Button);
          InsertChild (1, 2, 0); InsertChild (2, 3, 0); InsertChild (2, 6, 1);
          InsertChild (3, 4, 0); InsertChild (4, 5, 0);
          SetProp (3, InlineIconName, StringValue "keyboard");
          SetProp (3, HeightValue, IntValue 30);
          SetProp (3, PaddingHorizontal, IntValue 10);
          SetProp (3, PaddingVertical, IntValue 0);
          SetProp (5, WidthValue, IntValue 120);
          SetProp (5, HeightValue, IntValue 20);
          SetProp (6, InlineIconName, StringValue "x");
          SetProp (6, HeightValue, IntValue 30) ];
      Lui_layout.sync ~scale ~width:(600. *. scale) ~height:(80. *. scale)
        layout store;
      let rect id = Option.get (Lui_layout.rect layout id) in
      let button = rect 3 and child = rect 5 in
      check (float eps) "custom content determines button width"
        (140. *. scale) button.w;
      check bool "custom content stays inside its button" true
        (child.x >= button.x && child.x +. child.w <= button.x +. button.w);
      check (float eps) "childless icon buttons remain square"
        (30. *. scale) (rect 6).w;
      apply store [RemoveChild (4, 5); RemoveChild (3, 4)];
      Lui_layout.sync ~scale ~width:(600. *. scale) ~height:(80. *. scale)
        layout store;
      check (float eps) "removing custom content restores icon sizing"
        (30. *. scale) (rect 3).w)
    [1.; 2.]

let test_choice_intrinsic_size () =
  List.iter
    (fun kind ->
      List.iter
        (fun scale ->
          List.iter
            (fun labelled ->
              let store = Lui_store.create () in
              apply store
                ([
                   CreateNode (1, Root);
                   CreateNode (2, Row);
                   CreateNode (3, kind);
                   InsertChild (1, 2, 0);
                   InsertChild (2, 3, 0);
                   SetProp (2, WidthValue, IntValue 200);
                   SetProp (2, HeightValue, IntValue 64);
                   SetProp (2, CrossAlignment, StringValue "center");
                 ]
                @
                if labelled then
                  [ SetProp (3, TextValue, StringValue "Choice") ]
                else []);
              let layout = Lui_layout.create () in
              Lui_layout.sync ~scale
                ~measure:(fun _ _ _ _ -> Some (80. *. scale, 20. *. scale))
                ~width:(200. *. scale) ~height:(64. *. scale) layout store;
              let r = Option.get (Lui_layout.rect layout 3) in
              check (float eps) "choice intrinsic width"
                ((if labelled then 104. else 16.) *. scale)
                r.w;
              check (float eps) "choice intrinsic height"
                ((if labelled then 20. else 16.) *. scale)
                r.h;
              apply store
                [
                  SetProp (3, WidthValue, IntValue 12);
                  SetProp (3, HeightValue, IntValue 12);
                ];
              Lui_layout.sync ~scale ~measure:no_measure4 ~width:(200. *. scale)
                ~height:(64. *. scale) layout store;
              check (float eps) "explicit choice width wins" (12. *. scale)
                (Option.get (Lui_layout.rect layout 3)).w;
              check (float eps) "explicit choice height wins" (12. *. scale)
                (Option.get (Lui_layout.rect layout 3)).h)
            [ false; true ])
        [ 1.; 2. ])
    [ Checkbox; Radio ]

let () =
  run "lui_layout"
    [ ("layout",
       [ test_case "dialog viewport width" `Quick test_dialog_viewport_width;
         test_case "choice intrinsic size" `Quick test_choice_intrinsic_size;
         test_case "column padding/gap" `Quick test_column_padding_gap;
         test_case "button custom content" `Quick test_button_custom_content;
         test_case "list item content flow" `Quick test_list_item_content_flow;
         test_case "padding edges" `Quick test_padding_edges;
         test_case "absolute cross alignment" `Quick test_absolute_cross_alignment;
         test_case "border box layout" `Quick test_border_box_layout;
         test_case "split divider fraction" `Quick test_split_gap_fraction;
         test_case "split first-pane pixels" `Quick test_split_first_width;
         test_case "grid wraps" `Quick test_grid_wraps;
         test_case "grid gap fits" `Quick test_grid_gap_fits_columns;
         test_case "absolute inset" `Quick test_absolute_inset;
         test_case "text measured" `Quick test_text_measured;
         test_case "picker intrinsic width" `Quick test_picker_intrinsic_width;
         test_case "button icon gap" `Quick test_button_icon_gap;
         test_case "percent size" `Quick test_percent_size;
         test_case "column in row" `Quick test_nested_column_in_row;
         test_case "run placements" `Quick test_run_placements;
         test_case "display none" `Quick test_display_none_absent;
         test_case "rebuild" `Quick test_rebuild_after_mutation;
         test_case "resize retains measurements" `Quick test_resize_retains_measurements;
         test_case "sync memoized" `Quick test_sync_memoized;
         test_case "paint prop skips layout" `Quick test_paint_prop_skips_layout;
         test_case "frame grows" `Quick test_frame_grows_to_content;
         test_case "popup centered" `Quick test_popup_default_centered;
         test_case "root popup" `Quick test_root_popup_centered_in_frame;
         test_case "popup collision flip" `Quick test_popup_collision_flip;
         test_case "popup in centered dialog" `Quick test_popup_inside_centered_dialog;
         test_case "menu panel" `Quick test_menu_panel;
         test_case "select menu alignment" `Quick test_select_menu_alignment;
         test_case "menu height cap" `Quick test_menu_height_cap;
         test_case "popover available height" `Quick test_popover_available_height;
         test_case "anchored popover side height" `Quick test_anchored_popover_side_height;
         test_case "menu role layout" `Quick test_menu_role_layout;
         test_case "ac row" `Quick test_ac_row;
         test_case "vlist window" `Quick test_vlist_window_mounts_slice;
         test_case "vlist window moves" `Quick test_vlist_window_moves;
         test_case "vlist measured" `Quick test_vlist_measured_extents;
         test_case "vlist gap" `Quick test_vlist_gap;
         test_case "vlist unwindowed" `Quick test_vlist_unwindowed;
         test_case "vlist mounted children" `Quick
           test_vlist_mounted_children;
         test_case "vlist anchor drift" `Quick test_vlist_anchor_drift;
         test_case "vlist incremental child" `Quick
           test_vlist_incremental_child;
         test_case "snapped edges" `Quick test_snapped_edges;
         test_case "incremental equivalence" `Quick
           test_incremental_equivalence;
         test_case "incremental random" `Quick test_incremental_random;
         test_case "incremental root shift" `Quick
           test_incremental_root_shift;
         test_case "created subtree mirrored once" `Quick test_created_subtree_mirrored_once;
         test_case "created identity reuse" `Quick test_created_identity_reuse;
         test_case "updates before subtree disposal" `Quick test_updates_before_subtree_disposal;
         test_case "transient links before disposal" `Quick test_transient_links_before_disposal;
         test_case "nested disposal purges geometry" `Quick test_nested_disposal_purges_geometry;
         test_case "fractional ancestor offsets" `Quick test_fractional_ancestor_offsets;
         test_case "child restyle allocation" `Quick test_child_restyle_allocation;
         test_case "child restyle produced order" `Quick test_child_restyle_produced_order;
         test_case "deep rect refresh budget" `Quick test_deep_rect_refresh_budget;
         test_case "incremental large tree" `Quick
           test_incremental_large_tree ]) ]
