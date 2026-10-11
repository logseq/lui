(* lui_cli test suite — hand-rolled argument parsing including error
   paths, the pure package-routing plan, the init scaffold (built for
   real with `dune build` in a temp dir), doctor probe evaluation and
   version math, the dev watcher's line classifier, and the keygen
   command list. No network. *)

module C = Lui_cli
module A = C.Args

let ( / ) = Filename.concat
let check = Alcotest.check
let string = Alcotest.string
let bool = Alcotest.bool
let int = Alcotest.int

let expect_ok = function Ok v -> v | Error e -> Alcotest.fail e
let expect_err = function Error e -> e | Ok _ -> Alcotest.fail "expected Error"

let parse args = A.parse args

(* {1 args} *)

let test_parse_meta () =
  (match parse [] with
   | Ok (A.Help None) -> ()
   | _ -> Alcotest.fail "bare argv should be Help None");
  (match parse [ "version" ] with
   | Ok A.Version -> ()
   | _ -> Alcotest.fail "version parses");
  (match parse [ "--version" ] with
   | Ok A.Version -> ()
   | _ -> Alcotest.fail "--version parses");
  (match parse [ "help"; "init" ] with
   | Ok (A.Help (Some "init")) -> ()
   | _ -> Alcotest.fail "help init");
  (match parse [ "version"; "extra" ] with
   | Error _ -> ()
   | _ -> Alcotest.fail "version rejects arguments")

let test_parse_init () =
  (match parse [ "init"; "--name"; "My App"; "--dir"; "apps/x"; "--force" ] with
   | Ok (A.Init { i_name = Some "My App"; i_dir = "apps/x";
                  i_force = true }) -> ()
   | _ -> Alcotest.fail "init flags");
  (match parse [ "init"; "apps/y" ] with
   | Ok (A.Init { i_dir = "apps/y"; i_name = None; i_force = false }) ->
     ()
   | _ -> Alcotest.fail "init positional dir");
  (match parse [ "init" ] with
   | Ok (A.Init { i_dir = "."; _ }) -> ()
   | _ -> Alcotest.fail "init defaults to cwd");
  ignore (expect_err (parse [ "init"; "a"; "b" ]));
  ignore (expect_err (parse [ "init"; "--bogus" ]));
  ignore (expect_err (parse [ "init"; "--name" ]))

let test_parse_dev_build () =
  (match parse [ "dev"; "app" ] with
   | Ok (A.Dev { d_dir = "app"; d_exe = "main.exe" }) -> ()
   | _ -> Alcotest.fail "dev positional");
  (match parse [ "dev"; "--exe"; "tool.exe"; "app" ] with
   | Ok (A.Dev { d_dir = "app"; d_exe = "tool.exe" }) -> ()
   | _ -> Alcotest.fail "dev --exe");
  (match parse [ "dev"; "a"; "b" ] with
   | Error _ -> ()
   | _ -> Alcotest.fail "dev rejects extra positionals");
  (match parse [ "build"; "app"; "--release" ] with
   | Ok (A.Build { b_dir = "app"; b_release = true }) -> ()
   | _ -> Alcotest.fail "build --release");
  (match parse [ "build"; "--bogus" ] with
   | Error _ -> ()
   | _ -> Alcotest.fail "build rejects unknown options")

let test_parse_package () =
  (match
     parse
       [ "package"; "app"; "--platform"; "linux"; "--deb"; "--out"; "out";
         "--sign"; "thumb"; "--webview"; "--no-build"; "--name"; "N";
         "--bundle-id"; "com.x.n"; "--version"; "2.0"; "--icon"; "i.png";
         "--exe"; "bin/x" ]
   with
   | Ok (A.Package
           { p_dir = "app"; p_platform = A.P_linux; p_format = A.F_deb;
             p_out = "out"; p_sign = Some "thumb"; p_webview = true;
             p_build = false; p_name = Some "N";
             p_bundle_id = Some "com.x.n"; p_version = Some "2.0";
             p_icon = Some "i.png"; p_exe = Some "bin/x" }) -> ()
   | _ -> Alcotest.fail "package full flag set");
  (match parse [ "package" ] with
   | Ok (A.Package { p_dir = "."; p_platform = A.P_auto;
                     p_format = A.F_auto; p_build = true;
                     p_webview = false; _ }) -> ()
   | _ -> Alcotest.fail "package defaults");
  ignore (expect_err (parse [ "package"; "--platform"; "amiga" ]));
  ignore (expect_err (parse [ "package"; "--dmg"; "--zip" ]));
  ignore (expect_err (parse [ "package"; "--sign" ]))

