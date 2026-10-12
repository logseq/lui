(* lui_webapp test suite — spec JSON round-trips and errors, path
   handling, the prepared-plan checks, packaged-spec discovery in all
   three layouts, and the boot flow against a fake webview provider
   plus the real browser fallback. Pure OCaml; runs everywhere. *)

module W = Lui_webapp
module P = Lui_pkg.Private

let check = Alcotest.check
let ( / ) = Filename.concat

let pp_spec fmt s = Format.pp_print_string fmt (W.spec_to_string s)
let spec_t = Alcotest.testable pp_spec ( = )
let window_t = Alcotest.testable (fun fmt (w : W.window) ->
    Format.fprintf fmt "%dx%d r=%b min=%dx%d" w.width w.height
      w.resizable w.min_width w.min_height) ( = )
let perm_t = Alcotest.testable (fun fmt (p : W.permissions) ->
    Format.fprintf fmt "f=%b r=%b d=%b" p.file_access p.remote_content
      p.dev_tools) ( = )

let expect_ok = function
  | Ok v -> v
  | Error m -> Alcotest.fail ("expected Ok, got Error: " ^ m)

let expect_err = function
  | Error m -> m
  | Ok _ -> Alcotest.fail "expected Error, got Ok"

let tmp_dir () = P.Fs.temp_dir ~prefix:"lui-webapp-test-" ()

let sample =
  { W.app_id = "com.devin.sample";
    name = "Sample";
    version = "1.4.2";
    web_dir = "web";
    entry = "index.html";
    window =
      { width = 1280; height = 720; resizable = false;
        min_width = 640; min_height = 480 };
    icon = Some "icon.png";
    permissions =
      { file_access = true; remote_content = true; dev_tools = true } }

let write_web root =
  let web = root / "web" in
  P.Fs.mkdir_p (web / "js");
  P.Fs.write_file (web / "index.html") "<h1>hi</h1>";
  P.Fs.write_file (web / "js" / "app.js") "console.log(1)";
  web

let sample_json =
  {|{
  "app_id": "com.devin.sample", "name": "Sample", "version": "1.4.2",
  "web_dir": "web", "entry": "index.html",
  "window": {"width": 1280, "height": 720, "resizable": false,
             "min_width": 640, "min_height": 480},
  "icon": "icon.png",
  "permissions": {"file_access": true, "remote_content": true,
                  "dev_tools": true}}|}

let has_prefix s p =
  String.length s >= String.length p
  && String.sub s 0 (String.length p) = p

let contains s sub =
  let n = String.length sub and h = String.length s in
  let rec go i = i + n <= h && (String.sub s i n = sub || go (i + 1)) in
  h >= n && go 0

(** {1 Spec JSON} *)

let test_roundtrip () =
  let j = W.spec_to_json sample in
  check spec_t "json -> spec" sample (expect_ok (W.spec_of_json j));
  let s2 = expect_ok (W.spec_of_string sample_json) in
  check spec_t "string -> spec" sample s2;
  check spec_t "string round-trip" sample
    (expect_ok (W.spec_of_string (W.spec_to_string s2)))

let test_defaults () =
  let s =
    expect_ok
      (W.spec_of_string
         {|{"app_id":"a.b","name":"N","version":"0.0.1",
            "web_dir":"w","entry":"e.html"}|})
  in
  check window_t "window default" W.default_window s.window;
  check perm_t "permissions default" W.default_permissions s.permissions;
  check (Alcotest.option Alcotest.string) "no icon" None s.icon;
  (* partial window fields fill from defaults *)
  let s =
    expect_ok
      (W.spec_of_string
         {|{"app_id":"a.b","name":"N","version":"0.0.1",
            "web_dir":"w","entry":"e.html","window":{"width":333}}|})
  in
  check Alcotest.int "width override" 333 s.window.width;
  check Alcotest.int "height default" W.default_window.height
    s.window.height

let test_parse_errors () =
  let bad msg j =
    let m = expect_err (W.spec_of_string j) in
    check Alcotest.bool ("err: " ^ msg) true
      (String.length m > 0 && m <> "")
  in
  bad "not json" "{oops";
  bad "not object" "[1,2]";
  bad "missing app_id"
    {|{"name":"N","version":"1","web_dir":"w","entry":"e"}|};
  bad "wrong type"
    {|{"app_id":1,"name":"N","version":"1","web_dir":"w","entry":"e"}|};
  bad "bad window"
    {|{"app_id":"a","name":"N","version":"1","web_dir":"w",
       "entry":"e","window":"big"}|};
  bad "bad permissions"
    {|{"app_id":"a","name":"N","version":"1","web_dir":"w",
       "entry":"e","permissions":{"file_access":"yes"}}|};
  let m =
    expect_err
      (W.spec_of_string
         {|{"app_id":"a","name":"N","version":"1","web_dir":"w",
            "entry":"e","window":{"width":"wide"}}|})
  in
  check Alcotest.bool "names field" true
    (let needle = "width" in
     let n = String.length needle and h = String.length m in
     let rec go i =
       i + n <= h && (String.sub m i n = needle || go (i + 1))
     in
     go 0)

