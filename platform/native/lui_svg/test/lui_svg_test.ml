(* lui_svg tests: analytic coverage, AA edge behavior, transforms,
   gradients, fixture checksums, and a crash-fuzz pass over
   truncated/garbage inputs. *)

let parse_exn src =
  match Lui_svg.parse src with
  | Ok d -> d
  | Error m -> failwith ("parse: " ^ m)

let pix_g pix ~w x y = Char.code (Bytes.get pix (y * 4 * w + 4 * x + 1))
let pix_r pix ~w x y = Char.code (Bytes.get pix (y * 4 * w + 4 * x + 2))
let pix_a pix ~w x y = Char.code (Bytes.get pix (y * 4 * w + 4 * x + 3))

let total_alpha pix ~w ~h =
  let s = ref 0 in
  for i = 0 to w * h - 1 do
    s := !s + Char.code (Bytes.get pix (4 * i + 3))
  done;
  !s

let fnv1a (b : Bytes.t) =
  let h = ref 0x811c9dc5 in
  Bytes.iter (fun c ->
      h := (!h lxor Char.code c) * 0x01000193 land 0x7fffffff) b;
  !h

let svg ?(vb = "0 0 8 8") inner =
  "<svg viewBox=\"" ^ vb ^ "\">" ^ inner ^ "</svg>"

(* ---------- analytic coverage ---------- *)

(* Total coverage of an opaque fill equals its geometric area — the
   strongest correctness check a rasterizer can get. *)
let test_area () =
  let check ~w ~h inner expect =
    let d = parse_exn (svg inner) in
    let pix = Lui_svg.rasterize d ~w ~h in
    let got = float (total_alpha pix ~w ~h) /. 255. in
    Alcotest.(check (float 0.15)) "area" expect got
  in
  (* 4x4 rect in an 8x8 viewport: area 16 px *)
  check ~w:8 ~h:8 {|<rect x="2" y="2" width="4" height="4" fill="black"/>|} 16.;
  (* right triangle: area 8 *)
  check ~w:8 ~h:8 {|<path d="M1 1 L7 1 L1 7 Z" fill="black"/>|} 18.;
  (* circle r=3 at 4,4: polygon flattened at the curve tolerance ->
     area within ~10% of pi*r^2 *)
  let d = parse_exn (svg {|<circle cx="4" cy="4" r="3" fill="black"/>|}) in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  let got = float (total_alpha pix ~w:8 ~h:8) /. 255. in
  Alcotest.(check bool) "circle area" true
    (got > Float.pi *. 9. *. 0.85 && got < Float.pi *. 9. *. 1.02);
  (* half-plane fill: 32 px *)
  check ~w:8 ~h:8 {|<rect x="0" y="0" width="8" height="4" fill="black"/>|} 32.

(* A rectangle edge on a pixel boundary: full coverage next to it, no
   spill to the outside column. *)
let test_edge_pixels () =
  let d = parse_exn (svg {|<rect x="2" y="0" width="4" height="8" fill="black"/>|}) in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "inside edge" 255 (pix_a pix ~w:8 2 4);
  Alcotest.(check int) "inside far" 255 (pix_a pix ~w:8 5 4);
  Alcotest.(check int) "outside" 0 (pix_a pix ~w:8 1 4);
  Alcotest.(check int) "outside right" 0 (pix_a pix ~w:8 6 4)

(* A vertical edge through pixel centers: coverage splits evenly and
   sums to the geometric covered fraction. *)
let test_aa_edge () =
  let d = parse_exn (svg {|<rect x="2.5" y="0" width="4" height="8" fill="black"/>|}) in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  let left = pix_a pix ~w:8 2 4 and right = pix_a pix ~w:8 6 4 in
  Alcotest.(check int) "no far spill" 0 (pix_a pix ~w:8 7 4);
  Alcotest.(check int) "no left spill" 0 (pix_a pix ~w:8 1 4);
  Alcotest.(check bool) "edge half-ish" true (left > 60 && left < 200);
  Alcotest.(check bool) "edge half-ish r" true (right > 60 && right < 200);
  (* sum over the row must equal 4px width *)
  let sum = ref 0 in
  for x = 0 to 7 do sum := !sum + pix_a pix ~w:8 x 4 done;
  Alcotest.(check bool) "row sum = 4px" true (Int.abs (!sum - 4 * 255) <= 8)

