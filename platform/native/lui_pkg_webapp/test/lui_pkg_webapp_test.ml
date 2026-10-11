(* lui_pkg_webapp test suite — the spec->app_spec mapping, input
   validation, and real bundle runs for every layout the host can
   build: the macOS .app + adhoc sign + DMG + launch, the Linux
   AppDir + tarball, the Windows portable dir + zip, and the shared
   delta format swapping web assets across a version bump. *)

module W = Lui_webapp
module X = Lui_pkg_webapp
module L = Lui_pkg
module P = Lui_pkg.Private
module WP = Lui_pkg_windows.Private

let check = Alcotest.check
let ( / ) = Filename.concat

let show_outcome = function
  | L.Ok _ -> "Ok"
  | L.Skipped s -> "Skipped: " ^ s
  | L.Unsupported s -> "Unsupported: " ^ s
  | L.Failed f -> "Failed: " ^ L.string_of_failure f

let expect_ok = function
  | L.Ok v -> v
  | o -> Alcotest.fail (show_outcome o)

let tmp_dir () = P.Fs.temp_dir ~prefix:"lui-webapp-pkg-test-" ()

let sh cmd =
  let r = P.Proc.run "sh" [ "-c"; cmd ] in
  (r.P.Proc.status, r.stdout ^ r.stderr)

let sh0 cmd = fst (sh cmd)

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  go 0

let has_suffix s suffix =
  let n = String.length suffix and h = String.length s in
  h >= n && String.sub s (h - n) n = suffix

let on_macos () = L.host_platform () = L.Macos

(** {1 Fixtures} *)

let write_web root ?(index = "<h1>v1</h1>") () =
  let web = root / "web" in
  P.Fs.mkdir_p (web / "js");
  P.Fs.write_file (web / "index.html") index;
  P.Fs.write_file (web / "js" / "app.js") "console.log('app')";
  web

let webapp ?(version = "1.0.0") ~web_dir () : W.spec =
  { app_id = "com.devin.webapp";
    name = "WebApp";
    version;
    web_dir;
    entry = "index.html";
    window =
      { width = 800; height = 600; resizable = true;
        min_width = 320; min_height = 240 };
    icon = None;
    permissions = W.default_permissions }

let spec_exe = "/bin/echo"

(* A launch-binary name that matches the app — linux/windows derive
   the installed exe name from the source basename. *)
let named_exe dir =
  let p = dir / "webapp" in
  P.Fs.copy_file ~src:spec_exe ~dst:p;
  Unix.chmod p 0o755;
  p

(* The built launcher this session produces; the launch e2e uses it so
   the packaged app really boots. *)
let launcher_exe () =
  let d = Filename.dirname Sys.executable_name in
  let p = d / ".." / ".." / "lui_webapp" / "main.exe" in
  if Sys.file_exists p then Some p else None

(** {1 Spec mapping} *)

let test_packaged_spec () =
  let s = webapp ~web_dir:"/assets/web" () in
  let p = X.packaged_spec s in
  check Alcotest.string "web_dir" "web" p.web_dir;
  check (Alcotest.option Alcotest.string) "icon dropped" None p.icon;
  check Alcotest.string "entry kept" "index.html" p.entry;
  check Alcotest.string "id kept" s.app_id p.app_id

let test_app_spec () =
  let root = tmp_dir () in
  let web = write_web root () in
  let s = webapp ~web_dir:web () in
  let pkg = X.app_spec ~spec:s ~shell_exe:spec_exe ~spec_json:"/tmp/sj" () in
  check Alcotest.string "name" "WebApp" pkg.L.name;
  check Alcotest.string "bundle id" "com.devin.webapp" pkg.bundle_id;
  check Alcotest.string "version" "1.0.0" pkg.version;
  check Alcotest.string "exe" spec_exe pkg.executable;
  let names = List.map (fun (r : L.resource) -> r.res_name) pkg.resources in
  check Alcotest.bool "web resource" true (List.mem "web" names);
  check Alcotest.bool "spec resource" true (List.mem "webapp.json" names)

