(* GC stress for the pointer-detail bridge. The callback allocates on every
   call so a minor collection runs while the six callback arguments are live.
   Run with OCAMLRUNPARAM=s=4k. *)

external stress_press_detail : int -> unit = "stress_press_detail"

let () =
  Callback.register "lui_ocaml_press_detail"
    (fun node x y modifiers button target_class ->
      let buffer = Bytes.create 4096 in
      Bytes.fill buffer 0 4096 'x';
      ignore (Sys.opaque_identity (Bytes.to_string buffer));
      ignore
        (Sys.opaque_identity (node, x, y, modifiers, button, target_class));
      "");
  stress_press_detail 4000;
  print_endline "c1 stress ok"