let test_validate () =
  let bad msg s =
    match W.validate s with
    | Error _ -> ()
    | Ok () -> Alcotest.fail ("accepted: " ^ msg)
  in
  bad "empty app_id" { sample with app_id = "" };
  bad "empty name" { sample with name = "" };
  bad "abs entry" { sample with entry = "/etc/passwd" };
  bad "escape .." { sample with entry = "../evil.html" };
  bad "deep escape" { sample with entry = "a/../../evil.html" };
  bad "zero width"
    { sample with window = { sample.window with width = 0 } };
  check (Alcotest.result Alcotest.unit Alcotest.string) "nested ok"
    (Ok ())
    (W.validate { sample with entry = "pages/deep/index.html" })

(** {1 Paths} *)

let test_paths () =
  let s = W.resolve ~base:"/pack" sample in
  check Alcotest.string "web_dir" ("/pack" / "web") s.web_dir;
  check (Alcotest.option Alcotest.string) "icon"
    (Some ("/pack" / "icon.png"))
    s.icon;
  check Alcotest.string "entry" ("/pack" / "web" / "index.html")
    (W.entry_path s);
  let s =
    W.resolve ~base:"/b"
      { sample with web_dir = "/abs/web"; icon = Some "/abs/i.png" }
  in
  (* "/abs/web" is absolute on POSIX but relative on Windows, where it
     is joined under the base. *)
  check Alcotest.string "abs stays"
    (if Filename.is_relative "/abs/web" then "/b" / "/abs/web"
     else "/abs/web")
    s.web_dir;
  check Alcotest.string "file url" "file:///pack/web/index.html"
    (W.file_url "/pack/web/index.html");
  check Alcotest.string "file url escaping"
    "file:///my%20app/web/a%2Bb.html"
    (W.file_url "/my app/web/a+b.html")

(** {1 Prepare} *)

let test_prepare () =
  let root = tmp_dir () in
  ignore (write_web root);
  let p = expect_ok (W.prepare ~base:root sample) in
  check Alcotest.string "url"
    (W.file_url (root / "web" / "index.html"))
    p.url;
  check Alcotest.string "entry" (root / "web" / "index.html")
    p.entry_file;
  ignore
    (expect_err
       (W.prepare ~base:root { sample with entry = "missing.html" }));
  ignore
    (expect_err
       (W.prepare ~base:root { sample with web_dir = "no-such" }));
  ignore
    (expect_err (W.prepare ~base:root { sample with app_id = "" }))

(** {1 Entry source} *)

let test_entry_source () =
  let root = tmp_dir () in
  (* UTF-8 with CJK + emoji and no charset meta: the bytes must reach
     the page verbatim as an Html source, so the engine decodes UTF-8
     instead of sniffing Latin-1 *)
  let utf8_page =
    "<h1>lui_webapp 冒烟 — 中文 🎉</h1><p>… — em dash</p>"
  in
  let f = root / "index.html" in
  P.Fs.write_file f utf8_page;
  (match W.entry_source f with
   | Ok (Lui_webview.Html (html, base)) ->
     check Alcotest.string "utf-8 verbatim" utf8_page html;
     check Alcotest.bool "base is dir file url" true
       (has_prefix base "file://" && String.get base (String.length base - 1) = '/'
        && contains base "index.html" = false);
   | Ok _ -> Alcotest.fail "utf-8 entry must load as Html"
   | Error e -> Alcotest.fail e);
  (* non-UTF-8 keeps the File source — engine sniffing handles legacy
     encodings *)
  let legacy = root / "legacy.html" in
  P.Fs.write_file legacy "<h1>\xff\xfe old</h1>";
  (match W.entry_source legacy with
   | Ok (Lui_webview.File p) ->
     check Alcotest.string "file path" legacy p
   | Ok _ -> Alcotest.fail "non-utf-8 entry must keep File source"
   | Error e -> Alcotest.fail e);
  ignore
    (expect_err (W.entry_source (root / "does-not-exist.html")))

(** {1 Spec files} *)

let test_spec_io () =
  let root = tmp_dir () in
  let p = root / "webapp.json" in
  check
    (Alcotest.result Alcotest.unit Alcotest.string)
    "write" (Ok ()) (W.write_spec sample p);
  check spec_t "read back" sample (expect_ok (W.read_spec p));
  ignore (expect_err (W.read_spec (root / "nope.json")));
  ignore (expect_err (W.read_spec root));
  P.Fs.write_file (root / "bad.json") "{not json";
  ignore (expect_err (W.read_spec (root / "bad.json")))

