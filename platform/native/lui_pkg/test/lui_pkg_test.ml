(** lui_pkg test suite — pure-OCaml halves everywhere; the e2e group
    runs real codesign/hdiutil/ditto on macOS only and needs no
    credentials: adhoc signing works anywhere, notarization asserts the
    structured [Skipped]. *)

module L = Lui_pkg
module P = Lui_pkg.Private

let check = Alcotest.check
let string = Alcotest.string
let int = Alcotest.int
let bool = Alcotest.bool
let int32 = Alcotest.int32

let show_outcome = function
  | L.Ok _ -> "Ok"
  | Skipped s -> "Skipped: " ^ s
  | Unsupported s -> "Unsupported: " ^ s
  | Failed f -> "Failed: " ^ L.string_of_failure f

let expect_ok o =
  match o with L.Ok v -> v | o -> Alcotest.fail (show_outcome o)

let tmp_dir () = P.Fs.temp_dir ~prefix:"lui-pkg-test-" ()

let sh cmd =
  let r = P.Proc.run "sh" [ "-c"; cmd ] in
  (r.P.Proc.status, r.stdout ^ r.stderr)

let sh0 cmd = fst (sh cmd)

let on_macos () = L.host_platform () = L.Macos

(** {1 Fixtures} *)

let base_spec ?(icon = None) ~executable () =
  L.v_spec ~name:"PkgTest" ~bundle_id:"com.devin.pkgtest"
    ~version:"1.2.3" ?icon ~executable
    ~entitlements:[ ("com.apple.security.cs.disable-library-validation",
                     L.P_bool true) ]
    ~identity:L.Adhoc ~min_system:"12.0" ()

(** A tiny valid RGBA PNG written with our own crc32/zlib. *)
let write_png path ~size =
  let be32 v =
    String.init 4 (fun i -> Char.chr ((v lsr (8 * (3 - i))) land 0xff))
  in
  let chunk tag data =
    be32 (String.length data) ^ tag ^ data
    ^ be32 (Int32.to_int (P.Crc32.string (tag ^ data)))
  in
  let raw = Buffer.create (size * (size * 4 + 1)) in
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

let spec_exe = "/bin/echo"

let make_trees base =
  let old_d = Filename.concat base "old" and new_d = Filename.concat base "new" in
  P.Fs.mkdir_p (Filename.concat old_d "dir");
  P.Fs.mkdir_p (Filename.concat new_d "dir");
  P.Fs.write_file (Filename.concat old_d "a.txt") "version one\n";
  P.Fs.write_file (Filename.concat new_d "a.txt") "version two, slightly longer\n";
  P.Fs.write_file (Filename.concat old_d "dir/b.txt") "unchanged body\n";
  P.Fs.write_file (Filename.concat new_d "dir/b.txt") "unchanged body\n";
  P.Fs.write_file (Filename.concat old_d "oldpath.txt") "content that moved\n";
  P.Fs.write_file (Filename.concat new_d "newpath.txt") "content that moved\n";
  P.Fs.write_file (Filename.concat new_d "new.txt") "brand new file\n";
  P.Fs.write_file ~perm:0o755 (Filename.concat new_d "run.sh") "#!/bin/sh\nexit 0\n";
  (old_d, new_d)

let same_tree a b =
  let wa = P.Fs.walk a and wb = P.Fs.walk b in
  let files l =
    List.filter_map
      (fun (rel, k) -> match k with P.Fs.File -> Some rel | _ -> None)
      l
  in
  let fa = List.sort compare (files wa) and fb = List.sort compare (files wb) in
  check (Alcotest.list string) "same files" fa fb;
  List.iter
    (fun rel ->
       let sha p = P.Sha256.file p in
       check string ("content " ^ rel)
         (sha (Filename.concat a rel))
         (sha (Filename.concat b rel)))
    fa

(** {1 Pure units} *)

