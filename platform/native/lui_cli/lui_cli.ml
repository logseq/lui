(* Lui_cli — the `lui` developer command line for the native backend.
   See lui_cli.mli for the module contract; process/file helpers come
   from Lui_pkg's exposed internals rather than being re-implemented. *)

let name = "lui"
let version = "0.1.0"

let fmt = Printf.sprintf
let log f = Printf.printf (f ^^ "\n%!")
let err f = Printf.eprintf (f ^^ "\n%!")

(* Process and file primitives shared with the packagers: Proc.run
   captures into temp files (no pipe deadlock), Fs is the platform
   file vocabulary. *)
module Proc = Lui_pkg.Private.Proc
module Fs = Lui_pkg.Private.Fs

let ( / ) = Filename.concat

(* {1 Args} *)

module Args = struct
  type platform_sel = P_auto | P_mac | P_linux | P_windows
  type artifact_fmt =
    | F_auto | F_dmg | F_zip | F_deb | F_tar | F_appimage | F_msix | F_nsis
  type key_alg = Ed25519 | Rsa

  type init_spec = { i_name : string option; i_dir : string; i_force : bool }
  type dev_spec = { d_dir : string; d_exe : string }
  type build_spec = { b_dir : string; b_release : bool }
  type package_spec = {
    p_dir : string;
    p_platform : platform_sel;
    p_sign : string option;
    p_format : artifact_fmt;
    p_out : string;
    p_webview : bool;
    p_name : string option;
    p_bundle_id : string option;
    p_version : string option;
    p_icon : string option;
    p_exe : string option;
    p_build : bool;
  }
  type keygen_spec = {
    k_dir : string;
    k_name : string;
    k_alg : key_alg;
    k_force : bool;
  }
  type sign_spec = { s_key : string; s_in : string }
  type command =
    | Init of init_spec
    | Dev of dev_spec
    | Build of build_spec
    | Package of package_spec
    | Doctor
    | Keygen of keygen_spec
    | Sign of sign_spec
    | Version
    | Help of string option

  let string_of_platform = function
    | P_auto -> "auto" | P_mac -> "mac"
    | P_linux -> "linux" | P_windows -> "windows"

  let string_of_fmt = function
    | F_auto -> "auto" | F_dmg -> "dmg" | F_zip -> "zip"
    | F_deb -> "deb" | F_tar -> "tar" | F_appimage -> "appimage"
    | F_msix -> "msix" | F_nsis -> "nsis"

  let parse_platform = function
    | "auto" -> Ok P_auto
    | "mac" | "macos" | "darwin" -> Ok P_mac
    | "linux" -> Ok P_linux
    | "windows" | "win" | "mingw" | "mingw64" -> Ok P_windows
    | s -> Error (fmt "unknown --platform %S (auto|mac|linux|windows)" s)

  (* Command-line syntax is Cmdliner's: each subcommand below is a
     [Cmd.v] whose term builds the spec record, and [parse] evaluates
     the whole command group on an argv rebuilt from the token list —
     tests drive the same parser the binary runs, and Cmdliner owns
     option scanning, [--opt=value] splitting, positional arity and
     the generated manpages that [usage]/[usage_of] render. *)
  open Cmdliner

  let ( let+ ) t f = Term.app (Term.const f) t
  let ( and+ ) a b = Term.product a b

  let dir_pos doc =
    Arg.(value & pos 0 string "." & info [] ~docv:"DIR" ~doc)

  let init_cmd =
    let name =
      Arg.(value & opt (some string) None
           & info [ "name" ] ~docv:"NAME" ~doc:"application name")
    and dir =
      Arg.(value & opt (some string) None
           & info [ "dir" ] ~docv:"DIR" ~doc:"target directory")
    and force =
      Arg.(value & flag
           & info [ "force" ] ~doc:"allow a non-empty target directory")
    in
    let make name dir force pos =
      Init { i_name = name; i_force = force;
             i_dir = Option.value ~default:pos dir }
    in
    Cmd.v
      (Cmd.info "init" ~doc:"scaffold a minimal app")
      (let+ name and+ dir and+ force
       and+ pos = dir_pos "target directory" in
       make name dir force pos)

  let dev_cmd =
    let exe =
      Arg.(value & opt string "main.exe"
           & info [ "exe" ] ~docv:"NAME"
               ~doc:"exe under _build/default to (re)start")
    in
    Cmd.v
      (Cmd.info "dev" ~doc:"rebuild on change and restart the app")
      (let+ exe and+ dir = dir_pos "project directory" in
       Dev { d_dir = dir; d_exe = exe })

  let build_cmd =
    let release =
      Arg.(value & flag
           & info [ "release" ] ~doc:"build with the release profile")
    in
    Cmd.v
      (Cmd.info "build" ~doc:"build the app once")
      (let+ release and+ dir = dir_pos "project directory" in
       Build { b_dir = dir; b_release = release })

  let package_cmd =
    let platform =
      Arg.(value & opt (some string) None
           & info [ "platform" ] ~docv:"auto|mac|linux|windows"
               ~doc:"target platform (default: host)")
    and sign =
      Arg.(value & opt (some string) None
           & info [ "sign" ] ~docv:"IDENTITY" ~doc:"signing identity")
    and out =
      Arg.(value & opt (some string) None
           & info [ "out" ] ~docv:"DIR" ~doc:"output directory")
    and pname =
      Arg.(value & opt (some string) None
           & info [ "name" ] ~docv:"NAME" ~doc:"application name")
    and bundle_id =
      Arg.(value & opt (some string) None
           & info [ "bundle-id" ] ~docv:"ID" ~doc:"bundle identifier")
    and version =
      Arg.(value & opt (some string) None
           & info [ "version" ] ~docv:"VER" ~doc:"short version (semver)")
    and icon =
      Arg.(value & opt (some string) None
           & info [ "icon" ] ~docv:"PNG" ~doc:"source PNG for the icon")
    and exe =
      Arg.(value & opt (some string) None
           & info [ "exe" ] ~docv:"PATH" ~doc:"built binary to package")
    and webview =
      Arg.(value & flag
           & info [ "webview" ] ~doc:"bundle DIR/web/ as assets")
    and no_build =
      Arg.(value & flag
           & info [ "no-build" ] ~doc:"skip the dune build step")
    in
    let fmt_flag name doc =
      Arg.(value & flag & info [ name ] ~doc)
    in
    let f_dmg = fmt_flag "dmg" "disk image (macOS)"
    and f_zip = fmt_flag "zip" "zip archive (windows)"
    and f_deb = fmt_flag "deb" "deb package (linux)"
    and f_tar = fmt_flag "tar" "tarball (linux)"
    and f_appimage = fmt_flag "appimage" "AppImage (linux)"
    and f_msix = fmt_flag "msix" "MSIX package (windows)"
    and f_nsis = fmt_flag "nsis" "NSIS installer (windows)" in
    let make platform sign out pname bundle_id version icon exe webview
        no_build dir f_dmg f_zip f_deb f_tar f_appimage f_msix f_nsis =
      let fmts =
        List.filter_map
          (fun (b, f) -> if b then Some f else None)
          [ (f_dmg, F_dmg); (f_zip, F_zip); (f_deb, F_deb); (f_tar, F_tar);
            (f_appimage, F_appimage); (f_msix, F_msix); (f_nsis, F_nsis) ]
      in
      match fmts with
      | _ :: _ :: _ ->
        Error (`Msg "package takes at most one artifact format flag")
      | _ ->
        (match
           match platform with
           | None -> Ok P_auto
           | Some p ->
             (match parse_platform p with
              | Ok v -> Ok v
              | Error e -> Error (`Msg e))
         with
         | Error e -> Error e
         | Ok p_platform ->
           Ok
             (Package
                { p_dir = dir; p_platform;
                  p_format =
                    (match fmts with [] -> F_auto | f :: _ -> f);
                  p_out =
                    Option.value ~default:(dir / "dist") out;
                  p_webview = webview;
                  p_sign = sign; p_name = pname; p_bundle_id = bundle_id;
                  p_version = version; p_icon = icon; p_exe = exe;
                  p_build = not no_build }))
    in
    Cmd.v
      (Cmd.info "package" ~doc:"produce a distributable artifact")
      (Term.term_result
         (let+ platform and+ sign and+ out and+ pname and+ bundle_id
          and+ version and+ icon and+ exe and+ webview and+ no_build
          and+ dir = dir_pos "project directory"
          and+ f_dmg and+ f_zip and+ f_deb and+ f_tar and+ f_appimage
          and+ f_msix and+ f_nsis in
          make platform sign out pname bundle_id version icon exe webview
            no_build dir f_dmg f_zip f_deb f_tar f_appimage f_msix f_nsis))

  let doctor_cmd =
    Cmd.v
      (Cmd.info "doctor" ~doc:"check the toolchain")
      (Term.const Doctor)

  let keygen_cmd =
    let dir =
      Arg.(value & opt string ""
           & info [ "dir" ] ~docv:"DIR" ~doc:"key output directory")
    and kname =
      Arg.(value & opt string "lui-update"
           & info [ "name" ] ~docv:"NAME" ~doc:"basename of the key files")
    and alg =
      Arg.(value & opt (some string) None
           & info [ "alg" ] ~docv:"ed25519|rsa" ~doc:"key algorithm")
    and force =
      Arg.(value & flag
           & info [ "force" ] ~doc:"replace existing keys")
    in
    let make dir kname alg force =
      match
        match alg with
        | None | Some "ed25519" -> Ok Ed25519
        | Some "rsa" -> Ok Rsa
        | Some a -> Error (`Msg (fmt "unknown --alg %S (ed25519|rsa)" a))
      with
      | Error e -> Error e
      | Ok k_alg ->
        Ok (Keygen { k_dir = dir; k_name = kname; k_alg; k_force = force })
    in
    Cmd.v
      (Cmd.info "keygen" ~doc:"write an update-signing key pair")
      (Term.term_result
         (let+ dir and+ kname and+ alg and+ force in
          make dir kname alg force))

  let sign_cmd =
    let key =
      Arg.(required & opt (some string) None
           & info [ "key" ] ~docv:"PRIV.pem"
               ~doc:"Ed25519 PKCS8 PEM private key")
    and input =
      Arg.(required & opt (some string) None
           & info [ "in" ] ~docv:"FILE" ~doc:"file whose bytes to sign")
    in
    Cmd.v
      (Cmd.info "sign" ~doc:"Ed25519-sign a file's raw bytes")
      (let+ key and+ input in Sign { s_key = key; s_in = input })

  let version_cmd =
    Cmd.v
      (Cmd.info "version" ~doc:"print the cli version")
      (Term.const Version)

  let known = [ "init"; "dev"; "build"; "package"; "doctor"; "keygen";
                "sign"; "version"; "help" ]

  (* No ~version on the group info: Cmdliner would inject a [--version]
     option into every subcommand, colliding with [package]'s own
     [--version]. [parse] answers version and help before delegating. *)
  let cli_group =
    Cmd.group
      (Cmd.info "lui" ~doc:"developer tool for LUI native apps")
      [ init_cmd; dev_cmd; build_cmd; package_cmd; doctor_cmd;
        keygen_cmd; sign_cmd; version_cmd ]

  (* [render_help argv] runs the group evaluation with output captured:
     the help strings the interface exposes are Cmdliner's own manpage
     text, not a parallel hand-written copy. *)
  let render_help argv =
    let buf = Buffer.create 512 in
    let help = Format.formatter_of_buffer buf in
    ignore (Cmd.eval_value ~argv ~help ~err:help cli_group);
    Format.pp_print_flush help ();
    Buffer.contents buf

  let usage = render_help [| "lui"; "--help" |]

  let usage_of c =
    if List.mem c known then Some (render_help [| "lui"; c; "--help" |])
    else None

  (* [eval_args c rest] evaluates [c]'s subcommand on [rest]; Cmdliner
     reports parse and term errors on the captured formatter, which
     becomes [parse]'s human-readable [Error] string. *)
  let eval_args c rest =
    let argv = Array.of_list ("lui" :: c :: rest) in
    let buf = Buffer.create 256 in
    let fmt = Format.formatter_of_buffer buf in
    match Cmd.eval_value ~argv ~help:fmt ~err:fmt cli_group with
    | Ok (`Ok cmd) -> Ok cmd
    | Ok `Help -> Ok (Help (Some c))
    | Ok `Version -> Ok Version
    | Error _ ->
      Format.pp_print_flush fmt ();
      (match String.trim (Buffer.contents buf) with
       | "" -> Error "bad arguments"
       | m -> Error m)

  let parse = function
    | [] -> Ok (Help None)
    | ("help" | "-h" | "--help") :: rest ->
      (match rest with
       | [] -> Ok (Help None)
       | c :: _ when List.mem c known -> Ok (Help (Some c))
       | _ :: _ -> Ok (Help None))
    | ("version" | "-v" | "--version") :: rest ->
      (match rest with
       | [] -> Ok Version
       | _ -> Error "version takes no arguments")
    | c :: rest when List.mem c known ->
      (* A lone -h/--help anywhere in a subcommand asks for its usage. *)
      if List.exists (fun a -> a = "-h" || a = "--help") rest then
        Ok (Help (Some c))
      else eval_args c rest
    | c :: _ -> Error (fmt "unknown command %S (try `lui help`)" c)
