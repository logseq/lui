(* Unit tests for the flexbox layout engine. Expected rectangles are
   hand-computed; positions are relative to the parent's content box
   (or to the tree root for [absolute_layout]). *)

open Lui_flex

let eps = 1e-3

let rect_testable =
  let eq (a : rect) (b : rect) =
    Float.abs (a.x -. b.x) < eps
    && Float.abs (a.y -. b.y) < eps
    && Float.abs (a.w -. b.w) < eps
    && Float.abs (a.h -. b.h) < eps
  in
  let pp fmt (r : rect) =
    Format.fprintf fmt "(%g, %g, %g x %g)" r.x r.y r.w r.h
  in
  Alcotest.testable pp eq

let r x y w h = { x; y; w; h }

let check_rect msg expected node =
  Alcotest.check rect_testable msg expected (layout node)

let check_abs msg expected node =
  Alcotest.check rect_testable msg expected (absolute_layout node)

let leaf ?(style = default_style) () = create ~style []
let box ?(style = default_style) kids = create ~style kids

let run ?(w = 100.) ?(h = 100.) ?direction root =
  compute_layout root ~width:w ~height:h ?direction ()

(* -- axis distribution -------------------------------------------------- *)

let test_row () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c1 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c2 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let root =
    box ~style:{ default_style with flex_direction = Row }
      [c0; c1; c2]
  in
  run root;
  check_rect "c0" (r 0. 0. 10. 10.) c0;
  check_rect "c1" (r 10. 0. 10. 10.) c1;
  check_rect "c2" (r 20. 0. 10. 10.) c2

let test_column () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 20. } () in
  let c1 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 20. } () in
  let root = box [c0; c1] in
  run root;
  check_rect "c0" (r 0. 0. 10. 20.) c0;
  check_rect "c1" (r 0. 20. 10. 20.) c1

let test_justify_center () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let root =
    box ~style:{ default_style with flex_direction = Row;
                 justify_content = Justify_center } [c0]
  in
  run root;
  check_rect "c0" (r 45. 0. 10. 10.) c0

let test_justify_space_between () =
  let mk () = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c0, c1, c2 = mk (), mk (), mk () in
  let root =
    box ~style:{ default_style with flex_direction = Row;
                 justify_content = Justify_space_between } [c0; c1; c2]
  in
  run root;
  (* 70 free / 2 gaps = 35 between items *)
  check_rect "c0" (r 0. 0. 10. 10.) c0;
  check_rect "c1" (r 45. 0. 10. 10.) c1;
  check_rect "c2" (r 90. 0. 10. 10.) c2

let test_justify_space_evenly () =
  let mk () = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c0, c1, c2 = mk (), mk (), mk () in
  let root =
    box ~style:{ default_style with flex_direction = Row;
                 justify_content = Justify_space_evenly } [c0; c1; c2]
  in
  run root;
  (* 70 free / 4 = 17.5 between and around items *)
  check_rect "c0" (r 17.5 0. 10. 10.) c0;
  check_rect "c1" (r 45. 0. 10. 10.) c1;
  check_rect "c2" (r 72.5 0. 10. 10.) c2

let test_flex_grow () =
  let c0 = leaf ~style:{ default_style with flex_grow = 1. } () in
  let c1 = leaf ~style:{ default_style with flex_grow = 1. } () in
  let root =
    box ~style:{ default_style with flex_direction = Row; height = Pt 50. }
      [c0; c1]
  in
  run root ~h:50.;
  check_rect "c0" (r 0. 0. 50. 50.) c0;
  check_rect "c1" (r 50. 0. 50. 50.) c1

let test_flex_shrink () =
  let c0 = leaf ~style:{ default_style with width = Pt 80.; height = Pt 10. } () in
  let c1 = leaf ~style:{ default_style with width = Pt 80.; height = Pt 10. } () in
  let root =
    box ~style:{ default_style with flex_direction = Row } [c0; c1]
  in
  run root;
  (* 160 wanted, 100 available: each shrinks 30 *)
  check_rect "c0" (r 0. 0. 50. 10.) c0;
  check_rect "c1" (r 50. 0. 50. 10.) c1