let test_sha256 () =
  check string "empty"
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    (P.Sha256.string "");
  check string "abc"
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    (P.Sha256.string "abc");
  check string "fox"
    "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
    (P.Sha256.string "The quick brown fox jumps over the lazy dog");
  (* streaming vs one-shot *)
  let data = String.make 100_000 'x' in
  let d = tmp_dir () in
  let p = Filename.concat d "x.bin" in
  P.Fs.write_file p data;
  check string "file == string" (P.Sha256.string data) (P.Sha256.file p)

let test_crc () =
  check int32 "crc32" 0xcbf43926l (P.Crc32.string "123456789");
  check int32 "adler32" 0x11e60398l (P.Adler32.string "Wikipedia")

let test_varint () =
  let rt v =
    let b = Buffer.create 8 in
    P.Varint.append_uvarint b v;
    match P.Varint.uvarint (Buffer.contents b) 0 with
    | Some (got, next) ->
      check int "uvarint value" v got;
      check int "uvarint length" (String.length (Buffer.contents b)) next
    | None -> Alcotest.fail "uvarint decode failed"
  in
  List.iter rt [ 0; 1; 127; 128; 255; 300; 16383; 16384; 1 lsl 30 ];
  let rt v =
    let b = Buffer.create 8 in
    P.Varint.append_varint b v;
    match P.Varint.varint (Buffer.contents b) 0 with
    | Some (got, _) -> check int "svarint value" v got
    | None -> Alcotest.fail "svarint decode failed"
  in
  List.iter rt [ 0; 1; -1; 63; -64; 300; -300; 1 lsl 29; -(1 lsl 29) ]

let pseudo_random n =
  let b = Bytes.create n in
  let state = ref 0x9e3779b9 in
  for i = 0 to n - 1 do
    state := (!state * 1103515245 + 12345) land 0x7fffffff;
    Bytes.set b i (Char.chr ((!state lsr 8) land 0xff))
  done;
  Bytes.unsafe_to_string b

let test_deflate () =
  let cases =
    [
      ("empty", "");
      ("one", "x");
      ("short", "hello world");
      ("repetitive", String.make 70_000 'z');
      ("binary", String.init 256 Char.chr ^ String.init 256 Char.chr);
      ("random", pseudo_random 200_000);
    ]
  in
  List.iter
    (fun (name, data) ->
       check string ("roundtrip " ^ name) data
         (P.Deflate.inflate (P.Deflate.deflate data)))
    cases;
  let z = P.Deflate.zlib "payload" in
  check bool "zlib magic" true (z.[0] = '\x78' && z.[1] = '\x9c')

let test_bsdiff () =
  let cases =
    [
      ("", "");
      ("", "entirely new");
      ("some old content", "");
      ("the quick brown fox", "the quick red fox");
      ("aaaa bbbb cccc dddd", "zzzz aaaa bbbb cccc dddd yyyy");
      (pseudo_random 50_000, pseudo_random 50_000);
      (String.make 300 'a' ^ "needle" ^ String.make 300 'b',
       String.make 300 'a' ^ String.make 60 'X' ^ "needle" ^ String.make 300 'b');
    ]
  in
  List.iteri
    (fun i (o, n) ->
       let patch = P.Bsdiff.diff o n in
       let got = P.Bsdiff.patch ~old_data:o ~patch_data:patch (String.length n) in
       check string (Printf.sprintf "case %d" i) n got)
    cases

let collect_keys xml =
  let lines = String.split_on_char '\n' xml in
  List.filter_map
    (fun l ->
       let l = String.trim l in
       if String.length l > 5 && String.sub l 0 5 = "<key>" then
         Some
           (String.sub l 5
              (String.length l - 5 - String.length "</key>"))
       else None)
    lines

