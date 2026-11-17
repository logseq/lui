(* CoreText variant driver: same gallery, real shaped text, one
   master PNG (gallery_text.png). macOS only — see the dune stanza. *)

let out_dir =
  match Sys.getenv_opt "GALLERY_OUT" with
  | Some d -> d
  | None ->
    let rec find_root dir =
      if Sys.file_exists (Filename.concat dir "dune-project") then dir
      else
        let parent = Filename.dirname dir in
        if parent = dir then dir else find_root parent
    in
    Filename.concat
      (find_root (Sys.getcwd ()))
      (Filename.concat "platform" (Filename.concat "native" "gallery_out"))

let () =
  let eng = ref None in
  let f =
    Lui_gallery.render
      ~text_ops:(fun id r c s ->
        match !eng with
        | Some e -> Lui_gallery_text.text_ops e id r c s
        | None -> [])
      ~measure:(fun id t w h ->
        match !eng with
        | Some e -> Lui_gallery_text.measure e id t w h
        | None -> Lui_gallery.stub_measure id t w h)
      ~post_create:(fun host ->
        eng :=
          Some
            (Lui_gallery_text.create
               ~scene:(fun () -> Lui_host.scene host)
               ~scale:(fun () -> 1.)
               ~store:(fun () -> Lui_host.store host)))
      ()
  in
  Lui_gallery.mkdir_p out_dir;
  let img = match f.Lui_gallery.img with
    | Some i -> i
    | None -> failwith "no frame rendered"
  in
  let path = Filename.concat out_dir "gallery_text.png" in
  Lui_gallery.write_png path ~w:img.Lui_raster.Image.w
    ~h:img.Lui_raster.Image.h (Lui_gallery.rgba_bytes img);
  Printf.printf "wrote %s\n" path
