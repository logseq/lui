(* The glass plugin's tests: the level/mask math against fixed
   expectations, the emitted op structure, and the CPU twins against a
   straightforward evaluation of the shaders' own math — the golden the
   parity harness later checks on the GPU. *)

open Lui_scene
module G = Lui_plugin_glass
module Tk = Lui_raster_testkit.Testkit

let fmin = min and fmax = max
let close a b = Float.abs (a -. b) <= 1e-4
let checkf name a b = Alcotest.(check bool) name true (close a b)
let fst3 (a, _, _) = a and snd3 (_, b, _) = b and trd3 (_, _, c) = c

(* The backdrop without blur is the frame itself: a flat fill, so its
   sample anywhere is that fill's color. *)
let bd_at _x _y = (37. /. 255., 99. /. 255., 235. /. 255.)

(* ---------- blur_levels ---------- *)

let test_levels () =
  let lv = G.blur_levels 0. 0. in
  Alcotest.(check int) "no blur no levels" 0 (List.length lv);
  let lv = G.blur_levels 3. 3. in
  Alcotest.(check int) "constant blur one level" 1 (List.length lv);
  (match lv with
   | [ l ] ->
     checkf "single blur" 3. l.G.lblur;
     checkf "single lo" (-1.) l.G.llo;
     checkf "single hi" 0. l.G.lhi
   | _ -> Alcotest.fail "expected one level");
  let lv = G.blur_levels 0. 8. in
  (* his halve from 8 down to the finest level: 2, 4, 8. *)
  let exp =
    [ (2., 0., 2.); (sqrt 12., 2., 4.); (sqrt 48., 4., 8.) ]
  in
  Alcotest.(check int) "levels count" 3 (List.length lv);
  List.iter2
    (fun l (b, lo, hi) ->
      checkf "blur" b l.G.lblur;
      checkf "lo" lo l.G.llo;
      checkf "hi" hi l.G.lhi)
    lv exp;
  let lv = G.blur_levels 1. 8. in
  (* a floor level of 1 first, then the same halving his. *)
  Alcotest.(check int) "levels with floor" 4 (List.length lv);
  (match lv with
   | l0 :: _ ->
     checkf "floor blur" 1. l0.G.lblur;
     checkf "floor lo" (-1.) l0.G.llo;
     checkf "floor hi" 0. l0.G.lhi
   | _ -> Alcotest.fail "expected a floor level")

(* ---------- mask_line ---------- *)

let test_mask_line () =
  let r = rect 0. 0. 100. 50. in
  let f = G.fade ~from:1. ~to_:0. ~angle:180. () in
  let (x0, y0, x1, y1) = G.mask_line r f in
  (* angle 180 descends: From at the top edge's middle, To at the
     bottom's. *)
  checkf "line x0" 50. x0;
  checkf "line y0" 0. y0;
  checkf "line x1" 50. x1;
  checkf "line y1" 50. y1;
  let f = G.fade ~from:1. ~to_:0. ~angle:0. () in
  let (_, y0, _, y1) = G.mask_line r f in
  checkf "angle0 y0" 50. y0;
  checkf "angle0 y1" 0. y1;
  (* start/stop shorten the line within itself. *)
  let f = G.fade ~from:1. ~to_:0. ~angle:180. ~start:0.25 ~stop:0.75 () in
  let (x0, y0, _, y1) = G.mask_line r f in
  checkf "start y" 12.5 y0;
  checkf "stop y" 37.5 y1;
  ignore x0

(* ---------- blur_wanted ---------- *)

let test_blur_wanted () =
  let r = rect 0. 0. 100. 50. in
  let line = (50., 0., 50., 50.) in
  (* blur 8 at the top fading to 0 at the bottom: the part where it is
     more than 4 is the top half. *)
  (match G.blur_wanted r line 8. 0. 4. with
   | Some w ->
     checkf "wanted x" 0. w.x;
     checkf "wanted w" 100. w.w;
     checkf "wanted h" 25. w.h
   | None -> Alcotest.fail "expected a wanted rect");
  (match G.blur_wanted r line 8. 0. 8. with
   | None -> ()
   | Some _ -> Alcotest.fail "nothing wants blur 8");
  (* same blur everywhere covers the element or nothing. *)
  (match G.blur_wanted r line 8. 8. 4. with
   | Some w -> checkf "same covers" 50. w.h
   | None -> Alcotest.fail "same blur wanted");
  (match G.blur_wanted r line 8. 8. 9. with
   | None -> ()
   | Some _ -> Alcotest.fail "same blur unwanted")

(* ---------- lens / normal ---------- *)

let test_lens () =
  (* the lens bends most at the edge and none from the bezel in. *)
  checkf "lens at edge" 1. (G.glass_lens 0. 10.);
  checkf "lens at bezel" 0. (G.glass_lens 10. 10.);
  checkf "lens beyond" 0. (G.glass_lens 20. 10.);
  checkf "lens no bezel" 0. (G.glass_lens 5. 0.);
  let l = G.glass_lens 5. 10. in
  Alcotest.(check bool) "lens between" true (l > 0. && l < 1.)

let test_normal () =
  let r = rect 10. 10. 80. 40. in
  let radii = (8., 8., 8., 8.) in
  (* deep inside off the midline the normal points at the nearer side *)
  let nx, ny = G.glass_normal 20. 30. r radii in
  checkf "inner nx" (-1.) nx;
  checkf "inner ny" 0. ny;
  let nx, ny = G.glass_normal 80. 30. r radii in
  checkf "right nx" 1. nx;
  checkf "right ny" 0. ny;
  let nx, ny = G.glass_normal 50. 20. r radii in
  checkf "top nx" 0. nx;
  checkf "top ny" (-1.) ny;
  (* at a corner the normal turns the diagonal *)
  let nx, ny = G.glass_normal 14. 14. r radii in
  Alcotest.(check bool) "corner diagonal" true (nx < 0. && ny < 0.);
  let m = sqrt (nx *. nx +. ny *. ny) in
  checkf "corner unit" 1. m

(* ---------- tone ---------- *)

let test_toned () =
  let (r, g, b) = G.toned (0.5, 0.5, 0.5) 1. 0. in
  checkf "grey stays" 0.5 r;
  checkf "grey stays g" 0.5 g;
  checkf "grey stays b" 0.5 b;
  let (r, _, _) = G.toned (0.8, 0.2, 0.2) 0. 0. in
  (* saturation 0 collapses to the luminance *)
  let l = G.luminance (0.8, 0.2, 0.2) in
  checkf "desaturated" l r

(* ---------- the helpers' emitted ops ---------- *)

let last_ops s = s.ops
let n_effects s = List.length s.effects

let test_glass_emit () =
  let s = Tk.scene ~w:100 ~h:60 [] in
  G.glass ~scene:s ~radii:(Tk.radii 8.) (rect 20. 10. 60. 40.)
    (G.material ());
  Alcotest.(check int) "one op" 1 (List.length (last_ops s));
  Alcotest.(check int) "one effect" 1 (n_effects s);
  let e = List.hd s.effects in
  Alcotest.(check bool) "glass fx" true (e.ee == G.glass_fx);
  (* material: m=min(60,40)=40px at scale 1 → bezel=min(36,20)=20,
     refraction=32; Regular light ramp, blur=min(max(40*.035,1),10)=1.4 *)
  let (bz, rf, rm, rw) = e.eparams.(0) in
  checkf "bezel" 20. bz;
  checkf "refraction" 32. rf;
  checkf "rim" 0.35 rm;
  checkf "rimw" 1. rw;
  let (lo, hi, cu, sa) = e.eparams.(2) in
  checkf "low" 0.541 lo;
  checkf "high" 1. hi;
  checkf "curve" 1.2 cu;
  checkf "sat" 1. sa;
  checkf "eblur" 1.4 e.eblur;
  (match s.ops with
   | [ Effect ed ] ->
     Alcotest.(check int) "index" 0 ed.edindex;
     let (tl, _, _, _) = ed.edradii in
     checkf "radii" 8. tl
   | _ -> Alcotest.fail "expected one Effect op")

let test_glass_grow () =
  let s = Tk.scene ~w:100 ~h:60 [] in
  G.glass ~scene:s ~radii:(Tk.radii 8.) ~grow:1.
    (rect 20. 10. 60. 40.) (G.material ~interactive:true ());
  (match s.ops with
   | [ Effect ed ] ->
     (* grow 1: dx=1.1, dy=0.45 DIPs, radii += dy *)
     checkf "grow x" (20. -. 1.1) ed.edrect.x;
     checkf "grow y" (10. -. 0.45) ed.edrect.y;
     checkf "grow w" (60. +. 2.2) ed.edrect.w;
     checkf "grow h" (40. +. 0.9) ed.edrect.h;
     let (tl, _, _, _) = ed.edradii in
     checkf "grow radii" 8.45 tl
   | _ -> Alcotest.fail "expected one Effect op");
  (* non-interactive material ignores grow *)
  let s = Tk.scene ~w:100 ~h:60 [] in
  G.glass ~scene:s ~grow:1. (rect 20. 10. 60. 40.) (G.material ());
  (match s.ops with
   | [ Effect ed ] -> checkf "no grow x" 20. ed.edrect.x
   | _ -> Alcotest.fail "expected one Effect op")

let test_blur_emit () =
  let s = Tk.scene ~w:100 ~h:60 [] in
  G.blur ~scene:s ~radius:6. (rect 0. 0. 100. 50.);
  (* constant blur: a single full-coverage level *)
  Alcotest.(check int) "one level" 1 (n_effects s);
  Alcotest.(check int) "one op" 1 (List.length s.ops);
  let e = List.hd s.effects in
  let (_, _, lo, hi) = e.eparams.(1) in
  checkf "level lo" (-1.) lo;
  checkf "level hi" 0. hi;
  checkf "level blur" 6. e.eblur;
  (* a masked blur splits into levels and clips the square element *)
  let s = Tk.scene ~w:100 ~h:60 [] in
  let m = G.fade ~from:1. ~to_:0. ~angle:180. () in
  G.blur ~scene:s ~mask:m ~radius:8. (rect 0. 0. 100. 50.);
  let n = n_effects s in
  Alcotest.(check bool) "masked levels" true (n >= 3);
  (* each op after the first covers a smaller wanted rect *)
  (match s.ops with
   | _ :: Effect e2 :: _ ->
     Alcotest.(check bool) "clipped" true (e2.edrect.h < 50.)
   | _ -> Alcotest.fail "expected several Effect ops")

let test_scroll_edge () =
  let s = Tk.scene ~w:100 ~h:60 [] in
  let bg = color 250 250 250 255 in
  G.scroll_edge ~scene:s ~bg (rect 0. 0. 100. 74.);
  (match s.ops with
   | [ Fill f ] ->
     Alcotest.(check bool) "gradient" true (f.fpaint = Linear);
     let (_, y0, _, y1) = f.fgradient in
     checkf "from top" 0. y0;
     checkf "to bottom" 74. y1;
     Alcotest.(check int) "85%" 217 f.fcolor.a
   | _ -> Alcotest.fail "expected a soft Fill");
  let s = Tk.scene ~w:100 ~h:60 [] in
  G.scroll_edge ~scene:s ~hard:true ~bg (rect 0. 0. 100. 74.);
  (* hard: one blur effect op plus the hairline fill below *)
  Alcotest.(check int) "hard ops" 2 (List.length s.ops);
  Alcotest.(check int) "hard fx" 1 (n_effects s);
  (match List.rev s.ops with
   | Fill f :: Effect _ :: _ ->
     checkf "hairline y" 74. f.frect.y;
     Alcotest.(check bool) "hairline thin" true (f.frect.h <= 1.)
   | _ -> Alcotest.fail "expected Effect then hairline Fill")

(* ---------- the CPU twin against the shader's own math ----------

   The functions below evaluate the shaders' formulas directly (the
   pow curve rather than the twin's table), so comparing rendered
   bytes to them within a channel step checks the twin like the parity
   harness checks the GPU side. *)

let shader_tone c (lo, hi, cu, sat) =
  let (r, g, b) = c in
  let l = 0.2126 *. r +. 0.7152 *. g +. 0.0722 *. b in
  let t = lo +. (hi -. lo) *. (1. -. (fmax (1. -. l) 0. ** cu)) in
  let k = (hi -. lo) *. sat in
  let f v = fmin (fmax (t +. (v -. l) *. k) 0.) 1. in
  (f r, f g, f b)

let shader_glass x y r radii p =
  let t = fmax (~-.(sd_round_rect r radii x y)) 0. in
  let (bezel, refrac, rim, rimw) = p.(0) in
  let (tr, tg, tb, ta) = p.(1) in
  let (lx, ly, _, _) = p.(3) in
  let nx, ny =
    if t < bezel || t < 3. *. rimw then G.glass_normal x y r radii
    else (0., 0.)
  in
  let sx, sy =
    if t < bezel then begin
      let d = refrac *. G.glass_lens t bezel in
      (x -. nx *. d, y -. ny *. d)
    end
    else (x, y)
  in
  let cr, cg, cb = shader_tone (bd_at sx sy) p.(2) in
  let cr = cr +. (tr -. cr) *. ta
  and cg = cg +. (tg -. cg) *. ta
  and cb = cb +. (tb -. cb) *. ta in
  if rim > 0. && t < 3. *. rimw then begin
    let rr = t /. rimw in
    let a = rim *. exp (~-.(rr *. rr)) in
    let l = Float.abs (nx *. lx +. ny *. ly) in
    (cr +. (l -. cr) *. a, cg +. (l -. cg) *. a, cb +. (l -. cb) *. a)
  end
  else (cr, cg, cb)

let byte_at img w x y c =
  Char.code (Bytes.get img.Lui_raster.Image.pix (4 * (y * w + x) + c))

let test_glass_twin () =
  let w, h = (100, 60) in
  let radii = Tk.radii 8. in
  let params =
    [| (30., 48., 0.35, 1.); (0., 0., 0., 0.);
       (0.541, 1., 1.2, 1.); (0., 1., 0., 0.); (0., 0., 0., 0.) |]
  in
  let s =
    Tk.scene ~w ~h ~effects:[ { ee = G.glass_fx; eblur = 0.; eparams = params } ]
      [ Tk.ifill (rect 0. 0. 100. 60.) (color 37 99 235 255);
        Tk.ieffect ~radii (rect 20. 10. 60. 40.) 0 ]
  in
  let img = Lui_raster.render ~scene:s () in
  let er = rect 20. 10. 60. 40. in
  let probe x y =
    let (sr, sg, sb) =
      shader_glass (float x +. 0.5) (float y +. 0.5) er radii params
    in
    let to8 v = if v <= 0. then 0 else if v >= 1. then 255 else
        int_of_float (v *. 255. +. 0.5) in
    let ba = byte_at img w x y in
    let ok =
      Int.abs (ba 0 - to8 sb) <= 1 && Int.abs (ba 1 - to8 sg) <= 1
      && Int.abs (ba 2 - to8 sr) <= 1
    in
    Alcotest.(check bool)
      (Printf.sprintf "pixel %d,%d = %d,%d,%d want ~%d,%d,%d" x y (ba 0)
         (ba 1) (ba 2) (to8 sb) (to8 sg) (to8 sr))
      true ok
  in
  probe 50 30;
  probe 22 30;
  probe 24 16;
  probe 76 46;
  probe 49 11

(* The blur twin's weight fades its source over the destination, alpha
   included: under an unblurred uniform backdrop, a level's pixel is
   the tone of the fill times the weight, over the fill. *)
let test_blur_twin () =
  let w, h = (100, 60) in
  (* mask fading full blur at the top to none at the bottom; the level
     {lo 2, hi 4} shows from blur>2 upward, half at blur 3. *)
  let params =
    [| (50., 0., 50., 60.); (8., 0., 2., 4.); (0., 0., 0., 0.);
       (0., 0., 0., 0.); (0., 0., 0., 0.) |]
  in
  let s =
    Tk.scene ~w ~h ~effects:[ { ee = G.blur_fx; eblur = 0.; eparams = params } ]
      [ Tk.ifill (rect 0. 0. 100. 60.) (color 37 99 235 255);
        Tk.ieffect (rect 0. 0. 100. 60.) 0 ]
  in
  let img = Lui_raster.render ~scene:s () in
  (* blur at pixel row y: line top→bottom is 60 tall, blur = 8*(1-t)
     where t=(y+.5)/60; weight = clamp((blur-2)/2). Solve y for w=1:
     blur>4 → t<0.5 → y<29.5; w=0 at blur<=2 → t>=0.75 → y>=44.5. *)
  let bg = (235, 99, 37) in (* BGRA order in pix *)
  let full = byte_at img w 50 10 in
  Alcotest.(check int) "top blurred b" (fst3 bg) (full 0);
  Alcotest.(check int) "top blurred g" (snd3 bg) (full 1);
  Alcotest.(check int) "top blurred r" (trd3 bg) (full 2);
  Alcotest.(check int) "top alpha" 255 (full 3);
  let mid = byte_at img w 37 37 in
  (* blur=8*(1-37.5/60)=3 → w=0.5 → half the fill over the fill = fill *)
  Alcotest.(check int) "mid still fill" (fst3 bg) (mid 0);
  Alcotest.(check int) "mid alpha" 255 (mid 3);
  let low = byte_at img w 50 55 in
  Alcotest.(check int) "bottom clear" (fst3 bg) (low 0)

(* ---------- the plugin service ---------- *)

let to_num = function
  | `Int i -> float i
  | `Float f -> f
  | `Intlit s -> float_of_string s
  | _ -> Alcotest.fail "not a number"

let jlist j name = Yojson.Safe.Util.(member name j |> to_list)
let jfloats j = List.map to_num (Yojson.Safe.Util.to_list j)
let jmember n j = Yojson.Safe.Util.member n j

let call method_ payload =
  match Lui_plugin.call ~service:"plugin:glass" ~method_ payload with
  | Error e -> Alcotest.fail e
  | Ok out -> Yojson.Safe.from_string out

(* The service must answer with the same op doc the OCaml helper
   emits: same rect, same effect params. *)
let check_effect_op j eo er radii =
  let ops = jlist j "ops" in
  Alcotest.(check int) "one op" 1 (List.length ops);
  let fxs = jlist j "effects" in
  Alcotest.(check int) "one effect" 1 (List.length fxs);
  Alcotest.(check string) "fx name" eo.ee.ename
    (match jmember "name" (List.hd fxs) with
     | `String n -> n
     | _ -> Alcotest.fail "no name");
  let ps = jlist (List.hd fxs) "params" in
  Alcotest.(check int) "five params" 5 (List.length ps);
  List.iteri
    (fun i pj ->
      let got = jfloats pj in
      let (a, b, c, d) = eo.eparams.(i) in
      match got with
      | [ ga; gb; gc; gd ] ->
        checkf "p a" a ga; checkf "p b" b gb;
        checkf "p c" c gc; checkf "p d" d gd
      | _ -> Alcotest.fail "bad param")
    ps;
  let op = List.hd ops in
  (match jmember "rect" op with
   | `List [ x; y; w; h ] ->
     checkf "rect x" er.x (to_num x);
     checkf "rect y" er.y (to_num y);
     checkf "rect w" er.w (to_num w);
     checkf "rect h" er.h (to_num h)
   | _ -> Alcotest.fail "bad rect");
  (match jmember "radii" op with
   | `List [ a; b; c; d ] ->
     let (ta, tb, tc, td) = radii in
     checkf "radii tl" ta (to_num a);
     checkf "radii tr" tb (to_num b);
     checkf "radii br" tc (to_num c);
     checkf "radii bl" td (to_num d)
   | _ -> Alcotest.fail "bad radii")

let test_service () =
  (match Lui_plugin.use [ G.plugin ] with
   | Ok () -> ()
   | Error e -> Alcotest.fail e);
  (* material round-trip: the JSON doc equals the standalone emit *)
  let j =
    call "material"
      {|{"rect":[20,10,60,40],"radii":[8,8,8,8],"interactive":true,"grow":1}|}
  in
  let s = Tk.scene ~w:100 ~h:60 [] in
  G.glass ~scene:s ~radii:(Tk.radii 8.) ~grow:1.
    (rect 20. 10. 60. 40.)
    (G.material ~interactive:true ());
  check_effect_op j (List.hd s.effects) (rect 18.9 9.55 62.2 40.9)
    (Tk.radii 8.45);
  (* blur round-trip *)
  let j =
    call "blur"
      {|{"rect":[0,0,100,50],"radius":8,"mask":{"from":1,"to":0,"angle":180}}|}
  in
  Alcotest.(check bool) "masked levels" true
    (List.length (jlist j "effects") >= 3);
  (* scroll_edge: the gradient fill shows through the doc *)
  let j =
    call "scroll_edge" {|{"rect":[0,0,100,74],"bg":[250,250,250,255]}|}
  in
  (match jlist j "ops" with
   | [ f ] ->
     Alcotest.(check string) "fill" "fill"
       (match jmember "op" f with `String k -> k | _ -> "")
   | _ -> Alcotest.fail "expected one fill");
  Lui_plugin.reset ()

let () =
  Alcotest.run "lui_plugin_glass"
    [ ( "math",
        [ Alcotest.test_case "blur levels" `Quick test_levels;
          Alcotest.test_case "mask line" `Quick test_mask_line;
          Alcotest.test_case "blur wanted" `Quick test_blur_wanted;
          Alcotest.test_case "lens" `Quick test_lens;
          Alcotest.test_case "normal" `Quick test_normal;
          Alcotest.test_case "toned" `Quick test_toned ] );
      ( "emit",
        [ Alcotest.test_case "glass" `Quick test_glass_emit;
          Alcotest.test_case "glass grow" `Quick test_glass_grow;
          Alcotest.test_case "blur" `Quick test_blur_emit;
          Alcotest.test_case "scroll edge" `Quick test_scroll_edge ] );
      ( "twin",
        [ Alcotest.test_case "glass" `Quick test_glass_twin;
          Alcotest.test_case "blur" `Quick test_blur_twin ] );
      ("service", [ Alcotest.test_case "round-trip" `Quick test_service ]) ]