let test_parse_doctor_keygen () =
  (match parse [ "doctor" ] with
   | Ok A.Doctor -> ()
   | _ -> Alcotest.fail "doctor");
  (match parse [ "doctor"; "x" ] with
   | Error _ -> ()
   | _ -> Alcotest.fail "doctor takes no args");
  (match parse [ "keygen"; "--dir"; "k"; "--alg"; "rsa"; "--force" ] with
   | Ok (A.Keygen { k_dir = "k"; k_alg = A.Rsa; k_force = true; _ }) ->
     ()
   | _ -> Alcotest.fail "keygen flags");
  (match parse [ "keygen" ] with
   | Ok (A.Keygen { k_alg = A.Ed25519; k_force = false; _ }) -> ()
   | _ -> Alcotest.fail "keygen defaults");
  ignore (expect_err (parse [ "keygen"; "--alg"; "ecc" ]));
  ignore (expect_err (parse [ "keygen"; "pos" ]));
  ignore (expect_err (parse [ "frobnicate" ]))

let test_parse_platform () =
  check string "mac" "mac" (A.string_of_platform (expect_ok (A.parse_platform "mac")));
  check string "macos" "mac" (A.string_of_platform (expect_ok (A.parse_platform "macos")));
  check string "auto" "auto" (A.string_of_platform (expect_ok (A.parse_platform "auto")));
  ignore (expect_err (A.parse_platform "plan9"))

(* {1 package plan} *)

let test_plan () =
  let open C.Package in
  (match plan A.P_mac A.F_auto with
   | Ok { pk = Pk_macos; artifact = A_dmg } -> ()
   | _ -> Alcotest.fail "mac auto -> dmg");
  (match plan A.P_mac A.F_dmg with
   | Ok { pk = Pk_macos; artifact = A_dmg } -> ()
   | _ -> Alcotest.fail "mac --dmg");
  ignore (expect_err (plan A.P_mac A.F_zip));
  (match plan A.P_linux A.F_auto with
   | Ok { pk = Pk_linux; artifact = A_tar } -> ()
   | _ -> Alcotest.fail "linux auto -> tar");
  (match plan A.P_linux A.F_deb with
   | Ok { pk = Pk_linux; artifact = A_deb } -> ()
   | _ -> Alcotest.fail "linux --deb");
  (match plan A.P_linux A.F_appimage with
   | Ok { pk = Pk_linux; artifact = A_appimage } -> ()
   | _ -> Alcotest.fail "linux --appimage");
  ignore (expect_err (plan A.P_linux A.F_dmg));
  (match plan A.P_windows A.F_auto with
   | Ok { pk = Pk_windows; artifact = A_zip } -> ()
   | _ -> Alcotest.fail "windows auto -> zip");
  (match plan A.P_windows A.F_msix with
   | Ok { pk = Pk_windows; artifact = A_msix } -> ()
   | _ -> Alcotest.fail "windows --msix");
  (match plan A.P_windows A.F_nsis with
   | Ok { pk = Pk_windows; artifact = A_nsis } -> ()
   | _ -> Alcotest.fail "windows --nsis");
  ignore (expect_err (plan A.P_windows A.F_dmg));
  (* auto resolves to the host packager *)
  (match plan A.P_auto A.F_auto, Lui_pkg.host_platform () with
   | Ok { pk = Pk_macos; _ }, Lui_pkg.Macos -> ()
   | Ok { pk = Pk_linux; _ }, Lui_pkg.Linux -> ()
   | Ok { pk = Pk_windows; _ }, Lui_pkg.Windows -> ()
   | Ok _, _ -> Alcotest.fail "auto resolved to the wrong packager"
   | Error e, _ -> Alcotest.fail e)

