(* Cross-module tests for the native backend: scene invariants and the
   store→paint→scene pipeline. Renderer parity tests (raster vs gl) go
   here too once both renderers land. *)

open Alcotest
open Lui_scene
open Lui_protocol

let scene () =
  Lui_scene.create
    ~mask_atlas:(Atlas.create ~bpp:1 ~w:256 ~h:256)
    ~color_atlas:(Atlas.create ~bpp:4 ~w:256 ~h:256)

(* ---------- atlas ---------- *)

let test_atlas_alloc () =
  let a = Atlas.create ~bpp:1 ~w:64 ~h:64 in
  (match Atlas.alloc_last a 8 8 with
   | Some (x, y) -> check int "first at 0" 0 (x + y)
   | None -> fail "alloc failed");
  (match Atlas.alloc_last a 8 8 with
   | Some (x, y) -> check bool "advances" true (x + y > 0)
   | None -> fail "second alloc failed");
  check bool "too big fails" true (Atlas.alloc_last a 128 128 = None)

let test_atlas_transient () =
  let a = Atlas.create ~bpp:1 ~w:64 ~h:64 in
  ignore (Atlas.alloc_transient a 8 8);
  let top = a.Atlas.top in
  check bool "transient lowered top" true (top < a.h);
  Atlas.reset_transient a;
  check int "top restored" a.h a.Atlas.top

let test_atlas_changes () =
  let a = Atlas.create ~bpp:1 ~w:64 ~h:64 in
  let (x, y) = Option.get (Atlas.alloc_last a 4 4) in
  let v0 = a.Atlas.version in
  Atlas.put a ~x ~y ~w:4 ~h:4 ~src:(Bytes.make 16 '\001') ~stride:4;
  let rects, full = Atlas.changes a ~gen:a.Atlas.gen ~version:v0 in
  check bool "one change" true (not full && List.length rects = 1);
  let _, full = Atlas.changes a ~gen:(a.Atlas.gen + 1) ~version:v0 in
  check bool "gen mismatch full" true full

let test_atlas_grow () =
  let a = Atlas.create ~bpp:1 ~w:32 ~h:32 in
  check bool "grow" true (Atlas.grow a);
  check int "doubled" 64 a.w;
  let gen = a.Atlas.gen in
  ignore (Atlas.alloc_last a 4 4);
  Atlas.reset a;
  check bool "reset bumps gen" true (a.Atlas.gen > gen)

let test_atlas_repack () =
  let a = Atlas.create ~bpp:1 ~w:64 ~h:64 in
  let r1 = Option.get (Atlas.alloc_last a 8 8) in
  let r2 = Option.get (Atlas.alloc_last a 4 4) in
  ignore r1; ignore r2;
  let rects = [ irect 0 0 8 8; irect 0 0 4 4 ] in
  match Atlas.repack a rects with
  | Some pos -> check int "two positions" 2 (List.length pos)
  | None -> fail "repack failed"

(* ---------- scene math ---------- *)

let test_fit_radii () =
  let r = rect 0. 0. 100. 100. in
  let (tl, tr, br, bl) = fit_radii r (80., 80., 80., 80.) in
  check bool "halved" true (tl = 50. && tr = 50. && br = 50. && bl = 50.);
  let (tl, _, _, _) = fit_radii r (40., 0., 0., 0.) in
  check bool "fits" true (tl = 40.)

let test_corners_continuous () =
  let r = rect 0. 0. 10. 10. in
  let (tl, _, _, _) = corners r (5., 5., 5., 5.) true in
  check bool "negated" true (tl < 0.)

let test_inner_radii () =
  let r = rect 0. 0. 100. 100. in
  let (inner, _) = inner_radii r (10., 10., 10., 10.) (2., 2., 2., 2.) in
  check bool "inset" true (inner.x = 2. && inner.y = 2. && inner.w = 96.)

let test_sd_round_rect () =
  let r = rect 0. 0. 100. 100. in
  check bool "center inside" true (sd_round_rect r (0., 0., 0., 0.) 50. 50. < 0.);
  check bool "outside" true (sd_round_rect r (0., 0., 0., 0.) 150. 50. > 0.);
  check bool "edge ~0" true (Float.abs (sd_round_rect r (0., 0., 0., 0.) 100. 50.) < 0.01)

let test_gamma_ratios () =
  let (g0, g1, g2, g3) = gamma_ratios 1.8 in
  check bool "finite" true
    (Float.is_finite g0 && Float.is_finite g1 && Float.is_finite g2 && Float.is_finite g3)

let test_backdrop_of () =
  let r = rect 50. 50. 100. 100. in
  let b = backdrop_of r 10. 400 400 in
  check bool "area covers reach" true (b.barea.x0 < 50 && b.barea.x1 > 150);
  check bool "clamped to frame" true (b.barea.x0 >= 0 && b.barea.x1 <= 400);
  let w, h = backdrop_size b in
  check bool "size positive" true (w > 0 && h > 0)

let test_blur_weight () =
  check bool "sigma0" true (blur_weight 3 0. = 1.);
  check bool "decay" true (blur_weight 4 2. < blur_weight 1 2.)

(* ---------- store→paint pipeline ---------- *)

let test_pipeline () =
  let t = Lui_store.create () in
  Lui_store.apply_batch t
    { generation = 1;
      ops =
        [ CreateNode (1, Column);
          CreateNode (2, ViewThatFits);
          SetProp (2, BackgroundValue, StringValue "#3366ff");
          InsertChild (1, 2, 0) ] };
  let s = scene () in
  let hooks =
    { Lui_paint.color_of = (fun _ -> None);
      layout = (fun _ -> rect 0. 0. 100. 100.);
      text_ops = (fun _ _ _ _ -> []);
      image_of = (fun _ -> None);
      shadow_of = (fun _ -> None) }
  in
  Lui_paint.paint hooks t s ~width:100 ~height:100 ~scale:1. ~clear:(color 255 255 255 255);
  match s.ops with
  | [Fill f] ->
    check int "blue" 255 f.fcolor.b;
    check int "green" 102 f.fcolor.g
  | _ -> fail "expected single Fill"

let () =
  run "lui_native"
    [ ("atlas",
       [ test_case "alloc" `Quick test_atlas_alloc;
         test_case "transient" `Quick test_atlas_transient;
         test_case "changes" `Quick test_atlas_changes;
         test_case "grow+reset" `Quick test_atlas_grow;
         test_case "repack" `Quick test_atlas_repack ]);
      ("scene math",
       [ test_case "fit_radii" `Quick test_fit_radii;
         test_case "continuous" `Quick test_corners_continuous;
         test_case "inner_radii" `Quick test_inner_radii;
         test_case "sd_round_rect" `Quick test_sd_round_rect;
         test_case "gamma" `Quick test_gamma_ratios;
         test_case "backdrop" `Quick test_backdrop_of;
         test_case "blur weight" `Quick test_blur_weight ]);
      ("pipeline",
       [ test_case "store→paint" `Quick test_pipeline ]) ]
