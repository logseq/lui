(* lui_pkg_windows test suite — pure generators run on every platform:
   manifest/appx/nsi text, the PE scanner, the PNG-in-ICO container,
   the zip writer/reader round-trip, the portable-dir layout, signing
   skip semantics, and a fabricated-app -> zip -> delta round-trip.
   Real tool invocations live in lui_pkg_windows_tools_test, gated to
   mingw64. No test-framework dependency: the default switch has none,
   so checks are plain assertions counted by this harness. *)

module L = Lui_pkg
module P = Lui_pkg.Private
module W = Lui_pkg_windows
module WP = Lui_pkg_windows.Private

(** {1 Tiny check harness} *)

let failures = ref 0
let total = ref 0

let ok name cond =
  incr total;
  if not cond then (
    incr failures;
    Printf.printf "FAIL %s\n%!" name)

let eq name ~expected ~got pp =
  incr total;
  if expected <> got then (
    incr failures;
    Printf.printf "FAIL %s\n  expected: %s\n  got:      %s\n%!" name
      (pp expected) (pp got))

let eqs name expected got = eq name ~expected ~got (fun s -> s)
let eqi name expected got = eq name ~expected ~got string_of_int

let eqo name expected got =
  eq name ~expected ~got (function
    | None -> "None"
    | Some s -> Printf.sprintf "Some %S" s)

let contains hay needle =
  let n = String.length needle and h = String.length hay in
  let rec go i = i + n <= h && (String.sub hay i n = needle || go (i + 1)) in
  go 0

let has name hay needle = ok name (contains hay needle)

let () =
  at_exit (fun () ->
      Printf.printf "%d checks, %d failures\n%!" !total !failures;
      if !failures > 0 then exit 1)

(** {1 Outcome helpers} *)

let show_outcome = function
  | L.Ok _ -> "Ok"
  | L.Skipped s -> "Skipped: " ^ s
  | L.Unsupported s -> "Unsupported: " ^ s
  | L.Failed f -> "Failed: " ^ L.string_of_failure f

(* Fatal: an outcome the test cannot continue past. *)
let fail s =
  incr failures;
  Printf.printf "FAIL %s\n%!" s;
  raise (Failure s)

let expect_ok o = match o with L.Ok v -> v | o -> fail (show_outcome o)

let tmp_dir () = P.Fs.temp_dir ~prefix:"lui-pkg-win-test-" ()

(** {1 Fixtures} *)

(* A tiny valid RGBA PNG written with the shared crc32/zlib. *)
let write_png path ~size =
  let be32 v = String.init 4 (fun i -> Char.chr ((v lsr (8 * (3 - i))) land 0xff)) in
  let chunk tag data =
    be32 (String.length data) ^ tag ^ data
    ^ be32 (Int32.to_int (P.Crc32.string (tag ^ data)))
  in
  let raw = Buffer.create (size * ((size * 4) + 1)) in
  for y = 0 to size - 1 do
    Buffer.add_char raw '\000';
    for x = 0 to size - 1 do
      Buffer.add_char raw (Char.chr ((x * 255) / max 1 (size - 1)));
      Buffer.add_char raw (Char.chr ((y * 255) / max 1 (size - 1)));
      Buffer.add_char raw (Char.chr 128);
      Buffer.add_char raw (Char.chr 255)
    done
  done;
  let png =
    "\137PNG\r\n\026\n"
    ^ chunk "IHDR" (be32 size ^ be32 size ^ "\008\006\000\000\000")
    ^ chunk "IDAT" (P.Deflate.zlib (Buffer.contents raw))
    ^ chunk "IEND" ""
  in
  P.Fs.write_file path png

(* A fake but structurally sound PE32+ image: MZ header with e_lfanew,
   PE signature, file header, and an optional header with 8 data
   directories whose certificate table (index 4) the caller controls. *)
