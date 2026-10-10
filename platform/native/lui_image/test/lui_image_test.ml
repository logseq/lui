open Alcotest

module I = Lui_image

(* ---------- fixture generators (no binary files) ---------- *)

let to_writer f =
  let buf = Buffer.create 256 in
  f (ImageUtil.chunk_writer_of_buffer buf);
  Buffer.to_bytes buf

let png_of (im : Image.image) = to_writer (fun w -> ImageLib.PNG.write w im)
let gif_of (im : Image.image) = to_writer (fun w -> ImageLib.GIF.write w im)

(* Build an imagelib image, one RGBA8 pixel at a time. *)
let mk_rgba w h f =
  let im = Image.create_rgb ~alpha:true ~max_val:255 w h in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let (r, g, b, a) = f x y in
      Image.write_rgba im x y r g b a
    done
  done;
  im

let mk_rgb w h f =
  let im = Image.create_rgb ~max_val:255 w h in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let (r, g, b) = f x y in
      Image.write_rgb im x y r g b
    done
  done;
  im

let mk_greya w h f =
  let im = Image.create_grey ~alpha:true ~max_val:255 w h in
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let (g, a) = f x y in
      Image.write_greya im x y g a
    done
  done;
  im

(* Minimal binary PNM writers. *)
let pnm6 w h f =
  let b = Buffer.create 64 in
  Buffer.add_string b (Printf.sprintf "P6\n%d %d\n255\n" w h);
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      let (r, g, bl) = f x y in
      Buffer.add_char b (Char.chr r);
      Buffer.add_char b (Char.chr g);
      Buffer.add_char b (Char.chr bl)
    done
  done;
  Buffer.to_bytes b

let pnm5 w h f =
  let b = Buffer.create 64 in
  Buffer.add_string b (Printf.sprintf "P5\n%d %d\n255\n" w h);
  for y = 0 to h - 1 do
    for x = 0 to w - 1 do
      Buffer.add_char b (Char.chr (f x y))
    done
  done;
  Buffer.to_bytes b

(* Minimal uncompressed 24-bit BMP writer (bottom-up rows, BGR triplets
   padded to 4 bytes). *)
let bmp24 w h f =
  let stride = (w * 3 + 3) land lnot 3 in
  let body = stride * h and hdr = 54 in
  let b = Buffer.create (hdr + body) in
  let u16 v = Buffer.add_char b (Char.chr (v land 255));
              Buffer.add_char b (Char.chr ((v lsr 8) land 255)) in
  let u32 v = u16 (v land 0xFFFF); u16 ((v lsr 16) land 0xFFFF) in
  Buffer.add_string b "BM";
  u32 (hdr + body); u32 0; u32 hdr;
  u32 40; u32 w; u32 h; u16 1; u16 24; u32 0; u32 body; u32 0; u32 0;
  u32 0; u32 0;
  for y = h - 1 downto 0 do
    for x = 0 to w - 1 do
      let (r, g, bl) = f x y in
      Buffer.add_char b (Char.chr bl);
      Buffer.add_char b (Char.chr g);
      Buffer.add_char b (Char.chr r)
    done;
    for _ = w * 3 to stride - 1 do Buffer.add_char b '\000' done
  done;
  Buffer.to_bytes b

(* ---------- pixel readers ---------- *)

let px (i : I.image) x y =
  let p = I.pixels i and w = I.width i in
  let k = 4 * (y * w + x) in
  [ Bigarray.Array1.get p k;
    Bigarray.Array1.get p (k + 1);
    Bigarray.Array1.get p (k + 2);
    Bigarray.Array1.get p (k + 3) ]

let get_ok = function
  | Ok v -> v
  | Error e -> failf "expected Ok, got Error: %s" e

let is_error = function Ok _ -> false | Error _ -> true

(* ---------- decode ---------- *)

