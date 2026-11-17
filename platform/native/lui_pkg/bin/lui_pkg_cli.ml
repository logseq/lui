(** lui_pkg — package a LUI native app: bundle, sign, notarize, dmg,
    and delta-update between versions.

    Notarization credentials always come from the environment or the
    keychain, never from the command line. *)

open Cmdliner

let ( let+ ) t f = Term.app (Term.const f) t
let ( and+ ) a b = Term.app (Term.app (Term.const (fun x y -> (x, y))) a) b

(** {1 Shared spec flags} *)

let spec_term ~need_exe =
  let name =
    Arg.(required
         & opt (some string) None
         & info [ "name" ] ~docv:"NAME" ~doc:"application name")
  in
  let bundle_id =
    Arg.(value & opt string ""
         & info [ "bundle-id" ] ~docv:"ID"
             ~doc:"CFBundleIdentifier, e.g. com.example.app")
  in
  let version =
    Arg.(required
         & opt (some string) None
         & info [ "version" ] ~docv:"VER" ~doc:"short version (semver)")
  in
  let build =
    Arg.(value & opt (some string) None
         & info [ "build" ] ~docv:"N" ~doc:"CFBundleVersion (default: version)")
  in
  let icon =
    Arg.(value & opt (some string) None
         & info [ "icon" ] ~docv:"PNG" ~doc:"source PNG for the app icon")
  in
  let executable =
    let i = Arg.info [ "exe" ] ~docv:"PATH" ~doc:"built binary to bundle" in
    if need_exe then Arg.(required & opt (some string) None & i)
    else Arg.(value & opt string "" & i)
  in
  let resources =
    Arg.(value
         & opt_all (pair ~sep:':' string string) []
         & info [ "resource" ] ~docv:"NAME:PATH"
             ~doc:"extra file/dir installed into Contents/Resources")
  in
  let entitlements =
    Arg.(value
         & opt_all string []
         & info [ "e"; "entitlement" ] ~docv:"KEY[=VALUE]"
             ~doc:"entitlement (no value means boolean true)")
  in
  let identity =
    Arg.(value & opt string "adhoc"
         & info [ "identity" ] ~docv:"CERT|adhoc"
             ~doc:"signing identity name, or adhoc")
  in
  let keychain_profile =
    Arg.(value & opt (some string) None
         & info [ "keychain-profile" ] ~docv:"NAME"
             ~doc:"notarytool keychain profile")
  in
  let keychain =
    Arg.(value & opt (some string) None
         & info [ "keychain" ] ~docv:"PATH" ~doc:"keychain for the profile")
  in
  let apple_id_env =
    Arg.(value & opt (some string) None
         & info [ "apple-id-env" ] ~docv:"VAR"
             ~doc:"env var holding the Apple id")
  in
  let password_env =
    Arg.(value & opt string "LUI_PKG_APPLE_PASSWORD"
         & info [ "password-env" ] ~docv:"VAR"
             ~doc:"env var holding the app-specific password")
  in
  let team_id =
    Arg.(value & opt string ""
         & info [ "team-id" ] ~docv:"TEAM" ~doc:"Apple team id")
  in
  let min_system =
    Arg.(value & opt string "11.0"
         & info [ "min-system" ] ~docv:"VER" ~doc:"LSMinimumSystemVersion")
  in
  let production =
    Arg.(value & flag
         & info [ "production" ]
             ~doc:"hardened runtime + secure timestamp for real identities")
  in
  let make name bundle_id version build icon executable resources ents ident
      kc_profile kc apple_id_env password_env team_id min_system production =
    let resources =
      List.map
        (fun (res_name, res_src) -> Lui_pkg.{ res_name; res_src })
        resources
    in
    let entitlements =
      List.map
        (fun s ->
           match String.index_opt s '=' with
           | None -> (s, Lui_pkg.P_bool true)
           | Some i ->
             (String.sub s 0 i,
              Lui_pkg.P_string (String.sub s (i + 1) (String.length s - i - 1))))
        ents
    in
    let identity =
      if ident = "adhoc" || ident = "-" then Lui_pkg.Adhoc
      else Lui_pkg.Certificate ident
    in
    let notarization =
      match kc_profile, apple_id_env with
      | Some profile, _ ->
        Some (Lui_pkg.Keychain_profile { profile; keychain = kc })
      | None, Some apple_id_var ->
        Some
          (Lui_pkg.Apple_id_env
             { apple_id_var; password_var = password_env; team_id })
      | None, None -> None
    in
    Lui_pkg.v_spec ~name ~bundle_id ~version ?build ?icon
      ~executable ~resources ~entitlements ~identity ?notarization
      ~min_system ~production ()
  in
  let+ name and+ bundle_id and+ version and+ build and+ icon
  and+ executable and+ resources and+ entitlements and+ identity
  and+ keychain_profile and+ keychain and+ apple_id_env
  and+ password_env and+ team_id and+ min_system and+ production in
  make name bundle_id version build icon executable resources entitlements
    identity keychain_profile keychain apple_id_env password_env team_id
    min_system production

(** {1 Outcomes} *)

let print_report o ~ok =
  match o with
  | Lui_pkg.Ok v -> Printf.printf "%s\n%!" (ok v); Cmdliner.Cmd.Exit.ok
  | Skipped m -> Printf.printf "skipped: %s\n%!" m; Cmdliner.Cmd.Exit.ok
  | Unsupported m ->
    Printf.eprintf "unsupported: %s\n%!" m; Cmdliner.Cmd.Exit.some_error
  | Failed f ->
    Printf.eprintf "failed: %s\n%!" (Lui_pkg.string_of_failure f);
    Cmdliner.Cmd.Exit.some_error

