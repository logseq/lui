(* lui_text engine tests: shaping, metrics, wrapping, fallback,
   rasterization and subpixel positioning, all against the platform's
   text stack. *)

open Lui_text

let sys = system ~size:16. ()

let eps = 0.01

let near a b = Float.abs (a -. b) <= eps

let checkf ~msg ~eps a b =
  Alcotest.(check bool) msg true (Float.abs (a -. b) <= eps)

let line_height l = l.ascent +. l.descent +. l.leading

let all_runs (lines : line array) : run list =
  List.concat_map (fun l -> Array.to_list l.runs) (Array.to_list lines)

let all_glyphs lines =
  all_runs lines
  |> List.concat_map (fun r -> Array.to_list r.glyphs)
  |> Array.of_list

let ink_count b =
  let n = ref 0 in
  for i = 0 to Bytes.length b.pixels - 1 do
    if Bytes.get_uint8 b.pixels i > 0 then incr n
  done;
  !n

let test_metrics () =
  let m = metrics sys in
  Alcotest.(check bool) "size" true (near m.size 16.);
  Alcotest.(check bool) "ascent>0" true (m.ascent > 0.);
  Alcotest.(check bool) "descent>0" true (m.descent > 0.);
  Alcotest.(check bool) "leading>=0" true (m.leading >= 0.);
  checkf ~msg:"line_height" ~eps
    m.line_height (m.ascent +. m.descent +. m.leading)

let test_create_named () =
  let f = create ~families:[ "Helvetica" ] ~size:14. () in
  Alcotest.(check bool) "size" true (near (size f) 14.);
  Alcotest.(check bool) "family nonempty" true (family f <> "")

let test_create_missing_family () =
  (* An uninstalled family name falls back to a usable font. *)
  let f =
    create ~families:[ "No Such Family Xyzzy 42" ] ~size:14. ()
  in
  Alcotest.(check bool) "still works" true (size f > 0.)

let test_create_same_args_same_font () =
  let a = create ~families:[ "Helvetica" ] ~size:14. () in
  let b = create ~families:[ "Helvetica" ] ~size:14. () in
  Alcotest.(check bool) "same font" true (a = b)

(* The glyph id of the first glyph shaped for a single-char string. *)
let glyph_id_of f c =
  let lines = shape f (String.make 1 c) in
  let runs = lines.(0).runs in
  runs.(0).glyphs.(0).id

let test_weight_changes_glyphs () =
  let regular = create ~families:[ "Helvetica" ] ~size:20. () in
  let bold =
    create ~families:[ "Helvetica" ] ~weight:700 ~size:20. ()
  in
  match
    ( rasterize regular (glyph_id_of regular 'A'),
      rasterize bold (glyph_id_of bold 'A') )
  with
  | Some a, Some b ->
    Alcotest.(check bool) "bold differs" false
      (Bytes.to_string a.pixels = Bytes.to_string b.pixels)
  | _ -> Alcotest.fail "expected bitmaps"

let test_italic () =
  let f = create ~families:[ "Helvetica" ] ~italic:true ~size:14. () in
  Alcotest.(check bool) "size" true (near (size f) 14.)

let test_monospace () =
  let f = system ~monospace:true ~size:14. () in
  Alcotest.(check bool) "size" true (near (size f) 14.)

let test_shape_ascii () =
  let lines = shape sys "Hello" in
  Alcotest.(check int) "one line" 1 (Array.length lines);
  let l = lines.(0) in
  Alcotest.(check int) "line range" 5 (l.stop - l.start);
  Alcotest.(check bool) "runs" true (Array.length l.runs >= 1);
  let gs = all_glyphs lines in
  Alcotest.(check int) "five glyphs" 5 (Array.length gs);
  Array.iter
    (fun g ->
      Alcotest.(check bool) "advance>0" true (g.advance > 0.);
      Alcotest.(check bool) "cluster in range" true
        (g.cluster >= 0 && g.cluster < 5))
    gs;
  let sum = Array.fold_left (fun a g -> a +. g.advance) 0. gs in
  checkf ~msg:"advances ~ width" ~eps:2.5 sum l.width

let test_shape_wrap () =
  let s = "the quick brown fox jumps over the lazy dog" in
  let one = shape sys s in
  Alcotest.(check int) "one line" 1 (Array.length one);
  let w, h1 = measure sys s in
  Alcotest.(check bool) "width>0" true (w > 0.);
  let wrapped = shape ~width:(w /. 4.) sys s in
  Alcotest.(check bool) "wrapped more lines" true
    (Array.length wrapped > 1);
  Array.iter
    (fun l ->
      (* A wrapped line may exceed the wrap width by one trailing
         space: the typesetter counts it toward what fits. *)
      Alcotest.(check bool) "line fits" true (l.width <= w /. 4. +. 5.))
    wrapped;
  let _, h2 = measure ~width:(w /. 4.) sys s in
  Alcotest.(check bool) "wrapped taller" true (h2 > h1)

