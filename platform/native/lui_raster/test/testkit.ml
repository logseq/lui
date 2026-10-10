open Lui_scene

let white = color 255 255 255 255
let black = color 0 0 0 255
let transparent = color 0 0 0 0

(* ---------- scene builders ---------- *)

let atlases () =
  (Atlas.create ~bpp:1 ~w:8 ~h:8, Atlas.create ~bpp:4 ~w:8 ~h:8)

let scene ~w ~h ?(clear = white) ?mask ?color_atlas ?(glyphs = []) ?(effects = [])
    ?(text = default_text_params) ops =
  let mask_atlas = match mask with Some a -> a | None -> fst (atlases ()) in
  let ca = match color_atlas with Some a -> a | None -> snd (atlases ()) in
  let s = create ~mask_atlas ~color_atlas:ca in
  reset s ~width:w ~height:h ~scale:1. ~clear;
  s.ops <- ops;
  s.glyphs <- glyphs;
  s.effects <- effects;
  s.text <- text;
  s

let radii r = (r, r, r, r)
let no4 = (0., 0., 0., 0.)
let uniform w = (w, w, w, w)

let ifill ?(radii = no4) ?(cont = false) ?(paint = Solid) ?c2 ?(g = no4)
    ?(bw = no4) ?(bc = transparent) ?(dashed = false) ?(opacity = 0.) rc c =
  Fill
    { frect = rc; fradii = radii; fcontinuous = cont; fcolor = c;
      fpaint = paint; fcolor2 = (match c2 with Some c -> c | None -> c);
      fgradient = g; fborder = bw; fborder_color = bc; fdashed = dashed;
      fwide = 0; fopacity = opacity }

let ishadow ?(radii = no4) ?(cont = false) ?(inset = false)
    ?(cast = rect 0. 0. 0. 0.) ?(cradii = no4) ?(ccont = false)
    ?(opacity = 0.) ~blur rc c =
  Shadow
    { srect = rc; sradii = radii; scontinuous = cont; scolor = c;
      sblur = blur; sinset = inset; scast = cast; scast_radii = cradii;
      scast_continuous = ccont; swide = 0; sopacity = opacity }

let iclip ?(radii = no4) ?(cont = false) rc =
  Push_clip { crect = rc; cradii = radii; ccontinuous = cont }

let ihole ?(radii = no4) ?(cont = false) ?(opacity = 0.) rc =
  Hole { hrect = rc; hradii = radii; hcontinuous = cont; hopacity = opacity }

let iimage ?(radii = no4) ?(cont = false) ?(gray = false) ?(opacity = 0.) rc img src =
  Image
    { irect2 = rc; iradii = radii; icontinuous = cont; iimage = img;
      isrc = src; igrayscale = gray; iopacity = opacity }

let ieffect ?(radii = no4) ?(cont = false) ?(opacity = 0.) rc index =
  Effect
    { edrect = rc; edradii = radii; edcontinuous = cont; edindex = index;
      edopacity = opacity }

let iglyphs ?(paint = Solid) ?(c = black) ?(c2 = black) ?(g = no4)
    ?(opacity = 0.) a b =
  Glyphs
    { gstart = a; gend = b; gpaint = paint; gcolor = c; gcolor2 = c2;
      ggradient = g; gwide2 = 0; gopacity = opacity }

let glyph ?(colored = false) ?(subpixel = false) ?(thin = false) ~x ~y ~w ~h
    ~u ~v ~uw ~vh c =
  { gx = x; gy = y; gw = w; gh = h; gu = u; gv = v; guw = uw; gvh = vh;
    gcolor = c; gwide = 0; gcolored = colored; gsubpixel = subpixel;
    gthin = thin }

(* The test effects' CPU twins: grad paints x and y; dim halves its
   backdrop; lens samples its backdrop further in near the shape's edge
   and mixes a tint; tint paints its tint. *)
let test_fx =
  { ename = "testfx"; ebackdrop = false; eglsl = "";
    epixels = (fun () ->
      { begin_effect = (fun _ _ _ -> ());
        color_at = (fun x y _ -> (x /. 100., y /. 80., 0.6)) }) }

