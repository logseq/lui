(* Gallery contract tests: the rendered evidence decodes, every
   standard kind is exercised by a cell, every cell painted pixels,
   and the render is deterministic. *)

open Lui_gallery

let tmpdir () =
  let d =
    Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "lui_gallery_test_%d" (Unix.getpid ()))
  in
  Lui_gallery.mkdir_p d;
  d

let decode_png path =
  let ic = open_in_bin path in
  let s = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let ch = ImageUtil.chunk_reader_of_string s in
  let img = ImageLib.openfile ~extension:"png" ch in
  ImageUtil.close_chunk_reader ch;
  img

(* ---- coverage: every standard kind has a witness node ---- *)

let apply_gallery_store () =
  let g = Lui_gallery.build_gallery () in
  let e = Lui_gallery.emit g.root in
  let store = Lui_store.create () in
  Lui_store.apply_batch store
    { Lui_protocol.generation = 1; ops = e.ops };
  (g, e, store)

let test_kind_coverage () =
  let _g, e, store = apply_gallery_store () in
  (* Every tagged witness really has the kind it claims. *)
  List.iter
    (fun (kname, id) ->
      Alcotest.(check string)
        (Printf.sprintf "witness kind %s" kname) kname
        (Lui_store.kind store id))
    e.covered;
  (* Every standard wire kind is covered by at least one witness. *)
  let covered =
    List.fold_left
      (fun acc (k, _) ->
        if List.mem k acc then acc else k :: acc)
      [] e.covered
  in
  List.iter
    (fun k ->
      let kname = Lui_wire_schema.node_kind_name k in
      Alcotest.(check bool)
        (Printf.sprintf "kind %s exercised" kname) true
        (List.mem kname covered))
    Lui_wire_schema.all_node_kinds

(* ---- render: decode, geometry, pixels, determinism ---- *)

let render () = Lui_gallery.render ()

let test_master_png () =
  let f = render () in
  (match f.Lui_gallery.img with
   | Some _ -> ()
   | None -> Alcotest.fail "no frame captured");
  let dir = tmpdir () in
  let files = Lui_gallery.write_gallery f ~out_dir:dir in
  Alcotest.(check bool) "files listed" true (List.mem "gallery.png" files);
  let decoded = decode_png (Filename.concat dir "gallery.png") in
  Alcotest.(check int) "master width" f.Lui_gallery.fwidth decoded.Image.width;
  Alcotest.(check int) "master height" f.Lui_gallery.fheight decoded.Image.height;
  Alcotest.(check bool) "master nonempty" true
    ((in_channel_length (open_in_bin (Filename.concat dir "gallery.png"))) > 0)

let per_cell_pixels f =
  let img = match f.Lui_gallery.img with
    | Some i -> i
    | None -> Alcotest.fail "no frame captured"
  in
  let rgba = Lui_gallery.rgba_bytes img in
  let g = Lui_gallery.build_gallery () in
  List.map
    (fun c ->
      let r = Lui_gallery.cell_rect f c in
      let cw, ch, pix =
        Lui_gallery.crop rgba ~w:img.Lui_raster.Image.w r
      in
      (c, cw, ch, pix))
    g.Lui_gallery.cells

let test_cell_pngs () =
  let f = render () in
  let dir = tmpdir () in
  let files = Lui_gallery.write_gallery f ~out_dir:dir in
  let cells = per_cell_pixels f in
  List.iteri
    (fun i (c, cw, ch, _pix) ->
      let name =
        Printf.sprintf "cells/c%02d_%s.png" (i + 1)
          (String.map
             (fun ch -> if ch = ' ' then '_' else Char.lowercase_ascii ch)
             c.Lui_gallery.cname)
      in
      Alcotest.(check bool)
        (Printf.sprintf "%s listed" name) true (List.mem name files);
      let path = Filename.concat dir name in
      Alcotest.(check bool)
        (Printf.sprintf "%s exists" name) true (Sys.file_exists path);
      let d = decode_png path in
      Alcotest.(check int) (Printf.sprintf "%s w" name) cw d.Image.width;
      Alcotest.(check int) (Printf.sprintf "%s h" name) ch d.Image.height)
    cells

let test_cells_have_paint () =
  let f = render () in
  let cells = per_cell_pixels f in
  List.iter
    (fun (c, cw, ch, pix) ->
      (* Count pixels differing from the white cell background; every
         subject must draw something — a border, chrome, text rects or
         a bitmap. *)
      let n = ref 0 in
      for i = 0 to (Bytes.length pix / 4) - 1 do
        let r = Char.code (Bytes.get pix (i * 4))
        and g = Char.code (Bytes.get pix (i * 4 + 1))
        and b = Char.code (Bytes.get pix (i * 4 + 2))
        and a = Char.code (Bytes.get pix (i * 4 + 3)) in
        if (r < 245 || g < 245 || b < 245) && a > 0 then incr n
      done;
      Alcotest.(check bool)
        (Printf.sprintf "cell %s painted (%dx%d)" c.Lui_gallery.cname cw ch)
        true (!n > 4))
    cells

let test_determinism () =
  let a = render () and b = render () in
  let cells_a = per_cell_pixels a and cells_b = per_cell_pixels b in
  Alcotest.(check int) "same cell count"
    (List.length cells_a) (List.length cells_b);
  List.iter2
    (fun (ca, wa, ha, pa) (_cb, wb, hb, pb) ->
      Alcotest.(check int)
        (Printf.sprintf "%s w stable" ca.Lui_gallery.cname) wa wb;
      Alcotest.(check int)
        (Printf.sprintf "%s h stable" ca.Lui_gallery.cname) ha hb;
      Alcotest.(check string)
        (Printf.sprintf "%s checksum stable" ca.Lui_gallery.cname)
        (Digest.to_hex (Digest.bytes pa))
        (Digest.to_hex (Digest.bytes pb)))
    cells_a cells_b

let () =
  Alcotest.run "lui_gallery"
    [ ("coverage", [ Alcotest.test_case "all kinds exercised" `Quick test_kind_coverage ]);
      ("render",
       [ Alcotest.test_case "master png decodes" `Quick test_master_png;
         Alcotest.test_case "cell pngs decode" `Quick test_cell_pngs;
         Alcotest.test_case "every cell painted" `Quick test_cells_have_paint;
         Alcotest.test_case "deterministic" `Slow test_determinism ]) ]