let test_plist_xml () =
  let spec = base_spec ~executable:spec_exe () in
  let xml = P.Info_plist.plist spec ~exe_name:"PkgTest" ~icon_name:(Some "AppIcon.icns") in
  let keys = collect_keys xml in
  check bool "keys sorted" true (List.sort compare keys = keys);
  let has k = List.mem k keys in
  List.iter
    (fun k -> check bool ("has " ^ k) true (has k))
    [
      "CFBundleIdentifier"; "CFBundleExecutable"; "CFBundleIconFile";
      "CFBundleName"; "CFBundlePackageType"; "CFBundleShortVersionString";
      "CFBundleVersion"; "NSPrincipalClass"; "NSHighResolutionCapable";
      "NSSupportsAutomaticGraphicsSwitching"; "LSMinimumSystemVersion";
    ];
  check bool "principal class" true
    (P.Dmg.contains_sub xml "<key>NSPrincipalClass</key>\n    <string>NSApplication</string>"
     || P.Dmg.contains_sub xml "<key>NSPrincipalClass</key><string>NSApplication</string>"
     || P.Dmg.contains_sub xml "NSApplication");
  let spec2 =
    L.v_spec ~name:"U" ~bundle_id:"b" ~version:"1.0" ~executable:spec_exe
      ~url_schemes:[ "myscheme" ]
      ~doc_types:[ { L.doc_name = None; role = "Viewer";
                     extensions = [ "md"; "txt" ]; mime = [ "text/plain" ] } ]
      ()
  in
  let xml2 = P.Info_plist.plist spec2 ~exe_name:"U" ~icon_name:None in
  check bool "url schemes" true (P.Dmg.contains_sub xml2 "myscheme");
  check bool "doc types" true (P.Dmg.contains_sub xml2 "CFBundleDocumentTypes");
  check bool "doc ext" true (P.Dmg.contains_sub xml2 "<string>md</string>");
  check bool "no icon key" false (P.Dmg.contains_sub xml2 "CFBundleIconFile")

let test_plist_binary () =
  let data =
    P.Plist.binary [ ("Name", L.P_string "v"); ("Num", L.P_int 42);
                     ("On", L.P_bool true) ]
  in
  check string "magic" "bplist00" (String.sub data 0 8);
  check bool "non-empty" true (String.length data > 32)

let test_ds_store () =
  let d = P.Ds_store.dmg_store "PkgTest.app" in
  (* a .DS_Store opens with a 4-byte alignment count, then "Bud1" *)
  check string "magic" "Bud1" (String.sub d 4 4);
  check int "size" (4 + 0x4000) (String.length d)

let test_codesign_args () =
  let adhoc =
    P.Sign.codesign_args ~identity:L.Adhoc ~entitlements:None ~production:true
      "/x.app"
  in
  check bool "adhoc signs" true (List.mem "-" adhoc);
  check bool "adhoc deep" true (List.mem "--deep" adhoc);
  check bool "adhoc no runtime" false (List.mem "--options" adhoc);
  let prod =
    P.Sign.codesign_args ~identity:(L.Certificate "Dev ID")
      ~entitlements:(Some "/e.plist") ~production:true "/x.app"
  in
  check bool "cert name" true (List.mem "Dev ID" prod);
  check bool "runtime" true (List.mem "--options" prod && List.mem "runtime" prod);
  check bool "timestamp" true (List.mem "--timestamp" prod);
  check bool "entitlements" true (List.mem "--entitlements" prod);
  let nested =
    P.Sign.nested_args ~identity:L.Adhoc ~entitlements:None ~production:false
  in
  check bool "nested no deep" false (List.mem "--deep" nested);
  check bool "nested preserve" true
    (List.mem "--preserve-metadata=entitlements" nested)