let write_pe path ~signed =
  let b = Buffer.create 1024 in
  Buffer.add_string b "MZ";
  Buffer.add_string b (String.make 0x3a '\000');
  Buffer.add_string b "\x80\x00\x00\x00";
  Buffer.add_string b (String.make (0x80 - Buffer.length b) '\000');
  Buffer.add_string b "PE\000\000";
  Buffer.add_string b "\x64\x86";
  Buffer.add_string b "\x01\x00";
  Buffer.add_string b (String.make 12 '\000');
  Buffer.add_string b "\xf0\x00";
  Buffer.add_string b "\x22\x00";
  Buffer.add_string b "\x0b\x02";
  Buffer.add_string b (String.make (108 - 2) '\000');
  Buffer.add_string b "\x08\x00\x00\x00";
  Buffer.add_string b (String.make (4 * 8) '\000');
  if signed then Buffer.add_string b "\x00\x10\x00\x00\x38\x00\x00\x00"
  else Buffer.add_string b (String.make 8 '\000');
  Buffer.add_string b (String.make (3 * 8) '\000');
  P.Fs.write_file path (Buffer.contents b)

let base_spec ?(icon = None) ~executable () =
  L.v_spec ~name:"WinApp" ~bundle_id:"com.devin.winapp" ~version:"1.4.2"
    ~build:"42" ?icon ~executable
    ~doc_types:
      [
        { L.doc_name = None; role = "Editor"; extensions = [ "lui" ]; mime = [] };
      ]
    ~identity:L.Adhoc ()

(* A fabricated portable app tree: exe (fake PE), manifest, a dll and
   resources. *)
let make_app_dir root =
  let dir = Filename.concat root "app" in
  P.Fs.mkdir_p (Filename.concat dir "res");
  write_pe (Filename.concat dir "WinApp.exe") ~signed:false;
  P.Fs.write_file (Filename.concat dir "WinApp.exe.manifest") "<assembly/>\n";
  write_pe (Filename.concat dir "helper.dll") ~signed:false;
  P.Fs.write_file
    (Filename.concat dir "res/config.json")
    {|{"theme":"dark","font_size":13}|};
  P.Fs.write_file (Filename.concat dir "res/big.txt") (String.make 4096 'x');
  dir

(** {1 Tests} *)

let test_names () =
  let spec = base_spec ~executable:"x" () in
  eqs "portable dir" "WinApp-1.4.2-windows-x64"
    (W.portable_dir_name spec ~arch:"x64");
  eqs "zip" "WinApp-1.4.2-windows-x64.zip" (W.zip_name spec ~arch:"x64");
  eqs "msix" "WinApp-1.4.2-windows-x64.msix" (W.msix_name spec ~arch:"x64");
  eqs "installer" "WinApp Setup 1.4.2 x64.exe"
    (W.installer_name spec ~arch:"x64");
  eqs "format" "msix" (W.string_of_package_format W.Msix)

let test_version4 () =
  let open WP.Manifest in
  let check_v4 expected input =
    incr total;
    if version4 input <> expected then (
      incr failures;
      Printf.printf "FAIL version4 %S\n%!" input)
  in
  check_v4 (1, 4, 2, 0) "1.4.2";
  check_v4 (1, 0, 0, 0) "1";
  check_v4 (2, 3, 0, 0) "2.3-beta1";
  check_v4 (0, 0, 0, 0) "dev"

let test_manifest () =
  let spec = base_spec ~executable:"x" () in
  let m = W.manifest spec in
  List.iter
    (fun sub -> has ("manifest has " ^ sub) m sub)
    [
      "Microsoft.Windows.Common-Controls";
      "version=\"1.4.2.0\"";
      "com.devin.winapp";
      "PerMonitorV2";
      "true/pm";
      "UTF-8";
      "8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a";
      "manifestVersion=\"1.0\"";
    ]

let test_appx () =
  let spec = base_spec ~executable:"x" () in
  let m = W.appx_manifest spec ~arch:"x64" in
  List.iter
    (fun sub -> has ("appx has " ^ sub) m sub)
    [
      "ProcessorArchitecture=\"x64\"";
      "Version=\"1.4.2.0\"";
      "CN=WinApp";
      "WinApp.exe";
      "runFullTrust";
      "Windows.FullTrustApplication";
    ]