let test_min_max () =
  let c0 =
    leaf ~style:{ default_style with width = Pt 80.; height = Pt 10.;
                  max_width = Pt 50. } ()
  in
  let c1 =
    leaf ~style:{ default_style with width = Pt 10.; height = Pt 10.;
                  min_width = Pt 30. } ()
  in
  let root =
    box ~style:{ default_style with flex_direction = Row } [c0; c1]
  in
  run root;
  check_rect "clamped to max" (r 0. 0. 50. 10.) c0;
  check_rect "clamped to min" (r 50. 0. 30. 10.) c1

(* -- wrap --------------------------------------------------------------- *)

let test_wrap () =
  let mk () = leaf ~style:{ default_style with width = Pt 60.; height = Pt 10. } () in
  let c0, c1, c2 = mk (), mk (), mk () in
  let root =
    box ~style:{ default_style with flex_direction = Row; flex_wrap = Wrap }
      [c0; c1; c2]
  in
  run root;
  check_rect "line0" (r 0. 0. 60. 10.) c0;
  check_rect "line1" (r 0. 10. 60. 10.) c1;
  check_rect "line2" (r 0. 20. 60. 10.) c2

let test_wrap_gap () =
  let mk () = leaf ~style:{ default_style with width = Pt 60.; height = Pt 10. } () in
  let c0, c1 = mk (), mk () in
  let root =
    box ~style:{ default_style with flex_direction = Row; flex_wrap = Wrap;
                 row_gap = Pt 5. } [c0; c1]
  in
  run root;
  (* Wrapped lines are separated by row_gap *)
  check_rect "line0" (r 0. 0. 60. 10.) c0;
  check_rect "line1" (r 0. 15. 60. 10.) c1

(* -- gap ---------------------------------------------------------------- *)

let test_column_gap () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c1 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let root =
    box ~style:{ default_style with flex_direction = Row; column_gap = Pt 5. }
      [c0; c1]
  in
  run root;
  check_rect "c0" (r 0. 0. 10. 10.) c0;
  check_rect "c1" (r 15. 0. 10. 10.) c1

let test_row_gap () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c1 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let root =
    box ~style:{ default_style with row_gap = Pt 7. } [c0; c1]
  in
  run root;
  check_rect "c0" (r 0. 0. 10. 10.) c0;
  check_rect "c1" (r 0. 17. 10. 10.) c1

(* -- absolute positioning ------------------------------------------------ *)

let test_absolute_offsets () =
  let c0 =
    leaf ~style:{ default_style with
                  position_type = Absolute;
                  width = Pt 10.; height = Pt 10.;
                  position = { edges_auto with left = Pt 20.; top = Pt 30. } } ()
  in
  let root = box [c0] in
  run root;
  check_rect "abs" (r 20. 30. 10. 10.) c0

let test_absolute_trailing () =
  let c0 =
    leaf ~style:{ default_style with
                  position_type = Absolute;
                  width = Pt 10.; height = Pt 10.;
                  position = { edges_auto with right = Pt 5.; bottom = Pt 5. } } ()
  in
  let root = box [c0] in
  run root;
  (* right/bottom only: pinned to the trailing corner *)
  check_rect "abs" (r 85. 85. 10. 10.) c0

let test_absolute_ignored_in_flow () =
  let rel = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let abs =
    leaf ~style:{ default_style with position_type = Absolute;
                  width = Pt 10.; height = Pt 10. } ()
  in
  let root =
    box ~style:{ default_style with flex_direction = Row } [rel; abs]
  in
  run root;
  (* The absolute child takes no flex space: the relative child sits
     at index 0. *)
  check_rect "rel" (r 0. 0. 10. 10.) rel;
  check_rect "abs" (r 0. 0. 10. 10.) abs

(* -- nesting ------------------------------------------------------------- *)

let test_nested_padding () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c1 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let mid =
    box ~style:{ default_style with flex_direction = Row;
                 width = Pt 100.; height = Pt 50.;
                 padding = edges_ltrb ~left:(Pt 10.) ~top:(Pt 5.)
                   ~right:Unset ~bottom:Unset }
      [c0; c1]
  in
  let root = box [mid] in
  run root;
  check_rect "mid" (r 0. 0. 100. 50.) mid;
  (* Children start inside the padding box *)
  check_abs "c0" (r 10. 5. 10. 10.) c0;
  check_abs "c1" (r 20. 5. 10. 10.) c1