let dim_fx =
  { ename = "dim"; ebackdrop = true; eglsl = "";
    epixels = (fun () ->
      { begin_effect = (fun _ _ _ -> ());
        color_at = (fun x y b ->
          match b with
          | Some b ->
            let r, g, bl = backdrop_sample b x y in
            (r *. 0.5, g *. 0.5, bl *. 0.5)
          | None -> (0., 0., 0.)) }) }

let lens_fx =
  { ename = "lens"; ebackdrop = true; eglsl = "";
    epixels = (fun () ->
      let op = ref (Array.make 5 (0., 0., 0., 0.)) in
      let rc = ref (rect 0. 0. 0. 0.) and radii = ref no4 in
      { begin_effect = (fun e r ra -> op := e.eparams; rc := r; radii := ra);
        color_at = (fun x y b ->
          match b with
          | Some b ->
            let k, _, _, _ = !op.(0) in
            let d =
              Float.max (8. +. sd_round_rect !rc !radii x y) 0. *. k
            in
            let c0, c1, c2 = backdrop_sample b (x +. d) y in
            let t0, t1, t2, t3 = !op.(1) in
            (c0 +. (t0 -. c0) *. t3, c1 +. (t1 -. c1) *. t3,
             c2 +. (t2 -. c2) *. t3)
          | None -> (0., 0., 0.)) }) }

let tint_fx =
  { ename = "tint"; ebackdrop = false; eglsl = "";
    epixels = (fun () ->
      let op = ref (Array.make 5 (0., 0., 0., 0.)) in
      { begin_effect = (fun e _ _ -> op := e.eparams);
        color_at = (fun _ _ _ ->
          let t0, t1, t2, t3 = !op.(1) in
          (t0 *. t3, t1 *. t3, t2 *. t3)) }) }

(* ---------- the golden scenes ---------- *)

