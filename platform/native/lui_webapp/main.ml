(* main — the webapp launcher: the executable a packaged webapp runs.

   Usage:
     webapp [WEBAPP_JSON]     boot a spec file
     webapp --spec PATH       same, explicit flag
     webapp --no-browser      fail instead of the browser fallback
     webapp --browser         skip the native shell, open the browser
     webapp --print-url       print the resolved entry URL and exit
     webapp --help

   With no spec argument the launcher searches the packaged layouts:
   <exe>/webapp.json (flat / Windows portable), then
   <exe>/../Resources/webapp.json (macOS .app), then
   <exe>/../share/<app>/webapp.json (Linux AppDir). *)

let usage () =
  Printf.printf
    "webapp — run a webapp spec in a native webview shell\n\
     usage: %s [--spec WEBAPP_JSON | WEBAPP_JSON] [--no-browser] \
     [--browser] [--print-url] [--help]\n"
    Sys.argv.(0)

type args = {
  spec_path : string option;
  no_browser : bool;
  force_browser : bool;
  print_url : bool;
}

let parse argv =
  let rec go acc i =
    if i >= Array.length argv then Ok acc
    else
      match argv.(i) with
      | "--help" | "-h" -> Error `Help
      | "--no-browser" -> go { acc with no_browser = true } (i + 1)
      | "--browser" -> go { acc with force_browser = true } (i + 1)
      | "--print-url" -> go { acc with print_url = true } (i + 1)
      | "--spec" ->
        if i + 1 >= Array.length argv then
          Error (`Msg "--spec needs a path argument")
        else go { acc with spec_path = Some argv.(i + 1) } (i + 2)
      | s when String.length s > 0 && s.[0] = '-' ->
        Error (`Msg ("unknown option " ^ s))
      | s ->
        (match acc.spec_path with
         | Some _ -> Error (`Msg ("extra argument " ^ s))
         | None -> go { acc with spec_path = Some s } (i + 1))
  in
  go
    { spec_path = None; no_browser = false; force_browser = false;
      print_url = false }
    1

let find_spec args =
  match args.spec_path with
  | Some p -> Ok p
  | None ->
    (match Lui_webapp.find_embedded_spec ~exe:Sys.executable_name with
     | Some p -> Ok p
     | None ->
       Error
         (Printf.sprintf
            "no spec found — pass WEBAPP_JSON or bundle %s next to \
             the executable (searched: %s)"
            Lui_webapp.spec_file_name
            (String.concat ", "
               (Lui_webapp.embedded_spec_candidates
                  ~exe:Sys.executable_name))))

let () =
  match parse Sys.argv with
  | Error `Help -> usage ()
  | Error (`Msg m) ->
    prerr_endline ("webapp: " ^ m);
    usage ();
    exit 2
  | Ok args ->
    (match find_spec args with
     | Error m ->
       prerr_endline ("webapp: " ^ m);
       exit 2
     | Ok spec_path ->
       (match Lui_webapp.read_spec spec_path with
        | Error m ->
          prerr_endline ("webapp: " ^ m);
          exit 2
        | Ok spec ->
          let base = Filename.dirname spec_path in
          (match Lui_webapp.prepare ~base spec with
           | Error m ->
             prerr_endline ("webapp: " ^ m);
             exit 2
           | Ok prep ->
             if args.print_url then print_endline prep.url
             else if args.force_browser then
               (match Lui_webapp.open_in_browser prep.url with
                | Ok () -> ()
                | Error m ->
                  prerr_endline ("webapp: " ^ m);
                  exit 2)
             else
               Lui_webapp.boot ~base
                 ~fallback_browser:(not args.no_browser)
                 spec)))
