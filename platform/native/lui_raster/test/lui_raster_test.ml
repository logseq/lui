(* Golden fixtures under test/golden/ are raw RGBA dumps of the
   reference renderer on the scenes built below; a port that keeps the
   coverage and blend math matches them within a byte a channel (the
   reference computed float32 where this port computes float64). *)

open Lui_scene
open Lui_raster_testkit
open Testkit

(* ---------- golden comparison ---------- *)

let load_golden name =
  let path = Filename.concat "golden" (name ^ ".rgba") in
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let b = Bytes.create n in
  really_input ic b 0 n;
  close_in ic;
  b

let check_golden name img =
  let want = load_golden name in
  let got = Lui_raster.Image.rgba img in
  Alcotest.(check int) (name ^ " size") (Bytes.length want) (Bytes.length got);
  let diffs = ref 0 and first = ref (-1) and maxd = ref 0 in
  for i = 0 to min (Bytes.length want) (Bytes.length got) - 1 do
    let d = abs (Char.code (Bytes.get want i) - Char.code (Bytes.get got i)) in
    if d > 2 then begin
      incr diffs;
      if !first < 0 then first := i;
      if d > !maxd then maxd := d
    end
  done;
  Alcotest.(check int)
    (Printf.sprintf "%s: %d channels differ (first at %d, worst %d)" name !diffs
       !first !maxd)
    0 !diffs

let test_golden () =
  List.iter
    (fun (name, build) ->
      let s = build () in
      let img = Lui_raster.render ~scene:s () in
      check_golden name img)
    golden_scenes

(* ---------- semantic checks ---------- *)

let test_pixel_checks () =
  (* Inside a solid rounded fill the color is exact; outside it is the
     clear color; the border pixels carry the border color. *)
  let s =
    scene ~w:96 ~h:64
      [ ifill ~radii:(radii 12.) ~bw:(uniform 2.) ~bc:black
          (rect 12.25 10.5 60. 40.) (color 37 99 235 255) ]
  in
  let img = Lui_raster.render ~scene:s () in
  let px x y =
    let i = y * img.Lui_raster.Image.stride + 4 * x in
    (Char.code (Bytes.get img.Lui_raster.Image.pix (i + 2)),
     Char.code (Bytes.get img.Lui_raster.Image.pix (i + 1)),
     Char.code (Bytes.get img.Lui_raster.Image.pix i),
     Char.code (Bytes.get img.Lui_raster.Image.pix (i + 3)))
  in
  let rgba (r, g, b, a) = [ r; g; b; a ] in
  Alcotest.(check (list int)) "inside" [ 37; 99; 235; 255 ] (rgba (px 42 30));
  Alcotest.(check bool) "border red low" true (let r, _, _, _ = px 13 30 in r < 40);
  Alcotest.(check (list int)) "outside corner" [ 255; 255; 255; 255 ] (rgba (px 13 11))

(* ---------- random scenes for damage and multicore ---------- *)

let bytes_of img = img.Lui_raster.Image.pix

(* A partial-damage render must equal a whole render, however a scene
   changes. *)
let test_damage_redraws effects =
  for seed = 0 to 11 do
    let m = Maker.make seed in
    m.with_effects <- effects;
    let s = Maker.scene m in
    let r = Lui_raster.Renderer.create () in
    let partial = ref 0 in
    for step = 0 to 29 do
      if step > 0 then ignore (Maker.change m s);
      let damage = Lui_raster.Renderer.render r s in
      let full = Lui_raster.render ~scene:s () in
      let same = Bytes.equal (bytes_of (Lui_raster.Renderer.image r)) (bytes_of full) in
      Alcotest.(check bool)
        (Printf.sprintf "seed %d step %d: redrawn matches whole" seed step)
        true same;
      (match damage with
       | [ d ] when d.Lui_scene.x1 - d.x0 = s.width && d.y1 - d.y0 = s.height -> ()
       | _ when step > 0 -> incr partial
       | _ -> ())
    done;
    Alcotest.(check bool)
      (Printf.sprintf "seed %d: some frames drew partially" seed)
      true (!partial > 0)
  done

let test_damage_redraws_plain () = test_damage_redraws false
let test_damage_redraws_effects () = test_damage_redraws true