let golden_scenes =
  [ ( "fill_round", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~radii:(radii 12.) ~bw:(uniform 2.) ~bc:black
            (rect 12.25 10.5 60. 40.) (color 37 99 235 255) ] );
    ( "fill_square", fun () ->
      scene ~w:96 ~h:64
        [ ifill (rect 10. 10. 60. 40.) (color 220 38 38 128) ] );
    ( "fill_cont", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~radii:(radii 14.) ~cont:true
            (rect 12. 10. 60. 40.) (color 16 185 129 255) ] );
    ( "fill_cont_pill", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~radii:(radii 14.) ~cont:true
            (rect 8. 18. 80. 28.) (color 139 92 246 255) ] );
    ( "fill_linear", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~paint:Linear ~c2:(color 250 204 21 255) ~g:(10., 10., 86., 54.)
            (rect 10. 10. 76. 44.) (color 37 99 235 255) ] );
    ( "fill_oklab", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~paint:Oklab ~c2:(color 250 204 21 255) ~g:(10., 10., 86., 54.)
            (rect 10. 10. 76. 44.) (color 37 99 235 255) ] );
    ( "fill_linear_t", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~paint:Linear ~c2:(color 250 204 21 40) ~g:(48., 10., 48., 54.)
            (rect 10. 10. 76. 44.) (color 37 99 235 160) ] );
    ( "fill_stripes", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~paint:Stripes ~c2:(color 230 230 230 255) ~g:(1., 0., 6., 12.)
            (rect 10. 10. 76. 44.) (color 37 99 235 255) ] );
    ( "fill_dashed", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~radii:(radii 6.) ~bw:(uniform 2.5) ~bc:(color 37 99 235 255)
            ~dashed:true (rect 10. 10. 76. 44.) white ] );
    ( "shadow_cast", fun () ->
      scene ~w:128 ~h:96
        [ ishadow ~radii:(radii 10.) ~blur:12.
            (rect 30. 34. 60. 40.) (color 0 0 0 80) ] );
    ( "shadow_caster", fun () ->
      scene ~w:128 ~h:96
        [ ishadow ~radii:(radii 10.) ~blur:12.
            ~cast:(rect 30. 24. 60. 40.) ~cradii:(radii 10.)
            (rect 30. 34. 60. 40.) (color 0 0 0 120) ] );
    ( "shadow_inset", fun () ->
      scene ~w:96 ~h:64
        [ ifill ~radii:(radii 8.) (rect 12. 10. 72. 44.) (color 240 240 240 255);
          ishadow ~radii:(radii 6.) ~blur:8. ~inset:true
            ~cast:(rect 12. 10. 72. 44.) ~cradii:(radii 8.)
            (rect 16. 14. 64. 36.) (color 0 0 0 160) ] );
    ( "clip_nested", fun () ->
      scene ~w:96 ~h:64
        [ iclip ~radii:(radii 18.) (rect 10. 10. 76. 44.);
          ifill (rect 0. 0. 96. 64.) (color 220 38 38 255);
          iclip (rect 30. 20. 40. 24.);
          ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
          Pop_clip;
          ifill (rect 0. 0. 96. 64.) (color 16 185 129 80);
          Pop_clip ] );
    ( "clip_cont", fun () ->
      scene ~w:96 ~h:64
        [ iclip ~radii:(radii 16.) ~cont:true (rect 10. 10. 76. 44.);
          ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
          Pop_clip ] );
    ( "hole", fun () ->
      scene ~w:96 ~h:64
        [ ifill (rect 0. 0. 96. 64.) (color 220 38 38 255);
          ihole ~radii:(radii 8.) ~opacity:1. (rect 20. 12. 56. 40.);
          ihole ~opacity:0.5 (rect 30. 22. 20. 20.) ] );
    ( "image_ops", fun () ->
      let pix =
        Bytes.of_string
          (String.concat ""
             (List.map
                (fun c -> String.make 1 (Char.chr c))
                [ 255; 0; 0; 255; 0; 255; 0; 255; 255; 0; 0; 255; 0; 255; 0; 255;
                  0; 255; 0; 255; 255; 0; 0; 255; 0; 255; 0; 255; 255; 0; 0; 255;
                  255; 0; 0; 255; 0; 255; 0; 255; 255; 0; 0; 255; 0; 255; 0; 255;
                  0; 255; 0; 255; 255; 0; 0; 255; 0; 255; 0; 255; 255; 0; 0; 255 ]))
      in
      let checker = new_image ~w:4 ~h:4 pix in
      scene ~w:96 ~h:64
        [ iimage ~radii:(radii 6.) (rect 6. 8. 32. 32.) checker (rect 0. 0. 4. 4.);
          iimage ~opacity:0.5 ~gray:true (rect 48. 12. 32. 16.) checker
            (rect 1. 1. 2. 2.) ] );
    ( "glyphs", fun () ->
      let mask = Atlas.create ~bpp:1 ~w:64 ~h:16 in
      for y = 0 to 11 do
        for x = 0 to 11 do
          let edge = ref 0 in
          if x < 2 || x > 9 || y < 2 || y > 9 then edge := 255;
          if x = 1 || y = 1 || x = 10 || y = 10 then edge := 128;
          Bytes.set mask.Atlas.pix (y * mask.Atlas.w + x) (Char.chr !edge)
        done
      done;
      for y = 4 to 15 do
        for x = 20 to 31 do
          let m = if (x - 20 + y - 4) mod 4 < 2 then 255 else 0 in
          Bytes.set mask.Atlas.pix (y * mask.Atlas.w + x) (Char.chr m)
        done
      done;
      scene ~w:96 ~h:64 ~mask
        ~glyphs:
          [ glyph ~x:8.2 ~y:6.6 ~w:12. ~h:12. ~u:0 ~v:0 ~uw:12 ~vh:12 black;
            glyph ~x:24.7 ~y:18.4 ~w:12. ~h:12. ~u:0 ~v:0 ~uw:12 ~vh:12
              (color 200 30 30 180);
            glyph ~x:44. ~y:30. ~w:12. ~h:12. ~u:20 ~v:4 ~uw:12 ~vh:12
              (color 20 120 220 255) ]
        [ iglyphs 0 3 ] );
    ( "glyphs_color", fun () ->
      let ca = Atlas.create ~bpp:4 ~w:32 ~h:16 in
      for y = 0 to 11 do
        for x = 0 to 7 do
          let o = (y * ca.Atlas.w + x) * 4 in
          let v = 255 - (x + y) * 8 in
          Bytes.set ca.Atlas.pix o (Char.chr v);
          Bytes.set ca.Atlas.pix (o + 1) (Char.chr v);
          Bytes.set ca.Atlas.pix (o + 2) (Char.chr v);
          Bytes.set ca.Atlas.pix (o + 3) '\255'
        done
      done;
      for y = 0 to 9 do
        for x = 16 to 23 do
          let o = (y * ca.Atlas.w + x) * 4 in
          Bytes.set ca.Atlas.pix o (Char.chr 200);
          Bytes.set ca.Atlas.pix (o + 1) (Char.chr 60);
          Bytes.set ca.Atlas.pix (o + 2) (Char.chr 40);
          Bytes.set ca.Atlas.pix (o + 3) '\255'
        done
      done;
      scene ~w:96 ~h:64 ~color_atlas:ca
        ~glyphs:
          [ glyph ~subpixel:true ~x:10. ~y:8. ~w:8. ~h:12. ~u:0 ~v:0 ~uw:8 ~vh:12
              (color 20 20 20 255);
            glyph ~colored:true ~x:30. ~y:8. ~w:8. ~h:10. ~u:16 ~v:0 ~uw:8 ~vh:10
              white ]
        [ iglyphs 0 2 ] );
    ( "glyphs_text", fun () ->
      let mask = Atlas.create ~bpp:1 ~w:64 ~h:16 in
      for y = 0 to 11 do
        for x = 0 to 11 do
          let edge = ref 0 in
          if x < 2 || x > 9 || y < 2 || y > 9 then edge := 255;
          if x = 1 || y = 1 || x = 10 || y = 10 then edge := 128;
          Bytes.set mask.Atlas.pix (y * mask.Atlas.w + x) (Char.chr !edge)
        done
      done;
      for y = 4 to 15 do
        for x = 20 to 31 do
          let m = if (x - 20 + y - 4) mod 4 < 2 then 255 else 0 in
          Bytes.set mask.Atlas.pix (y * mask.Atlas.w + x) (Char.chr m)
        done
      done;
      scene ~w:96 ~h:64 ~mask
        ~text:
          { gamma_ratios = gamma_ratios 1.8; contrast = 0.4;
            subpixel_contrast = 0.2 }
        ~glyphs:
          [ glyph ~x:8. ~y:8. ~w:12. ~h:12. ~u:0 ~v:0 ~uw:12 ~vh:12 black;
            glyph ~thin:true ~x:30. ~y:8. ~w:12. ~h:12. ~u:20 ~v:4 ~uw:12 ~vh:12
              black ]
        [ iglyphs 0 2 ] );
    ( "effect", fun () ->
      scene ~w:96 ~h:64
        ~effects:[ { ee = test_fx; eblur = 0.;
                     eparams = [| (0.5, 0.5, 20., 0.); (0., 0., 0., 0.);
                                  (0., 0., 0., 0.); (0., 0., 0., 0.);
                                  (0., 0., 0., 0.) |] } ]
        [ ifill (rect 0. 0. 96. 64.) (color 250 230 200 255);
          ieffect ~radii:(radii 8.) (rect 18. 10. 60. 44.) 0 ] );
    ( "effect_backdrop", fun () ->
      scene ~w:96 ~h:64
        ~effects:[ { ee = dim_fx; eblur = 8.;
                     eparams = [| (0., 0., 0., 0.); (0., 0., 0., 0.);
                                  (0., 0., 0., 0.); (0., 0., 0., 0.);
                                  (0., 0., 0., 0.) |] } ]
        [ ifill (rect 0. 0. 96. 64.) (color 37 99 235 255);
          ifill (rect 20. 10. 40. 30.) (color 250 204 21 255);
          ieffect ~radii:(radii 6.) (rect 12. 8. 60. 40.) 0 ] );
    ( "edges", fun () ->
      scene ~w:64 ~h:48 ~clear:(color 12 20 30 255)
        [ ifill (rect 0. 0. 0. 20.) (color 255 0 0 255);
          ifill ~radii:(radii 40.) (rect 5. 5. 20. 12.) (color 16 185 129 255);
          ifill (rect 10.5 30.5 30. 10.) (color 255 128 0 200);
          iclip (rect 200. 200. 10. 10.);
          ifill (rect 0. 0. 64. 48.) (color 255 0 0 255);
          Pop_clip;
          ifill (rect (-5.) (-5.) 16. 16.) (color 255 0 0 120);
          ifill ~radii:(4., 0., 4., 0.) ~cont:true (rect 50. 34. 8. 8.)
            (color 0 0 200 255) ] );
    ( "two_effects", fun () ->
      scene ~w:96 ~h:64
        ~effects:[ { ee = test_fx; eblur = 0.;
                     eparams = [| (0., 0., 0., 0.); (0., 0., 0., 0.);
                                  (0., 0., 0., 0.); (0., 0., 0., 0.);
                                  (0., 0., 0., 0.) |] } ]
        [ ifill (rect 0. 0. 96. 64.) (color 240 240 255 255);
          ieffect (rect 8. 8. 24. 24.) 0;
          ifill (rect 40. 20. 30. 20.) (color 200 100 40 255);
          ieffect ~radii:(radii 6.) (rect 56. 30. 24. 24.) 0 ] ) ]