(* {1 webview resources + spec} *)

let test_webview () =
  let dir = C.Fs.temp_dir ~prefix:"lui-cli-test-" () in
  (match C.Package.webview_resources ~dir ~webview:false with
   | Ok [] -> ()
   | _ -> Alcotest.fail "no webview flag, no resources");
  (match C.Package.webview_resources ~dir ~webview:true with
   | Error _ -> ()
   | _ -> Alcotest.fail "missing web/ must error");
  C.Fs.mkdir_p (Filename.concat dir "web");
  (match C.Package.webview_resources ~dir ~webview:true with
   | Ok [ { Lui_pkg.res_name = "web"; res_src } ]
     when res_src = Filename.concat dir "web" -> ()
   | _ -> Alcotest.fail "web/ becomes one 'web' resource");
  C.Fs.rm_rf dir

let test_spec_of () =
  let dir = C.Fs.temp_dir ~prefix:"lui-cli-test-" () in
  let s =
    { A.p_dir = dir; p_platform = A.P_auto; p_sign = None;
      p_format = A.F_auto; p_out = dir; p_webview = false;
      p_name = None; p_bundle_id = None; p_version = None;
      p_icon = None; p_exe = None; p_build = true }
  in
  let spec = C.Package.spec_of s ~exe:"/bin/x" ~resources:[] in
  check bool "exe" true (spec.Lui_pkg.executable = "/bin/x");
  check bool "version default" true (spec.Lui_pkg.version = "0.1.0");
  check bool "bundle id derived" true
    (String.length spec.Lui_pkg.bundle_id > 8
     && String.sub spec.Lui_pkg.bundle_id 0 8 = "app.lui.");
  check bool "adhoc identity" true (spec.Lui_pkg.identity = Lui_pkg.Adhoc);
  let s2 =
    { s with p_sign = Some "Developer ID Application: X";
             p_version = Some "9.9" }
  in
  let spec2 = C.Package.spec_of s2 ~exe:"/bin/x" ~resources:[] in
  check bool "cert identity" true
    (spec2.Lui_pkg.identity
     = Lui_pkg.Certificate "Developer ID Application: X");
  check string "version" "9.9" spec2.Lui_pkg.version;
  C.Fs.rm_rf dir

(* {1 init} *)

let test_sanitize () =
  let cases =
    [ ("My App!", "my-app"); ("app", "app"); ("  ", "app");
      ("A_B_C", "a-b-c"); ("-x-", "x"); ("Counter App", "counter-app") ]
  in
  List.iter
    (fun (inp, want) ->
       check string inp want (C.Init.sanitize_name inp))
    cases

let test_scaffold () =
  let dir = Filename.concat (C.Fs.temp_dir ~prefix:"lui-cli-test-" ()) "myapp" in
  let written =
    expect_ok
      (C.Init.scaffold ~dir ~name:(Some "My App") ~force:false)
  in
  check int "5 files" 5 (List.length written);
  check bool "main.ml mentions Lui_app" true
    (let body = C.Fs.read_file (Filename.concat dir "main.ml") in
     let needle = "Lui_app.create" in
     let rec find i =
       i + String.length needle <= String.length body
       && (String.sub body i (String.length needle) = needle
           || find (i + 1))
     in
     find 0);
  check bool "dune-project" true
    (C.Fs.read_file (Filename.concat dir "dune-project")
     = "(lang dune 3.17)\n");
  (* a second scaffold into the same non-empty dir refuses *)
  (match C.Init.scaffold ~dir ~name:None ~force:false with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "non-empty dir must refuse");
  (match C.Init.scaffold ~dir ~name:None ~force:true with
   | Ok _ -> ()
   | Error e -> Alcotest.fail e);
  (* a file at the target path errors *)
  let f = Filename.concat (C.Fs.temp_dir ~prefix:"lui-cli-test-" ()) "f" in
  C.Fs.write_file f "x";
  (match C.Init.scaffold ~dir:f ~name:None ~force:false with
   | Error _ -> ()
   | Ok _ -> Alcotest.fail "file target must error");
  C.Fs.rm_rf dir