let test_deep_nesting () =
  let leaf0 = leaf ~style:{ default_style with width = Pt 5.; height = Pt 5. } () in
  let inner =
    box ~style:{ default_style with flex_direction = Row;
                 padding = edges_all (Pt 2.) } [leaf0]
  in
  let mid =
    box ~style:{ default_style with
                 margin = edges_ltrb ~left:(Pt 10.) ~top:(Pt 10.)
                   ~right:Unset ~bottom:Unset } [inner]
  in
  let root = box [mid] in
  run root ~w:100. ~h:100.;
  (* mid margin 10 + inner padding 2 = 12 *)
  check_abs "leaf0" (r 12. 12. 5. 5.) leaf0

(* -- percentages and auto sizes ------------------------------------------ *)

let test_percent_dims () =
  let c0 =
    leaf ~style:{ default_style with width = Percent 50.; height = Percent 20. } ()
  in
  let root = box [c0] in
  run root;
  check_rect "c0" (r 0. 0. 50. 20.) c0

let test_percent_against_inner () =
  let c0 = leaf ~style:{ default_style with width = Percent 50.; height = Pt 10. } () in
  let mid =
    box ~style:{ default_style with width = Pt 80.; flex_direction = Row;
                 padding = edges_ltrb ~left:(Pt 10.) ~top:Unset
                   ~right:Unset ~bottom:Unset }
      [c0]
  in
  let root = box [mid] in
  run root;
  (* mid inner width = 80 - 10 = 70; 50% = 35 *)
  check_rect "c0" (r 10. 0. 35. 10.) c0

let test_percent_margin () =
  let c0 =
    leaf ~style:{ default_style with width = Pt 10.; height = Pt 10.;
                  margin = { edges_auto with left = Percent 10. } } ()
  in
  let root =
    box ~style:{ default_style with flex_direction = Row } [c0]
  in
  run root;
  check_rect "c0" (r 10. 0. 10. 10.) c0

let test_auto_container () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 20. } () in
  let root = box [c0] in
  run root ~w:undefined ~h:undefined;
  (* Root with no size spec shrinks to its contents *)
  check_rect "root" (r 0. 0. 10. 20.) root;
  check_rect "c0" (r 0. 0. 10. 20.) c0

let test_percent_flex_basis () =
  let c0 =
    leaf ~style:{ default_style with flex_basis = Percent 50.; height = Pt 10. } ()
  in
  let root =
    box ~style:{ default_style with flex_direction = Row } [c0]
  in
  run root;
  check_rect "c0" (r 0. 0. 50. 10.) c0

(* -- auto margins --------------------------------------------------------- *)

let test_auto_margin_main () =
  let c0 =
    leaf ~style:{ default_style with width = Pt 10.; height = Pt 10.;
                  margin = { edges_auto with left = Auto } } ()
  in
  let root =
    box ~style:{ default_style with flex_direction = Row } [c0]
  in
  run root;
  (* 90 free space is absorbed by the auto left margin *)
  check_rect "c0" (r 90. 0. 10. 10.) c0

let test_auto_margin_split () =
  let c0 =
    leaf ~style:{ default_style with width = Pt 10.; height = Pt 10.;
                  margin = edges_all Auto } ()
  in
  let root =
    box ~style:{ default_style with flex_direction = Row } [c0]
  in
  run root;
  (* left+right auto share the 90 free: 45 each; top+bottom auto share
     the 90 cross free: 45 each *)
  check_rect "c0" (r 45. 45. 10. 10.) c0

(* -- alignment ------------------------------------------------------------ *)

let test_align_stretch () =
  let c0 = leaf ~style:{ default_style with width = Pt 10. } () in
  let root =
    box ~style:{ default_style with flex_direction = Row; height = Pt 50. } [c0]
  in
  run root ~h:50.;
  check_rect "stretched" (r 0. 0. 10. 50.) c0

let test_align_center () =
  let m _node ~width:_ ~width_mode:_ ~height:_ ~height_mode:_ =
    { width = 10.; height = 10. }
  in
  let c0 = create ~measure:m [] in
  let root =
    box ~style:{ default_style with flex_direction = Row; height = Pt 50.;
                 align_items = Align_center } [c0]
  in
  run root ~h:50.;
  check_rect "centered" (r 0. 20. 10. 10.) c0

