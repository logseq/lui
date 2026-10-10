(* Prints a file as an OCaml string literal bound to [source], so data
   files can be embedded in a library. *)
let () =
  let ic = open_in_bin Sys.argv.(1) in
  let data = really_input_string ic (in_channel_length ic) in
  close_in ic;
  Printf.printf "let source = %S\n" data