let test_nsis_script () =
  let base = tmp_dir () in
  let app = make_app_dir base in
  let spec = base_spec ~executable:"x" () in
  let s =
    W.nsis_script spec ~src:app ~out:"C:\\out\\setup.exe" ~arch:"x64"
  in
  List.iter
    (fun sub -> has ("nsi has " ^ sub) s sub)
    [
      "InstallDir \"$LOCALAPPDATA\\Programs\\WinApp\"";
      "RequestExecutionLevel user";
      "WinApp.exe";
      "Uninstall.exe";
      "com.devin.winapp";
      "Software\\Classes\\.lui";
      "File /r";
      "$SMPROGRAMS";
    ];
  P.Fs.rm_rf base

let test_pe () =
  let base = tmp_dir () in
  let unsigned = Filename.concat base "u.exe" in
  let signed = Filename.concat base "s.exe" in
  let txt = Filename.concat base "t.txt" in
  write_pe unsigned ~signed:false;
  write_pe signed ~signed:true;
  P.Fs.write_file txt "not a pe";
  ok "u is pe" (WP.Pe.is_pe unsigned);
  ok "u unsigned" (not (WP.Pe.is_signed unsigned));
  ok "s signed" (WP.Pe.is_signed signed);
  ok "txt not pe" (not (WP.Pe.is_pe txt));
  ok "missing not pe" (not (WP.Pe.is_pe (Filename.concat base "none.exe")));
  P.Fs.rm_rf base

let test_ico () =
  let base = tmp_dir () in
  let png = Filename.concat base "a.png" in
  write_png png ~size:32;
  (match WP.Ico.of_png (P.Fs.read_file png) with
   | L.Ok ico ->
     eqs "ico magic" "\x00\x00\x01\x00" (String.sub ico 0 4);
     eqi "count" 1 (Char.code ico.[4]);
     eqi "w" 32 (Char.code ico.[6]);
     eqi "h" 32 (Char.code ico.[7]);
     ok "png inside" (String.sub ico 22 8 = "\137PNG\r\n\026\n")
   | o -> fail ("Ico.of_png: " ^ show_outcome o));
  eq "png dims" ~expected:(Some (32, 32))
    ~got:(WP.Ico.png_dimensions (P.Fs.read_file png))
    (function None -> "None" | Some (w, h) -> Printf.sprintf "Some (%d,%d)" w h);
  (match WP.Ico.of_png "garbage" with
   | L.Ok _ -> fail "bad png accepted"
   | _ -> ());
  P.Fs.rm_rf base

let test_zip_roundtrip () =
  let base = tmp_dir () in
  let app = make_app_dir base in
  let z = Filename.concat base "app.zip" in
  WP.Zip.write_dir ~src:app ~out:z;
  let members = WP.Zip.list z in
  let names = List.map (fun (n, _, _) -> n) members in
  ok "exe present" (List.mem "WinApp.exe" names);
  ok "manifest present" (List.mem "WinApp.exe.manifest" names);
  ok "nested file" (List.mem "res/config.json" names);
  ok "dir entry" (List.mem "res/" names);
  let method_of n =
    List.find_map (fun (name, _, m) -> if name = n then Some m else None) members
  in
  eqo "big.txt deflates" (Some "8")
    (Option.map string_of_int (method_of "res/big.txt"));
  eqo "config back"
    (Some {|{"theme":"dark","font_size":13}|})
    (WP.Zip.extract z "res/config.json");
  eqo "missing" None (WP.Zip.extract z "nope");
  let dst = Filename.concat base "out" in
  P.Fs.mkdir_p dst;
  WP.Zip.extract_all ~src:z ~dst;
  eqs "exe identical"
    (P.Fs.read_file (Filename.concat app "WinApp.exe"))
    (P.Fs.read_file (Filename.concat dst "WinApp.exe"));
  eqs "config identical" {|{"theme":"dark","font_size":13}|}
    (P.Fs.read_file
       (Filename.concat (Filename.concat dst "res") "config.json"));
  P.Fs.rm_rf base