(** {1 Commands} *)

let bundle_cmd =
  let dir =
    Arg.(required
         & opt (some string) None
         & info [ "dir" ] ~docv:"DIR" ~doc:"output directory for the .app")
  in
  let run spec dir =
    print_report (Lui_pkg.bundle spec ~dir) ~ok:(fun p -> p)
  in
  Cmd.v
    (Cmd.info "bundle" ~doc:"assemble a .app around the executable")
    (let+ spec = spec_term ~need_exe:true and+ dir in run spec dir)

let sign_cmd =
  let app = Arg.(required & pos 0 (some string) None & info [] ~docv:"APP") in
  let run spec app =
    print_report (Lui_pkg.sign spec app) ~ok:(fun r ->
        Printf.sprintf "signed %d item(s); codesign -vvv: %s%s"
          (List.length r.Lui_pkg.signed)
          (if r.codesign_verify.tc_ok then "ok" else "FAILED")
          (match r.spctl with
           | Some s -> Printf.sprintf "; spctl: %s" (if s.tc_ok then "ok" else "rejected")
           | None -> ""))
  in
  Cmd.v
    (Cmd.info "sign" ~doc:"codesign a bundle (adhoc works anywhere)")
    (let+ spec = spec_term ~need_exe:false and+ app in run spec app)

let notarize_cmd =
  let path =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"DMG|ZIP|APP")
  in
  let run spec path =
    print_report (Lui_pkg.notarize spec path) ~ok:(fun r ->
        Printf.sprintf "status %s, stapled %b%s" r.Lui_pkg.nz_status
          r.nz_stapled
          (match r.nz_submission_id with
           | Some id -> " (submission " ^ id ^ ")"
           | None -> ""))
  in
  Cmd.v
    (Cmd.info "notarize"
       ~doc:"submit to the notary service and staple; skips without creds")
    (let+ spec = spec_term ~need_exe:false and+ path in run spec path)

let dmg_cmd =
  let app = Arg.(required & pos 0 (some string) None & info [] ~docv:"APP") in
  let dir =
    Arg.(required
         & opt (some string) None
         & info [ "dir" ] ~docv:"DIR" ~doc:"output directory for the image")
  in
  let run spec app dir =
    print_report (Lui_pkg.dmg spec app ~dir) ~ok:(fun p -> p)
  in
  Cmd.v
    (Cmd.info "dmg" ~doc:"create a disk image (zip when hdiutil is absent)")
    (let+ spec = spec_term ~need_exe:false and+ app and+ dir in
     run spec app dir)

let update_cmd =
  let from =
    Arg.(required & opt (some string) None
         & info [ "from" ] ~docv:"VER" ~doc:"version being updated")
  and to_ =
    Arg.(required & opt (some string) None
         & info [ "to" ] ~docv:"VER" ~doc:"target version")
  and old_dir =
    Arg.(required & opt (some string) None
         & info [ "old" ] ~docv:"DIR" ~doc:"tree of the 'from' version")
  and new_dir =
    Arg.(required & opt (some string) None
         & info [ "new" ] ~docv:"DIR" ~doc:"tree of the 'to' version")
  and out =
    Arg.(required & pos 0 (some string) None
         & info [] ~docv:"DELTA" ~doc:"delta file to write")
  in
  let run from to_ old_dir new_dir out =
    print_report
      (Lui_pkg.update_pkg ~from ~to_ ~old_dir ~new_dir out)
      ~ok:(fun () ->
        match Lui_pkg.delta_info out with
        | Ok (f, t, n) ->
          Printf.sprintf "%s (%s -> %s, %d entries)" out f t n
        | _ -> out)
  in
  Cmd.v
    (Cmd.info "update" ~doc:"write a delta update between two version trees")
    (let+ from and+ to_ and+ old_dir and+ new_dir and+ out in
     run from to_ old_dir new_dir out)

let apply_cmd =
  let delta =
    Arg.(required & pos 0 (some string) None & info [] ~docv:"DELTA")
  and from =
    Arg.(required & opt (some string) None & info [ "from" ] ~docv:"VER")
  and to_ =
    Arg.(required & opt (some string) None & info [ "to" ] ~docv:"VER")
  and old_dir =
    Arg.(required & opt (some string) None & info [ "old" ] ~docv:"DIR")
  and new_dir =
    Arg.(required & opt (some string) None & info [ "new" ] ~docv:"DIR")
  in
  let run delta from to_ old_dir new_dir =
    print_report
      (Lui_pkg.apply_delta ~delta ~from ~to_ ~old_dir ~new_dir)
      ~ok:(fun () -> Printf.sprintf "rebuilt %s at %s" to_ new_dir)
  in
  Cmd.v
    (Cmd.info "apply" ~doc:"verify and apply a delta update")
    (let+ delta and+ from and+ to_ and+ old_dir and+ new_dir in
     run delta from to_ old_dir new_dir)

let () =
  let info =
    Cmd.info "lui_pkg"
      ~doc:"package a LUI native app for distribution"
  in
  let cmds =
    [ bundle_cmd; sign_cmd; notarize_cmd; dmg_cmd; update_cmd; apply_cmd ]
  in
  exit (Cmd.eval' (Cmd.group info cmds))