let test_notarize_creds () =
  (match P.Notarize.creds_args None with
   | Error `No_creds -> ()
   | _ -> Alcotest.fail "no creds should be No_creds");
  (match
     P.Notarize.creds_args
       (Some (L.Keychain_profile { profile = "prof"; keychain = None }))
   with
   | Ok args -> check bool "profile args" true (List.mem "prof" args)
   | Error _ -> Alcotest.fail "keychain profile should resolve");
  let nz =
    L.Apple_id_env
      { apple_id_var = "LUI_PKG_TEST_UNSET_ID";
        password_var = "LUI_PKG_TEST_UNSET_PW"; team_id = "TEAM" }
  in
  (match P.Notarize.creds_args (Some nz) with
   | Error (`Missing_env vars) ->
     check bool "both vars" true
       (List.mem "LUI_PKG_TEST_UNSET_ID" vars
        && List.mem "LUI_PKG_TEST_UNSET_PW" vars)
   | _ -> Alcotest.fail "unset env should be Missing_env");
  Unix.putenv "LUI_PKG_TEST_ID" "me@example.com";
  Unix.putenv "LUI_PKG_TEST_PW" "xxxx-yyyy";
  (match
     P.Notarize.creds_args
       (Some
          (L.Apple_id_env
             { apple_id_var = "LUI_PKG_TEST_ID";
               password_var = "LUI_PKG_TEST_PW"; team_id = "TEAM" }))
   with
   | Ok args ->
     check bool "apple id resolved" true
       (List.mem "me@example.com" args && List.mem "TEAM" args)
   | Error _ -> Alcotest.fail "env creds should resolve")

let test_parse_submission () =
  let sample =
    "Conducting pre-submission checks for dmg.\n\
     Initiating upload...\n\
     {\"id\":\"aa-bb-cc\",\"status\":\"Accepted\",\"message\":\"ok\"}\n"
  in
  let id, status, _ = P.Notarize.parse_submission sample in
  check string "id" "aa-bb-cc" id;
  check string "status" "Accepted" status

let test_dmg_names () =
  let spec = base_spec ~executable:spec_exe () in
  check string "dmg name" "PkgTest 1.2.3 arm64.dmg"
    (P.Dmg.dmg_name spec ~arch:"arm64");
  check string "dmg name universal" "PkgTest 1.2.3.dmg"
    (P.Dmg.dmg_name spec ~arch:"universal");
  check string "fs_name" "a-b" (P.Dmg.fs_name "a/b");
  check bool "busy" true (P.Dmg.hdiutil_busy "hdiutil: create: Resource busy");
  check bool "not busy" false (P.Dmg.hdiutil_busy "all good");
  check bool "contains" true (P.Dmg.contains_sub "hello world" "lo wo");
  check bool "not contains" false (P.Dmg.contains_sub "hi" "long")

let test_delta_relpath () =
  let good = [ "a"; "a/b.txt"; "Contents/MacOS/x"; "a.b/c-d_e f" ] in
  let bad = [ ""; "/abs"; "a//b"; "../up"; "a/../b"; "a/./b"; ".";
              "\\win"; "a/../../b" ]
  in
  List.iter (fun p -> check bool ("ok " ^ p) true (P.Delta.valid_rel_path p)) good;
  List.iter (fun p -> check bool ("bad " ^ p) false (P.Delta.valid_rel_path p)) bad

let test_delta_manifest () =
  let base = tmp_dir () in
  let old_d, new_d = make_trees base in
  let out = Filename.concat base "u.delta" in
  let entries =
    P.Delta.write ~from:"1.0" ~to_:"1.1" ~old_dir:old_d ~new_dir:new_d out
  in
  let find p = List.find_opt (fun e -> e.P.Delta.path = p) entries in
  (* unchanged file: copy *)
  (match find "dir/b.txt" with
   | Some e ->
     check string "copy from" "dir/b.txt" e.from;
     check int "copy data" 0 e.data
   | None -> Alcotest.fail "b.txt missing");
  (* moved content: from = old path *)
  (match find "newpath.txt" with
   | Some e -> check string "moved from" "oldpath.txt" e.from
   | None -> Alcotest.fail "newpath.txt missing");
  (* new file: blob *)
  (match find "new.txt" with
   | Some e ->
     check string "new from" "" e.from;
     check bool "new data" true (e.data > 0)
   | None -> Alcotest.fail "new.txt missing");
  (* index parses back *)
  let data = P.Fs.read_file out in
  let f, t, es, _ = P.Delta.parse_index data in
  check string "from" "1.0" f;
  check string "to" "1.1" t;
  check int "entries" (List.length entries) (List.length es);
  (* index check accepts our own output *)
  let _, _, es, data_start = P.Delta.parse_index data in
  P.Delta.check_index es ~data_start ~size:(String.length data);
  (* corrupt: a file entry with no data and no source *)
  let bad =
    { P.Delta.path = "ghost"; dir = false; link = ""; mode = 0;
      size = 1; sha256 = "ab"; from = ""; data = 0 }
  in
  (match
     try P.Delta.check_index (bad :: es) ~data_start ~size:(String.length data); false
     with P.Delta.Damaged _ -> true
   with
   | true -> ()
   | false -> Alcotest.fail "damaged index accepted")

