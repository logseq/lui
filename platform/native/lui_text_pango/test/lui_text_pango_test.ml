(* lui_text_pango engine tests: shaping, metrics, wrapping, fallback,
   rasterization and subpixel positioning, all against the platform's
   text stack (Fontconfig + Pango + cairo). Cases that need a font the
   machine may not have installed skip with a reason. *)

open Lui_text_pango

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

(* Whether the system has a font covering [s]'s characters beyond
   [base] — the probe the fallback-dependent cases need. *)
let has_coverage base s =
  match fallback base s with Some f -> f <> base | None -> false

let need reason cond test =
  if cond then test ()
  else (
    Printf.eprintf "lui_text_pango: skipped, %s\n%!" reason;
    Alcotest.skip ())

let test_metrics () =
  let m = metrics sys in
  Alcotest.(check bool) "size" true (near m.size 16.);
  Alcotest.(check bool) "ascent>0" true (m.ascent > 0.);
  Alcotest.(check bool) "descent>0" true (m.descent > 0.);
  Alcotest.(check bool) "leading>=0" true (m.leading >= 0.);
  checkf ~msg:"line_height" ~eps
    m.line_height (m.ascent +. m.descent +. m.leading)

let test_create_named () =
  let f = create ~families:[ "DejaVu Sans" ] ~size:14. () in
  Alcotest.(check bool) "size" true (near (size f) 14.);
  Alcotest.(check bool) "family nonempty" true (family f <> "")

let test_create_missing_family () =
  (* An uninstalled family name falls back to a usable font. *)
  let f =
    create ~families:[ "No Such Family Xyzzy 42" ] ~size:14. ()
  in
  Alcotest.(check bool) "still works" true (size f > 0.)

let test_create_same_args_same_font () =
  let a = create ~families:[ "DejaVu Sans" ] ~size:14. () in
  let b = create ~families:[ "DejaVu Sans" ] ~size:14. () in
  Alcotest.(check bool) "same font" true (a = b)

(* The glyph id of the first glyph shaped for a single-char string. *)
let glyph_id_of f c =
  let lines = shape f (String.make 1 c) in
  let runs = lines.(0).runs in
  runs.(0).glyphs.(0).id

let test_weight_changes_glyphs () =
  let regular = create ~families:[ "DejaVu Sans" ] ~size:20. () in
  let bold =
    create ~families:[ "DejaVu Sans" ] ~weight:700 ~size:20. ()
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
  let f =
    create ~families:[ "DejaVu Sans" ] ~italic:true ~size:14. ()
  in
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
  let base = create ~families:[ "DejaVu Sans" ] ~size:20. () in
  need "no CJK font installed" (has_coverage base "\xE4\xBD\xA0")
    (fun () ->
    let f = base in
    let lines = shape f "\xE4\xBD\xA0\xE5\xA5\xBD\xE4\xB8\x96\xE7\x95\x8C" in
    let gs = all_glyphs lines in
    Alcotest.(check int) "four glyphs" 4 (Array.length gs);
    Array.iter
      (fun g ->
        Alcotest.(check bool) "full width" true
          (g.advance > size f *. 0.5 && g.advance < size f *. 1.5))
      gs;
    (* The base font lacks CJK: some run must come from a fallback. *)
    let runs = all_runs lines in
    Alcotest.(check bool) "fallback font used" true
      (List.exists (fun r -> r.font <> f) runs))

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

(* A color-emoji font is installed when the fallback for an emoji is
   a color font. *)
let has_color_emoji () =
  match fallback sys "\xF0\x9F\x8E\xA8" with
  | Some f -> is_color f
  | None -> false

let test_emoji_color_glyph () =
  need "no color-emoji font installed" (has_color_emoji ()) (fun () ->
    let f = system ~size:16. () in
    let lines = shape f "\xF0\x9F\x8E\xA8" (* U+1F3A8 *) in
    let runs = all_runs lines in
    Alcotest.(check bool) "runs" true (List.length runs >= 1);
    let r = List.hd runs in
    match rasterize r.font r.glyphs.(0).id with
    | Some b ->
      Alcotest.(check bool) "color bitmap" true b.color;
      Alcotest.(check bool) "bgra size" true
        (Bytes.length b.pixels = b.w * b.h * 4);
      Alcotest.(check bool) "has ink" true (ink_count b > 0)
    | None -> Alcotest.fail "expected a color bitmap")

let test_fallback_font () =
  need "no color-emoji font installed" (has_color_emoji ()) (fun () ->
    match fallback sys "\xF0\x9F\x8E\xA8" with
    | Some f ->
      Alcotest.(check bool) "color fallback" true (is_color f)
    | None -> Alcotest.fail "expected a fallback font")

let test_rasterize_mask () =
  let f = create ~families:[ "DejaVu Sans" ] ~size:20. () in
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
  let f = create ~families:[ "DejaVu Sans" ] ~size:20. () in
  let id = glyph_id_of f 'e' in
  match rasterize ~dx:0.25 f id, rasterize ~dx:0.25 f id with
  | Some a, Some b ->
    Alcotest.(check bool) "deterministic" true
      (Bytes.to_string a.pixels = Bytes.to_string b.pixels
       && a.left = b.left && a.top = b.top && a.w = b.w && a.h = b.h)
  | _ -> Alcotest.fail "expected bitmaps"

let test_rasterize_subpixel () =
  let f = create ~families:[ "DejaVu Sans" ] ~size:20. () in
  let id = glyph_id_of f 'e' in
  match rasterize ~dx:0. f id, rasterize ~dx:0.5 f id with
  | Some a, Some b ->
    Alcotest.(check bool) "phase differs" false
      (Bytes.to_string a.pixels = Bytes.to_string b.pixels)
  | _ -> Alcotest.fail "expected bitmaps"

let test_rasterize_scale () =
  let f = create ~families:[ "DejaVu Sans" ] ~size:20. () in
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
  Alcotest.check_raises "dx range"
    (Invalid_argument "Lui_text_pango.rasterize")
    (fun () -> ignore (rasterize ~dx:1.5 sys 42));
  Alcotest.check_raises "scale range"
    (Invalid_argument "Lui_text_pango.rasterize")
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

let () =
  let open Alcotest in
  run "lui_text_pango"
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
          test_case "baseline" `Quick test_baseline ] ) ]