module Maker = struct
  type t = {
    rnd : Random.State.t;
    atlas : Atlas.t;
    mutable img : image;
    mutable masks : (int * int * int * int) list;
    mutable with_effects : bool;
  }

  let rnd_int m n = Random.State.int m.rnd n
  let rnd_float m f = Random.State.float m.rnd f

  let make seed =
    let m = {
      rnd = Random.State.make [| seed |];
      atlas = Atlas.create ~bpp:1 ~w:128 ~h:128;
      img = new_image ~w:8 ~h:8 (Bytes.make 0 '\000');
      masks = []; with_effects = false;
    } in
    let pixels n = Bytes.init n (fun _ -> Char.chr (rnd_int m 256)) in
    let rec fill = function
      | 0 -> ()
      | k ->
        let w = 4 + rnd_int m 12 and h = 4 + rnd_int m 12 in
        (match Atlas.alloc_last m.atlas w h with
         | Some (x, y) ->
           Atlas.put m.atlas ~x ~y ~w ~h ~src:(pixels (w * h)) ~stride:w;
           m.masks <- (x, y, w, h) :: m.masks;
           fill (k - 1)
         | None -> ())
    in
    fill 6;
    m.img <- new_image ~w:8 ~h:8 (pixels (8 * 8 * 4));
    m

  let rcolor m = color (rnd_int m 256) (rnd_int m 256) (rnd_int m 256) (64 + rnd_int m 192)

  let mrect m =
    rect (rnd_float m 150. -. 10.) (rnd_float m 110. -. 10.)
      (2. +. rnd_float m 60.) (2. +. rnd_float m 50.)

  let op m s =
    if m.with_effects && rnd_int m 4 = 0 then begin
      let r = rnd_float m 20. in
      let fx =
        { ee = (if rnd_int m 3 = 0 then tint_fx else lens_fx);
          eblur = float (rnd_int m 4) *. 3.;
          eparams = [| (rnd_float m 4., 0., 0., 0.); (0., 0., 0., 0.);
                       (0., 0., 0., 0.); (0., 0., 0., 0.); (0., 0., 0., 0.) |] }
      in
      let c = rcolor m in
      fx.eparams.(1) <-
        (float c.r /. 255., float c.g /. 255., float c.b /. 255., float c.a /. 255.);
      s.effects <- s.effects @ [ fx ];
      ieffect ~radii:(radii r) (mrect m) (List.length s.effects - 1)
    end
    else
      match rnd_int m 4 with
      | 0 ->
        let r = rnd_float m 12. in
        ifill ~radii:(radii r) ~bw:(uniform (float (rnd_int m 3)))
          ~bc:(rcolor m) (mrect m) (rcolor m)
      | 1 -> ishadow ~radii:(radii 4.) ~blur:(rnd_float m 16.) (mrect m) (rcolor m)
      | 2 ->
        let start = List.length s.glyphs in
        let gs =
          List.init (1 + rnd_int m 3) (fun _ ->
            let x, y, w, h = List.nth m.masks (rnd_int m (List.length m.masks)) in
            glyph ~x:(float (rnd_int m 150)) ~y:(float (rnd_int m 110))
              ~w:(float w) ~h:(float h) ~u:x ~v:y ~uw:w ~vh:h (rcolor m))
        in
        s.glyphs <- s.glyphs @ gs;
        iglyphs start (List.length s.glyphs)
      | _ -> iimage (mrect m) m.img (rect 0. 0. 8. 8.)

  let scene m =
    let s =
      scene ~w:160 ~h:120 ~clear:(color 250 250 250 255) ~mask:m.atlas []
    in
    let ops =
      List.init 8 (fun _ -> op m s)
      @ [ iclip ~radii:(radii 6.) (mrect m) ]
      @ List.init 5 (fun _ -> op m s)
      @ [ Pop_clip ]
      @ List.init 4 (fun _ -> op m s)
    in
    s.ops <- ops;
    s

  (* Change s a little, as a frame of an app would. *)
  let change m s =
    let drawing =
      List.filter_map
        (fun (i, o) -> match o with Push_clip _ | Pop_clip -> None | _ -> Some i)
        (List.mapi (fun i o -> (i, o)) s.ops)
    in
    let idx = List.nth drawing (rnd_int m (List.length drawing)) in
    let ops = Array.of_list s.ops in
    (match rnd_int m 8 with
     | 0 -> (
       match ops.(idx) with
       | Fill f -> ops.(idx) <- Fill { f with fcolor = rcolor m }
       | Shadow sh -> ops.(idx) <- Shadow { sh with scolor = rcolor m }
       | Image i -> ops.(idx) <- Image { i with iopacity = 0.5 }
       | Glyphs g -> ops.(idx) <- Glyphs { g with gcolor = rcolor m }
       | Hole h -> ops.(idx) <- Hole { h with hopacity = 0.5 }
       | Effect e -> ops.(idx) <- Effect { e with edopacity = 0.5 }
       | _ -> ())
     | 1 -> (
       let shift = rnd_float m 20. -. 10. in
       match ops.(idx) with
       | Glyphs g ->
         s.glyphs <-
           List.mapi
             (fun i gl ->
               if i = g.gstart then { gl with gx = gl.gx +. 3. } else gl)
             s.glyphs
       | Fill f -> ops.(idx) <- Fill { f with frect = { f.frect with x = f.frect.x +. shift } }
       | Shadow sh -> ops.(idx) <- Shadow { sh with srect = { sh.srect with x = sh.srect.x +. shift } }
       | Image i -> ops.(idx) <- Image { i with irect2 = { i.irect2 with x = i.irect2.x +. shift } }
       | Hole h -> ops.(idx) <- Hole { h with hrect = { h.hrect with x = h.hrect.x +. shift } }
       | Effect e -> ops.(idx) <- Effect { e with edrect = { e.edrect with x = e.edrect.x +. shift } }
       | _ -> ())
     | 2 ->
       s.ops <-
         List.mapi (fun i o -> (i, o)) s.ops
         |> List.concat_map (fun (i, o) -> if i = idx then [ op m s; o ] else [ o ])
     | 3 ->
       if List.length drawing > 4 then
         s.ops <- List.filteri (fun i _ -> i <> idx) s.ops
     | 4 ->
       s.ops <-
         List.map
           (fun o -> match o with Push_clip _ -> iclip ~radii:(radii 6.) (mrect m) | _ -> o)
           s.ops
     | 5 -> (
       match m.masks with
       | [] -> ()
       | ms ->
         let x, y, w, h = List.nth ms (rnd_int m (List.length ms)) in
         let src = Bytes.init (w * h) (fun _ -> Char.chr (rnd_int m 256)) in
         Atlas.put m.atlas ~x ~y ~w ~h ~src ~stride:w)
     | 6 ->
       for i = 0 to Bytes.length m.img.ipix - 1 do
         Bytes.set m.img.ipix i (Char.chr (rnd_int m 256))
       done;
       image_changed m.img
     | _ -> ());
    s
end