let test_macho () =
  let d = tmp_dir () in
  let f = Filename.concat d "m" in
  P.Fs.write_file f ("\xfe\xed\xfa\xcf" ^ String.make 60 '\000');
  check bool "macho" true (P.Mach_o.is_macho f);
  P.Fs.write_file f "hello";
  check bool "not macho" false (P.Mach_o.is_macho f)

let test_stubs () =
  let spec = base_spec ~executable:spec_exe () in
  let lin = L.packager_for L.Linux and win = L.packager_for L.Windows in
  (match lin.pkg_bundle spec "/tmp" with
   | L.Unsupported s -> check bool "linux msg" true (String.length s > 0)
   | _ -> Alcotest.fail "linux bundle should be unsupported");
  (match win.pkg_sign spec "/x.app" with
   | L.Unsupported _ -> ()
   | _ -> Alcotest.fail "win sign should be unsupported");
  (match win.pkg_notarize spec "/x.dmg" with
   | L.Unsupported _ -> ()
   | _ -> Alcotest.fail "win notarize should be unsupported");
  (match lin.pkg_disk_image spec "/x.app" "/tmp" with
   | L.Unsupported _ -> ()
   | _ -> Alcotest.fail "linux dmg should be unsupported")

(** {1 macOS real-tool e2e} *)

let test_bundle_e2e () =
  if on_macos () then begin
    let dir = tmp_dir () in
    let icon = Filename.concat dir "icon.png" in
    write_png icon ~size:64;
    let spec = base_spec ~icon:(Some icon) ~executable:spec_exe () in
    let app = expect_ok (L.bundle spec ~dir) in
    check string "app path" (Filename.concat dir "PkgTest.app") app;
    List.iter
      (fun p ->
         check bool ("exists " ^ p) true
           (P.Fs.exists (Filename.concat app p)))
      [ "Contents"; "Contents/Info.plist"; "Contents/PkgInfo";
        "Contents/MacOS"; "Contents/MacOS/PkgTest";
        "Contents/Resources"; "Contents/Resources/AppIcon.icns";
        "Contents/Frameworks" ];
    check string "pkginfo" "APPL????"
      (P.Fs.read_file (Filename.concat app "Contents/PkgInfo"));
    let icns =
      P.Fs.read_file (Filename.concat app "Contents/Resources/AppIcon.icns")
    in
    check string "icns magic" "icns" (String.sub icns 0 4);
    check int "plutil lint" 0
      (sh0
         (Printf.sprintf "plutil -lint '%s/Contents/Info.plist'" app));
    (* executable bit preserved *)
    check bool "exe bit" true
      (((Unix.stat (Filename.concat app "Contents/MacOS/PkgTest")).Unix.st_perm
        land 0o111)
       <> 0)
  end

let test_sign_e2e () =
  if on_macos () then begin
    let dir = tmp_dir () in
    (* /bin/echo arrives sealed: strip its signature so adhoc signing
       has real work to do. *)
    let unsigned = Filename.concat dir "stub" in
    P.Fs.copy_file ~src:spec_exe ~dst:unsigned;
    check int "remove signature" 0
      (sh0 (Printf.sprintf "codesign --remove-signature '%s'" unsigned));
    let spec = base_spec ~executable:unsigned () in
    let app = expect_ok (L.bundle spec ~dir) in
    let report = expect_ok (L.sign spec app) in
    check bool "signed something" true (List.length report.L.signed > 0);
    check bool "exe signed" true
      (List.exists (fun s -> s = "MacOS/PkgTest") report.signed);
    check bool "verify ran" true report.codesign_verify.tc_ran;
    check bool "verify ok" true report.codesign_verify.tc_ok;
    check bool "mach-o sees signature" true
      (P.Mach_o.is_signed (Filename.concat app "Contents/MacOS/PkgTest"));
    check int "codesign --verify --deep --strict" 0
      (sh0 (Printf.sprintf "codesign --verify --deep --strict -vvv '%s'" app));
    (* re-signing is idempotent: everything already sealed *)
    let report2 = expect_ok (L.sign spec app) in
    check bool "still verifies" true report2.codesign_verify.tc_ok
  end