(* The generated tree must actually build: `dune build` it inside the
   scaffolded temp dir. The scaffold links `lui` and `ocaml-signal` as
   public libraries, so it only builds where they are installed into the
   switch — e.g. `opam install .` after a clone. A plain deps-only
   switch (what `dune build @runtest` runs under in CI) cannot resolve
   them, and the build itself is skipped there. *)
let lib_installed pkg =
  match C.Proc.which "ocamlfind" with
  | None -> false
  | Some _ -> (C.Proc.run "ocamlfind" [ "query"; pkg ]).status = 0

let test_scaffold_builds () =
  match C.Proc.which "dune" with
  | None -> () (* no toolchain in this context — nothing to verify *)
  | Some _
    when not (lib_installed "lui" && lib_installed "ocaml-signal") ->
    () (* scaffold needs `lui` and `ocaml-signal` installed *)
  | Some _ ->
    let dir = Filename.concat (C.Fs.temp_dir ~prefix:"lui-cli-test-" ()) "app" in
    ignore (expect_ok (C.Init.scaffold ~dir ~name:None ~force:false));
    let cwd = Sys.getcwd () in
    Fun.protect
      ~finally:(fun () -> Unix.chdir cwd)
      (fun () ->
         Unix.chdir dir;
         let r = C.Proc.run "dune" [ "build" ] in
         check bool
           (Printf.sprintf "dune build scaffold (status %d): %s%s"
              r.status r.stdout r.stderr)
           true (r.status = 0);
         check bool "main.exe produced" true
           (C.Fs.exists "_build/default/main.exe");
         let run = C.Proc.run "./_build/default/main.exe" [] in
         check bool "app runs" true (run.status = 0);
         check bool "prints a frame" true
           (String.length run.stdout > 0
            && String.sub run.stdout 0 5 = "frame"));
    C.Fs.rm_rf dir

(* {1 doctor} *)

let test_parse_version () =
  let cases =
    [ ("5.5.0", Some (5, 5, 0)); ("4.14.1", Some (4, 14, 1));
      ("5.4", Some (5, 4, 0)); ("3.20.3~rc1", Some (3, 20, 3));
      ("abc", None); ("", None) ]
  in
  List.iter
    (fun (inp, want) ->
       let got =
         match C.Doctor.parse_version inp, want with
         | Some (a, b, c), Some (x, y, z) -> a = x && b = y && c = z
         | None, None -> true
         | _ -> false
       in
       check bool (Printf.sprintf "parse_version %S" inp) true got)
    cases

let test_version_at_least () =
  check bool "5.5.0 >= 5.4.0" true
    (C.Doctor.version_at_least (5, 5, 0) (5, 4, 0));
  check bool "4.14.1 < 5.4" true
    (not (C.Doctor.version_at_least (4, 14, 1) (5, 4, 0)));
  check bool "equal ok" true
    (C.Doctor.version_at_least (5, 4, 0) (5, 4, 0))

let test_doctor_probes () =
  let open C.Doctor in
  (match eval (On_path "sh") with
   | Ok _ -> ()
   | _ -> Alcotest.fail "sh should resolve");
  (match eval (On_path "lui-cli-definitely-missing") with
   | Missing -> ()
   | _ -> Alcotest.fail "missing tool");
  (match eval (Cmd_ok ("sh", [ "-c"; "echo probe-ok" ])) with
   | Ok "probe-ok" -> ()
   | Ok s -> Alcotest.fail s
   | _ -> Alcotest.fail "Cmd_ok echo");
  (match eval (Cmd_ok ("sh", [ "-c"; "exit 3" ])) with
   | Missing -> ()
   | _ -> Alcotest.fail "nonzero -> Missing");
  (match eval (Version_ok ("echo", [ "5.5.0" ], 5, 4, 0)) with
   | Ok _ -> ()
   | _ -> Alcotest.fail "echo version 5.5.0 should pass a 5.4 floor");
  (match eval (Version_ok ("echo", [ "3.0.0" ], 9, 0, 0)) with
   | Skip _ -> ()
   | _ -> Alcotest.fail "below-floor version should Skip");
  (match eval (Any [ On_path "nope-missing"; On_path "sh" ]) with
   | Ok _ -> ()
   | _ -> Alcotest.fail "Any falls through to the first hit");
  (* the check lists name the right tools per platform *)
  let names p = List.map (fun c -> c.c_name) (checks_for p) in
  check bool "common ocaml" true (List.mem "ocaml" (names Lui_pkg.Linux));
  check bool "mac codesign" true (List.mem "codesign" (names Lui_pkg.Macos));
  check bool "mac sdl2" true (List.mem "sdl2" (names Lui_pkg.Macos));
  check bool "linux pkg-config" true
    (List.mem "pkg-config" (names Lui_pkg.Linux));
  check bool "win mingw" true
    (List.mem "mingw32-cc" (names Lui_pkg.Windows))