let test_decode_rgba_png () =
  (* pixels: (255,0,0,255) (0,255,0,128) / (0,0,255,0) (10,20,30,60) *)
  let data =
    png_of (mk_rgba 2 2 (fun x y ->
      match x, y with
      | 0, 0 -> (255, 0, 0, 255)
      | 1, 0 -> (0, 255, 0, 128)
      | 0, _ -> (0, 0, 255, 0)
      | _ -> (10, 20, 30, 60)))
  in
  match I.sniff data with
  | Some I.Png ->
    let i = get_ok (I.decode data) in
    check int "w" 2 (I.width i);
    check int "h" 2 (I.height i);
    check int "bytes" 16 (I.size_bytes i);
    check bool "format" true (I.format i = I.Png);
    check (list int) "opaque px" [255; 0; 0; 255] (px i 0 0);
    check (list int) "half px" [0; 128; 0; 128] (px i 1 0);
    check (list int) "zero alpha" [0; 0; 0; 0] (px i 0 1);
    check (list int) "premul px" [2; 5; 7; 60] (px i 1 1)
  | _ -> fail "sniff did not see png"

let test_decode_rgb_png () =
  let data = png_of (mk_rgb 2 1 (fun x _ -> if x = 0 then (7, 8, 9) else (1, 2, 3))) in
  let i = get_ok (I.decode data) in
  check (list int) "opaque" [7; 8; 9; 255] (px i 0 0);
  check (list int) "opaque2" [1; 2; 3; 255] (px i 1 0)

let test_decode_greya_png () =
  let data = png_of (mk_greya 2 1 (fun x _ -> if x = 0 then (200, 255) else (128, 64))) in
  let i = get_ok (I.decode data) in
  check (list int) "grey" [200; 200; 200; 255] (px i 0 0);
  check (list int) "greya" [32; 32; 32; 64] (px i 1 0)

let test_decode_pnm () =
  let c = get_ok (I.decode (pnm6 2 1 (fun x _ -> if x = 0 then (9, 8, 7) else (6, 5, 4)))) in
  check bool "pnm format" true (I.format c = I.Pnm);
  check (list int) "p6 px" [9; 8; 7; 255] (px c 0 0);
  check (list int) "p6 px2" [6; 5; 4; 255] (px c 1 0);
  let g = get_ok (I.decode (pnm5 2 1 (fun x _ -> 10 + x))) in
  check (list int) "p5 px" [10; 10; 10; 255] (px g 0 0);
  check (list int) "p5 px2" [11; 11; 11; 255] (px g 1 0)

let test_decode_bmp () =
  let data = bmp24 2 2 (fun x y ->
    match x, y with
    | 0, 0 -> (255, 0, 0)
    | 1, 0 -> (0, 255, 0)
    | 0, _ -> (0, 0, 255)
    | _ -> (1, 2, 3))
  in
  match I.sniff data with
  | Some I.Bmp ->
    let i = get_ok (I.decode data) in
    check int "w" 2 (I.width i);
    check int "h" 2 (I.height i);
    check (list int) "tl" [255; 0; 0; 255] (px i 0 0);
    check (list int) "tr" [0; 255; 0; 255] (px i 1 0);
    check (list int) "bl" [0; 0; 255; 255] (px i 0 1);
    check (list int) "br" [1; 2; 3; 255] (px i 1 1)
  | _ -> fail "sniff did not see bmp"

let test_decode_gif () =
  let data = gif_of (mk_rgb 2 1 (fun x _ -> if x = 0 then (10, 20, 30) else (40, 50, 60))) in
  match I.sniff data with
  | Some I.Gif ->
    let i = get_ok (I.decode data) in
    check int "w" 2 (I.width i);
    check int "h" 1 (I.height i);
    check (list int) "first" [10; 20; 30; 255] (px i 0 0);
    check (list int) "second" [40; 50; 60; 255] (px i 1 0)
  | _ -> fail "sniff did not see gif"

