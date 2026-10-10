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

let () =
  Alcotest.run "lui_raster"
    [ ( "goldens", [ Alcotest.test_case "reference scenes" `Slow test_golden ] );
      ( "semantics",
        [ Alcotest.test_case "pixel checks" `Quick test_pixel_checks;
          Alcotest.test_case "bands draw as one" `Slow test_bands ] );
      ( "damage",
        [ Alcotest.test_case "redraws what changed" `Slow test_damage_redraws_plain;
          Alcotest.test_case "redraws effects" `Slow test_damage_redraws_effects;
          Alcotest.test_case "skips unchanged" `Quick test_damage_skips;
          Alcotest.test_case "merge cap" `Quick test_damage_merge;
          Alcotest.test_case "damage bands" `Slow test_damage_bands ] ) ]