end

(* {1 shared command helpers} *)

(* cd into a project dir, erroring out when it is not a directory. *)
let with_dir dir f =
  if not (Fs.is_dir dir) then begin
    err "lui: %s is not a directory" dir;
    1
  end
  else begin
    Unix.chdir dir;
    f ()
  end

(* {1 Init} *)

module Init = struct
  let sanitize_name s =
    let b = Buffer.create (String.length s) in
    let dash = ref true in (* suppress a leading dash too *)
    String.iter
      (fun c ->
         match Char.lowercase_ascii c with
         | ('a' .. 'z' | '0' .. '9') as c ->
           Buffer.add_char b c;
           dash := false
         | _ ->
           if not !dash then begin
             Buffer.add_char b '-';
             dash := true
           end)
      s;
    let s = Buffer.contents b in
    let s =
      if String.length s > 0 && s.[String.length s - 1] = '-' then
        String.sub s 0 (String.length s - 1)
      else s
    in
    if s = "" then "app" else s

  let dune_project = "(lang dune 3.17)\n"

  let dune_file =
    "(executable\n (name main)\n (modules main)\n (libraries lui ocaml-signal))\n"

  (* The scaffold keeps the app free of the desktop host so a fresh
     tree builds anywhere `lui` is installed; the recording backend
     prints one line per flushed batch where a real host would present
     a frame. The model/reducer/view triple is exactly what the window
     host drives. *)
  let main_ml name =
    fmt
      "(* %s — a LUI application scaffolded by `lui init`.\n\n   Every LUI host drives the same triple: a model, a reducer from\n   (model, action) to model, and a view tree built with Lui_elements.\n   The desktop host in the LUI repository (platform/native/lui_window)\n   feeds window events into Lui_app.dispatch_event and presents every\n   flushed patch batch on screen. This standalone build swaps that host\n   for a recording backend so the app compiles wherever `lui` is\n   installed — it prints one line per flushed batch.\n\n   Point the backend at a real host to render; nothing above the `let ()`\n   driver changes. *)\n\ntype model = { clicks : int }\ntype action = Clicked\n\nlet reduce model Clicked = { clicks = model.clicks + 1 }\n\nlet view _context model_source send =\n  Lui_elements.column ~gap:8\n    [ Lui_elements.dyn ~equal:( = )\n        (fun (m : model) ->\n           Lui_elements.text\n             ~value:(Printf.sprintf \"You clicked %%d time(s).\" m.clicks)\n             [])\n        model_source;\n      Lui_elements.button ~text:\"Click me\"\n        ~on_press:(Lui_elements.press send Clicked) [] ]\n\nlet () =\n  let frame = ref 0 in\n  let backend =\n    { Lui_protocol.backend_profile = Lui_protocol.generic_profile ();\n      apply_batch =\n        (fun batch ->\n           incr frame;\n           Printf.printf \"frame %%d: %%d op(s)\\n%%!\" !frame\n             (List.length batch.Lui_protocol.ops);\n           true) }\n  in\n  let app = Lui_app.create backend { clicks = 0 } reduce view in\n  ignore (Lui_app.start app);\n  ignore (Lui_app.flush app);\n  ignore (Lui_app.send app Clicked);\n  ignore (Lui_app.flush app);\n  ignore (Lui_app.dispose app)\n"
      name

  let gitignore =
    "_build/\n_opam/\n*.install\n*.merlin\ndist/\n*.app/\n*.dmg\n*.delta\n*-priv.pem\n"

  let readme name =
    fmt
      "# %s\n\nA LUI desktop app scaffolded by `lui init`.\n\n## Layout\n\n- `main.ml` — model / reducer / view, plus a recording backend that\n  prints each patch batch. Swap the backend for the window host\n  (`platform/native/lui_window` in the LUI repository) to render.\n- `web/` — optional assets bundled by `lui package --webview`.\n\n## Develop\n\n```sh\nlui dev        # rebuild on change, restart the app\nlui build      # one-shot dune build\nlui package    # dist artifact for the host platform\nlui doctor     # check the toolchain\nlui keygen     # update-signing key pair\n```\n"
      name

  let files ~name =
    [ ("dune-project", dune_project);
      ("dune", dune_file);
      ("main.ml", main_ml name);
      (".gitignore", gitignore);
      ("README.md", readme name) ]

  let scaffold ~dir ~name ~force =
    let name =
      match name with
      | Some n -> sanitize_name n
      | None ->
        sanitize_name
          (Filename.basename
             (if String.length dir > 1 && dir.[String.length dir - 1] = '/' then
                String.sub dir 0 (String.length dir - 1)
              else dir))
    in
    if Fs.exists dir && not (Sys.is_directory dir) then
      Error (fmt "%s exists and is not a directory" dir)
    else if
      Fs.exists dir && Sys.readdir dir <> [||] && not force
    then
      Error
        (fmt "%s is not empty — pass --force to scaffold into it anyway" dir)
    else begin
      Fs.mkdir_p dir;
      let written =
        List.map
          (fun (rel, content) ->
             let path = dir / rel in
             Fs.write_file path content;
             path)
          (files ~name)
      in
      Ok written
    end

  let run (s : Args.init_spec) =
    match scaffold ~dir:s.i_dir ~name:s.i_name ~force:s.i_force with
    | Error e -> err "lui init: %s" e; 1
    | Ok written ->
      List.iter (log "wrote %s") written;
      log "\nnext: cd %s && lui dev" s.i_dir;
      0
