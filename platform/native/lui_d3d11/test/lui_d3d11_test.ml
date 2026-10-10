(* Pixel parity of the Direct3D 11 backend against the CPU renderer:
   every golden scene and a few seeded Maker scenes are drawn by the
   real D3D11 device (hardware, or the WARP software rasterizer) into
   an offscreen BGRA8 target, read back and compared channel by channel
   with Lui_raster's premultiplied BGRA output. Differences above 2 per
   channel count as failures — the shaders evaluate the same float32
   math as the CPU's float64, so rounding may differ by a unit or two.

   The scenes' test effects carry a GLSL body in eglsl; this backend's
   effect shader language is HLSL, so the tests substitute bodies the
   GPU-side twin computes with its CPU twin — the same semantics the
   golden scenes check between effect shaders and epixels. *)

open Lui_raster_testkit
open Testkit

(* The render target is one size for every scene; the scene draws into
   its own w×h viewport, so only that prefix of each row compares. *)
let rtw, rth = 224, 160

let dev =
  match Lui_d3d11.init_offscreen ~w:rtw ~h:rth with
  | Ok t -> t
  | Error m -> failwith (Printf.sprintf "init_offscreen: %s" m)

let () = Printf.printf "lui_d3d11: warp device = %b\n%!" (Lui_d3d11.warp dev)

let hlsl_of name =
  match name with
  | "testfx" ->
    "float4 effect(float2 p, Effect e) \
     { return float4(p.x / 100.0, p.y / 80.0, 0.6, 1.0); }"
  | "dim" ->
    "float4 effect(float2 p, Effect e) \
     { return float4(sampleBackdrop(e, p) * 0.5, 1.0); }"
  | "tint" ->
    "float4 effect(float2 p, Effect e) \
     { return float4(e.p1.rgb * e.p1.a, 1.0); }"
  | "lens" ->
    "float4 effect(float2 p, Effect e) { \
     float k = e.p0.x; \
     float d = max(8.0 + sdRoundRect(p, e.rect, e.radii), 0.0) * k; \
     float3 c = sampleBackdrop(e, float2(p.x + d, p.y)); \
     return float4(lerp(c, e.p1.rgb, e.p1.a), 1.0); }"
  | _ -> ""

(* Swap each effect's GLSL body for the HLSL body its CPU twin
   computes; epixels stays for the raster side. *)
let substitute (s : Lui_scene.t) =
  s.effects <-
    List.map
      (fun (e : Lui_scene.effect_op) ->
        { e with
          ee = { e.ee with Lui_scene.eglsl = hlsl_of e.ee.Lui_scene.ename } })
      s.effects;
  s

let frame_of (s : Lui_scene.t) =
  Lui_d3d11.render dev s;
  let f = Lui_d3d11.read_frame dev ~w:rtw ~h:rth in
  let w, h = s.width, s.height in
  let out = Bytes.create (4 * w * h) in
  for y = 0 to h - 1 do
    Bytes.blit f (y * 4 * rtw) out (y * 4 * w) (4 * w)
  done;
  out

(* FNV-1a over the frame — a deterministic printout. *)
let checksum b =
  let h = ref 0xcbf29ce484222325L in
  for i = 0 to Bytes.length b - 1 do
    h := Int64.logxor !h (Int64.of_int (Char.code (Bytes.get b i)));
    h := Int64.mul !h 0x100000001b3L
  done;
  !h

let failures = ref 0

let stats gpu cpu =
  let n = Bytes.length gpu in
  let diffs = ref 0 and maxd = ref 0 and first = ref (-1) in
  for i = 0 to n - 1 do
    let a = Char.code (Bytes.get gpu i)
    and b = Char.code (Bytes.get cpu i) in
    let d = abs (a - b) in
    if d > 2 then begin
      incr diffs;
      if !first < 0 then first := i
    end;
    if d > !maxd then maxd := d
  done;
  (!diffs, !maxd, !first)

let opname (o : Lui_scene.op) =
  let r (rc : Lui_scene.rect) =
    Printf.sprintf "(%.1f,%.1f %.1fx%.1f)" rc.x rc.y rc.w rc.h
  in
  match o with
  | Fill f -> "fill " ^ r f.frect
  | Shadow s -> "shadow " ^ r s.srect
  | Hole h -> "hole " ^ r h.hrect
  | Image i -> "image " ^ r i.irect2
  | Effect e -> "effect " ^ r e.edrect
  | Glyphs g -> Printf.sprintf "glyphs %d-%d" g.gstart g.gend
  | Push_clip c -> "push_clip " ^ r c.crect
  | Pop_clip -> "pop_clip"

