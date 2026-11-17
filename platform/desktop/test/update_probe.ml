let () =
  try
    (match Array.to_list Sys.argv with
    | [_; "authenticate"; key; app_id; platform; build; envelope] ->
        let found = Lui_desktop_update.authenticate ~public_key:key ~app_id ~platform
            ~current_build:(int_of_string build)
            (Lui_desktop_update.read_file ~limit:1_048_576 envelope) in
        (match found with
         | None -> print_endline "current"
         | Some found -> Printf.printf "%s:%d:%b\n" found.version found.build (found.delta <> None))
    | [_; "stage"; package; installed; destination] ->
        Lui_desktop_update.stage ~package ~installed ~destination
    | [_; "install"; staged; target] ->
        Lui_desktop_update.install ~staged ~target |> Lui_desktop_update.confirm
    | [_; "rollback"; staged; target] ->
        Lui_desktop_update.install ~staged ~target |> Lui_desktop_update.rollback
    | _ -> invalid_arg "Unknown probe command");
    exit 0
  with error -> prerr_endline (Printexc.to_string error); exit 1