end

(* {1 Dev} *)

module Dev = struct
  type line_kind = Built | Broken | Info

  let icontains ~sub s =
    let n = String.length sub and m = String.length s in
    let rec go i =
      if i + n > m then false
      else
        (let rec eq j =
           j >= n
           || (Char.lowercase_ascii s.[i + j]
               = Char.lowercase_ascii sub.[j]
               && eq (j + 1))
         in
         eq 0 || go (i + 1))
    in
    go 0

  let classify line =
    if icontains ~sub:"success" line then Built
    else if
      icontains ~sub:"error" line || icontains ~sub:"failed" line
      || icontains ~sub:"fatal" line
    then Broken
    else Info

  let exe_path ~dir ~exe = dir / "_build" / "default" / exe

  (* Pids of the watcher and the live app; the SIGINT handler needs
     them at signal time. *)
  let watch_pid = ref None
  let app_pid = ref None

  let kill_pid pid =
    try Unix.kill pid Sys.sigterm
    with Unix.Unix_error _ -> ()

  let reap pid =
    (* Give a SIGTERM a moment before the KILL, then always reap. *)
    let rec poll n =
      match Unix.waitpid [ Unix.WNOHANG ] pid with
      | 0, _ when n > 0 ->
        Unix.sleepf 0.05;
        poll (n - 1)
      | r -> r
    in
    (match poll 20 with
     | 0, _ ->
       (try Unix.kill pid Sys.sigkill
        with Unix.Unix_error _ -> ());
       (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ())
     | _ -> ())

  let stop_app () =
    match !app_pid with
    | None -> ()
    | Some pid ->
      app_pid := None;
      kill_pid pid;
      reap pid

  let cleanup () =
    stop_app ();
    (match !watch_pid with
     | Some pid -> kill_pid pid
     | None -> ())

  let run (s : Args.dev_spec) =
    with_dir s.d_dir (fun () ->
        match Proc.which "dune" with
        | None -> err "lui dev: dune not found in PATH"; 1
        | Some _ ->
          let exe = exe_path ~dir:"." ~exe:s.d_exe in
          let rd, wr = Unix.pipe () in
          let wpid =
            Unix.create_process "dune" [| "dune"; "build"; "-w" |]
              Unix.stdin wr Unix.stderr
          in
          Unix.close wr;
          watch_pid := Some wpid;
          let ic = Unix.in_channel_of_descr rd in
          let stop = ref false in
          Sys.set_signal Sys.sigint
            (Sys.Signal_handle
               (fun _ ->
                  cleanup ();
                  exit 130));
          log "lui dev: watching %s (app: %s)" (Sys.getcwd ()) exe;
          let rec loop () =
            match input_line ic with
            | line ->
              (match classify line with
               | Built ->
                 log "rebuilt — restarting app";
                 stop_app ();
                 if Fs.exists exe then
                   app_pid :=
                     Some
                       (Unix.create_process exe [| exe |]
                          Unix.stdin Unix.stdout Unix.stderr)
                 else
                   err "lui dev: build succeeded but %s is missing" exe
               | Broken -> ()
               | Info -> ());
              print_string (line ^ "\n");
              flush stdout;
              (* Reap a dead app so it never lingers as a zombie; the
                 next successful build restarts it. *)
              (match !app_pid with
               | Some pid ->
                 (match Unix.waitpid [ Unix.WNOHANG ] pid with
                  | 0, _ -> ()
                  | _, st ->
                    app_pid := None;
                    (match st with
                     | Unix.WEXITED n ->
                       log "app exited (status %d)" n
                     | Unix.WSIGNALED sg ->
                       log "app killed (signal %d)" sg
                     | Unix.WSTOPPED _ -> ()))
               | None -> ());
              if not !stop then loop ()
            | exception End_of_file -> ()
          in
          loop ();
          cleanup ();
          let status =
            match Unix.waitpid [] wpid with
            | _, Unix.WEXITED n -> n
            | _, Unix.WSIGNALED sg -> 128 + sg
            | _, Unix.WSTOPPED sg -> 128 + sg
          in
          status)