let test_zip_bad () =
  let base = tmp_dir () in
  let z = Filename.concat base "bad.zip" in
  P.Fs.write_file z "this is not a zip";
  (match WP.Zip.list z with
   | _ -> fail "non-zip listed"
   | exception WP.Zip.Bad _ -> ());
  P.Fs.rm_rf base

let test_powershell_zip_shape () =
  (* Compress-Archive interop is exercised on mingw64; here only that
     the fallback never crashes when powershell is absent. *)
  let base = tmp_dir () in
  (match WP.Ps_zip.compress_archive ~src:base ~out:(Filename.concat base "x.zip") with
   | L.Ok _ | L.Skipped _ -> ()
   | L.Failed f -> fail (L.string_of_failure f)
   | L.Unsupported s -> fail s);
  P.Fs.rm_rf base

let test_bundle () =
  let base = tmp_dir () in
  let exe = Filename.concat base "bin.exe" in
  let png = Filename.concat base "icon.png" in
  let res = Filename.concat base "res-src" in
  write_pe exe ~signed:false;
  write_png png ~size:16;
  P.Fs.mkdir_p res;
  P.Fs.write_file (Filename.concat res "data.bin") "payload";
  let spec =
    {
      (base_spec ~icon:(Some png) ~executable:exe ()) with
      L.resources = [ { L.res_name = "res"; res_src = res } ];
    }
  in
  let dir = Filename.concat base "dist" in
  P.Fs.mkdir_p dir;
  let app = expect_ok (W.bundle spec ~dir) in
  eqs "dir name"
    (Filename.concat dir "WinApp-1.4.2-windows-x64")
    app;
  ok "exe" (Sys.file_exists (Filename.concat app "WinApp.exe"));
  ok "manifest" (Sys.file_exists (Filename.concat app "WinApp.exe.manifest"));
  ok "ico" (Sys.file_exists (Filename.concat app "WinApp.ico"));
  ok "resource"
    (Sys.file_exists (Filename.concat (Filename.concat app "res") "data.bin"));
  P.Fs.rm_rf base

let test_bundle_bad_name () =
  let spec = { (base_spec ~executable:"/bin/echo" ()) with L.name = "a/b" } in
  (match W.bundle spec ~dir:"." with
   | L.Failed (L.Invalid _) -> incr total
   | o -> fail (show_outcome o));
  let spec = base_spec ~executable:"/nonexistent-exe" () in
  match W.bundle spec ~dir:"." with
  | L.Failed (L.Missing _) -> incr total
  | o -> fail (show_outcome o)

let test_sign_skips () =
  let base = tmp_dir () in
  let app = make_app_dir base in
  let spec = base_spec ~executable:"x" () in
  (match W.sign spec app with
   | L.Skipped s -> ok "adhoc reason" (String.length s > 0)
   | L.Failed (L.Missing _) -> () (* no signtool / no bundle on this host *)
   | o -> fail (show_outcome o));
  let spec = { spec with L.identity = L.Certificate "no-such-cert" } in
  (match W.sign spec app with
   | L.Skipped _ | L.Failed (L.Missing _) -> incr total
   | L.Ok _ -> incr total (* real signtool + cert materialized *)
   | L.Failed f -> fail (L.string_of_failure f)
   | L.Unsupported s -> fail s);
  P.Fs.rm_rf base