let test_dmg_e2e () =
  if on_macos () then begin
    let dir = tmp_dir () in
    let spec = base_spec ~executable:spec_exe () in
    let app = expect_ok (L.bundle spec ~dir) in
    let dmg = expect_ok (L.dmg spec app ~dir) in
    check string "dmg suffix" ".dmg"
      (String.sub dmg (String.length dmg - 4) 4);
    let mnt = Filename.concat dir "mnt" in
    P.Fs.mkdir_p mnt;
    check int "hdiutil attach" 0
      (sh0
         (Printf.sprintf
            "hdiutil attach -nobrowse -readonly -mountpoint '%s' '%s'"
            mnt dmg));
    check bool "app inside image" true
      (P.Fs.exists (Filename.concat mnt "PkgTest.app"));
    check bool "Applications link" true
      (P.Fs.kind_of (Filename.concat mnt "Applications") = P.Fs.Link);
    ignore (sh (Printf.sprintf "hdiutil detach '%s'" mnt))
  end

let test_notarize_e2e () =
  if on_macos () then begin
    let dir = tmp_dir () in
    let spec = base_spec ~executable:spec_exe () in
    let app = expect_ok (L.bundle spec ~dir) in
    (* no creds configured anywhere -> structured Skipped *)
    (match L.notarize spec app with
     | L.Skipped reason ->
       check bool "reason mentions creds" true
         (P.Dmg.contains_sub reason "credential"
          || P.Dmg.contains_sub reason "env")
     | o -> Alcotest.failf "expected Skipped, got %s" (show_outcome o));
    (* env creds named but unset -> still Skipped, payload validated *)
    let spec2 =
      L.v_spec ~name:"PkgTest" ~bundle_id:"com.devin.pkgtest"
        ~version:"1.2.3" ~executable:spec_exe
        ~notarization:
          (L.Apple_id_env
             { apple_id_var = "LUI_PKG_TEST_UNSET_ID2";
               password_var = "LUI_PKG_TEST_UNSET_PW2"; team_id = "TEAM" })
        ()
    in
    (match L.notarize spec2 app with
     | L.Skipped reason ->
       check bool "mentions vars" true
         (P.Dmg.contains_sub reason "LUI_PKG_TEST_UNSET_ID2")
     | o -> Alcotest.failf "expected Skipped, got %s" (show_outcome o))
  end

let test_delta_e2e () =
  (* delta update is platform-agnostic: build, apply, compare *)
  let base = tmp_dir () in
  let old_d, new_d = make_trees base in
  let out = Filename.concat base "u.delta" in
  expect_ok (L.update_pkg ~from:"1.0" ~to_:"1.1" ~old_dir:old_d ~new_dir:new_d out);
  (match L.delta_info out with
   | Ok (f, t, n) ->
     check string "from" "1.0" f;
     check string "to" "1.1" t;
     check bool "entries" true (n >= 6)
   | o -> Alcotest.failf "delta_info: %s" (show_outcome o));
  let rebuilt = Filename.concat base "rebuilt" in
  expect_ok
    (L.apply_delta ~delta:out ~from:"1.0" ~to_:"1.1" ~old_dir:old_d
       ~new_dir:rebuilt);
  same_tree new_d rebuilt;
  (* modes ride along; Windows has no executable permission bit *)
  if not Sys.win32 then
    check bool "exec mode" true
      (((Unix.stat (Filename.concat rebuilt "run.sh")).Unix.st_perm land 0o111)
       <> 0);
  (* applying onto an existing dir is refused *)
  (match
     L.apply_delta ~delta:out ~from:"1.0" ~to_:"1.1" ~old_dir:old_d
       ~new_dir:rebuilt
   with
   | L.Failed (L.Invalid _) -> ()
   | o -> Alcotest.failf "expected Invalid, got %s" (show_outcome o));
  (* a delta that points outside is rejected *)
  let bad_entries =
    [
      { P.Delta.path = "../escape"; dir = false; link = ""; mode = 0;
        size = 1; sha256 = String.make 64 '0'; from = ""; data = 2 };
    ]
  in
  (match
     try P.Delta.check_index bad_entries ~data_start:0 ~size:100; false
     with P.Delta.Damaged _ -> true
   with
   | true -> ()
   | false -> Alcotest.fail "escape path accepted")