(* {1 dev} *)

let test_classify () =
  let open C.Dev in
  check bool "success line" true
    (classify "Success, waiting for filesystem changes..." = Built);
  check bool "had errors" true
    (classify "Had 2 errors, waiting for filesystem changes..." = Broken);
  check bool "failed" true (classify "Failed to build the target" = Broken);
  check bool "info" true (classify "watching for changes" = Info);
  check string "exe path"
    ("d" / "_build" / "default" / "main.exe")
    (exe_path ~dir:"d" ~exe:"main.exe")

(* {1 build + keygen} *)

let test_build_args () =
  check bool "dev args" true (C.Build.dune_args ~release:false = [ "build" ]);
  check bool "release args" true
    (C.Build.dune_args ~release:true
     = [ "build"; "--profile"; "release" ])

let test_keygen_commands () =
  let open C.Keygen in
  let ed =
    commands ~alg:A.Ed25519 ~priv:"/k/priv.pem" ~pub:"/k/pub.pem" in
  check int "two commands" 2 (List.length ed);
  check bool "ed25519 genpkey" true
    (match ed with
     | ("openssl", args) :: _
       when List.mem "ed25519" args && List.mem "/k/priv.pem" args ->
       true
     | _ -> false);
  check bool "pubout second" true
    (match List.nth ed 1 with
     | "openssl", args ->
       List.mem "-pubout" args && List.mem "/k/pub.pem" args
     | _ -> false);
  let rsa = commands ~alg:A.Rsa ~priv:"/k/p" ~pub:"/k/q" in
  check bool "rsa bits" true
    (match rsa with
     | ("openssl", args) :: _ ->
       List.mem "RSA" args && List.mem "rsa_keygen_bits:3072" args
     | _ -> false)

(* {1 runner} *)

let () =
  Alcotest.run "lui_cli"
    [ ("args",
       [ Alcotest.test_case "meta" `Quick test_parse_meta;
         Alcotest.test_case "init" `Quick test_parse_init;
         Alcotest.test_case "dev+build" `Quick test_parse_dev_build;
         Alcotest.test_case "package" `Quick test_parse_package;
         Alcotest.test_case "doctor+keygen" `Quick test_parse_doctor_keygen;
         Alcotest.test_case "platform" `Quick test_parse_platform ]);
      ("package",
       [ Alcotest.test_case "plan" `Quick test_plan;
         Alcotest.test_case "webview" `Quick test_webview;
         Alcotest.test_case "spec" `Quick test_spec_of ]);
      ("init",
       [ Alcotest.test_case "sanitize" `Quick test_sanitize;
         Alcotest.test_case "scaffold" `Quick test_scaffold;
         Alcotest.test_case "scaffold builds" `Slow test_scaffold_builds ]);
      ("doctor",
       [ Alcotest.test_case "parse_version" `Quick test_parse_version;
         Alcotest.test_case "version_at_least" `Quick test_version_at_least;
         Alcotest.test_case "probes" `Quick test_doctor_probes ]);
      ("dev",
       [ Alcotest.test_case "classify" `Quick test_classify ]);
      ("build+keygen",
       [ Alcotest.test_case "dune_args" `Quick test_build_args;
         Alcotest.test_case "keygen cmds" `Quick test_keygen_commands ]) ]
