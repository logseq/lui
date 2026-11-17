(** lui_pkg_linux e2e — real AppDir builds and tool runs (tar, zstd,
    dpkg-deb, appimagetool, desktop-file-validate). Linux only; each
    case skips what the host cannot run. *)

module L = Lui_pkg
module X = Lui_pkg_linux
module P = X.Private
module Fs = L.Private.Fs
module Proc = L.Private.Proc

let check = Alcotest.check
let string = Alcotest.string
let int = Alcotest.int
let bool = Alcotest.bool

let show_outcome = function
  | L.Ok _ -> "Ok"
  | Skipped s -> "Skipped: " ^ s
  | Unsupported s -> "Unsupported: " ^ s
  | Failed f -> "Failed: " ^ L.string_of_failure f

let expect_ok o =
  match o with L.Ok v -> v | o -> Alcotest.fail (show_outcome o)

let tmp_dir () = Fs.temp_dir ~prefix:"lui-pkg-linux-e2e-" ()
let on_linux () = L.host_platform () = L.Linux

let sh cmd =
  let r = Proc.run "sh" [ "-c"; cmd ] in
  (r.Proc.status, r.stdout ^ r.stderr)

let sh0 cmd = fst (sh cmd)

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i = i + m <= n && (String.sub s i m = sub || go (i + 1)) in
  go 0

let write_png path ~size =
  let module DP = L.Private in
  let be32 v = String.init 4 (fun i -> Char.chr ((v lsr (8 * (3 - i))) land 0xff)) in
  let chunk tag data =
    be32 (String.length data) ^ tag ^ data
    ^ be32 (Int32.to_int (DP.Crc32.string (tag ^ data)))
  in
  let raw = Buffer.create (size * 4) in
  for y = 0 to size - 1 do
    Buffer.add_char raw '\000';
    for x = 0 to size - 1 do
      Buffer.add_char raw (Char.chr ((x * 255) / max 1 (size - 1)));
      Buffer.add_char raw (Char.chr ((y * 255) / max 1 (size - 1)));
      Buffer.add_char raw '\128';
      Buffer.add_char raw '\255'
    done
  done;
  Fs.write_file path
    ("\137PNG\r\n\026\n"
    ^ chunk "IHDR" (be32 size ^ be32 size ^ "\008\006\000\000\000")
    ^ chunk "IDAT" (DP.Deflate.zlib (Buffer.contents raw))
    ^ chunk "IEND" "")

(** A fabricated app: a shell-script exe plus an icon and a resource. *)
let make_spec dir ~version =
  let exe = Filename.concat dir "stubapp" in
  Fs.write_file ~perm:0o755 exe "#!/bin/sh\necho stub-app\n";
  let icon = Filename.concat dir "icon.png" in
  write_png icon ~size:48;
  let res = Filename.concat dir "help.txt" in
  Fs.write_file res ("help for " ^ version ^ "\n");
  L.v_spec ~name:"Stub App" ~bundle_id:"com.devin.stubapp" ~version
    ~icon ~executable:exe
    ~resources:[ { L.res_name = "data/help.txt"; res_src = res } ]
    ~doc_types:
      [
        {
          L.doc_name = Some "Stub Doc";
          role = "Editor";
          extensions = [ "stub" ];
          mime = [ "application/x-stub" ];
        };
      ]
    ~url_schemes:[ "stubapp" ] ()

(** Tree signature: relative path, kind tag, content hash or link
    target — so two trees compare element-wise. *)
let tree_sig root =
  Fs.walk root
  |> List.filter_map (fun (rel, kind) ->
         match kind with
         | Fs.Dir -> Some (rel, "d", "")
         | Fs.File ->
           Some (rel, "f", L.Private.Sha256.file (Filename.concat root rel))
         | Fs.Link ->
           Some (rel, "l", Unix.readlink (Filename.concat root rel))
         | _ -> None)
  |> List.sort compare

