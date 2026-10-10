(* Unit tests for the spike's pure renderer: coverage ramp, determinism of
   the animated scene, SDF-driven fill and the text blit path. No SDL is
   initialized here; the interactive window/headless paths are exercised
   manually per the README. *)

let unpack px =
  let v = Int32.to_int px in
  ((v lsr 16) land 0xFF, (v lsr 8) land 0xFF, v land 0xFF)

let test_coverage () =
  Alcotest.(check (float 1e-9)) "deep inside" 1. (Spike_render.coverage (-5.));
  Alcotest.(check (float 1e-9)) "far outside" 0. (Spike_render.coverage 5.);
  Alcotest.(check (float 1e-9)) "on the edge" 0.5 (Spike_render.coverage 0.)

let test_deterministic () =
  let a = Spike_render.create ~w:96 ~h:64 in
  let b = Spike_render.create ~w:96 ~h:64 in
  Spike_render.render a ~time:1.25;
  Spike_render.render b ~time:1.25;
  Alcotest.(check bool)
    "same time, same checksum" true
    (Spike_render.fnv1a a = Spike_render.fnv1a b);
  Spike_render.render a ~time:0.;
  let h0 = Spike_render.fnv1a a in
  Spike_render.render a ~time:1.;
  Alcotest.(check bool)
    "different time, different checksum" true
    (h0 <> Spike_render.fnv1a a)

(* At t=0 the first rounded rect is deep-filled at (100,147) of a 200x200
   buffer: SDF depth saturates the gradient at the (64,30,110) end. *)
let test_sdf_fill () =
  let t = Spike_render.create ~w:200 ~h:200 in
  Spike_render.render t ~time:0.;
  let r, g, b = unpack (Spike_render.get t ~x:100 ~y:147) in
  Alcotest.(check bool)
    "interior gradient pixel" true
    (abs (r - 64) <= 1 && abs (g - 30) <= 1 && abs (b - 110) <= 1)

let test_blit () =
  let t = Spike_render.create ~w:8 ~h:8 in
  Spike_render.render t ~time:0.;
  let lpix =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout (8 * 2)
  in
  (* 2x2 label, pitch 8 bytes: opaque red *)
  for i = 0 to 3 do
    let sx = i mod 2 and sy = i / 2 in
    let si = sy * 8 + sx * 4 in
    lpix.{si} <- 0;
    lpix.{si + 1} <- 0;
    lpix.{si + 2} <- 255;
    lpix.{si + 3} <- 255
  done;
  let before = Spike_render.get t ~x:1 ~y:1 in
  Spike_render.blit_label t ~x0:1 ~y0:1
    { Spike_render.lw = 2; lh = 2; lpitch = 8; lpix };
  Alcotest.(check bool)
    "opaque source-over" true
    (Spike_render.get t ~x:1 ~y:1 = 0xFFFF0000l);
  Alcotest.(check bool)
    "neighbour untouched" true
    (Spike_render.get t ~x:5 ~y:5 = Spike_render.get t ~x:6 ~y:6);
  (* fully transparent source leaves the destination alone *)
  let lpix0 =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout (8 * 2)
  in
  let before0 = Spike_render.get t ~x:0 ~y:0 in
  Spike_render.blit_label t ~x0:0 ~y0:0
    { Spike_render.lw = 2; lh = 2; lpitch = 8; lpix = lpix0 };
  Alcotest.(check bool)
    "transparent no-op" true
    (Spike_render.get t ~x:0 ~y:0 = before0);
  ignore before

let () =
  Alcotest.run "spike_render"
    [
      ( "render",
        [
          Alcotest.test_case "coverage ramp" `Quick test_coverage;
          Alcotest.test_case "deterministic" `Quick test_deterministic;
          Alcotest.test_case "sdf fill" `Quick test_sdf_fill;
          Alcotest.test_case "label blit" `Quick test_blit;
        ] );
    ]