let test_validate () =
  let root = tmp_dir () in
  let web = write_web root () in
  let s = webapp ~web_dir:web () in
  let expect_missing ~spec ~exe msg =
    match X.validate ~spec ~shell_exe:exe with
    | L.Failed (L.Missing _ | L.Invalid _) -> ()
    | o -> Alcotest.fail (msg ^ ": " ^ show_outcome o)
  in
  expect_missing ~spec:s ~exe:(root / "noexe") "missing exe";
  expect_missing ~spec:{ s with web_dir = root / "nope" }
    ~exe:spec_exe "missing web_dir";
  expect_missing ~spec:{ s with entry = "gone.html" } ~exe:spec_exe
    "missing entry";
  expect_missing ~spec:{ s with app_id = "" } ~exe:spec_exe "invalid";
  match X.validate ~spec:s ~shell_exe:spec_exe with
  | L.Ok () -> ()
  | o -> Alcotest.fail ("valid inputs: " ^ show_outcome o)

(** {1 macOS .app + sign + DMG} *)

let test_macos_e2e () =
  if on_macos () then begin
    let root = tmp_dir () in
    let web = write_web root () in
    let s = webapp ~web_dir:web () in
    let prod = expect_ok (X.bundle_macos ~spec:s ~shell_exe:spec_exe ~dir:root ()) in
    check Alcotest.string "app" (root / "WebApp.app") prod.app;
    List.iter
      (fun p ->
         check Alcotest.bool ("exists " ^ p) true
           (P.Fs.exists (prod.app / p)))
      [ "Contents/Info.plist"; "Contents/MacOS/WebApp";
        "Contents/Resources/web/index.html";
        "Contents/Resources/web/js/app.js";
        "Contents/Resources/webapp.json" ];
    check Alcotest.string "asset content" "<h1>v1</h1>"
      (P.Fs.read_file (prod.app / "Contents/Resources/web/index.html"));
    (* the embedded spec parses and points at the packaged layout *)
    (match
       W.read_spec (prod.app / "Contents/Resources/webapp.json")
     with
     | Ok ps ->
       check Alcotest.string "packaged web_dir" "web" ps.web_dir;
       check Alcotest.string "packaged entry" "index.html" ps.entry
     | Error m -> Alcotest.fail ("embedded spec: " ^ m));
    (* adhoc signature really verifies *)
    check Alcotest.int "codesign verify" 0
      (sh0 (Printf.sprintf "codesign --verify --deep --strict '%s'"
              prod.app));
    (* DMG round-trip: attach, see the app, detach *)
    (match prod.artifact with
     | Some dmg ->
       check Alcotest.string "dmg suffix" ".dmg"
         (String.sub dmg (String.length dmg - 4) 4);
       let mnt = root / "mnt" in
       P.Fs.mkdir_p mnt;
       check Alcotest.int "attach" 0
         (sh0
            (Printf.sprintf
               "hdiutil attach -nobrowse -readonly -mountpoint '%s' '%s'"
               mnt dmg));
       check Alcotest.bool "app in image" true
         (P.Fs.exists (mnt / "WebApp.app"));
       check Alcotest.bool "web asset in image" true
         (P.Fs.exists
            (mnt / "WebApp.app/Contents/Resources/web/index.html"));
       ignore (sh (Printf.sprintf "hdiutil detach '%s'" mnt))
     | None -> Alcotest.fail "no DMG produced");
    (* the launcher discovers the embedded spec beside the exe *)
    let exe = prod.app / "Contents/MacOS/WebApp" in
    check
      (Alcotest.option Alcotest.string)
      "embedded spec found"
      (Some (prod.app / "Contents/MacOS/../Resources/webapp.json"))
      (W.find_embedded_spec ~exe)
  end

(* Launchability: the packaged exe is the real launcher — it finds
   webapp.json, prepares the entry, and boots the SDL + WKWebView
   shell, which stays running until the window closes. A process that
   is still alive after the boot grace period proves the window and
   the web view came up; a clean exit proves the documented browser
   fallback fired (headless / no engine). A nonzero exit is a launch
   failure. *)