let test_decode_jpeg_unsupported () =
  let data = Bytes.of_string "\xFF\xD8\xFF\xE0\x00\x10JFIF\x00" in
  match I.sniff data with
  | Some I.Jpeg ->
    (match I.decode data with
     | Error _ -> ()
     | Ok _ -> fail "jpeg should not decode")
  | _ -> fail "sniff did not see jpeg"

let test_decode_errors () =
  check bool "empty" true (is_error (I.decode Bytes.empty));
  check bool "garbage" true (is_error (I.decode (Bytes.of_string "not an image")));
  check bool "sig only" true
    (is_error (I.decode (Bytes.of_string "\x89PNG\x0D\x0A\x1A\x0A")));
  check bool "truncated png" true
    (is_error (I.decode (Bytes.sub (png_of (mk_rgb 4 4 (fun _ _ -> (1, 2, 3)))) 0 20)))

let test_scene_image () =
  let i = get_ok (I.decode (png_of (mk_rgba 1 1 (fun _ _ -> (9, 9, 9, 128))))) in
  let si = I.to_scene_image i in
  check int "scene w" 1 si.Lui_scene.iw;
  check int "scene h" 1 si.Lui_scene.ih;
  check int "premul byte" 5
    (Char.code (Bytes.get si.Lui_scene.ipix 0))

(* ---------- atlas ---------- *)

let atlas () = Lui_scene.Atlas.create ~bpp:4 ~w:16 ~h:16

let test_upload () =
  let i = get_ok (I.decode (png_of (mk_rgba 4 4 (fun _ _ -> (100, 50, 25, 128))))) in
  let a = atlas () in
  match I.upload a i with
  | Error e -> fail e
  | Ok e ->
    check int "w" 4 e.I.ew;
    check int "h" 4 e.I.eh;
    check int "gen" a.Lui_scene.Atlas.gen e.I.egen;
    check bool "transient" true e.I.etransient;
    (* pixel check: premultiplied (50,25,13,128) at entry origin *)
    let at dx dy c =
      let k = ((e.I.ey + dy) * a.Lui_scene.Atlas.w + e.I.ex + dx) * 4 + c in
      Char.code (Bytes.get a.Lui_scene.Atlas.pix k)
    in
    check int "r" 50 (at 0 0 0);
    check int "g" 25 (at 0 0 1);
    check int "b" 13 (at 0 0 2);
    check int "a" 128 (at 0 0 3)

let test_upload_mask_atlas_rejected () =
  let i = get_ok (I.decode (pnm6 2 2 (fun _ _ -> (1, 2, 3)))) in
  let m = Lui_scene.Atlas.create ~bpp:1 ~w:16 ~h:16 in
  check bool "bpp=1 rejected" true (is_error (I.upload m i))

let test_upload_grows () =
  let i = get_ok (I.decode (pnm6 8 8 (fun _ _ -> (1, 2, 3)))) in
  let a = Lui_scene.Atlas.create ~bpp:4 ~w:4 ~h:4 in
  let gen0 = a.Lui_scene.Atlas.gen in
  match I.upload a i with
  | Error e -> fail e
  | Ok e ->
    check bool "grew" true (a.Lui_scene.Atlas.w >= 16 && e.I.egen > gen0);
    check (list int) "size" [8; 8] [e.I.ew; e.I.eh]

let test_upload_too_big () =
  (* 4100x1 can never fit the 4096 cap (needs w+1 in a shelf row) *)
  let i = get_ok (I.decode (pnm6 4100 1 (fun _ _ -> (1, 2, 3)))) in
  let a = atlas () in
  check bool "overflow" true (is_error (I.upload a i))