(** {1 Embedded-spec discovery} *)

let test_discovery () =
  let root = tmp_dir () in
  (* flat / windows-portable layout: webapp.json beside the exe *)
  let flat = root / "flat" in
  P.Fs.mkdir_p flat;
  P.Fs.write_file (flat / "app") "";
  P.Fs.write_file (flat / "webapp.json") "{}";
  check
    (Alcotest.option Alcotest.string)
    "flat" (Some (flat / "webapp.json"))
    (W.find_embedded_spec ~exe:(flat / "app"));
  (* macOS .app: Contents/MacOS/x -> ../Resources/webapp.json *)
  let mac = root / "Mac.app" / "Contents" in
  P.Fs.mkdir_p (mac / "MacOS");
  P.Fs.mkdir_p (mac / "Resources");
  P.Fs.write_file (mac / "MacOS" / "app") "";
  P.Fs.write_file (mac / "Resources" / "webapp.json") "{}";
  check
    (Alcotest.option Alcotest.string)
    "mac"
    (Some (mac / "MacOS" / ".." / "Resources" / "webapp.json"))
    (W.find_embedded_spec ~exe:(mac / "MacOS" / "app"));
  (* linux AppDir: usr/bin/x -> usr/share/<app>/webapp.json *)
  let appdir = root / "X.AppDir" in
  P.Fs.mkdir_p (appdir / "usr" / "bin");
  P.Fs.mkdir_p (appdir / "usr" / "share" / "xapp");
  P.Fs.write_file (appdir / "usr" / "bin" / "x") "";
  P.Fs.write_file
    (appdir / "usr" / "share" / "xapp" / "webapp.json")
    "{}";
  check
    (Alcotest.option Alcotest.string)
    "appdir"
    (Some (appdir / "usr" / "share" / "xapp" / "webapp.json"))
    (W.find_embedded_spec ~exe:(appdir / "usr" / "bin" / "x"));
  (* nothing there *)
  let empty = root / "empty" in
  P.Fs.mkdir_p empty;
  check
    (Alcotest.option Alcotest.string)
    "none" None
    (W.find_embedded_spec ~exe:(empty / "app"));
  (* candidates list always carries the two layout-agnostic probes *)
  let c = W.embedded_spec_candidates ~exe:"/a/b/x" in
  check Alcotest.bool "has flat probe" true
    (List.mem ("/a/b" / "webapp.json") c);
  check Alcotest.bool "has mac probe" true
    (List.mem ("/a/b" / ".." / "Resources" / "webapp.json") c)

(** {1 Boot} *)

let events = ref []

module Fake = struct
  type t = unit

  let create ~(window : W.window) ~title ~(permissions : W.permissions)
      =
    events :=
      [ Printf.sprintf "create %s %dx%d r=%b f=%b" title window.width
          window.height window.resizable permissions.file_access ];
    Ok ()

  let load_url () u =
    events := !events @ [ "load " ^ u ];
    Ok ()

  let eval () js = events := !events @ [ "eval " ^ js ]
  let set_message_handler () f =
    events := !events @ [ "handler" ];
    f {|{"from":"js"}|}

  let set_close_handler () _f = events := !events @ [ "close" ]
  let run () = events := !events @ [ "run" ]
  let close () = events := !events @ [ "close!" ]
end

let test_boot_webview () =
  let root = tmp_dir () in
  ignore (write_web root);
  events := [];
  let msgs = ref [] in
  let evals = ref [] in
  W.boot ~base:root ~webview:(module Fake : W.WEBVIEW)
    ~on_message:(fun m -> msgs := m :: !msgs)
    ~on_ready:(fun ~eval -> evals := [ eval "window.x=1" ])
    sample;
  let log = !events in
  check Alcotest.bool "create first" true
    (match log with e :: _ -> has_prefix e "create" | [] -> false);
  check Alcotest.bool "loads file url" true
    (List.exists (fun e -> has_prefix e "load file://") log);
  check Alcotest.bool "run last" true
    (match List.rev log with e :: _ -> e = "run" | [] -> false);
  check Alcotest.string "msg" {|{"from":"js"}|}
    (match !msgs with [ m ] -> m | _ -> "none");
  check Alcotest.bool "eval wired" true (!evals <> [])

