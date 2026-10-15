(* Gallery renderer driver: builds the scene, renders, writes PNGs. *)

let out_dir =
  (* dune runs the exe from _build; walk up to the source tree root and
     land outputs next to the module directory. GALLERY_OUT wins when
     set (tests). *)
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
  let f = Lui_gallery.render () in
  Lui_gallery.mkdir_p out_dir;
  let files = Lui_gallery.write_gallery f ~out_dir in
  Printf.printf "wrote %d files into %s\n" (List.length files) out_dir;
  List.iter (fun fn -> Printf.printf "  %s\n" fn) files;
  (* Report kinds that emit nothing unadorned. *)
  let probe = Lui_gallery.probe_own_ops () in
  let empty =
    List.filter_map (fun (k, n) -> if n = 0 then Some k else None) probe
  in
  Printf.printf "kinds emitting no ops unadorned (%d):\n  %s\n"
    (List.length empty) (String.concat ", " empty)
