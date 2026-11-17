(* CPU test pattern for the SDL spike. The framebuffer is an int32 bigarray
   of 0xAARRGGBB pixels; on little-endian hosts the memory byte order is
   B,G,R,A, which is what SDL_PIXELFORMAT_ARGB8888 expects. *)

type t = {
  w : int;
  h : int;
  px : (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t;
}

type label = {
  lw : int;
  lh : int;
  lpitch : int; (* bytes per row *)
  lpix : (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t;
}

let create ~w ~h =
  if w <= 0 || h <= 0 then invalid_arg "Spike_render.create";
  {
    w;
    h;
    px =
      Bigarray.Array1.create Bigarray.int32 Bigarray.c_layout (w * h);
  }

let get t ~x ~y = t.px.{y * t.w + x}

(* Coverage of a signed distance field edge: 1 inside, 0 outside, linear
   ramp across a 1.5 px antialiasing band centered on the edge. *)
let coverage d =
  if d <= -0.75 then 1.
  else if d >= 0.75 then 0.
  else 0.5 -. d *. (2. /. 3.)

let clamp8 v = if v < 0. then 0 else if v > 255. then 255 else int_of_float v

let pack ~r ~g ~b =
  Int32.logor 0xFF000000l
    (Int32.logor
       (Int32.shift_left (Int32.of_int (clamp8 r)) 16)
       (Int32.logor
          (Int32.shift_left (Int32.of_int (clamp8 g)) 8)
          (Int32.of_int (clamp8 b))))

let lerp a b u = a +. (b -. a) *. u

(* The demo scene: a dark vertical background gradient plus two rounded
   rects moving on Lissajous orbits. Each rect is filled with a gradient
   driven by SDF depth and edged with a light rim near the border.
   Deterministic for a given [time]. *)
let render t ~time =
  let fw = float t.w and fh = float t.h in
  let cx1 = fw *. 0.5 +. fw *. 0.30 *. sin (time *. 1.1) in
  let cy1 = fh *. 0.5 +. fh *. 0.28 *. sin (time *. 1.7 +. 1.0) in
  let cx2 = fw *. 0.5 -. fw *. 0.30 *. sin (time *. 0.9 +. 0.4) in
  let cy2 = fh *. 0.5 -. fh *. 0.24 *. sin (time *. 1.3) in
  let rad1 = 28. +. 12. *. sin (time *. 2.1) in
  let rad2 = 20. +. 8. *. cos (time *. 1.4) in
  let r1 =
    { Lui_scene.x = cx1 -. 110.; y = cy1 -. 70.; w = 220.; h = 140. }
  in
  let r2 =
    { Lui_scene.x = cx2 -. 70.; y = cy2 -. 45.; w = 140.; h = 90. }
  in
  for y = 0 to t.h - 1 do
    let row = y * t.w in
    let fy = float y in
    let u = fy /. fh in
    let bg_r = 16. +. 24. *. u in
    let bg_g = 14. +. 18. *. u in
    let bg_b = 38. +. 58. *. u in
    for x = 0 to t.w - 1 do
      let fx = float x in
      let d1 = Lui_scene.sd_round_rect r1 (rad1, rad1, rad1, rad1) fx fy in
      let d2 = Lui_scene.sd_round_rect r2 (rad2, rad2, rad2, rad2) fx fy in
      let d = min d1 d2 in
      let px =
        if d < 0.75 then begin
          let cov = coverage d in
          (* Interior gradient keyed on depth below the edge; the two
             shapes use different palettes. *)
          let depth = min 1. (-.d /. 40.) in
          let ir, ig, ib =
            if d1 <= d2 then
              (lerp 250. 64. depth, lerp 150. 30. depth, lerp 70. 110. depth)
            else
              (lerp 60. 30. depth, lerp 170. 60. depth, lerp 230. 160. depth)
          in
          let rim = if d > -3.5 then 0.8 else 0. in
          let ir = lerp ir 255. rim
          and ig = lerp ig 240. rim
          and ib = lerp ib 210. rim in
          let inv = 1. -. cov in
          pack
            ~r:(bg_r *. inv +. ir *. cov)
            ~g:(bg_g *. inv +. ig *. cov)
            ~b:(bg_b *. inv +. ib *. cov)
        end
        else pack ~r:bg_r ~g:bg_g ~b:bg_b
      in
      t.px.{row + x} <- px
    done
  done

(* Source-over blend of a straight-alpha B,G,R,A byte image (the memory
   layout of an ARGB8888 SDL surface on little-endian) into the
   framebuffer. [lpitch] is in bytes. *)
let blit_label t ~x0 ~y0 (l : label) =
  let ymax = min l.lh (Bigarray.Array1.dim l.lpix / max 1 l.lpitch) in
  for sy = 0 to ymax - 1 do
    let dy = y0 + sy in
    if dy >= 0 && dy < t.h then begin
      let row = dy * t.w in
      let srow = sy * l.lpitch in
      for sx = 0 to l.lw - 1 do
        let dx = x0 + sx in
        if dx >= 0 && dx < t.w then begin
          let si = srow + sx * 4 in
          let sa = l.lpix.{si + 3} in
          if sa > 0 then begin
            let a = float sa /. 255. and inv = 1. -. float sa /. 255. in
            let dv = t.px.{row + dx} in
            let dr = float (Int32.(to_int (logand (shift_right_logical dv 16) 0xFFl))) in
            let dg = float (Int32.(to_int (logand (shift_right_logical dv 8) 0xFFl))) in
            let db = float (Int32.(to_int (logand dv 0xFFl))) in
            let sb = float l.lpix.{si}
            and sg = float l.lpix.{si + 1}
            and sr = float l.lpix.{si + 2} in
            t.px.{row + dx} <-
              pack
                ~r:(sr *. a +. dr *. inv)
                ~g:(sg *. a +. dg *. inv)
                ~b:(sb *. a +. db *. inv)
          end
        end
      done
    end
  done

(* FNV-1a 64 over the whole framebuffer; identical renders give identical
   checksums, which is what the headless mode reports. *)
let fnv1a t =
  let h = ref 0xcbf29ce484222325L in
  let n = Bigarray.Array1.dim t.px in
  for i = 0 to n - 1 do
    h :=
      Int64.mul
        (Int64.logxor !h (Int64.logand 0xFFFFFFFFL (Int64.of_int32 t.px.{i})))
        0x100000001b3L
  done;
  !h