let test_measure_matches () =
  let s = "measure me" in
  let lines = shape sys s in
  let w, h = measure sys s in
  let l = lines.(0) in
  checkf ~msg:"w is line width" ~eps w l.width;
  checkf ~msg:"h is line height" ~eps h (line_height l);
  let gs = all_glyphs lines in
  let sum = Array.fold_left (fun a g -> a +. g.advance) 0. gs in
  checkf ~msg:"w vs advances" ~eps:2.5 w sum

let test_newlines () =
  let lines = shape sys "ab\ncd" in
  Alcotest.(check int) "two lines" 2 (Array.length lines);
  Alcotest.(check int) "first line" 2 (lines.(0).stop - lines.(0).start);
  Alcotest.(check int) "second starts after nl" 3 lines.(1).start;
  Alcotest.(check int) "second line" 2
    (lines.(1).stop - lines.(1).start);
  let lines = shape sys "ab\n" in
  Alcotest.(check int) "trailing empty line" 2 (Array.length lines);
  Alcotest.(check int) "empty" 0 (lines.(1).stop - lines.(1).start)

let test_cjk () =
  let f = create ~families:[ "Helvetica" ] ~size:20. () in
  let lines = shape f "你好世界" in
  let gs = all_glyphs lines in
  Alcotest.(check int) "four glyphs" 4 (Array.length gs);
  Array.iter
    (fun g ->
      Alcotest.(check bool) "full width" true
        (g.advance > size f *. 0.5 && g.advance < size f *. 1.5))
    gs;
  (* The base font lacks CJK: some run must come from a fallback. *)
  let runs =
    all_runs lines
  in
  Alcotest.(check bool) "fallback font used" true
    (List.exists (fun r -> r.font <> f) runs)

let test_mixed_runs () =
  (* Latin + Hebrew: the run list splits by script direction. *)
  let lines = shape sys "abc\xD7\x90\xD7\x91\xD7\x92def" in
  let runs = all_runs lines in
  Alcotest.(check bool) "several runs" true (List.length runs >= 2);
  Alcotest.(check bool) "an rtl run" true
    (List.exists (fun r -> r.rtl) runs);
  let gs = all_glyphs lines in
  Alcotest.(check int) "nine glyphs" 9 (Array.length gs)

let test_rtl_paragraph () =
  let lines = shape ~rtl:true sys "\xD7\x90\xD7\x91" in
  let runs = all_runs lines in
  Alcotest.(check bool) "runs" true (List.length runs >= 1);
  Alcotest.(check bool) "rtl" true (List.for_all (fun r -> r.rtl) runs)

let test_emoji_color_glyph () =
  let f = system ~size:16. () in
  let lines = shape f "\xF0\x9F\x8E\xA8" (* U+1F3A8 *) in
  let runs =
    all_runs lines
  in
  Alcotest.(check bool) "runs" true (List.length runs >= 1);
  let r = List.hd runs in
  let b = rasterize r.font r.glyphs.(0).id in
  match b with
  | Some b ->
    Alcotest.(check bool) "color bitmap" true b.color;
    Alcotest.(check bool) "bgra size" true
      (Bytes.length b.pixels = b.w * b.h * 4);
    Alcotest.(check bool) "has ink" true (ink_count b > 0)
  | None -> Alcotest.fail "expected a color bitmap"

let test_fallback_font () =
  match fallback sys "\xF0\x9F\x8E\xA8" with
  | Some f ->
    Alcotest.(check bool) "color fallback" true (is_color f)
  | None -> Alcotest.fail "expected a fallback font"

let test_rasterize_mask () =
  let f = create ~families:[ "Helvetica" ] ~size:20. () in
  let id = glyph_id_of f 'A' in
  match rasterize f id with
  | Some b ->
    Alcotest.(check bool) "mask" false b.color;
    Alcotest.(check bool) "size" true
      (Bytes.length b.pixels = b.w * b.h);
    Alcotest.(check bool) "has ink" true (ink_count b > 0);
    let frac = float (ink_count b) /. float (b.w * b.h) in
    Alcotest.(check bool) "ink fraction sane" true
      (frac > 0.01 && frac < 0.95)
  | None -> Alcotest.fail "expected a bitmap"

let test_rasterize_determinism () =
  let f = create ~families:[ "Helvetica" ] ~size:20. () in
  let id = glyph_id_of f 'e' in
  match rasterize ~dx:0.25 f id, rasterize ~dx:0.25 f id with
  | Some a, Some b ->
    Alcotest.(check bool) "deterministic" true
      (Bytes.to_string a.pixels = Bytes.to_string b.pixels
       && a.left = b.left && a.top = b.top && a.w = b.w && a.h = b.h)
  | _ -> Alcotest.fail "expected bitmaps"