let test_boot_fallback () =
  let root = tmp_dir () in
  ignore (write_web root);
  (* no provider, native shell bypassed, fallback off -> clear
     Failure *)
  (match
     try
       W.boot ~base:root ~native_shell:false ~fallback_browser:false
         sample;
       `Ran
     with Failure m -> `Failed m
   with
   | `Failed m ->
     check Alcotest.bool "names webview" true
       (let n = "webview" in
        let nl = String.length n and h = String.length m in
        let rec go i =
          i + nl <= h && (String.sub m i nl = n || go (i + 1))
        in
        h >= nl && go 0)
   | `Ran -> Alcotest.fail "boot without backend must fail");
  (* invalid spec -> Failure before any backend decision *)
  (match
     try
       W.boot ~base:root ~native_shell:false ~fallback_browser:false
         { sample with app_id = "" };
       `Ran
     with Failure _ -> `Failed ""
   with
   | `Failed _ -> ()
   | `Ran -> Alcotest.fail "invalid spec must fail")

(* The launcher's own CLI: argument errors, missing spec, and the
   --print-url surface, run against the real main.exe. *)

let cli_exe () = Filename.dirname Sys.executable_name / ".." / "main.exe"

(* Spawn the launcher directly: no [sh -c] indirection, whose quoting
   and path translation of a native Windows path is shell-dependent
   (a fresh Cygwin sh exits 127 on it). *)
let run_cli args =
  let r = P.Proc.run (cli_exe ()) args in
  (r.P.Proc.status, String.trim (r.P.Proc.stdout ^ r.P.Proc.stderr))

let test_cli_errors () =
  if Sys.file_exists (cli_exe ()) then begin
    let code, out = run_cli [ "--bogus" ] in
    check Alcotest.int "unknown option exits 2" 2 code;
    check Alcotest.bool "names the option" true
      (contains out "unknown option --bogus");
    let code, out = run_cli [ "/nonexistent/webapp.json" ] in
    check Alcotest.int "missing spec exits 2" 2 code;
    check Alcotest.bool "names the file" true
      (contains out "nonexistent")
  end

let test_cli_print_url () =
  if Sys.file_exists (cli_exe ()) then begin
    let root = tmp_dir () in
    let web = write_web root in
    let spec_json =
      Yojson.Safe.pretty_to_string
        (W.spec_to_json { sample with web_dir = web })
    in
    let spec_path = root / "webapp.json" in
    P.Fs.write_file spec_path spec_json;
    let code, out = run_cli [ "--print-url"; spec_path ] in
    check Alcotest.int "print-url exits 0" 0 code;
    check Alcotest.bool "prints file url" true
      (has_prefix out "file://")
  end

let test_backend_probe () =
  check Alcotest.bool "probe mirrors backend_name" true
    (W.Sdl_shell.available () = (Lui_webview.backend_name () <> "none"))

let test_browser_open () =
  let root = tmp_dir () in
  ignore (write_web root);
  let url = W.file_url (root / "web" / "index.html") in
  match Lui_pkg.host_platform (), W.open_in_browser url with
  | Lui_pkg.Macos, Ok () -> ()
  | Lui_pkg.Macos, Error m ->
    Alcotest.fail ("macOS open failed: " ^ m)
  | _, Ok () -> ()
  | _, Error m ->
    check Alcotest.bool "error explains" true (String.length m > 0)

let () =
  Alcotest.run "lui_webapp"
    [ ( "spec",
        [ Alcotest.test_case "json round-trip" `Quick test_roundtrip;
          Alcotest.test_case "defaults" `Quick test_defaults;
          Alcotest.test_case "parse errors" `Quick test_parse_errors;
          Alcotest.test_case "validate" `Quick test_validate ] );
      ( "paths",
        [ Alcotest.test_case "resolve/entry/file_url" `Quick
            test_paths ] );
      ( "prepare",
        [ Alcotest.test_case "prepare" `Quick test_prepare ] );
      ( "entry source",
        [ Alcotest.test_case "utf-8/legacy/missing" `Quick
            test_entry_source ] );
      ( "spec file",
        [ Alcotest.test_case "read/write" `Quick test_spec_io ] );
      ( "discovery",
        [ Alcotest.test_case "embedded spec" `Quick test_discovery ] );
      ( "boot",
        [ Alcotest.test_case "webview provider" `Quick
            test_boot_webview;
          Alcotest.test_case "fallback errors" `Quick
            test_boot_fallback;
          Alcotest.test_case "backend probe" `Quick test_backend_probe ] );
      ( "cli",
        [ Alcotest.test_case "arg errors" `Quick test_cli_errors;
          Alcotest.test_case "print url" `Quick test_cli_print_url ] );
      ( "browser",
        match Sys.getenv_opt "GITHUB_ACTIONS" with
        | Some _ ->
          (* open_in_browser spawns the OS browser; on headless CI
             sessions that blocks for minutes. *)
          []
        | None -> [ Alcotest.test_case "browser open" `Quick test_browser_open ] ) ]