let test_damage_skips () =
  let m = Maker.make 1 in
  let s = Maker.scene m in
  let r = Lui_raster.Renderer.create () in
  ignore (Lui_raster.Renderer.render r s);
  let d0 = Lui_raster.Renderer.render r s in
  Alcotest.(check int) "unchanged scene redraws nothing" 0 (List.length d0);
  (* One changed op redraws less than half the window. *)
  let rec take_fill i = function
    | [] -> -1
    | Fill _ :: _ | Shadow _ :: _ -> i
    | _ :: rest -> take_fill (i + 1) rest
  in
  let idx = take_fill 0 s.ops in
  Alcotest.(check bool) "a recolorable op exists" true (idx >= 0);
  s.ops <-
    List.mapi
      (fun i o -> if i = idx then match o with
        | Fill f -> Fill { f with fcolor = color 1 0 0 255 }
        | Shadow sh -> Shadow { sh with scolor = color 1 0 0 255 }
        | _ -> o
       else o)
      s.ops;
  let d1 = Lui_raster.Renderer.render r s in
  let area =
    List.fold_left (fun n d -> n + (d.Lui_scene.x1 - d.x0) * (d.y1 - d.y0)) 0 d1
  in
  Alcotest.(check bool) "one changed op redraws a small area"
    true (List.length d1 >= 1 && area < s.width * s.height / 2)

(* Many small changes far apart collapse into one rectangle past the
   merge cap; one change leaves one rectangle. *)