let test_rasterize_subpixel () =
  let f = create ~families:[ "Helvetica" ] ~size:20. () in
  let id = glyph_id_of f 'e' in
  match rasterize ~dx:0. f id, rasterize ~dx:0.5 f id with
  | Some a, Some b ->
    Alcotest.(check bool) "phase differs" false
      (Bytes.to_string a.pixels = Bytes.to_string b.pixels)
  | _ -> Alcotest.fail "expected bitmaps"

let test_rasterize_scale () =
  let f = create ~families:[ "Helvetica" ] ~size:20. () in
  let id = glyph_id_of f 'A' in
  match rasterize ~scale:1. f id, rasterize ~scale:2. f id with
  | Some a, Some b ->
    Alcotest.(check bool) "wider at 2x" true (b.w > a.w && b.h > a.h);
    let fa = float (ink_count a) /. float (a.w * a.h)
    and fb = float (ink_count b) /. float (b.w * b.h) in
    Alcotest.(check bool) "coverage similar" true
      (Float.abs (fa -. fb) < 0.3)
  | _ -> Alcotest.fail "expected bitmaps"

let test_rasterize_invalid () =
  Alcotest.check_raises "dx range" (Invalid_argument "Lui_text.rasterize")
    (fun () -> ignore (rasterize ~dx:1.5 sys 42));
  Alcotest.check_raises "scale range"
    (Invalid_argument "Lui_text.rasterize")
    (fun () -> ignore (rasterize ~scale:0. sys 42))

let test_subpixel_positions () =
  let n = subpixel_positions sys in
  Alcotest.(check bool) "1..5" true (n >= 1 && n <= 5);
  let n2 = subpixel_positions ~scale:2. sys in
  Alcotest.(check bool) "2x also 1..5" true (n2 >= 1 && n2 <= 5)

let test_baseline () =
  Alcotest.(check bool) "floor-ish" true (baseline 10.3 = 11.);
  Alcotest.(check bool) "exact" true (baseline 10. = 10.)

let test_empty () =
  let lines = shape sys "" in
  Alcotest.(check int) "one empty line" 1 (Array.length lines);
  Alcotest.(check int) "no runs" 0 (Array.length lines.(0).runs)

let test_run_font_matches () =
  (* ASCII through the system font stays in the asked-for font. *)
  let lines = shape sys "plain" in
  List.iter
    (fun r ->
      Alcotest.(check bool) "run font" true (r.font = sys))
    (Array.to_list lines.(0).runs)

let ink_sum b =
  let n = ref 0 in
  for i = 0 to Bytes.length b.pixels - 1 do
    n := !n + Bytes.get_uint8 b.pixels i
  done;
  !n