let same_tree a b =
  check bool (Printf.sprintf "trees %s == %s" a b) true (tree_sig a = tree_sig b)

(** {1 AppDir} *)

let test_bundle_appdir () =
  if on_linux () then begin
    let d = tmp_dir () in
    let spec = make_spec d ~version:"1.0.0" in
    let appdir = expect_ok (X.bundle spec ~dir:d) in
    check string "name" (Filename.concat d "stub-app.AppDir") appdir;
    let at rel = Filename.concat appdir rel in
    (* AppRun is a real launcher script, delta-safe *)
    check bool "apprun file" true (Fs.kind_of (at "AppRun") = Fs.File);
    check bool "apprun runnable" true
      ((Unix.stat (at "AppRun")).Unix.st_perm land 0o111 <> 0);
    check bool "apprun execs exe" true
      (contains (Fs.read_file (at "AppRun")) "usr/bin/stubapp");
    check bool "exe copied" true
      (Fs.kind_of (at "usr/bin/stubapp") = Fs.File);
    check bool "exe runnable" true
      ((Unix.stat (at "usr/bin/stubapp")).Unix.st_perm land 0o111 <> 0);
    (* desktop entry at both canonical spots *)
    let desk = at "usr/share/applications/com.devin.stubapp.desktop" in
    check bool "usr desktop" true (Fs.kind_of desk = Fs.File);
    check bool "root desktop" true
      (Fs.kind_of (at "com.devin.stubapp.desktop") = Fs.File);
    let body = Fs.read_file desk in
    check bool "exec" true (contains body "Exec=stubapp %U\n");
    check bool "mimetype" true
      (contains body "MimeType=application/x-stub;x-scheme-handler/stubapp;\n");
    (* icon: hicolor at real size + root copy *)
    check bool "hicolor icon" true
      (Fs.kind_of
         (at "usr/share/icons/hicolor/48x48/apps/com.devin.stubapp.png")
      = Fs.File);
    check bool "root icon" true
      (Fs.kind_of (at "com.devin.stubapp.png") = Fs.File);
    (* mime package + resource *)
    check bool "mime xml" true
      (Fs.kind_of (at "usr/share/mime/packages/com.devin.stubapp.xml")
      = Fs.File);
    check string "resource" ("help for 1.0.0\n")
      (Fs.read_file (at "usr/share/stub-app/data/help.txt"))
  end

(** {1 Tar round-trip} *)

let test_tarball_roundtrip () =
  if on_linux () then begin
    let d = tmp_dir () in
    let spec = make_spec d ~version:"1.0.0" in
    let appdir = expect_ok (X.bundle spec ~dir:d) in
    let out_dir = Filename.concat d "dist" in
    let tar = expect_ok (X.tarball spec appdir ~dir:out_dir) in
    (* compressor chain decides the extension *)
    let expect_ext =
      if Proc.which "zstd" <> None then ".tar.zst"
      else if Proc.which "gzip" <> None then ".tar.gz"
      else ".tar"
    in
    check bool "ext" true
      (String.length tar >= String.length expect_ext
       && String.sub tar (String.length tar - String.length expect_ext)
            (String.length expect_ext)
          = expect_ext);
    (* extract by the format actually produced *)
    let dst = Filename.concat d "unpacked" in
    Fs.mkdir_p dst;
    let cmd =
      if Filename.check_suffix tar ".zst" then
        Printf.sprintf "zstd -dc %s | tar -x -C %s" tar dst
      else if Filename.check_suffix tar ".gz" then
        Printf.sprintf "tar -xzf %s -C %s" tar dst
      else Printf.sprintf "tar -xf %s -C %s" tar dst
    in
    check int "extract" 0 (sh0 cmd);
    same_tree appdir (Filename.concat dst "stub-app.AppDir");
    (* pkg_disk_image on the record is the tarball *)
    let via_record =
      expect_ok (X.linux_packager.pkg_disk_image spec appdir out_dir)
    in
    check string "record == tarball" tar via_record
  end