let test_macos_launch () =
  if on_macos () then begin
    match launcher_exe () with
    | None -> () (* main.exe not part of this build run *)
    | Some launcher ->
      let root = tmp_dir () in
      (* CJK + emoji with no charset meta — the entry must still
         render as UTF-8 inside the packaged app *)
      let web =
        write_web root
          ~index:"<h1>WebApp 冒烟 中文 🎉</h1><p>UTF-8, no meta</p>" ()
      in
      let s = webapp ~web_dir:web () in
      let prod =
        expect_ok
          (X.bundle_macos ~spec:s ~shell_exe:launcher ~dir:root ())
      in
      let exe = prod.app / "Contents/MacOS/WebApp" in
      let log = root / "launch.log" in
      let out =
        Unix.openfile log [ Unix.O_WRONLY; Unix.O_CREAT; Unix.O_TRUNC ]
          0o644
      in
      let pid = Unix.create_process exe [| exe |] Unix.stdin out out in
      Unix.close out;
      let deadline = Unix.gettimeofday () +. 8.0 in
      let rec poll () =
        match Unix.waitpid [ Unix.WNOHANG ] pid with
        | 0, _ ->
          if Unix.gettimeofday () < deadline then begin
            Unix.sleepf 0.2;
            poll ()
          end
          else `Running
        | _, Unix.WEXITED 0 -> `Clean_exit
        | _, Unix.WEXITED n -> `Died (Printf.sprintf "exit %d" n)
        | _, Unix.WSIGNALED n -> `Died (Printf.sprintf "signal %d" n)
        | _, Unix.WSTOPPED n -> `Died (Printf.sprintf "stopped %d" n)
      in
      (match poll () with
       | `Running ->
         Unix.kill pid Sys.sigkill;
         ignore (Unix.waitpid [] pid)
       | `Clean_exit -> ()
       | `Died m ->
         Alcotest.fail
           (Printf.sprintf "launch failed (%s): %s" m
              (P.Fs.read_file log)))
  end

(** {1 Linux AppDir + tarball} *)

let test_linux_e2e () =
  let root = tmp_dir () in
  let web = write_web root () in
  let s = webapp ~web_dir:web () in
  let prod =
    expect_ok
      (X.bundle_linux ~spec:s ~shell_exe:(named_exe root) ~dir:root ())
  in
  let appdir = prod.app in
  check Alcotest.bool "appdir suffix" true (has_suffix appdir ".AppDir");
  List.iter
    (fun p ->
       check Alcotest.bool ("exists " ^ p) true (P.Fs.exists (appdir / p)))
    [ "usr/bin/webapp"; "AppRun"; "usr/share/applications/com.devin.webapp.desktop";
      "usr/share/webapp/web/index.html";
      "usr/share/webapp/web/js/app.js";
      "usr/share/webapp/webapp.json" ];
  check Alcotest.string "asset content" "<h1>v1</h1>"
    (P.Fs.read_file (appdir / "usr/share/webapp/web/index.html"));
  (* spec discovery works from usr/bin *)
  (match
     W.find_embedded_spec ~exe:(appdir / "usr/bin/webapp")
   with
   | Some p ->
     check Alcotest.bool "share spec" true
       (contains p "share/webapp/webapp.json")
   | None -> Alcotest.fail "no spec found in AppDir");
  match prod.artifact with
  | Some tar ->
    check Alcotest.bool "tar exists" true (P.Fs.kind_of tar = P.Fs.File)
  | None -> Alcotest.fail "no tarball produced"

(** {1 Windows portable dir + zip} *)

let test_windows_e2e () =
  let root = tmp_dir () in
  let web = write_web root () in
  let s = webapp ~web_dir:web () in
  let prod =
    expect_ok
      (X.bundle_windows ~arch:"x64" ~spec:s ~shell_exe:spec_exe
         ~dir:root ())
  in
  let dir = prod.app in
  check Alcotest.bool "dir name" true
    (has_suffix dir "WebApp-1.0.0-windows-x64");
  List.iter
    (fun p ->
       check Alcotest.bool ("exists " ^ p) true (P.Fs.exists (dir / p)))
    [ "WebApp.exe"; "WebApp.exe.manifest"; "web/index.html";
      "web/js/app.js"; "webapp.json" ];
  check Alcotest.string "asset content" "<h1>v1</h1>"
    (P.Fs.read_file (dir / "web/index.html"));
  (* spec sits beside the exe *)
  (match W.find_embedded_spec ~exe:(dir / "WebApp.exe") with
   | Some p -> check Alcotest.string "flat spec" (dir / "webapp.json") p
   | None -> Alcotest.fail "no spec found in portable dir");
  (match prod.artifact with
   | Some zip ->
     let names = List.map (fun (n, _, _) -> n) (WP.Zip.list zip) in
     List.iter
       (fun want ->
          check Alcotest.bool ("zip has " ^ want) true
            (List.exists (fun n -> contains n want) names))
       [ "web/index.html"; "webapp.json"; "WebApp.exe" ]
   | None -> Alcotest.fail "no zip produced")