let test_cert_args () =
  let open WP.Sign in
  (match cert_args L.Adhoc with
   | Error (`Skipped _) -> incr total
   | _ -> fail "adhoc must skip");
  (match cert_args (L.Certificate "/definitely/not/here.pfx") with
   | Error (`Skipped _) -> incr total
   | _ -> fail "missing cert must skip");
  (match cert_args (L.Certificate "0123456789abcdef0123456789abcdef01234567") with
   | Stdlib.Ok [ "/sha1"; _ ] -> incr total
   | _ -> fail "thumbprint must resolve");
  match cert_args (L.Certificate "not a cert at all") with
  | Error (`Skipped _) -> incr total
  | _ -> fail "junk must skip"

let test_notarize () =
  let spec = base_spec ~executable:"x" () in
  match W.windows_packager.L.pkg_notarize spec "x.zip" with
  | L.Skipped _ -> incr total
  | o -> fail (show_outcome o)

(* The required end-to-end: two fabricated app trees, a delta written
   between them, the delta applied into a staging directory (the
   Windows file-lock discipline), and the staged tree verified byte
   for byte. *)
let test_zip_delta_roundtrip () =
  let base = tmp_dir () in
  let v1 = Filename.concat base "v1" and v2 = Filename.concat base "v2" in
  P.Fs.mkdir_p (Filename.concat v1 "res");
  P.Fs.mkdir_p (Filename.concat v2 "res");
  write_pe (Filename.concat v1 "WinApp.exe") ~signed:false;
  write_pe (Filename.concat v2 "WinApp.exe") ~signed:false;
  P.Fs.write_file
    (Filename.concat v1 "WinApp.exe.manifest")
    "<assembly version=\"1\" />\n";
  P.Fs.write_file
    (Filename.concat v2 "WinApp.exe.manifest")
    "<assembly version=\"2\" />\n";
  P.Fs.write_file (Filename.concat v1 "res/config.json") {|{"v":1}|};
  P.Fs.write_file (Filename.concat v2 "res/config.json") {|{"v":2}|};
  P.Fs.write_file (Filename.concat v1 "res/same.bin") (String.make 2048 's');
  P.Fs.write_file (Filename.concat v2 "res/same.bin") (String.make 2048 's');
  P.Fs.write_file (Filename.concat v2 "res/new.dat") "new payload";
  let spec = base_spec ~executable:"x" () in
  let dist = Filename.concat base "dist" in
  P.Fs.mkdir_p dist;
  let zip = expect_ok (W.package ~fmt:W.Zip spec v2 ~dir:dist) in
  ok "zip exists" (Sys.file_exists zip);
  ok "zip has exe"
    (List.exists (fun (n, _, _) -> n = "WinApp.exe") (WP.Zip.list zip));
  let delta = Filename.concat base "u.ludelta" in
  let _ =
    expect_ok (W.update_pkg ~from:"1.0" ~to_:"2.0" ~old_dir:v1 ~new_dir:v2 delta)
  in
  (match W.windows_packager.L.pkg_platform with
   | L.Windows -> incr total
   | _ -> fail "packager platform");
  (match L.delta_info delta with
   | L.Ok ("1.0", "2.0", n) -> ok "entries" (n > 0)
   | _ -> fail "delta_info");
  let install = Filename.concat base "installed" in
  P.Fs.mkdir_p install;
  P.Fs.install ~src:v1 ~dst:install;
  let stage = W.stage_dir_for install in
  eqs "stage name" "installed.update" (Filename.basename stage);
  let _ =
    expect_ok
      (W.apply_delta ~delta ~from:"1.0" ~to_:"2.0" ~old_dir:install
         ~new_dir:stage)
  in
  eqs "manifest updated"
    (P.Fs.read_file (Filename.concat v2 "WinApp.exe.manifest"))
    (P.Fs.read_file (Filename.concat stage "WinApp.exe.manifest"));
  eqs "config updated" {|{"v":2}|}
    (P.Fs.read_file
       (Filename.concat (Filename.concat stage "res") "config.json"));
  ok "new file"
    (Sys.file_exists
       (Filename.concat (Filename.concat stage "res") "new.dat"));
  eqs "unchanged identical"
    (P.Fs.read_file (Filename.concat v1 "res/same.bin"))
    (P.Fs.read_file (Filename.concat stage "res/same.bin"));
  P.Fs.rm_rf base

let () =
  test_names ();
  test_version4 ();
  test_manifest ();
  test_appx ();
  test_nsis_script ();
  test_pe ();
  test_ico ();
  test_zip_roundtrip ();
  test_zip_bad ();
  test_powershell_zip_shape ();
  test_bundle ();
  test_bundle_bad_name ();
  test_sign_skips ();
  test_cert_args ();
  test_notarize ();
  test_zip_delta_roundtrip ()
