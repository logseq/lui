(* Prints files as OCaml string literals, one [let <name> = "..."] per
   pair of arguments, so shader binaries and sources can be embedded
   in the library: embed name1 file1 name2 file2 ... *)
let () =
  let n = (Array.length Sys.argv - 1) / 2 in
  for i = 0 to n - 1 do
    let name = Sys.argv.(1 + (2 * i)) and file = Sys.argv.(2 + (2 * i)) in
    let ic = open_in_bin file in
    let data = really_input_string ic (in_channel_length ic) in
    close_in ic;
    Printf.printf "let %s = %S\n" name data
  done