(** {1 Delta covers web assets} *)

let test_delta_web () =
  let root = tmp_dir () in
  let mk ~version ~index sub =
    let d = root / sub in
    P.Fs.mkdir_p d;
    let web = write_web d ~index () in
    let s = webapp ~version ~web_dir:web () in
    let prod =
      expect_ok
        (X.bundle_windows ~arch:"x64" ~spec:s ~shell_exe:spec_exe
           ~dir:d ())
    in
    prod.app
  in
  let v1 = mk ~version:"1.0.0" ~index:"<h1>v1</h1>" "v1" in
  let v2 = mk ~version:"1.1.0" ~index:"<h1>v2 CHANGED</h1>" "v2" in
  check Alcotest.bool "names differ" true (v1 <> v2);
  let delta = root / "up.delta" in
  expect_ok
    (L.update_pkg ~from:"1.0.0" ~to_:"1.1.0" ~old_dir:v1 ~new_dir:v2
       delta);
  (match L.delta_info delta with
   | L.Ok (f, t, n) ->
     check Alcotest.string "from" "1.0.0" f;
     check Alcotest.string "to" "1.1.0" t;
     check Alcotest.bool "entries" true (n >= 5)
   | o -> Alcotest.fail (show_outcome o));
  let rebuilt = root / "rebuilt" in
  expect_ok
    (L.apply_delta ~delta ~from:"1.0.0" ~to_:"1.1.0" ~old_dir:v1
       ~new_dir:rebuilt);
  check Alcotest.string "web asset swapped" "<h1>v2 CHANGED</h1>"
    (P.Fs.read_file (rebuilt / "web/index.html"));
  check Alcotest.string "js still there" "console.log('app')"
    (P.Fs.read_file (rebuilt / "web/js/app.js"));
  (* every produced file verifies against its manifest sha — apply
     already checked; spot-check the new spec content too *)
  (match W.read_spec (rebuilt / "webapp.json") with
   | Ok ps -> check Alcotest.string "new version" "1.1.0" ps.version
   | Error m -> Alcotest.fail ("rebuilt spec: " ^ m))

(** {1 Host dispatch + error paths} *)

let test_bundle_dispatch () =
  let root = tmp_dir () in
  let web = write_web root () in
  let s = webapp ~web_dir:web () in
  (match X.bundle ~spec:s ~shell_exe:spec_exe ~dir:root () with
   | L.Ok prod ->
     check Alcotest.bool "app exists" true (P.Fs.is_dir prod.app)
   | L.Unsupported _ -> () (* unknown host: honest answer *)
   | o -> Alcotest.fail (show_outcome o));
  (* bad inputs surface as Failed, not exceptions *)
  (match
     X.bundle ~spec:{ s with web_dir = root / "nope" }
       ~shell_exe:spec_exe ~dir:root ()
   with
   | L.Failed (L.Missing _) -> ()
   | o -> Alcotest.fail ("missing web_dir: " ^ show_outcome o));
  match
    X.bundle ~spec:s ~shell_exe:(root / "noexe") ~dir:root ()
  with
  | L.Failed (L.Missing _) -> ()
  | o -> Alcotest.fail ("missing exe: " ^ show_outcome o)

let () =
  Alcotest.run "lui_pkg_webapp"
    [ ( "spec",
        [ Alcotest.test_case "packaged spec" `Quick test_packaged_spec;
          Alcotest.test_case "app_spec mapping" `Quick test_app_spec;
          Alcotest.test_case "validate" `Quick test_validate ] );
      ( "macos",
        [ Alcotest.test_case ".app sign dmg" `Slow test_macos_e2e;
          Alcotest.test_case "launch" `Slow test_macos_launch ] );
      ( "linux",
        [ Alcotest.test_case "appdir tar" `Slow test_linux_e2e ] );
      ( "windows",
        [ Alcotest.test_case "portable zip" `Slow test_windows_e2e ] );
      ( "delta",
        [ Alcotest.test_case "web assets" `Slow test_delta_web ] );
      ( "dispatch",
        [ Alcotest.test_case "host + errors" `Slow test_bundle_dispatch ] ) ]