end

(* {1 Build} *)

module Build = struct
  let dune_args ~release =
    if release then [ "build"; "--profile"; "release" ] else [ "build" ]

  let artifacts ~dir =
    let d = dir / "_build" / "default" in
    if not (Fs.is_dir d) then []
    else
      List.filter_map
        (fun (p, k) ->
           match k with
           | Fs.File when Filename.check_suffix p ".exe" -> Some (d / p)
           | _ -> None)
        (Fs.walk d)

  let run (s : Args.build_spec) =
    with_dir s.b_dir (fun () ->
        match Proc.which "dune" with
        | None -> err "lui build: dune not found in PATH"; 1
        | Some _ ->
          let r = Proc.run "dune" (dune_args ~release:s.b_release) in
          print_string r.stdout;
          prerr_string r.stderr;
          if r.status <> 0 then r.status
          else begin
            (match artifacts ~dir:"." with
             | [] -> log "build ok (no executables under _build/default)"
             | arts -> List.iter (log "artifact: %s") arts);
            0
          end)
end

(* {1 Package} *)

module Package = struct
  type pack_kind = Pk_macos | Pk_linux | Pk_windows
  type artifact = A_dmg | A_tar | A_deb | A_appimage | A_zip | A_msix | A_nsis
  type plan = { pk : pack_kind; artifact : artifact }

  let string_of_artifact = function
    | A_dmg -> "dmg" | A_tar -> "tar" | A_deb -> "deb"
    | A_appimage -> "appimage" | A_zip -> "zip" | A_msix -> "msix"
    | A_nsis -> "nsis"

  let pack_kind_of = function
    | Lui_pkg.Macos -> Ok Pk_macos
    | Lui_pkg.Linux -> Ok Pk_linux
    | Lui_pkg.Windows -> Ok Pk_windows
    | Lui_pkg.Unknown s -> Error (fmt "unsupported platform %S" s)

  let plan sel afmt =
    let host =
      match sel with
      | Args.P_auto -> Ok (Lui_pkg.host_platform ())
      | P_mac -> Ok Lui_pkg.Macos
      | P_linux -> Ok Lui_pkg.Linux
      | P_windows -> Ok Lui_pkg.Windows
    in
    match host with
    | Error e -> Error e
    | Ok plat ->
      (match pack_kind_of plat with
       | Error e -> Error e
       | Ok pk ->
         let pick allowed default =
           match afmt with
           | Args.F_auto -> Ok default
           | f ->
             (match List.assoc_opt f allowed with
              | Some a -> Ok a
              | None ->
                Error
                  (fmt "--%s is not a %s format (supported: %s)"
                     (Args.string_of_fmt afmt)
                     (match pk with
                      | Pk_macos -> "macOS" | Pk_linux -> "linux"
                      | Pk_windows -> "windows")
                     (String.concat ", "
                        (List.map
                           (fun (f, _) -> Args.string_of_fmt f)
                           allowed))))
         in
         let chosen =
           match pk with
           | Pk_macos -> pick [ (Args.F_dmg, A_dmg) ] A_dmg
           | Pk_linux ->
             pick
               [ (Args.F_tar, A_tar); (Args.F_deb, A_deb);
                 (Args.F_appimage, A_appimage) ]
               A_tar
           | Pk_windows ->
             pick
               [ (Args.F_zip, A_zip); (Args.F_msix, A_msix);
                 (Args.F_nsis, A_nsis) ]
               A_zip
         in
         (match chosen with
          | Error e -> Error e
          | Ok artifact -> Ok { pk; artifact }))

  let webview_resources ~dir ~webview =
    if not webview then Ok []
    else
      let web = dir / "web" in
      if Fs.is_dir web then
        Ok [ { Lui_pkg.res_name = "web"; res_src = web } ]
      else
        Error
          (fmt "--webview requested but %s does not exist — create it with the app's web assets" web)

  let spec_of (s : Args.package_spec) ~exe ~resources =
    let name =
      match s.p_name with
      | Some n -> n
      | None ->
        Init.sanitize_name
          (Filename.basename (Unix.realpath s.p_dir))
    in
    let bundle_id =
      match s.p_bundle_id with
      | Some b -> b
      | None -> "app.lui." ^ Init.sanitize_name name
    in
    let version = Option.value ~default:"0.1.0" s.p_version in
    let identity =
      match s.p_sign with
      | None -> Lui_pkg.Adhoc
      | Some "adhoc" | Some "-" -> Lui_pkg.Adhoc
      | Some id -> Lui_pkg.Certificate id
    in
    Lui_pkg.v_spec ~name ~bundle_id ~version ?icon:s.p_icon
      ~executable:exe ~resources ~identity ()

  let outcome_line o ~ok =
    match o with
    | Lui_pkg.Ok v -> log "%s" (ok v); `Ok v
    | Skipped m -> log "skipped: %s" m; `Skipped
    | Unsupported m -> err "unsupported: %s" m; `Bad 1
    | Failed f -> err "failed: %s" (Lui_pkg.string_of_failure f); `Bad 1

  (* A build must exist before bundling; --exe bypasses it when the
     caller built externally. *)
  let ensure_exe (s : Args.package_spec) =
    let exe =
      Option.value ~default:("." / "_build" / "default" / "main.exe")
        s.p_exe
    in
    if Fs.exists exe || not s.p_build then
      if Fs.exists exe then Ok exe
      else Error (fmt "executable %s not found" exe)
    else begin
      log "building app…";
      let r = Proc.run "dune" [ "build" ] in
      print_string r.stdout;
      prerr_string r.stderr;
      if r.status <> 0 then
        Error (fmt "dune build failed (status %d)" r.status)
      else if Fs.exists exe then Ok exe
      else
        Error
          (fmt "build ok but %s is missing — pass --exe PATH" exe)
    end

  let run (s : Args.package_spec) =
    with_dir s.p_dir (fun () ->
        match plan s.p_platform s.p_format with
        | Error e -> err "lui package: %s" e; 1
        | Ok plan ->
          (match webview_resources ~dir:"." ~webview:s.p_webview with
           | Error e -> err "lui package: %s" e; 1
           | Ok resources ->
             (match ensure_exe s with
              | Error e -> err "lui package: %s" e; 1
              | Ok exe ->
                let spec = spec_of s ~exe ~resources in
                Fs.mkdir_p s.p_out;
                let sign_wanted = s.p_sign <> None in
                (match plan.pk with
                 | Pk_macos ->
                   (match outcome_line (Lui_pkg.bundle spec ~dir:s.p_out)
                            ~ok:(fun p -> "bundle: " ^ p) with
                    | `Ok app ->
                      (* adhoc signing is free and makes the bundle
                         launchable everywhere; a Certificate identity
                         only runs when --sign was passed. *)
                      (match
                         outcome_line (Lui_pkg.sign spec app)
                           ~ok:(fun r ->
                             fmt "signed %d item(s) (verify %s)"
                               (List.length r.Lui_pkg.signed)
                               (if r.codesign_verify.tc_ok then "ok"
                                else "FAILED"))
                       with
                       | `Bad c -> c
                       | _ ->
                         (match
                            outcome_line
                              (Lui_pkg.dmg spec app ~dir:s.p_out)
                              ~ok:(fun p -> "artifact: " ^ p)
                          with
                          | `Bad c -> c
                          | _ -> 0))
                    | `Bad c -> c
                    | _ -> 1)
                 | Pk_linux ->
                   if sign_wanted then
                     log "note: linux has no signing step (--sign ignored)";
                   (match
                      outcome_line
                        (Lui_pkg_linux.bundle spec ~dir:s.p_out)
                        ~ok:(fun p -> "appdir: " ^ p)
                    with
                    | `Ok appdir ->
                      let o =
                        match plan.artifact with
                        | A_deb -> Lui_pkg_linux.deb spec appdir ~dir:s.p_out
                        | A_appimage ->
                          Lui_pkg_linux.appimage spec appdir ~dir:s.p_out
                        | _ -> Lui_pkg_linux.tarball spec appdir ~dir:s.p_out
                      in
                      (match outcome_line o ~ok:(fun p -> "artifact: " ^ p)
                       with
                       | `Bad c -> c
                       | `Skipped -> 1
                       | _ -> 0)
                    | `Bad c -> c
                    | _ -> 1)
                 | Pk_windows ->
                   (match
                      outcome_line
                        (Lui_pkg_windows.bundle spec ~dir:s.p_out)
                        ~ok:(fun p -> "app dir: " ^ p)
                    with
                    | `Ok app ->
                      if sign_wanted then
                        ignore
                          (outcome_line (Lui_pkg_windows.sign spec app)
                             ~ok:(fun r ->
                               fmt "signed %d image(s)"
                                 (List.length r.Lui_pkg.signed)));
                      let fmt' =
                        match plan.artifact with
                        | A_msix -> Lui_pkg_windows.Msix
                        | A_nsis -> Lui_pkg_windows.Nsis
                        | _ -> Lui_pkg_windows.Zip
                      in
                      (match
                         outcome_line
                           (Lui_pkg_windows.package ~fmt:fmt' spec app
                              ~dir:s.p_out)
                           ~ok:(fun p -> "artifact: " ^ p)
                       with
                       | `Bad c -> c
                       | `Skipped -> 1
                       | _ -> 0)
                    | `Bad c -> c
                    | _ -> 1)))))
end

(* {1 Doctor} *)

module Doctor = struct
  type status = Ok of string | Missing | Skip of string
  type probe =
    | On_path of string
    | Version_ok of string * string list * int * int * int
    | Pkg_config of string
    | Brew of string
    | Cmd_ok of string * string list
    | Any of probe list
  type check = {
    c_name : string;
    c_required : bool;
    c_hint : string;
    c_probe : probe;
  }

  let first_line s =
    match String.index_opt s '\n' with
    | None -> String.trim s
    | Some i -> String.trim (String.sub s 0 i)

  let parse_version s =
    let comps = String.split_on_char '.' (String.trim s) in
    let num w =
      let n = String.length w in
      let i = ref 0 in
      while !i < n && w.[!i] >= '0' && w.[!i] <= '9' do
        incr i
      done;
      if !i = 0 then None else int_of_string_opt (String.sub w 0 !i)
    in
    match List.map num comps with
    | [ Some a; Some b; Some c ] -> Some (a, b, c)
    | [ Some a; Some b ] -> Some (a, b, 0)
    | [ Some a ] -> Some (a, 0, 0)
    | _ -> None

  let version_at_least got want = got >= want

  let rec eval = function
    | On_path tool ->
      (match Proc.which tool with
       | Some p -> Ok p
       | None -> Missing)
    | Cmd_ok (tool, args) ->
      let r = Proc.run tool args in
      if r.status = 0 then Ok (first_line r.stdout) else Missing
    | Version_ok (tool, args, a, b, c) ->
      let r = Proc.run tool args in
      if r.status <> 0 then Missing
      else
        (match parse_version (first_line r.stdout) with
         | Some (x, y, z) when version_at_least (x, y, z) (a, b, c) ->
           Ok (fmt "%d.%d.%d (>= %d.%d.%d)" x y z a b c)
         | Some (x, y, z) ->
           Skip (fmt "%d.%d.%d below required %d.%d.%d" x y z a b c)
         | None -> Skip "unparseable version")
    | Pkg_config lib ->
      (match Proc.which "pkg-config" with
       | None -> Missing
       | Some _ ->
         let r = Proc.run "pkg-config" [ "--exists"; lib ] in
         if r.status = 0 then
           let v = Proc.run "pkg-config" [ "--modversion"; lib ] in
           Ok (first_line v.stdout)
         else Missing)
    | Brew formula ->
      (match Proc.which "brew" with
       | None -> Missing
       | Some _ ->
         let r = Proc.run "brew" [ "list"; "--versions"; formula ] in
         if r.status = 0 && String.trim r.stdout <> "" then
           Ok (first_line r.stdout)
         else Missing)
    | Any probes ->
      let rec go = function
        | [] -> Missing
        | p :: rest ->
          (match eval p with
           | Missing -> go rest
           | s -> s)
      in
      go probes

  let common =
    [ { c_name = "ocaml"; c_required = true;
        c_hint = "opam switch create 5.5.0";
        c_probe = Version_ok ("ocamlc", [ "-version" ], 5, 4, 0) };
      { c_name = "opam switch"; c_required = true;
        c_hint = "run inside `opam exec` or `eval $(opam env)`";
        c_probe = Cmd_ok ("opam", [ "switch"; "show" ]) };
      { c_name = "dune"; c_required = true;
        c_hint = "opam install dune";
        c_probe = Version_ok ("dune", [ "--version" ], 3, 17, 0) } ]

  let checks_for = function
    | Lui_pkg.Macos ->
      common
      @ [ { c_name = "sdl2"; c_required = true;
            c_hint = "brew install sdl2";
            c_probe = Any [ Pkg_config "sdl2"; Brew "sdl2" ] };
          { c_name = "sdl2_ttf"; c_required = true;
            c_hint = "brew install sdl2_ttf";
            c_probe = Any [ Pkg_config "SDL2_ttf"; Brew "sdl2_ttf" ] };
          { c_name = "codesign"; c_required = true;
            c_hint = "xcode-select --install";
            c_probe = On_path "codesign" };
          { c_name = "hdiutil"; c_required = true;
            c_hint = "part of macOS — reinstall the OS tools";
            c_probe = On_path "hdiutil" };
          { c_name = "xcrun"; c_required = true;
            c_hint = "xcode-select --install";
            c_probe = On_path "xcrun" };
          { c_name = "notarytool"; c_required = false;
            c_hint = "ships with Xcode — needed to notarize";
            c_probe = Cmd_ok ("xcrun", [ "notarytool"; "--version" ]) };
          { c_name = "iconutil"; c_required = false;
            c_hint = "part of Xcode — needed for .icns icons";
            c_probe = On_path "iconutil" };
          { c_name = "openssl"; c_required = false;
            c_hint = "needed for `lui keygen`";
            c_probe = On_path "openssl" } ]
    | Lui_pkg.Linux ->
      common
      @ [ { c_name = "cc"; c_required = true;
            c_hint = "apt install build-essential";
            c_probe = On_path "cc" };
          { c_name = "pkg-config"; c_required = true;
            c_hint = "apt install pkg-config";
            c_probe = On_path "pkg-config" };
          { c_name = "sdl2"; c_required = true;
            c_hint = "apt install libsdl2-dev";
            c_probe = Pkg_config "sdl2" };
          { c_name = "tar"; c_required = true;
            c_hint = "apt install tar";
            c_probe = On_path "tar" };
          { c_name = "dpkg-deb"; c_required = false;
            c_hint = "apt install dpkg — needed for --deb";
            c_probe = On_path "dpkg-deb" };
          { c_name = "appimagetool"; c_required = false;
            c_hint = "https://appimage.github.io/appimagetool/ — for --appimage";
            c_probe = On_path "appimagetool" };
          { c_name = "zstd"; c_required = false;
            c_hint = "apt install zstd — smaller tar artifacts";
            c_probe = On_path "zstd" };
          { c_name = "openssl"; c_required = false;
            c_hint = "needed for `lui keygen`";
            c_probe = On_path "openssl" } ]
    | Lui_pkg.Windows ->
      common
      @ [ { c_name = "mingw32-cc"; c_required = true;
            c_hint = "x86_64-w64-mingw32 toolchain";
            c_probe = On_path "x86_64-w64-mingw32-cc" };
          { c_name = "signtool"; c_required = false;
            c_hint = "Windows SDK — needed for --sign";
            c_probe = On_path "signtool" };
          { c_name = "makeappx"; c_required = false;
            c_hint = "Windows SDK — needed for --msix";
            c_probe = On_path "makeappx" };
          { c_name = "makensis"; c_required = false;
            c_hint = "NSIS — needed for --nsis";
            c_probe = On_path "makensis" };
          { c_name = "openssl"; c_required = false;
            c_hint = "needed for `lui keygen`";
            c_probe = On_path "openssl" } ]
    | Lui_pkg.Unknown _ -> common

  let report ?(platform = Lui_pkg.host_platform ()) () =
    log "lui doctor — %s/%s"
      (Lui_pkg.string_of_platform platform)
      (Lui_pkg.host_arch ());
    let missing = ref 0 in
    List.iter
      (fun c ->
         match eval c.c_probe with
         | Ok detail -> log "  OK       %-14s %s" c.c_name detail
         | Missing ->
           if c.c_required then begin
             incr missing;
             log "  MISSING  %-14s required — %s" c.c_name c.c_hint
           end
           else log "  SKIP     %-14s optional — %s" c.c_name c.c_hint
         | Skip why ->
           if c.c_required then begin
             incr missing;
             log "  MISSING  %-14s %s — %s" c.c_name why c.c_hint
           end
           else log "  SKIP     %-14s %s" c.c_name why)
      (checks_for platform);
    if !missing > 0 then begin
      err "%d required tool(s) missing" !missing;
      1
    end
    else begin
      log "all required tools present";
      0
    end

  let run () = report ()
end

(* {1 Sign} *)

module Sign = struct
  (* The raw key material of an Ed25519 PKCS8/SPKI blob is always its
     last 32 bytes; the rest is fixed ASN.1 framing around the
     1.3.101.112 OID (06 03 2b 65 70). *)
  let oid_ed25519 = "\x06\x03\x2b\x65\x70"

  let der_of_pem path =
    let s = Fs.read_file path in
    let body =
      String.split_on_char '\n' s
      |> List.filter (fun l ->
             String.length l > 0 && l.[0] <> '-' && l.[0] <> '\r')
      |> String.concat ""
    in
    match Lui_ed25519.decode_base64 body with
    | Some der when String.length der >= 32 -> Some der
    | _ -> None

  let is_ed25519 der =
    let ol = String.length oid_ed25519 and dl = String.length der in
    let rec go i =
      i + ol <= dl
      && (String.sub der i ol = oid_ed25519 || go (i + 1))
    in
    go 0

  let raw32 der = String.sub der (String.length der - 32) 32

  let run (s : Args.sign_spec) =
    match der_of_pem s.s_key with
    | None -> err "lui sign: %s is not a PEM key" s.s_key; 1
    | Some der ->
      if not (is_ed25519 der) then begin
        err "lui sign: %s is not an Ed25519 key" s.s_key;
        1
      end
      else
        let sk = raw32 der in
        let msg = Fs.read_file s.s_in in
        (match Lui_ed25519.sign ~sk ~msg with
         | None -> err "lui sign: bad seed in %s" s.s_key; 1
         | Some sig_ ->
           log "signature (hex):    %s" (Lui_ed25519.encode_hex sig_);
           log "signature (base64): %s" (Lui_ed25519.encode_base64 sig_);
           (match Lui_ed25519.public_key ~sk with
            | Some pk ->
              log "pubkey (hex):       %s" (Lui_ed25519.encode_hex pk);
              log "pubkey (base64):    %s"
                (Lui_ed25519.encode_base64 pk)
            | None -> ());
           0)
end

(* {1 Keygen} *)

module Keygen = struct
  let default_dir () =
    if Sys.win32 then
      match Sys.getenv_opt "APPDATA" with
      | Some d -> d / "lui" / "update-keys"
      | None -> "." / "lui" / "update-keys"
    else
      match Sys.getenv_opt "XDG_CONFIG_HOME" with
      | Some d -> d / "lui" / "update-keys"
      | None ->
        (match Sys.getenv_opt "HOME" with
         | Some h -> h / ".config" / "lui" / "update-keys"
         | None -> "." / "lui" / "update-keys")

  let commands ~alg ~priv ~pub =
    match alg with
    | Args.Ed25519 ->
      [ ("openssl", [ "genpkey"; "-algorithm"; "ed25519"; "-out"; priv ]);
        ("openssl", [ "pkey"; "-in"; priv; "-pubout"; "-out"; pub ]) ]
    | Rsa ->
      [ ("openssl",
         [ "genpkey"; "-algorithm"; "RSA"; "-pkeyopt";
           "rsa_keygen_bits:3072"; "-out"; priv ]);
        ("openssl", [ "pkey"; "-in"; priv; "-pubout"; "-out"; pub ]) ]

  let run (s : Args.keygen_spec) =
    let dir = if s.k_dir = "" then default_dir () else s.k_dir in
    let priv = dir / s.k_name ^ "-priv.pem"
    and pub = dir / s.k_name ^ "-pub.pem" in
    match Proc.which "openssl" with
    | None -> err "lui keygen: openssl not found — install openssl"; 1
    | Some _ ->
      if
        (Fs.exists priv || Fs.exists pub) && not s.k_force
      then begin
        err "lui keygen: %s already holds keys — pass --force to replace" dir;
        1
      end
      else begin
        Fs.mkdir_p ~perm:0o700 dir;
        let ok =
          List.for_all
            (fun (prog, args) ->
               let r = Proc.run prog args in
               if r.status <> 0 then begin
                 err "%s %s failed:\n%s" prog
                   (String.concat " " args) r.stderr;
                 false
               end
               else true)
            (commands ~alg:s.k_alg ~priv ~pub)
        in
        if not ok then 1
        else begin
          (try Unix.chmod priv 0o600 with Unix.Unix_error _ -> ());
          log "private key: %s   (signs update manifests — keep it secret)" priv;
          log "public key:  %s" pub;
          log "";
          (match s.k_alg with
           | Args.Ed25519 -> (
             match Sign.der_of_pem pub with
             | Some der when Sign.is_ed25519 der ->
               let pk_hex = Lui_ed25519.encode_hex (Sign.raw32 der) in
               log "pubkey (hex):  %s" pk_hex;
               log "";
               log "wire it into the update feed (platform/native/lui_updater):";
               log "  hand the pubkey to install/download as [pk], or export it:";
               log "    LUI_UPDATE_PUBKEY=%s" pk_hex;
               log "  sign each artifact's raw bytes:";
               log "    lui sign --key %s --in <artifact>" priv;
               log "  set the printed signature as \"signature\" on the";
               log "  artifact in <channel>.json."
             | _ ->
               log "wire it into the update feed: publish the raw";
               log "pubkey and sign artifacts with `lui sign`.")
           | Rsa ->
             log "note: Lui_updater verifies Ed25519 signatures;";
             log "regenerate with --alg ed25519 for the update feed.");
          0
        end
      end
end

(* {1 main} *)

let main argv =
  match Args.parse argv with
  | Error e ->
    err "lui: %s" e;
    err "run `lui help` for usage";
    2
  | Ok cmd ->
    (match cmd with
     | Args.Init s -> Init.run s
     | Dev s -> Dev.run s
     | Build s -> Build.run s
     | Package s -> Package.run s
     | Doctor -> Doctor.run ()
     | Keygen s -> Keygen.run s
     | Sign s -> Sign.run s
     | Version -> log "lui %s" version; 0
     | Help None -> print_string (Args.usage ^ "\n"); 0
     | Help (Some c) ->
       (match Args.usage_of c with
        | Some u -> print_string (u ^ "\n"); 0
        | None -> print_string (Args.usage ^ "\n"); 0))