let test_row_reverse () =
  let c0 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let c1 = leaf ~style:{ default_style with width = Pt 10.; height = Pt 10. } () in
  let root =
    box ~style:{ default_style with flex_direction = Row_reverse } [c0; c1]
  in
  run root;
  (* Row-reverse packs to the trailing edge, first child rightmost *)
  check_rect "c0" (r 90. 0. 10. 10.) c0;
  check_rect "c1" (r 80. 0. 10. 10.) c1

(* -- measure leaves -------------------------------------------------------- *)

let test_measure_leaf () =
  let seen_w = ref nan and seen_h = ref nan in
  let m _node ~width:w ~width_mode:_ ~height:h ~height_mode:_ =
    seen_w := w;
    seen_h := h;
    { width = 30.; height = 12. }
  in
  let c0 = create ~measure:m [] in
  let root =
    box ~style:{ default_style with align_items = Align_flex_start } [c0]
  in
  run root;
  check_rect "measure" (r 0. 0. 30. 12.) c0;
  (* The callback saw the container's inner size as its constraint *)
  Alcotest.(check bool) "saw inner width" true (!seen_w > 90.);
  Alcotest.(check bool) "saw inner height" true (!seen_h > 90.)

let test_measure_is_leaf () =
  let m _node ~width:_ ~width_mode:_ ~height:_ ~height_mode:_ =
    { width = 1.; height = 1. }
  in
  let c0 = leaf () in
  Alcotest.check_raises "measure with children rejected"
    (Invalid_argument
       "Lui_flex.create: a measure callback is only allowed on leaf nodes")
    (fun () -> ignore (create ~measure:m [c0]))

let () =
  Alcotest.run "lui_flex"
    [ "axis",
      [ Alcotest.test_case "row" `Quick test_row;
        Alcotest.test_case "column" `Quick test_column;
        Alcotest.test_case "justify_center" `Quick test_justify_center;
        Alcotest.test_case "space_between" `Quick test_justify_space_between;
        Alcotest.test_case "space_evenly" `Quick test_justify_space_evenly;
        Alcotest.test_case "flex_grow" `Quick test_flex_grow;
        Alcotest.test_case "flex_shrink" `Quick test_flex_shrink;
        Alcotest.test_case "min_max" `Quick test_min_max ];
      "wrap",
      [ Alcotest.test_case "wrap" `Quick test_wrap;
        Alcotest.test_case "wrap_gap" `Quick test_wrap_gap ];
      "gap",
      [ Alcotest.test_case "column_gap" `Quick test_column_gap;
        Alcotest.test_case "row_gap" `Quick test_row_gap ];
      "absolute",
      [ Alcotest.test_case "offsets" `Quick test_absolute_offsets;
        Alcotest.test_case "trailing" `Quick test_absolute_trailing;
        Alcotest.test_case "ignored_in_flow" `Quick test_absolute_ignored_in_flow ];
      "nesting",
      [ Alcotest.test_case "padding" `Quick test_nested_padding;
        Alcotest.test_case "deep" `Quick test_deep_nesting ];
      "percent_and_auto",
      [ Alcotest.test_case "percent_dims" `Quick test_percent_dims;
        Alcotest.test_case "percent_inner" `Quick test_percent_against_inner;
        Alcotest.test_case "percent_margin" `Quick test_percent_margin;
        Alcotest.test_case "auto_container" `Quick test_auto_container;
        Alcotest.test_case "percent_basis" `Quick test_percent_flex_basis;
        Alcotest.test_case "auto_margin_main" `Quick test_auto_margin_main;
        Alcotest.test_case "auto_margin_split" `Quick test_auto_margin_split ];
      "align",
      [ Alcotest.test_case "stretch" `Quick test_align_stretch;
        Alcotest.test_case "center" `Quick test_align_center;
        Alcotest.test_case "row_reverse" `Quick test_row_reverse ];
      "measure",
      [ Alcotest.test_case "leaf" `Quick test_measure_leaf;
        Alcotest.test_case "is_leaf" `Quick test_measure_is_leaf ];
    ]