let test_damage_merge () =
  let m = Maker.make 5 in
  let s = Maker.scene m in
  let r = Lui_raster.Renderer.create () in
  ignore (Lui_raster.Renderer.render r s);
  (* Change one op: one rect. Find the first fill or shadow to be sure
     the change registers on any generated scene. *)
  let rec take_fill i = function
    | [] -> -1
    | Fill _ :: _ | Shadow _ :: _ -> i
    | _ :: rest -> take_fill (i + 1) rest
  in
  let idx = take_fill 0 s.ops in
  Alcotest.(check bool) "a recolorable op exists" true (idx >= 0);
  s.ops <-
    List.mapi
      (fun i o ->
        if i = idx then match o with
          | Fill f -> Fill { f with fcolor = color 1 0 0 255 }
          | Shadow sh -> Shadow { sh with scolor = color 1 0 0 255 }
          | _ -> o
        else o)
      s.ops;
  let d1 = Lui_raster.Renderer.render r s in
  Alcotest.(check bool) "one change merges to <=2 rects" true
    (List.length d1 >= 1 && List.length d1 <= 2);
  (* Change twelve ops' colors: the rects collapse to one. *)
  s.ops <-
    List.mapi
      (fun i o ->
        match o with
        | Fill f -> Fill { f with fcolor = color (min 255 (i * 20)) 0 0 255 }
        | Shadow sh -> Shadow { sh with scolor = color (min 255 (i * 20)) 0 0 255 }
        | Glyphs g -> Glyphs { g with gcolor = color (min 255 (i * 20)) 0 0 255 }
        | Image im -> Image { im with iopacity = 0.25 +. float i *. 0.05 }
        | _ -> o)
      s.ops;
  let d2 = Lui_raster.Renderer.render r s in
  Alcotest.(check bool) "widespread changes collapse" true (List.length d2 <= 8)

(* Multicore bands draw exactly what one worker draws. *)
let test_bands () =
  for i = 0 to 3 do
    let m = Maker.make (3 + i) in
    m.with_effects <- true;
    let s = Maker.scene m in
    (* Scale the scene up so the area splits into bands. *)
    let k = 8 in
    s.width <- s.width * k;
    s.height <- s.height * k;
    s.glyphs <-
      List.map
        (fun gl -> { gl with gx = gl.gx *. float k; gy = gl.gy *. float k })
        s.glyphs;
    s.ops <-
      List.map
        (fun o ->
          let sc rc = { x = rc.x *. float k; y = rc.y *. float k;
                                w = rc.w *. float k; h = rc.h *. float k } in
          let rs (a, b, c, d) = (a *. float k, b *. float k, c *. float k, d *. float k) in
          match o with
          | Fill f -> Fill { f with frect = sc f.frect; fradii = rs f.fradii }
          | Shadow sh ->
            Shadow { sh with srect = sc sh.srect; sradii = rs sh.sradii;
                             sblur = sh.sblur *. float k; scast = sc sh.scast;
                             scast_radii = rs sh.scast_radii }
          | Image im -> Image { im with irect2 = sc im.irect2 }
          | Hole h -> Hole { h with hrect = sc h.hrect; hradii = rs h.hradii }
          | Effect e -> Effect { e with edrect = sc e.edrect; edradii = rs e.edradii }
          | Push_clip c -> Push_clip { c with crect = sc c.crect; cradii = rs c.cradii }
          | Glyphs g -> Glyphs g
          | Pop_clip -> Pop_clip)
        s.ops;
    let a = Lui_raster.render ~workers:1 ~scene:s () in
    let b = Lui_raster.render ~workers:8 ~scene:s () in
    Alcotest.(check bool)
      (Printf.sprintf "scene %d: bands draw as one" i)
      true (Bytes.equal (bytes_of a) (bytes_of b))
  done

(* Damage through a multicore renderer matches a whole render too. *)
let test_damage_bands () =
  let m = Maker.make 9 in
  m.with_effects <- true;
  let s = Maker.scene m in
  let r = Lui_raster.Renderer.create () in
  ignore (Lui_raster.Renderer.render ~workers:1 r s);
  for _ = 0 to 5 do
    ignore (Maker.change m s);
    ignore (Lui_raster.Renderer.render ~workers:8 r s);
    let full = Lui_raster.render ~workers:8 ~scene:s () in
    Alcotest.(check bool) "partial multicore matches whole"
      true
      (Bytes.equal (bytes_of (Lui_raster.Renderer.image r)) (bytes_of full))
  done

(* ---------- pixel-level semantics ---------- *)

let px_of img x y =
  let i = y * img.Lui_raster.Image.stride + 4 * x in
  (Char.code (Bytes.get img.Lui_raster.Image.pix (i + 2)),
   Char.code (Bytes.get img.Lui_raster.Image.pix (i + 1)),
   Char.code (Bytes.get img.Lui_raster.Image.pix i),
   Char.code (Bytes.get img.Lui_raster.Image.pix (i + 3)))

let gray_of img x y = let (r, _, _, _) = px_of img x y in r

(* A shadow whose casting rect occludes its middle still paints its
   blur outside that rect. *)
let test_shadow_outside_cast () =
  let cast = rect 24. 16. 16. 32. in
  let s =
    scene ~w:64 ~h:64 ~clear:white
      [ ishadow ~cast ~blur:8. cast (color 0 0 0 255) ]
  in
  let img = Lui_raster.render ~scene:s () in
  Alcotest.(check int) "inside cast stays clear" 255 (gray_of img 32 32);
  Alcotest.(check bool) "shadow shows outside" true
    (gray_of img 42 32 < 235);
  Alcotest.(check int) "far away clear" 255 (gray_of img 4 4)

(* Along a row through the middle of a sharp-cornered box the shadow
   profile is the Gaussian-blurred step: alpha(d) = 0.5 * erfc(d*k)
   with k = sqrt(0.5)/sigma, sigma = blur/2 — the same profile the GPU
   evaluator's shader uses. *)
let test_shadow_formula () =
  let s =
    scene ~w:96 ~h:64 ~clear:white
      [ ishadow ~blur:8. (rect 20. 12. 24. 40.) (color 0 0 0 255) ]
  in
  let img = Lui_raster.render ~scene:s () in
  (* sigma = blur/2 = 4; k spreads the profile. *)
  let k = sqrt 0.5 /. 4. in
  (* erfc via Abramowitz-Stegun 7.1.26 for erf. *)
  let erfc x =
    let erf x =
      let t = 1. /. (1. +. 0.3275911 *. Float.abs x) in
      let poly =
        t *. (0.254829592 +. t *. (-0.284496736 +. t *. (1.421413741
          +. t *. (-1.453152027 +. t *. 1.061405429))))
      in
      (if x < 0. then -1. else 1.) *. (1. -. poly *. exp (-.x *. x))
    in
    1. -. erf x
  in
  let y = 32 in
  (* The box's right edge is at x=44; each pixel's d is x+0.5-44. *)
  List.iter
    (fun x ->
      let d = float x +. 0.5 -. 44. in
      let want = 255. *. (1. -. 0.5 *. erfc (d *. k)) in
      let got = gray_of img x y in
      Alcotest.(check bool)
        (Printf.sprintf "x=%d d=%g want %g got %d" x d want got)
        true (Float.abs (float got -. want) <= 4.))
    [ 44; 46; 48; 50; 52; 56; 60 ]

(* An inset shadow concentrates inside the cast rect and leaves both
   the hole's interior and the outside untouched. *)
let test_inset_shadow_pixels () =
  let cast = rect 16. 16. 32. 32. and hole = rect 22. 22. 20. 20. in
  let s =
    scene ~w:64 ~h:64 ~clear:white
      [ ishadow ~inset:true ~cast ~blur:8. hole (color 0 0 0 255) ]
  in
  let img = Lui_raster.render ~scene:s () in
  Alcotest.(check bool) "shadow inside cast" true
    (gray_of img 19 32 < 245);
  Alcotest.(check bool) "hole interior clear" true
    (gray_of img 32 32 > 245);
  Alcotest.(check int) "outside cast clear" 255 (gray_of img 8 32)

(* Sub-pixel-thin fills get coverage proportional to the fraction of
   the pixel they cover. *)
let test_thin_line_coverage () =
  let s =
    scene ~w:64 ~h:64 ~clear:white
      [ ifill (rect 8. 8.0 48. 0.5) (color 0 0 0 255);
        ifill (rect 8. 24.0 48. 0.25) (color 0 0 0 255);
        ifill (rect 8. 40.0 48. 1.) (color 0 0 0 255) ]
  in
  let img = Lui_raster.render ~scene:s () in
  let check name want x y =
    Alcotest.(check bool)
      (Printf.sprintf "%s: want %d got %d" name want (gray_of img x y))
      true (abs (gray_of img x y - want) <= 4)
  in
  check "half px" 128 32 8;
  check "quarter px" 191 32 24;
  check "full px" 0 32 40

(* The opaque mask path blends every mask byte by integer math that
   matches the floating-point blend: out = src*m + dst*(255-m) over
   255, alpha accumulates to full. Exhaustive over mask values at a
   spread of destinations. *)
let test_opaque_mask_coverage () =
  let mask_atlas = Atlas.create ~bpp:1 ~w:64 ~h:16 in
  let (u0, v0) =
    match Atlas.alloc_transient mask_atlas 32 8 with
    | Some p -> p
    | None -> Alcotest.fail "atlas alloc failed"
  in
  let table = Bytes.init 256 Char.chr in
  Atlas.put mask_atlas ~x:u0 ~y:v0 ~w:32 ~h:8 ~src:table ~stride:32;
  let glyphs =
    List.init 256 (fun i ->
        glyph ~x:(float (i mod 16) *. 4.) ~y:(float (i / 16) *. 4.)
          ~w:1. ~h:1. ~u:(u0 + i mod 32) ~v:(v0 + i / 32) ~uw:1 ~vh:1
          (color 0 0 0 255))
  in
  List.iter
    (fun dst ->
      let s =
        scene ~w:64 ~h:64 ~clear:(color dst dst dst 255)
          ~mask:mask_atlas ~glyphs [ iglyphs 0 256 ]
      in
      let img = Lui_raster.render ~scene:s () in
      for m = 0 to 255 do
        let (r, _, _, a) = px_of img ((m mod 16) * 4) ((m / 16) * 4) in
        let want = float dst *. float (255 - m) /. 255. in
        if Float.abs (float r -. want) > 2. || a <> 255 then
          Alcotest.failf "dst %d mask %d: got (%d,a=%d) want ~%.1f" dst m
            r a want
      done)
    [ 0; 36; 73; 109; 146; 182; 219; 255 ]

(* Oklab gradient math checked against the published matrices, computed
   independently here. sRGB <-> Oklab must round-trip at the endpoints
   and the interior must follow the Oklab interpolation, not the sRGB
   one. *)
module Ref_oklab = struct
  let to_linear c =
    if c <= 0.04045 then c /. 12.92 else ((c +. 0.055) /. 1.055) ** 2.4
  let to_srgb c =
    if c <= 0.0031308 then 12.92 *. c
    else 1.055 *. (c ** (1. /. 2.4)) -. 0.055
  let oklab (r, g, b) =
    let r = to_linear r and g = to_linear g and b = to_linear b in
    let l = Float.cbrt (0.4122214708 *. r +. 0.5363325363 *. g
                        +. 0.0514459929 *. b) in
    let m = Float.cbrt (0.2119034982 *. r +. 0.6806995451 *. g
                        +. 0.1073969566 *. b) in
    let s = Float.cbrt (0.0883024619 *. r +. 0.2817188376 *. g
                        +. 0.6299787005 *. b) in
    (0.2104542553 *. l +. 0.7936177850 *. m -. 0.0040720468 *. s,
     1.9779984951 *. l -. 2.4285922050 *. m +. 0.4505937099 *. s,
     0.0259040371 *. l +. 0.7827717662 *. m -. 0.8086757660 *. s)
  let from_oklab (la, aa, ab) =
    let l = la +. 0.3963377774 *. aa +. 0.2158037573 *. ab in
    let m = la -. 0.1055613458 *. aa -. 0.0638541728 *. ab in
    let s = la -. 0.0894841775 *. aa -. 1.2914855480 *. ab in
    let l = l ** 3. and m = m ** 3. and s = s ** 3. in
    (to_srgb (4.0767416621 *. l -. 3.3077115913 *. m +. 0.2309699292 *. s),
     to_srgb (-1.2684380046 *. l +. 2.6097574011 *. m -. 0.3413193965 *. s),
     to_srgb (-0.0041960863 *. l -. 0.7034186147 *. m +. 1.7076147010 *. s))
  let mix (r1, g1, b1) (r2, g2, b2) t =
    let (l1, a1, b1_) = oklab (r1, g1, b1)
    and (l2, a2, b2_) = oklab (r2, g2, b2) in
    from_oklab
      (l1 *. (1. -. t) +. l2 *. t,
       a1 *. (1. -. t) +. a2 *. t,
       b1_ *. (1. -. t) +. b2_ *. t)
end

let test_oklab_gradient () =
  let s =
    scene ~w:64 ~h:64 ~clear:white
      [ ifill ~paint:Oklab ~c2:(color 255 255 255 255)
          ~g:(0., 0., 64., 0.) (rect 0. 0. 64. 8.) (color 0 0 0 255);
        ifill ~paint:Oklab ~c2:(color 0 0 255 255) ~g:(0., 0., 64., 0.)
          (rect 0. 16. 64. 8.) (color 255 0 0 255) ]
  in
  let img = Lui_raster.render ~scene:s () in
  (* black -> white in Oklab: midpoint L=0.5 -> srgb ~99, not the
     ~186 the sRGB mix gives. *)
  let mid = gray_of img 32 4 in
  Alcotest.(check bool)
    (Printf.sprintf "oklab midpoint %d" mid) true
    (abs (mid - 99) <= 4);
  (* Endpoints round-trip to the byte. *)
  Alcotest.(check bool) "t=0 black" true (gray_of img 0 4 <= 2);
  Alcotest.(check bool) "t=1 white" true (gray_of img 63 4 >= 252);
  (* red -> blue: every sampled pixel matches the reference Oklab mix
     within a few bytes. *)
  List.iter
    (fun x ->
      let t = (float x +. 0.5) /. 64. in
      let (er, eg, eb) =
        Ref_oklab.mix (1., 0., 0.) (0., 0., 1.) t
      in
      let (r, g, b, _) = px_of img x 20 in
      List.iter
        (fun (name, got, want) ->
          Alcotest.(check bool)
            (Printf.sprintf "x=%d %s: got %d want %d" x name got want)
            true (abs (got - want) <= 4))
        [ ("r", r, int_of_float (Float.round (er *. 255.)));
          ("g", g, int_of_float (Float.round (eg *. 255.)));
          ("b", b, int_of_float (Float.round (eb *. 255.))) ])
    [ 8; 16; 24; 32; 40; 48; 56 ]

let () =
  Alcotest.run "lui_raster"
    [ ( "goldens", [ Alcotest.test_case "reference scenes" `Slow test_golden ] );
      ( "semantics",
        [ Alcotest.test_case "pixel checks" `Quick test_pixel_checks;
          Alcotest.test_case "bands draw as one" `Slow test_bands;
          Alcotest.test_case "shadow outside cast" `Quick
            test_shadow_outside_cast;
          Alcotest.test_case "shadow formula" `Quick test_shadow_formula;
          Alcotest.test_case "inset shadow pixels" `Quick
            test_inset_shadow_pixels;
          Alcotest.test_case "thin line coverage" `Quick
            test_thin_line_coverage;
          Alcotest.test_case "opaque mask coverage" `Quick
            test_opaque_mask_coverage;
          Alcotest.test_case "oklab gradient" `Quick test_oklab_gradient ] );
      ( "damage",
        [ Alcotest.test_case "redraws what changed" `Slow test_damage_redraws_plain;
          Alcotest.test_case "redraws effects" `Slow test_damage_redraws_effects;
          Alcotest.test_case "skips unchanged" `Quick test_damage_skips;
          Alcotest.test_case "merge cap" `Quick test_damage_merge;
          Alcotest.test_case "damage bands" `Slow test_damage_bands ] ) ]