let test_upload_lasting () =
  let i = get_ok (I.decode (pnm6 2 2 (fun _ _ -> (1, 2, 3)))) in
  let a = atlas () in
  let e = get_ok (I.upload ~transient:false a i) in
  check bool "lasting" false e.I.etransient;
  Lui_scene.Atlas.reset_transient a;
  (* lasting region survives a transient reset *)
  let k = (e.I.ey * a.Lui_scene.Atlas.w + e.I.ex) * 4 in
  check int "pixel intact" 1 (Char.code (Bytes.get a.Lui_scene.Atlas.pix k))

(* ---------- cache ---------- *)

let p6c v = pnm6 4 4 (fun _ _ -> (v, v + 1, v + 2))

let test_cache_decode () =
  let c = I.Cache.create () in
  let b = p6c 10 in
  let i1 = get_ok (I.Cache.decode c b) in
  let i2 = get_ok (I.Cache.decode c b) in
  check bool "memoized" true (i1 == i2);
  check int "slots" 1 (I.Cache.length c);
  check int "nbytes" 64 (I.Cache.bytes_used c);
  check bool "mem" true (I.Cache.mem c b);
  check bool "no mem" false (I.Cache.mem c (p6c 11));
  ignore (get_ok (I.Cache.decode c (p6c 12)));
  check int "slots 2" 2 (I.Cache.length c)

let test_cache_atlas_entry () =
  let c = I.Cache.create () in
  let a = atlas () in
  let b = p6c 7 in
  let e1 = get_ok (I.Cache.atlas_entry c a b) in
  let v = a.Lui_scene.Atlas.version in
  let e2 = get_ok (I.Cache.atlas_entry c a b) in
  check (list int) "same region" [e1.I.ex; e1.I.ey; e1.I.ew; e1.I.eh]
    [e2.I.ex; e2.I.ey; e2.I.ew; e2.I.eh];
  check int "no rewrite" v a.Lui_scene.Atlas.version

let test_cache_frame () =
  let c = I.Cache.create () in
  let a = atlas () in
  let b = p6c 7 in
  let e1 = get_ok (I.Cache.atlas_entry c a b) in
  Lui_scene.Atlas.reset_transient a;
  I.Cache.begin_frame c;
  let v0 = a.Lui_scene.Atlas.version in
  let e2 = get_ok (I.Cache.atlas_entry c a b) in
  (* transient entry was re-uploaded into the reset space *)
  check bool "reuploaded" true (a.Lui_scene.Atlas.version > v0);
  check int "gen stable" e1.I.egen e2.I.egen;
  (* lasting entries survive begin_frame *)
  let l1 = get_ok (I.Cache.atlas_entry ~transient:false c a (p6c 8)) in
  let v = a.Lui_scene.Atlas.version in
  I.Cache.begin_frame c;
  let l2 = get_ok (I.Cache.atlas_entry ~transient:false c a (p6c 8)) in
  check (list int) "lasting kept" [l1.I.ex; l1.I.ey] [l2.I.ex; l2.I.ey];
  check int "lasting no rewrite" v a.Lui_scene.Atlas.version

let test_cache_stale_gen () =
  let c = I.Cache.create () in
  let a = atlas () in
  let b = p6c 9 in
  let e1 = get_ok (I.Cache.atlas_entry c a b) in
  Lui_scene.Atlas.reset a;
  let e2 = get_ok (I.Cache.atlas_entry c a b) in
  check bool "new gen" true (e2.I.egen > e1.I.egen)

let test_cache_lru () =
  (* room for exactly 3 decoded images (3 * 4*4*4 = 192 bytes) *)
  let c = I.Cache.create ~max_bytes:192 () in
  let b1 = p6c 1 and b2 = p6c 2 and b3 = p6c 3 and b4 = p6c 4 in
  ignore (get_ok (I.Cache.decode c b1));
  ignore (get_ok (I.Cache.decode c b2));
  ignore (get_ok (I.Cache.decode c b3));
  check int "3 slots" 3 (I.Cache.length c);
  ignore (get_ok (I.Cache.decode c b1));  (* touch b1 → b2 is now oldest *)
  ignore (get_ok (I.Cache.decode c b4));
  check int "still 3" 3 (I.Cache.length c);
  check bool "b2 evicted" false (I.Cache.mem c b2);
  check bool "b1 kept" true (I.Cache.mem c b1);
  check bool "b3 kept" true (I.Cache.mem c b3);
  check bool "b4 kept" true (I.Cache.mem c b4);
  I.Cache.clear c;
  check int "cleared" 0 (I.Cache.length c);
  check int "no bytes" 0 (I.Cache.bytes_used c)