(* ---------- transforms ---------- *)

let test_transforms () =
  (* translate(2,1) on a 2x2 rect covers x 2..4 y 1..3 *)
  let d = parse_exn
      (svg {|<g transform="translate(2,1)"><rect width="2" height="2" fill="black"/></g>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "moved" 255 (pix_a pix ~w:8 2 1);
  Alcotest.(check int) "moved far" 255 (pix_a pix ~w:8 3 2);
  Alcotest.(check int) "before" 0 (pix_a pix ~w:8 1 1);
  (* nested: scale(2) then translate — user-space unit becomes 2px *)
  let d = parse_exn
      (svg {|<g transform="scale(2)"><rect x="1" y="1" width="1" height="1" fill="black"/></g>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "scaled" 255 (pix_a pix ~w:8 2 2);
  Alcotest.(check int) "scaled far" 255 (pix_a pix ~w:8 3 3);
  (* rotate(90) about (4,4) maps a rightward bar to a downward bar:
     x in [4,6] y in [3,4] -> x in [4,5] y in [4,6] *)
  let d = parse_exn
      (svg {|<g transform="rotate(90 4 4)"><rect x="4" y="3" width="2" height="1" fill="black"/></g>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "rotated" 255 (pix_a pix ~w:8 4 5);
  Alcotest.(check int) "rotated old spot" 0 (pix_a pix ~w:8 5 3);
  (* matrix + nested transform composition: same as manual *)
  let d = parse_exn
      (svg {|<g transform="translate(1,0) scale(2)"><rect x="1" y="1" width="1" height="1" fill="black"/></g>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "composed" 255 (pix_a pix ~w:8 3 2)

(* ---------- gradients ---------- *)

let test_gradient () =
  let src =
    {|<svg viewBox="0 0 8 2"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="0">|}
    ^ {|<stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/>|}
    ^ {|</linearGradient></defs><rect width="8" height="2" fill="url(#g)"/></svg>|}
  in
  let d = parse_exn src in
  let pix = Lui_svg.rasterize d ~w:8 ~h:2 in
  let v x = pix_r pix ~w:8 x 0 in
  Alcotest.(check bool) "monotone" true
    (v 0 < v 2 && v 2 < v 4 && v 4 < v 6);
  Alcotest.(check bool) "starts dark" true (v 0 < 48);
  Alcotest.(check bool) "ends light" true (v 7 > 208);
  (* pad spread clamps beyond the gradient vector *)
  let src =
    {|<svg viewBox="0 0 8 2"><defs><linearGradient id="g" x1="0.25" y1="0" x2="0.75" y2="0">|}
    ^ {|<stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/>|}
    ^ {|</linearGradient></defs><rect width="8" height="2" fill="url(#g)"/></svg>|}
  in
  let d = parse_exn src in
  let pix = Lui_svg.rasterize d ~w:8 ~h:2 in
  Alcotest.(check bool) "pad left" true (pix_r pix ~w:8 0 0 < 16);
  Alcotest.(check bool) "pad right" true (pix_r pix ~w:8 7 0 > 240);
  (* userSpaceOnUse: t in user units across the 8-wide box *)
  let src =
    {|<svg viewBox="0 0 8 2"><defs><linearGradient id="g" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="8" y2="0">|}
    ^ {|<stop offset="0" stop-color="#000000"/><stop offset="1" stop-color="#ffffff"/>|}
    ^ {|</linearGradient></defs><rect x="4" width="4" height="2" fill="url(#g)"/></svg>|}
  in
  let d = parse_exn src in
  let pix = Lui_svg.rasterize d ~w:8 ~h:2 in
  let v x = pix_r pix ~w:8 x 0 in
  Alcotest.(check bool) "usu mid" true (v 4 > 80 && v 4 < 176)

(* ---------- structure ---------- *)

let test_structure () =
  (* group opacity: black over white at 0.5 -> ~128 *)
  let d = parse_exn
      (svg {|<rect width="8" height="8" fill="white"/><g opacity="0.5"><rect width="8" height="8" fill="black"/></g>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check bool) "group op" true
    (let a = pix_r pix ~w:8 4 4 in a > 120 && a < 136);
  (* clip-path: circle clip keeps center, kills corner *)
  let d = parse_exn
      (svg {|<defs><clipPath id="c"><circle cx="4" cy="4" r="3"/></clipPath></defs><rect width="8" height="8" fill="black" clip-path="url(#c)"/>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "clip center" 255 (pix_a pix ~w:8 4 4);
  Alcotest.(check int) "clip corner" 0 (pix_a pix ~w:8 0 0);
  (* use href pulls defs content at x,y *)
  let d = parse_exn
      (svg {|<defs><rect id="r" width="2" height="2" fill="black"/></defs><use href="#r" x="4" y="4"/>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "use" 255 (pix_a pix ~w:8 5 5);
  Alcotest.(check int) "use before" 0 (pix_a pix ~w:8 3 3);
  (* display:none skips *)
  let d = parse_exn
      (svg {|<rect width="8" height="8" fill="black" display="none"/>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "display none" 0 (total_alpha pix ~w:8 ~h:8);
  (* evenodd hole *)
  let d = parse_exn
      (svg {|<path d="M0 0H8V8H0Z M2 2H6V6H2Z" fill="black" fill-rule="evenodd"/>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "eo hole" 0 (pix_a pix ~w:8 4 4);
  Alcotest.(check int) "eo ring" 255 (pix_a pix ~w:8 1 4);
  (* same path nonzero: hole fills (same winding) *)
  let d = parse_exn
      (svg {|<path d="M0 0H8V8H0Z M2 2H6V6H2Z" fill="black"/>|})
  in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  Alcotest.(check int) "nz fills" 255 (pix_a pix ~w:8 4 4)

(* ---------- api ---------- *)

let test_api () =
  (match Lui_svg.parse "<svg viewBox=\"0 0 1 1\">" with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "unclosed svg should error");
  (match Lui_svg.parse "<html/>" with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "non-svg root should error");
  (match Lui_svg.parse (svg {|<path d="M0 0 L x"/>|}) with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "bad path data should error");
  let d = parse_exn (svg {||} ~vb:"0 0 4 2") in
  (match Lui_svg.view_box d with
   | Some (0., 0., 4., 2.) -> ()
   | _ -> Alcotest.fail "viewBox");
    let d2 = parse_exn {|<svg width="24" height="12"/>|} in
  (match Lui_svg.intrinsic_size d2 with
   | Some (24., 12.) -> ()
   | _ -> Alcotest.fail "intrinsic_size");
  (* to_scene_image swaps BGRA -> RGBA *)
  let d = parse_exn (svg {|<rect width="8" height="8" fill="#010203"/>|}) in
  let pix = Lui_svg.rasterize d ~w:8 ~h:8 in
  let img = Lui_svg.to_scene_image ~w:8 ~h:8 pix in
  let ip = img.Lui_scene.ipix in
  Alcotest.(check int) "rgba r" 1 (Char.code (Bytes.get ip 0));
  Alcotest.(check int) "rgba g" 2 (Char.code (Bytes.get ip 1));
  Alcotest.(check int) "rgba b" 3 (Char.code (Bytes.get ip 2));
  Alcotest.(check int) "rgba a" 255 (Char.code (Bytes.get ip 3));
  (* render one-shot *)
  (match Lui_svg.render (svg {|<rect width="8" height="8"/>|}) ~w:8 ~h:8 with
   | Ok img -> Alcotest.(check int) "render a" 255
                 (Char.code (Bytes.get img.Lui_scene.ipix 3))
   | Error m -> Alcotest.fail m);
  (* empty + degenerate output stays transparent *)
  let d = parse_exn (svg {||}) in
  let pix = Lui_svg.rasterize d ~w:4 ~h:4 in
  Alcotest.(check int) "empty" 0 (total_alpha pix ~w:4 ~h:4);
  Alcotest.(check int) "zero size" 0 (Bytes.length (Lui_svg.rasterize d ~w:0 ~h:4))

(* ---------- fixtures ---------- *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let b = really_input_string ic n in
  close_in ic; b

(* Stable checksums of the BGRA buffers — regression goldens. *)
let fixture_hashes = [
  ("basic.svg", 788033139);
  ("curves.svg", 544143534);
  ("arcs.svg", 1566578933);
  ("gradients.svg", 850492802);
  ("transforms.svg", 768834319);
  ("icon.svg", 813697398);
  ("text_ignore.svg", 813379957);
  ("styles.svg", 2052817861);
  ("group_opacity.svg", 1494345133);
  ("use_symbol.svg", 255281733);
  ("dashes_clip.svg", 1148644281);
]

let fixture_dir =
  let cands = [ "testdata"; Filename.concat ".." "testdata";
                "platform/native/lui_svg/testdata" ] in
  match List.find_opt Sys.file_exists cands with
  | Some d -> d
  | None -> failwith "testdata dir not found"

let test_fixtures () =
  List.iter (fun (name, expect) ->
      let src = read_file (Filename.concat fixture_dir name) in
      match Lui_svg.parse src with
      | Error m -> Alcotest.fail (name ^ ": " ^ m)
      | Ok d ->
        let pix = Lui_svg.rasterize d ~w:24 ~h:24 in
        Alcotest.(check bool) (name ^ " paints") true
          (total_alpha pix ~w:24 ~h:24 > 0);
        Alcotest.(check int) (name ^ " hash") expect (fnv1a pix))
    fixture_hashes

let test_fixture_pixels () =
  (* text-ignore fixture: text renders nothing, shapes do *)
  let src = read_file (Filename.concat fixture_dir "text_ignore.svg") in
  let d = parse_exn src in
  let pix = Lui_svg.rasterize d ~w:24 ~h:24 in
  Alcotest.(check bool) "text ignored" true
    (total_alpha pix ~w:24 ~h:24 > 0);
  (* styles: the styled rect is hot red *)
  let src = read_file (Filename.concat fixture_dir "styles.svg") in
  let d = parse_exn src in
  let pix = Lui_svg.rasterize d ~w:24 ~h:24 in
  Alcotest.(check bool) "class fill" true
    (pix_r pix ~w:24 4 4 > 200 && pix_g pix ~w:24 4 4 < 100)

(* ---------- fuzz ---------- *)

let test_fuzz () =
  let docs =
    [ "<svg viewBox=\"0 0 8 8\"><rect x=\"1\" y=\"1\" width=\"4\" height=\"4\" fill=\"#336699\"/><path d=\"M2 2 L6 6 L2 6 Z\" fill=\"red\" stroke=\"blue\" stroke-width=\"0.5\"/></svg>";
      read_file (Filename.concat fixture_dir "basic.svg");
      read_file (Filename.concat fixture_dir "icon.svg") ]
  in
  List.iter (fun src ->
      let n = String.length src in
      (* every truncation *)
      for i = 0 to n do
        ignore (Lui_svg.parse (String.sub src 0 i))
      done;
      (* garbage mutations at each byte *)
      for i = 0 to n - 1 do
        let bad = Bytes.of_string src in
        Bytes.set bad i '%';
        ignore (Lui_svg.parse (Bytes.to_string bad))
      done;
      ignore (Lui_svg.parse src);
      (* rasterize valid parses at odd sizes *)
      match Lui_svg.parse src with
      | Error _ -> ()
      | Ok d ->
        ignore (Lui_svg.rasterize d ~w:1 ~h:1);
        ignore (Lui_svg.rasterize d ~w:33 ~h:17))
    docs;
  (* outright garbage *)
  ignore (Lui_svg.parse "");
  ignore (Lui_svg.parse "<");
  ignore (Lui_svg.parse "<svg");
  ignore (Lui_svg.parse "\x00\x01\x02<svg>\x03");
  ignore (Lui_svg.parse "<svg><svg><svg><svg></svg>");
  ignore (Lui_svg.parse "<svg d='unterminated");
  ()

let () =
  Alcotest.run "lui_svg" [
    ("coverage", [
        Alcotest.test_case "area" `Quick test_area;
        Alcotest.test_case "edge pixels" `Quick test_edge_pixels;
        Alcotest.test_case "aa edge" `Quick test_aa_edge;
      ]);
    ("transforms", [
        Alcotest.test_case "compose" `Quick test_transforms;
      ]);
    ("paint", [
        Alcotest.test_case "gradients" `Quick test_gradient;
      ]);
    ("structure", [
        Alcotest.test_case "groups/clips/use" `Quick test_structure;
      ]);
    ("api", [
        Alcotest.test_case "api" `Quick test_api;
      ]);
    ("fixtures", [
        Alcotest.test_case "hash" `Quick test_fixtures;
        Alcotest.test_case "pixels" `Quick test_fixture_pixels;
      ]);
    ("fuzz", [
        Alcotest.test_case "no crash" `Quick test_fuzz;
      ]);
  ]
