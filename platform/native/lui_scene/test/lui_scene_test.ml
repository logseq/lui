(* Scene-level semantics that renderers rely on: atlas packing and
   pixel persistence, and the text-coverage correction the renderers
   apply to glyph masks. *)

open Lui_scene

let fcheck name want got =
  Alcotest.(check (float 1e-6)) name want got

let atlas_byte a x y = Char.code (Bytes.get a.Atlas.pix (y * a.Atlas.w + x))

(* Atlas.put writes a one-byte padding column and row around the bitmap
   and keeps them clear across repeated puts, so bilinear reads at the
   edge never see the previous bitmap's edge pixels. *)
let test_atlas_put_clears_padding () =
  let a = Atlas.create ~bpp:1 ~w:16 ~h:16 in
  let (x, y) =
    match Atlas.alloc_last a 4 3 with
    | Some p -> p
    | None -> Alcotest.fail "alloc failed"
  in
  let src = Bytes.make (4 * 3) '\xaa' in
  Atlas.put a ~x ~y ~w:4 ~h:3 ~src ~stride:4;
  for j = 0 to 2 do
    Alcotest.(check int) "right pad" 0 (atlas_byte a (x + 4) (y + j))
  done;
  for i = 0 to 4 do
    Alcotest.(check int) "bottom pad" 0 (atlas_byte a (x + i) (y + 3))
  done;
  Alcotest.(check int) "data kept" 0xaa (atlas_byte a x y);
  (* Re-put different bytes: padding is cleared again, not stale. *)
  Atlas.put a ~x ~y ~w:4 ~h:3 ~src:(Bytes.make 12 '\xbb') ~stride:4;
  Alcotest.(check int) "right pad again" 0 (atlas_byte a (x + 4) y);
  Alcotest.(check int) "bottom pad again" 0 (atlas_byte a x (y + 3));
  Alcotest.(check int) "data replaced" 0xbb (atlas_byte a x y)

(* When a lasting allocation no longer fits, growing the atlas must
   preserve the bytes already written and make room for more entries;
   a mask longer than the atlas fits after enough growth. *)
let test_atlas_make_room () =
  let a = Atlas.create ~bpp:1 ~w:16 ~h:16 in
  let (x1, y1) =
    match Atlas.alloc_last a 8 8 with
    | Some p -> p
    | None -> Alcotest.fail "first alloc failed"
  in
  Atlas.put a ~x:x1 ~y:y1 ~w:8 ~h:8 ~src:(Bytes.make 64 '\x5a') ~stride:8;
  (* A second 8x8 fits neither the shelf row nor the remaining height. *)
  Alcotest.(check bool) "full" true
    (Atlas.alloc_last a 8 8 = None);
  let gen0 = a.Atlas.gen in
  Alcotest.(check bool) "grow" true (Atlas.grow a);
  Alcotest.(check bool) "gen bumped" true (a.Atlas.gen > gen0);
  Alcotest.(check int) "doubled" 32 a.Atlas.w;
  (* The earlier bitmap survived the grow. *)
  Alcotest.(check int) "data kept" 0x5a (atlas_byte a x1 y1);
  Alcotest.(check bool) "room now" true
    (Atlas.alloc_last a 8 8 <> None);
  (* Long mask: still too wide for the grown atlas, fits after another. *)
  Alcotest.(check bool) "too long" true
    (Atlas.alloc_last a 40 4 = None);
  ignore (Atlas.grow a);
  Alcotest.(check bool) "long fits" true
    (Atlas.alloc_last a 40 4 <> None)

(* A repack of the lasting rects keeps every bitmap's bytes whole at
   its new position — the frames the renderer draws stay intact. *)
let test_atlas_full_frames () =
  let a = Atlas.create ~bpp:1 ~w:16 ~h:16 in
  let alloc_put w h fill =
    match Atlas.alloc_last a w h with
    | None -> Alcotest.fail "alloc failed"
    | Some (x, y) ->
      Atlas.put a ~x ~y ~w ~h ~src:(Bytes.make (w * h) (Char.chr fill))
        ~stride:w;
      (x, y, irect x y (x + w) (y + h))
  in
  let (_, _, r1) = alloc_put 8 4 0x11 in
  let (_, _, _r2) = alloc_put 8 4 0x22 in
  (* The third 8x4 fits no remaining shelf space — the atlas is full. *)
  Alcotest.(check bool) "full" true
    (Atlas.alloc_last a 8 4 = None);
  let saved r =
    let row = irect_w r in
    let b = Bytes.create (row * irect_h r) in
    for j = 0 to irect_h r - 1 do
      Bytes.blit a.Atlas.pix (((r.y0 + j) * a.Atlas.w + r.x0) * a.Atlas.bpp)
        b (j * row) row
    done;
    b
  in
  let s1 = saved r1 in
  (* Repack keeping only r1: its frame stays whole at the new spot and
     the dropped rect's space is free again. *)
  let pos =
    match Atlas.repack a [ r1 ] with
    | Some p -> p
    | None -> Alcotest.fail "repack failed"
  in
  let (x, y) =
    match pos with [ p ] -> p | _ -> Alcotest.fail "one position"
  in
  let got =
    let row = irect_w r1 in
    let b = Bytes.create (row * irect_h r1) in
    for j = 0 to irect_h r1 - 1 do
      Bytes.blit a.Atlas.pix (((y + j) * a.Atlas.w + x) * a.Atlas.bpp) b
        (j * row) row
    done;
    b
  in
  Alcotest.(check bool) "r1 whole" true (Bytes.equal s1 got);
  Alcotest.(check bool) "room" true
    (Atlas.alloc_last a 8 4 <> None)

(* Text coverage correction: with no contrast, boost or gamma the
   coverage passes through untouched; otherwise the documented curve
   applies, clamped to [0,1]. *)
let test_text_coverage () =
  let zeros = (0., 0., 0., 0.) in
  fcheck "passthrough" 0.6
    (text_coverage 0.6 (0., 0., 0.) ~contrast:0. ~boost:0. zeros);
  (* boost 1 doubles coverage at a=1/3: a' = 2a/(a+1). *)
  fcheck "boost" (2. *. 0.5 /. 1.5)
    (text_coverage 0.5 (0., 0., 0.) ~contrast:0. ~boost:1. zeros);
  (* Contrast scales with ink darkness: full effect on black ink. *)
  fcheck "contrast dark ink" (2. *. 0.5 /. 1.5)
    (text_coverage 0.5 (0., 0., 0.) ~contrast:1. ~boost:0. zeros);
  (* ... and none on white ink. *)
  fcheck "contrast white ink" 0.5
    (text_coverage 0.5 (1., 1., 1.) ~contrast:1. ~boost:0. zeros);
  (* Gamma term: a + a(1-a)((g0 f + g1) a + (g2 f + g3)). *)
  fcheck "gamma" 0.5625
    (text_coverage 0.5 (0., 0., 0.) ~contrast:0. ~boost:0.
       (0., 0.5, 0., 0.));
  (* Clamps: full stays full, empty stays empty. *)
  fcheck "clamp high" 1.
    (text_coverage 1. (0., 0., 0.) ~contrast:0. ~boost:4. zeros);
  fcheck "clamp low" 0.
    (text_coverage 0. (0., 0., 0.) ~contrast:0. ~boost:0. zeros);
  (* Subpixel variant corrects each channel and returns a triple. *)
  let (ar, ag, ab) =
    subpixel_coverage (0.5, 0.5, 0.5) (0., 0., 0.) ~contrast:0. ~boost:1.
      zeros
  in
  fcheck "subpixel r" (2. *. 0.5 /. 1.5) ar;
  fcheck "subpixel g" (2. *. 0.5 /. 1.5) ag;
  fcheck "subpixel b" (2. *. 0.5 /. 1.5) ab

let () =
  Alcotest.run "lui_scene"
    [ ( "atlas",
        [ Alcotest.test_case "put clears padding" `Quick
            test_atlas_put_clears_padding;
          Alcotest.test_case "make room" `Quick test_atlas_make_room;
          Alcotest.test_case "frames stay whole" `Quick
            test_atlas_full_frames ] );
      ( "text coverage",
        [ Alcotest.test_case "correction curve" `Quick test_text_coverage
        ] ) ]