let test_gzip_interop () =
  if on_macos () then begin
    let d = tmp_dir () in
    let data = pseudo_random 100_000 ^ String.make 10_000 'r' in
    let p = Filename.concat d "data" in
    P.Fs.write_file p data;
    check int "gzip runs" 0 (sh0 (Printf.sprintf "gzip -c '%s' > '%s.gz'" p p));
    let gz = P.Fs.read_file (p ^ ".gz") in
    check bool "gzip magic" true
      (Char.code gz.[0] = 0x1f && Char.code gz.[1] = 0x8b);
    (* header: 10 bytes + optional extras *)
    let flg = Char.code gz.[3] in
    let off = ref 10 in
    if flg land 0x04 <> 0 then begin
      let xlen = Char.code gz.[!off] lor (Char.code gz.[!off + 1] lsl 8) in
      off := !off + 2 + xlen
    end;
    if flg land 0x08 <> 0 then while gz.[!off] <> '\000' do incr off done;
    if flg land 0x08 <> 0 then incr off;
    if flg land 0x10 <> 0 then while gz.[!off] <> '\000' do incr off done;
    if flg land 0x10 <> 0 then incr off;
    if flg land 0x02 <> 0 then off := !off + 2;
    check string "inflate(gzip body)" data (P.Deflate.inflate ~off:!off gz)
  end

let () =
  Alcotest.run "lui_pkg"
    [
      ( "unit",
        [
          Alcotest.test_case "sha256" `Quick test_sha256;
          Alcotest.test_case "crc/adler" `Quick test_crc;
          Alcotest.test_case "varint" `Quick test_varint;
          Alcotest.test_case "deflate roundtrip" `Quick test_deflate;
          Alcotest.test_case "bsdiff roundtrip" `Quick test_bsdiff;
          Alcotest.test_case "Info.plist" `Quick test_plist_xml;
          Alcotest.test_case "binary plist" `Quick test_plist_binary;
          Alcotest.test_case ".DS_Store" `Quick test_ds_store;
          Alcotest.test_case "codesign args" `Quick test_codesign_args;
          Alcotest.test_case "notarize creds" `Quick test_notarize_creds;
          Alcotest.test_case "notarytool parse" `Quick test_parse_submission;
          Alcotest.test_case "dmg names" `Quick test_dmg_names;
          Alcotest.test_case "delta paths" `Quick test_delta_relpath;
          Alcotest.test_case "delta manifest" `Quick test_delta_manifest;
          Alcotest.test_case "mach-o" `Quick test_macho;
          Alcotest.test_case "platform stubs" `Quick test_stubs;
        ] );
      ( "e2e",
        [
          Alcotest.test_case "bundle" `Quick test_bundle_e2e;
          Alcotest.test_case "sign+verify" `Quick test_sign_e2e;
          Alcotest.test_case "dmg roundtrip" `Quick test_dmg_e2e;
          Alcotest.test_case "notarize skipped" `Quick test_notarize_e2e;
          Alcotest.test_case "delta roundtrip" `Quick test_delta_e2e;
          Alcotest.test_case "gzip interop" `Quick test_gzip_interop;
        ] );
    ]