(* ---------- fit_rect ---------- *)

let fr f iw ih x y w h = I.fit_rect f ~iw ~ih ~x ~y ~w ~h
let irect_t = testable
    (fun fmt (x, y, w, h) -> Format.fprintf fmt "(%d,%d %dx%d)" x y w h)
    (fun a b -> a = b)

let test_fit () =
  check irect_t "fill" (10, 20, 30, 40) (fr I.Fill 100 50 10 20 30 40);
  check irect_t "natural" (6, 7, 7, 5) (fr I.Natural 7 5 0 0 20 20);
  check irect_t "natural odd" (0, 0, 5, 4) (fr I.Natural 5 4 0 0 4 4);
  check irect_t "contain wide" (0, 12, 50, 25) (fr I.Contain 100 50 0 0 50 50);
  check irect_t "contain tall" (37, 0, 25, 50) (fr I.Contain 50 100 0 0 100 50);
  check irect_t "cover wide" (-25, 0, 100, 50) (fr I.Cover 100 50 0 0 50 50);
  check irect_t "cover tall" (0, -25, 50, 100) (fr I.Cover 50 100 0 0 50 50);
  check irect_t "contain exact" (0, 0, 40, 20) (fr I.Contain 100 50 0 0 40 20);
  (* rounding: 3x2 contain into 4x4 → 4x3 (2*4/3 = 2.67 → 3) *)
  check irect_t "contain round" (0, 0, 4, 3) (fr I.Contain 3 2 0 0 4 4);
  (* rounding: 3x2 cover into 4x4 → 6x4 (3*4/2 = 6) *)
  check irect_t "cover round" (-1, 0, 6, 4) (fr I.Cover 3 2 0 0 4 4);
  check irect_t "zero src" (1, 2, 0, 0) (fr I.Contain 0 10 1 2 5 5);
  check irect_t "zero dst" (1, 2, 0, 0) (fr I.Cover 10 10 1 2 0 5)

(* ---------- run ---------- *)

let () =
  run "lui_image"
    [ ("decode",
       [ test_case "rgba png" `Quick test_decode_rgba_png;
         test_case "rgb png" `Quick test_decode_rgb_png;
         test_case "greya png" `Quick test_decode_greya_png;
         test_case "pnm" `Quick test_decode_pnm;
         test_case "bmp" `Quick test_decode_bmp;
         test_case "gif" `Quick test_decode_gif;
         test_case "jpeg unsupported" `Quick test_decode_jpeg_unsupported;
         test_case "errors" `Quick test_decode_errors;
         test_case "scene image" `Quick test_scene_image ]);
      ("atlas",
       [ test_case "upload" `Quick test_upload;
         test_case "mask atlas rejected" `Quick test_upload_mask_atlas_rejected;
         test_case "grow" `Quick test_upload_grows;
         test_case "too big" `Quick test_upload_too_big;
         test_case "lasting" `Quick test_upload_lasting ]);
      ("cache",
       [ test_case "decode" `Quick test_cache_decode;
         test_case "atlas entry" `Quick test_cache_atlas_entry;
         test_case "frame" `Quick test_cache_frame;
         test_case "stale gen" `Quick test_cache_stale_gen;
         test_case "lru" `Quick test_cache_lru ]);
      ("fit",
       [ test_case "fit_rect" `Quick test_fit ]) ]