(* The shade parameter darkens or lightens a glyph's mask, and font
   weight changes the same glyph's mask: thin stays lighter than bold. *)
let test_glyph_shades () =
  let f = create ~families:[ "Helvetica" ] ~size:32. () in
  let id = glyph_id_of f 'A' in
  match rasterize ~shade:1. f id, rasterize ~shade:0.3 f id with
  | Some full, Some faint ->
    Alcotest.(check bool) "shade changes mask" false
      (Bytes.to_string full.pixels = Bytes.to_string faint.pixels);
    Alcotest.(check bool) "darker shade more ink" true
      (ink_sum full > ink_sum faint)
  | _ -> Alcotest.fail "expected bitmaps"

(* Thin and bold cuts of one family produce different masks for the
   same glyph — thick strokes cover more pixels. *)
let test_glyph_thick () =
  let thin = create ~families:[ "Helvetica" ] ~weight:100 ~size:32. () in
  let bold = create ~families:[ "Helvetica" ] ~weight:700 ~size:32. () in
  match
    ( rasterize thin (glyph_id_of thin 'A'),
      rasterize bold (glyph_id_of bold 'A') )
  with
  | Some t, Some b ->
    Alcotest.(check bool) "weight changes mask" false
      (Bytes.to_string t.pixels = Bytes.to_string b.pixels);
    Alcotest.(check bool) "bold more ink" true (ink_sum b > ink_sum t)
  | _ -> Alcotest.fail "expected bitmaps"

(* Fonts of many sizes report their own size and keep sensible,
   non-decreasing line metrics. *)
let test_fonts_many_sizes () =
  let prev = ref 0. in
  List.iter
    (fun s ->
      let f = create ~families:[ "Helvetica" ] ~size:s () in
      Alcotest.(check bool) "size" true (near (size f) s);
      let m = metrics f in
      Alcotest.(check bool) "line height grows" true
        (m.line_height >= !prev);
      prev := m.line_height)
    [ 8.; 10.; 12.; 14.; 18.; 24.; 36.; 48. ]

(* ---- editing model ---- *)

(* Synthetic lines drive the caret/hit/selection model without shaping:
   glyph positions and cluster boundaries are fixtures, so these pin
   the model's geometry rather than a font's. *)

let fake_glyph x adv cluster = { id = 1; x; y = 0.; advance = adv; cluster }

let fake_run start stop rtl glyphs =
  { font = sys; start; stop; rtl; glyphs; rcolor = None; under = 0 }

let fake_line_r start stop runs =
  let w =
    Array.fold_left
      (fun m (r : run) ->
         Array.fold_left
           (fun m (g : glyph) -> max m (g.x +. g.advance)) m r.glyphs)
      0. runs
  in
  { start; stop; width = w; ascent = 10.; descent = 2.; leading = 0.;
    runs }

let fake_line start stop glyphs =
  fake_line_r start stop [| fake_run start stop false glyphs |]

(* "abc" as three 10pt cells; every byte boundary is a grapheme. *)
let labc =
  layout_of_lines ~breaks:[| 0; 1; 2; 3 |] sys "abc"
    [| fake_line 0 3
         [| fake_glyph 0. 10. 0; fake_glyph 10. 10. 1;
            fake_glyph 20. 10. 2 |] |]

let test_caret_edges () =
  let r0 = caret_rect labc 0 and r3 = caret_rect labc 3 in
  checkf ~msg:"start" ~eps r0.rx 0.;
  checkf ~msg:"end" ~eps r3.rx 30.;
  checkf ~msg:"mid 1" ~eps (caret_rect labc 1).rx 10.;
  checkf ~msg:"mid 2" ~eps (caret_rect labc 2).rx 20.;
  checkf ~msg:"clamp low" ~eps (caret_rect labc (-5)).rx r0.rx;
  checkf ~msg:"clamp high" ~eps (caret_rect labc 99).rx r3.rx;
  checkf ~msg:"top" ~eps r0.ry 0.;
  checkf ~msg:"height" ~eps r0.rh 12.;
  checkf ~msg:"zero width" ~eps r0.rw 0.

let test_hit_edges () =
  Alcotest.(check int) "left of line" 0 (hit_test labc (-3., 5.));
  Alcotest.(check int) "right of line" 3 (hit_test labc (100., 5.));
  Alcotest.(check int) "cell 0 left half" 0 (hit_test labc (4., 5.));
  Alcotest.(check int) "cell 0 right half" 1 (hit_test labc (7., 5.));
  Alcotest.(check int) "cell 2 right half" 3 (hit_test labc (28., 5.));
  Alcotest.(check int) "above" 0 (hit_test labc (4., -50.));
  Alcotest.(check int) "below" 3 (hit_test labc (100., 500.))

(* One glyph cluster covering the line is a ligature stand-in: the
   caret never enters it. *)
let test_ligature () =
  let lig =
    layout_of_lines ~breaks:[| 0; 1; 2; 3 |] sys "abc"
      [| fake_line 0 3 [| fake_glyph 0. 30. 0 |] |]
  in
  checkf ~msg:"inside snaps left" ~eps (caret_rect lig 1).rx 0.;
  checkf ~msg:"inside snaps right" ~eps (caret_rect lig 2).rx 30.;
  Alcotest.(check int) "hit snaps" 0 (hit_test lig (10., 5.));
  Alcotest.(check int) "hit snaps far" 3 (hit_test lig (25., 5.));
  Alcotest.(check int) "before 2" 0 (caret_before lig 2);
  Alcotest.(check int) "after 1" 3 (caret_after lig 1)

(* An rtl unit's first byte sits at its right edge. *)
let test_rtl_model () =
  let rl =
    layout_of_lines ~breaks:[| 0; 1; 2 |] ~rtl:true sys "ab"
      [| fake_line_r 0 2
           [| fake_run 0 2 true
                [| fake_glyph 20. 10. 0; fake_glyph 10. 10. 1 |] |] |]
  in
  checkf ~msg:"byte0 right" ~eps (caret_rect rl 0).rx 30.;
  checkf ~msg:"byte1 mid" ~eps (caret_rect rl 1).rx 20.;
  checkf ~msg:"byte2 left" ~eps (caret_rect rl 2).rx 10.;
  Alcotest.(check int) "far right hit" 0 (hit_test rl (99., 5.));
  Alcotest.(check int) "right cell near edge" 1
    (hit_test rl (22., 5.))

(* "ab\ncd": the newline gets a pseudo-unit selections can light up. *)
let lnl =
  layout_of_lines ~breaks:[| 0; 1; 2; 3; 4; 5 |] sys "ab\ncd"
    [| fake_line 0 2 [| fake_glyph 0. 10. 0; fake_glyph 10. 10. 1 |];
       fake_line 3 5 [| fake_glyph 0. 10. 3; fake_glyph 10. 10. 4 |] |]

let test_newline_unit () =
  (* Index 2 — before the [\n] — shares the line-end caret spot. *)
  checkf ~msg:"before nl" ~eps (caret_rect lnl 2).rx 20.;
  checkf ~msg:"after nl" ~eps (caret_rect lnl 3).rx 0.;
  checkf ~msg:"after nl on line 2" ~eps (caret_rect lnl 3).ry 12.;
  (* Clicks past the last glyph land on the line's end, not the next
     line's start. *)
  Alcotest.(check int) "gap hit" 2 (hit_test lnl (24., 5.));
  Alcotest.(check int) "line 2 hit" 4 (hit_test lnl (15., 15.))

let test_selection_multiline () =
  match selection_rects lnl (0, 5) with
  | [ r1; r2 ] ->
    checkf ~msg:"l1 from 0" ~eps r1.rx 0.;
    (* Covers "ab" plus the [\n]'s half-em span. *)
    checkf ~msg:"l1 through nl" ~eps (r1.rx +. r1.rw) 28.;
    checkf ~msg:"l1 row" ~eps r1.ry 0.;
    checkf ~msg:"l2 from 0" ~eps r2.rx 0.;
    checkf ~msg:"l2 covers" ~eps r2.rw 20.;
    checkf ~msg:"l2 row" ~eps r2.ry 12.
  | _ -> Alcotest.fail "expected two rects"

let test_selection_excludes_nl () =
  (* (0,2) stops before the [\n]: the pseudo-unit stays unlit. *)
  match selection_rects lnl (0, 2) with
  | [ r ] ->
    checkf ~msg:"line only" ~eps r.rw 20.;
    checkf ~msg:"row" ~eps r.ry 0.
  | _ -> Alcotest.fail "expected one rect"

let test_selection_partial () =
  match selection_rects lnl (1, 4) with
  | [ r1; r2 ] ->
    checkf ~msg:"l1 partial" ~eps r1.rx 10.;
    checkf ~msg:"l1 through nl" ~eps (r1.rx +. r1.rw) 28.;
    checkf ~msg:"l2 partial" ~eps r2.rw 10.
  | _ -> Alcotest.fail "expected two rects"

(* A bidi gap: the covered byte range misses the middle unit; its hole
   stays visible — rects merge only while intervals touch. *)
let test_selection_bidi_gap () =
  let lay =
    layout_of_lines ~breaks:[| 0; 1; 2; 3; 4 |] sys "abcd"
      [| fake_line_r 0 4
           [| fake_run 0 2 false
                [| fake_glyph 0. 10. 0; fake_glyph 10. 10. 1 |];
              fake_run 2 3 true [| fake_glyph 20. 10. 2 |];
              fake_run 3 4 false [| fake_glyph 30. 10. 3 |] |] |]
  in
  let full = selection_rects lay (0, 4) in
  (match full with
   | [ r ] -> checkf ~msg:"full cover" ~eps r.rw 40.
   | _ -> Alcotest.fail "expected one merged rect");
  (* Selecting only bytes 0..1 and 3..4: two disjoint selections land
     as two rects on the same row, with the rtl cell a hole. *)
  let both =
    let r1 = selection_rects lay (0, 2)
    and r2 = selection_rects lay (3, 4) in
    List.sort compare (r1 @ r2)
  in
  match both with
  | [ r1; r2 ] ->
    checkf ~msg:"left piece" ~eps r1.rw 20.;
    checkf ~msg:"right piece at 30" ~eps r2.rx 30.;
    checkf ~msg:"same row" ~eps r1.ry r2.ry
  | _ -> Alcotest.fail "expected two rects"

let test_caret_vertical () =
  Alcotest.(check int) "down keeps x" 4 (caret_down lnl 1);
  Alcotest.(check int) "up keeps x" 1 (caret_up lnl 4);
  Alcotest.(check int) "up at top" 0 (caret_up lnl 0);
  Alcotest.(check int) "down at bottom" 5 (caret_down lnl 4);
  Alcotest.(check int) "up clamps doc start" 0 (caret_up lnl 3)

(* Real-CoreText checks: the same model over real shaping, plus the
   engine hooks. *)

let test_layout_real () =
  let s = "the quick brown fox jumps over the lazy dog" in
  let lay = layout ~width:80. sys s in
  Alcotest.(check bool) "wrapped" true (Array.length lay.lay_lines > 1);
  let top = ref (-.1.) and hsum = ref 0. and wmax = ref 0. in
  Array.iter
    (fun (lb : line_layout) ->
       Alcotest.(check bool) "tops rise" true (lb.ll_top > !top);
       top := lb.ll_top;
       hsum := !hsum +. lb.ll_height;
       wmax := max !wmax lb.ll_line.width;
       checkf ~msg:"baseline" ~eps lb.ll_baseline
         (lb.ll_top +. lb.ll_line.ascent))
    lay.lay_lines;
  checkf ~msg:"height is sum" ~eps:0.1 lay.lay_height !hsum;
  checkf ~msg:"width is max" ~eps lay.lay_width !wmax

let test_layout_paragraphs () =
  let lay = layout sys "ab\ncd" in
  Alcotest.(check int) "two lines" 2 (Array.length lay.lay_lines);
  checkf ~msg:"line2 top" ~eps lay.lay_lines.(1).ll_top
    lay.lay_lines.(0).ll_height

(* Caret and hit agree at every boundary of a shaped line. *)
let test_hit_caret_roundtrip () =
  let lay = layout sys "abcde" in
  let lb = lay.lay_lines.(0) in
  let mid = lb.ll_top +. lb.ll_height /. 2. in
  for i = 0 to 5 do
    let r = caret_rect lay i in
    Alcotest.(check int) (Printf.sprintf "roundtrip %d" i) i
      (hit_test lay (r.rx, mid))
  done

let test_rtl_real () =
  let lay = layout ~rtl:true sys "\xD7\x90\xD7\x91" (* Hebrew *) in
  let r0 = caret_rect lay 0 and rend = caret_rect lay 4 in
  Alcotest.(check bool) "rtl caret order" true (r0.rx > rend.rx)

let test_graphemes_ascii () =
  Alcotest.(check (array int)) "abc" [| 0; 1; 2; 3 |] (graphemes "abc");
  Alcotest.(check (array int)) "empty" [| 0 |] (graphemes "")

let test_graphemes_cjk () =
  (* Each CJK codepoint is its own cluster. *)
  Alcotest.(check (array int)) "ni hao" [| 0; 3; 6 |]
    (graphemes "\xE4\xBD\xA0\xE5\xA5\xBD")

let test_graphemes_emoji () =
  (* Family ZWJ chain: 18 bytes, one cluster. *)
  let fam = "\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7" in
  Alcotest.(check (array int)) "zwj family" [| 0; 18 |] (graphemes fam);
  (* Regional indicator pair: two codepoints, one flag cluster. *)
  let flag = "\xF0\x9F\x87\xAB\xF0\x9F\x87\xB7" in
  Alcotest.(check (array int)) "flag" [| 0; 8 |] (graphemes flag);
  (* e + combining acute stays one cluster. *)
  Alcotest.(check (array int)) "combining" [| 0; 3 |]
    (graphemes "e\xCC\x81")

(* Hits inside an emoji never land mid-cluster. *)
let test_emoji_boundaries () =
  let s = "a\xF0\x9F\x91\xA8\xE2\x80\x8D\xF0\x9F\x91\xA9\xE2\x80\x8D\xF0\x9F\x91\xA7z" in
  let lay = layout sys s in
  let lb = lay.lay_lines.(0) in
  let mid = lb.ll_top +. lb.ll_height /. 2. in
  let seen = ref [] in
  for x = 0 to 60 do
    let i = hit_test lay (float x, mid) in
    if not (List.mem i !seen) then seen := i :: !seen
  done;
  List.iter
    (fun i ->
      Alcotest.(check bool)
        (Printf.sprintf "hit %d on boundary" i) true
        (List.mem i [ 0; 1; 19; 20 ]))
    !seen;
  Alcotest.(check bool) "no interior hits" true
    (List.for_all (fun i -> List.mem i [ 0; 1; 19; 20 ]) !seen)

let test_spans_color () =
  let s = "abcdef" in
  let red = 0xFF0000FF in
  let spans =
    [ { text = s;
        style = { default_style with scolor = Some red };
        range = (0, 3) } ]
  in
  let runs = all_runs (shape_spans sys spans) in
  Alcotest.(check bool) "colored run over left" true
    (List.exists (fun r -> r.rcolor = Some red && r.start <= 0) runs);
  Alcotest.(check bool) "plain run over right" true
    (List.exists (fun r -> r.rcolor = None && r.stop >= 4) runs)

let test_spans_font () =
  let s = "abcdef" in
  let big = system ~size:24. () in
  let spans =
    [ { text = s;
        style = { default_style with sfont = Some big };
        range = (0, 3) } ]
  in
  let runs = all_runs (shape_spans sys spans) in
  Alcotest.(check bool) "big font on range" true
    (List.exists (fun r -> r.font = big && r.start <= 0) runs);
  Alcotest.(check bool) "base font after" true
    (List.exists (fun r -> r.font = sys && r.start >= 3) runs)

let test_spans_kern () =
  let s = "ababab" in
  let w0, _ = measure sys s in
  let spans =
    [ { text = s;
        style = { default_style with skern = 4. };
        range = (0, 6) } ]
  in
  let lines = shape_spans sys spans in
  Alcotest.(check bool) "kern widens" true
    (lines.(0).width > w0 +. 8.)

let test_spans_under () =
  let s = "abcdef" in
  let spans =
    [ { text = s; style = { default_style with sunder = 1 };
        range = (0, 3) } ]
  in
  let runs = all_runs (shape_spans sys spans) in
  Alcotest.(check bool) "underlined run" true
    (List.exists (fun r -> r.under = 1 && r.start <= 0) runs)

(* A span's range is clipped per paragraph: (1,4) styles "b" on line 1
   and "c" on line 2 across the [\n]. *)
let test_spans_across_paragraph () =
  let s = "ab\ncd" in
  let red = 0x00FF00FF in
  let spans =
    [ { text = s;
        style = { default_style with scolor = Some red };
        range = (1, 4) } ]
  in
  let lines = shape_spans sys spans in
  Alcotest.(check int) "two lines" 2 (Array.length lines);
  Array.iteri
    (fun i (l : line) ->
       Alcotest.(check bool)
         (Printf.sprintf "line %d has colored run" i) true
         (List.exists (fun r -> r.rcolor = Some red)
            (Array.to_list l.runs)))
    lines

let test_layout_spans_api () =
  let s = "abcdef" in
  let spans =
    [ { text = s;
        style = { default_style with scolor = Some 0xFF0000FF };
        range = (0, 3) } ]
  in
  let lay = layout_spans sys spans in
  Alcotest.(check int) "one line" 1 (Array.length lay.lay_lines);
  Alcotest.(check bool) "caret works" true
    ((caret_rect lay 3).rx > 0.)

let test_truncate_end () =
  let s = "the quick brown fox jumps over the lazy dog" in
  match truncate ~width:60. sys s with
  | Some l ->
    Alcotest.(check bool) "fits" true (l.width <= 60.01);
    Alcotest.(check bool) "has glyphs" true
      (Array.length l.runs > 0
       && Array.length l.runs.(0).glyphs > 0)
  | None -> Alcotest.fail "expected a truncated line"

let test_truncate_modes () =
  let s = "the quick brown fox jumps over the lazy dog" in
  List.iter
    (fun mode ->
       match truncate ~mode ~width:60. sys s with
       | Some l ->
         Alcotest.(check bool) "fits" true (l.width <= 60.01)
       | None -> Alcotest.fail "expected a truncated line")
    [ `Start; `Middle ]

let test_truncate_none () =
  Alcotest.(check bool) "zero width" true
    (truncate ~width:0. sys "hello" = None);
  Alcotest.(check bool) "empty" true
    (truncate ~width:50. sys "" = None)

let test_utf16 () =
  (* a(1B/1u) é(2B/1u) 𝄞(4B/2u): 7 bytes, 4 units. *)
  let s = "a\xC3\xA9\xF0\x9D\x84\x9E" in
  Alcotest.(check int) "units" 4 (utf16_length s);
  Alcotest.(check int) "byte0" 0 (utf16_of_byte s 0);
  Alcotest.(check int) "byte1" 1 (utf16_of_byte s 1);
  Alcotest.(check int) "byte3" 2 (utf16_of_byte s 3);
  Alcotest.(check int) "byte inside" 2 (utf16_of_byte s 4);
  Alcotest.(check int) "end" 4 (utf16_of_byte s 7);
  Alcotest.(check int) "unit0" 0 (byte_of_utf16 s 0);
  Alcotest.(check int) "unit1" 1 (byte_of_utf16 s 1);
  Alcotest.(check int) "unit2" 3 (byte_of_utf16 s 2);
  Alcotest.(check int) "surrogate half" 3 (byte_of_utf16 s 3);
  Alcotest.(check int) "past end" 7 (byte_of_utf16 s 4)

let test_cache_hits () =
  let c = Cache.create 4 in
  ignore (Cache.measure c sys "alpha");
  Alcotest.(check (pair int int)) "miss" (0, 1) (Cache.stats c);
  (* Measure-first: the layout reuses the entry measure populated. *)
  ignore (Cache.layout c sys "alpha");
  Alcotest.(check (pair int int)) "hit" (1, 1) (Cache.stats c);
  let mw, _ = Cache.measure c sys "alpha" in
  let rw, _ = measure sys "alpha" in
  checkf ~msg:"same extent" ~eps mw rw

let test_cache_eviction () =
  let c = Cache.create 2 in
  ignore (Cache.layout c sys "alpha");
  ignore (Cache.layout c sys "beta");
  ignore (Cache.layout c sys "gamma");
  Alcotest.(check int) "bounded" 2 (Cache.length c);
  (* alpha was the coldest: it went. *)
  let _, misses = Cache.stats c in
  ignore (Cache.layout c sys "gamma");
  ignore (Cache.layout c sys "alpha");
  let _, misses' = Cache.stats c in
  Alcotest.(check int) "alpha missed" (misses + 1) misses'

let test_cache_version () =
  let c = Cache.create 4 in
  ignore (Cache.layout c sys "alpha");
  Cache.set_version c 7;
  Alcotest.(check int) "cleared" 0 (Cache.length c);
  Alcotest.(check int) "version" 7 (Cache.version c);
  ignore (Cache.layout c sys "alpha");
  let _, misses = Cache.stats c in
  Alcotest.(check int) "missed after bump" 2 misses

let test_cache_oversized () =
  let c = Cache.create ~max_bytes:8 4 in
  ignore (Cache.layout c sys "this is a long string");
  Alcotest.(check int) "not kept" 0 (Cache.length c)

let test_cache_span_keys () =
  let c = Cache.create 4 in
  let s = "abc" in
  ignore (Cache.layout c sys s);
  ignore
    (Cache.layout_spans c sys
       [ { text = s;
           style = { default_style with scolor = Some 0xFF0000FF };
           range = (0, 3) } ]);
  (* Styled and unstyled are different entries. *)
  Alcotest.(check int) "two entries" 2 (Cache.length c);
  let _, misses = Cache.stats c in
  Alcotest.(check int) "both missed" 2 misses

let () =
  let open Alcotest in
  run "lui_text"
    [ ( "fonts",
        [ test_case "metrics" `Quick test_metrics;
          test_case "named family" `Quick test_create_named;
          test_case "missing family" `Quick test_create_missing_family;
          test_case "same args" `Quick test_create_same_args_same_font;
          test_case "weight" `Quick test_weight_changes_glyphs;
          test_case "italic" `Quick test_italic;
          test_case "monospace" `Quick test_monospace ] );
      ( "shape",
        [ test_case "ascii" `Quick test_shape_ascii;
          test_case "wrap" `Quick test_shape_wrap;
          test_case "measure" `Quick test_measure_matches;
          test_case "newlines" `Quick test_newlines;
          test_case "cjk fallback" `Quick test_cjk;
          test_case "mixed directions" `Quick test_mixed_runs;
          test_case "rtl" `Quick test_rtl_paragraph;
          test_case "empty" `Quick test_empty;
          test_case "run font" `Quick test_run_font_matches ] );
      ( "rasterize",
        [ test_case "emoji color" `Quick test_emoji_color_glyph;
          test_case "fallback" `Quick test_fallback_font;
          test_case "mask" `Quick test_rasterize_mask;
          test_case "determinism" `Quick test_rasterize_determinism;
          test_case "subpixel" `Quick test_rasterize_subpixel;
          test_case "scale" `Quick test_rasterize_scale;
          test_case "invalid" `Quick test_rasterize_invalid;
          test_case "positions" `Quick test_subpixel_positions;
          test_case "baseline" `Quick test_baseline ] );
      ( "glyphs",
        [ test_case "shades" `Quick test_glyph_shades;
          test_case "thick" `Quick test_glyph_thick;
          test_case "many sizes" `Quick test_fonts_many_sizes ] );
      ( "editing",
        [ test_case "caret edges" `Quick test_caret_edges;
          test_case "hit edges" `Quick test_hit_edges;
          test_case "ligature" `Quick test_ligature;
          test_case "rtl model" `Quick test_rtl_model;
          test_case "newline unit" `Quick test_newline_unit;
          test_case "sel multiline" `Quick test_selection_multiline;
          test_case "sel excludes nl" `Quick test_selection_excludes_nl;
          test_case "sel partial" `Quick test_selection_partial;
          test_case "sel bidi gap" `Quick test_selection_bidi_gap;
          test_case "caret vertical" `Quick test_caret_vertical;
          test_case "layout real" `Quick test_layout_real;
          test_case "layout paragraphs" `Quick test_layout_paragraphs;
          test_case "hit caret roundtrip" `Quick test_hit_caret_roundtrip;
          test_case "rtl real" `Quick test_rtl_real ] );
      ( "graphemes",
        [ test_case "ascii" `Quick test_graphemes_ascii;
          test_case "cjk" `Quick test_graphemes_cjk;
          test_case "emoji" `Quick test_graphemes_emoji;
          test_case "emoji boundaries" `Quick test_emoji_boundaries ] );
      ( "spans",
        [ test_case "color" `Quick test_spans_color;
          test_case "font" `Quick test_spans_font;
          test_case "kern" `Quick test_spans_kern;
          test_case "under" `Quick test_spans_under;
          test_case "across paragraph" `Quick test_spans_across_paragraph;
          test_case "layout_spans" `Quick test_layout_spans_api ] );
      ( "truncate",
        [ test_case "end" `Quick test_truncate_end;
          test_case "modes" `Quick test_truncate_modes;
          test_case "none" `Quick test_truncate_none ] );
      ( "utf16", [ test_case "mapping" `Quick test_utf16 ] );
      ( "cache",
        [ test_case "hits" `Quick test_cache_hits;
          test_case "eviction" `Quick test_cache_eviction;
          test_case "version" `Quick test_cache_version;
          test_case "oversized" `Quick test_cache_oversized;
          test_case "span keys" `Quick test_cache_span_keys ] ) ]