(* Where the channels differ, by sixteenths of the frame, and the ops
   the scene drew — what a failing scene leaves to look at. *)
let dump_diff name (s : Lui_scene.t) gpu cpu =
  let w, h = s.width, s.height in
  List.iteri
    (fun i o -> Printf.printf "  %2d %s\n%!" i (opname o)) s.ops;
  List.iteri
    (fun i (g : Lui_scene.glyph) ->
      Printf.printf "  glyph %d (%.1f,%.1f %.0fx%.0f) uv(%d,%d %dx%d)\n%!"
        i g.gx g.gy g.gw g.gh g.gu g.gv g.guw g.gvh)
    s.glyphs;
  for gy = 0 to (h + 15) / 16 - 1 do
    for gx = 0 to (w + 15) / 16 - 1 do
      let n = ref 0 in
      for y = gy * 16 to min h (gy * 16 + 16) - 1 do
        for x = gx * 16 to min w (gx * 16 + 16) - 1 do
          for ch = 0 to 3 do
            let i = (y * w + x) * 4 + ch in
            let d =
              abs
                (Char.code (Bytes.get gpu i) -
                 Char.code (Bytes.get cpu i))
            in
            if d > 2 then incr n
          done
        done
      done;
      Printf.printf "%4d" !n
    done;
    Printf.printf "\n%!"
  done;
  let shown = ref 0 in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let i = (y * w + x) * 4 in
      let d = abs (Char.code (Bytes.get gpu i) - Char.code (Bytes.get cpu i)) in
      if d > 2 && !shown < 12 then begin
        incr shown;
        Printf.printf "  (%d,%d) gpu %d,%d,%d,%d cpu %d,%d,%d,%d\n%!" x y
          (Char.code (Bytes.get gpu i))
          (Char.code (Bytes.get gpu (i + 1)))
          (Char.code (Bytes.get gpu (i + 2)))
          (Char.code (Bytes.get gpu (i + 3)))
          (Char.code (Bytes.get cpu i))
          (Char.code (Bytes.get cpu (i + 1)))
          (Char.code (Bytes.get cpu (i + 2)))
          (Char.code (Bytes.get cpu (i + 3)))
      end
    done
  done;
  Printf.printf "%s done\n%!" name

let check_parity name (s : Lui_scene.t) =
  let s = substitute s in
  let gpu = frame_of s in
  let cpu = (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix in
  let diffs, maxd, first = stats gpu cpu in
  Printf.printf "%-20s sum=%016Lx diffs=%d max=%d\n%!" name (checksum gpu)
    diffs maxd;
  if diffs > 0 then begin
    incr failures;
    Printf.printf "FAIL %s: %d channels differ by >2 (first at %d)\n%!"
      name diffs first;
    dump_diff name s gpu cpu
  end

let () =
  List.iter (fun (name, build) -> check_parity name (build ()))
    golden_scenes;

  (* Same scene twice: byte-identical. *)
  let _, build = List.hd golden_scenes in
  let s = substitute (build ()) in
  let a = frame_of s and b = frame_of s in
  if not (Bytes.equal a b) then begin
    incr failures;
    Printf.printf "FAIL deterministic: renders differ\n%!"
  end;

  (* Seeded fuzz with effect ops. *)
  for i = 0 to 7 do
    let m = Maker.make i in
    m.Maker.with_effects <- true;
    let s = Maker.scene m in
    check_parity (Printf.sprintf "fuzz%d" i) s
  done;

  (* The swapchain path on a hidden window, when a desktop exists. *)
  (match Lui_d3d11.create_window ~w:96 ~h:64 with
   | hwnd ->
     (match Lui_d3d11.init_hwnd hwnd ~w:96 ~h:64 with
      | Error m ->
        Lui_d3d11.destroy_window hwnd;
        incr failures;
        Printf.printf "FAIL init_hwnd: %s\n%!" m
      | Ok r ->
        let _, build = List.hd golden_scenes in
        let s = build () in
        Lui_d3d11.render r s;
        let gpu = Lui_d3d11.read_frame r ~w:96 ~h:64 in
        Lui_d3d11.release r;
        Lui_d3d11.destroy_window hwnd;
        let cpu =
          (Lui_raster.render ~scene:s ()).Lui_raster.Image.pix in
        let diffs, maxd, _ = stats gpu cpu in
        Printf.printf "%-20s diffs=%d max=%d\n%!" "hwnd" diffs maxd;
        if diffs > 0 then incr failures));

  Lui_d3d11.release dev;
  if !failures > 0 then
    (Printf.printf "lui_d3d11: %d FAILURE(S)\n%!" !failures; exit 1)
  else
    Printf.printf "lui_d3d11: all scenes within tolerance\n%!"