(** {1 Delta update over AppDirs} *)

let test_delta_appdir () =
  if on_linux () then begin
    let d = tmp_dir () in
    let v1_dir = Filename.concat d "v1" and v2_dir = Filename.concat d "v2" in
    Fs.mkdir_p v1_dir;
    Fs.mkdir_p v2_dir;
    let s1 = make_spec v1_dir ~version:"1.0.0" in
    let s2 = make_spec v2_dir ~version:"2.0.0" in
    let a1 = expect_ok (X.bundle s1 ~dir:v1_dir) in
    let a2 = expect_ok (X.bundle s2 ~dir:v2_dir) in
    let delta = Filename.concat d "update.ldp" in
    expect_ok
      (X.update_pkg ~from:"1.0.0" ~to_:"2.0.0" ~old_dir:a1 ~new_dir:a2 delta);
    let rebuilt = Filename.concat d "rebuilt" in
    expect_ok
      (X.apply_delta ~delta ~from:"1.0.0" ~to_:"2.0.0" ~old_dir:a1
         ~new_dir:rebuilt);
    same_tree a2 rebuilt
  end

(** {1 .deb via dpkg-deb} *)

let test_deb () =
  if on_linux () then begin
    let d = tmp_dir () in
    let spec = make_spec d ~version:"1.0.0" in
    let appdir = expect_ok (X.bundle spec ~dir:d) in
    match X.deb spec appdir ~dir:(Filename.concat d "dist") with
    | L.Skipped _ ->
      check bool "dpkg-deb absent" true (Proc.which "dpkg-deb" = None)
    | L.Ok deb ->
      check bool "deb exists" true (Fs.kind_of deb = Fs.File);
      let st, info = sh (Printf.sprintf "dpkg-deb --info %s" deb) in
      check int "info runs" 0 st;
      check bool "package" true (contains info "Package: stub-app");
      check bool "version" true (contains info "Version: 1.0.0");
      let st, contents = sh (Printf.sprintf "dpkg-deb -c %s" deb) in
      check int "contents runs" 0 st;
      List.iter
        (fun want ->
           check bool (Printf.sprintf "has %s" want) true
             (contains contents want))
        [ "opt/stub-app/AppRun";
          "opt/stub-app/usr/bin/stubapp";
          "usr/bin/stubapp";
          "usr/share/applications/com.devin.stubapp.desktop";
          "usr/share/icons/hicolor/48x48/apps/com.devin.stubapp.png";
          "usr/share/mime/packages/com.devin.stubapp.xml" ]
    | o -> Alcotest.fail (show_outcome o)
  end

(** {1 AppImage / tool probe} *)

let test_appimage () =
  if on_linux () then begin
    let d = tmp_dir () in
    let spec = make_spec d ~version:"1.0.0" in
    let appdir = expect_ok (X.bundle spec ~dir:d) in
    match X.appimage spec appdir ~dir:(Filename.concat d "dist") with
    | L.Ok path -> check bool "exists" true (Fs.kind_of path = Fs.File)
    | L.Skipped _ ->
      check bool "appimagetool absent" true
        (Proc.which "appimagetool" = None)
    | o -> Alcotest.fail (show_outcome o)
  end

let test_probe () =
  if on_linux () then begin
    let tools = X.probe () in
    check bool "lists tools" true (List.length tools >= 5);
    check bool "tar probed" true (List.assoc "tar" tools <> None)
  end

let () =
  Alcotest.run "lui_pkg_linux_e2e"
    [
      ( "e2e",
        [
          Alcotest.test_case "AppDir bundle" `Quick test_bundle_appdir;
          Alcotest.test_case "tar roundtrip" `Quick test_tarball_roundtrip;
          Alcotest.test_case "delta AppDir" `Quick test_delta_appdir;
          Alcotest.test_case "deb" `Quick test_deb;
          Alcotest.test_case "appimage" `Quick test_appimage;
          Alcotest.test_case "probe" `Quick test_probe;
        ] );
    ]
