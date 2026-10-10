(** lui_pkg_linux unit tests — pure generators and record wiring; runs
    on every OS. Real-tool coverage lives in lui_pkg_linux_e2e. *)

module L = Lui_pkg
module X = Lui_pkg_linux
module P = X.Private
module Fs = L.Private.Fs

let check = Alcotest.check
let string = Alcotest.string
let int = Alcotest.int
let bool = Alcotest.bool
let option t = Alcotest.option t
let pair a b = Alcotest.pair a b

let base_spec ?icon ?(doc_types = []) ?(url_schemes = []) ~executable () =
  L.v_spec ~name:"Stub App" ~bundle_id:"com.devin.stubapp" ~version:"1.2.3"
    ?icon ~executable ~doc_types ~url_schemes ()

let doc_stub =
  {
    L.doc_name = Some "Stub Doc";
    role = "Editor";
    extensions = [ "stub" ];
    mime = [ "application/x-stub" ];
  }

(** A tiny valid RGBA PNG via the shared crc32/zlib. *)
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

(** {1 slugify and names} *)

let test_slugify () =
  check string "plain" "stub-app" (P.slugify "Stub App");
  check string "punct run" "a-b" (P.slugify "a !@# b");
  check string "keeps dots" "com.devin.app" (P.slugify "com.devin.app");
  check string "trim" "x" (P.slugify "--x--");
  check string "empty falls back" "app" (P.slugify "!!!");
  check string "unicode folds" "caf" (P.slugify "caf\xC3\xA9")

let test_names () =
  let spec = base_spec ~executable:"/bin/echo" () in
  check string "appdir" "stub-app.AppDir" (P.appdir_name spec);
  check string "desktop" "com.devin.stubapp" (P.desktop_name spec);
  check string "exe" "echo" (P.exe_name spec);
  check string "tarball" "stub-app-1.2.3-linux-x86_64.tar.zst"
    (P.archive_name spec ~arch:"x86_64" ~ext:"tar.zst");
  check string "appimage" "stub-app-1.2.3-linux-arm64.AppImage"
    (P.appimage_name spec ~arch:"arm64");
  check string "deb" "stub-app_1.2.3_amd64.deb" (P.deb_name spec ~arch:"amd64")

(** {1 Desktop entry} *)

let contains s sub =
  let n = String.length s and m = String.length sub in
  let rec go i =
    i + m <= n && (String.sub s i m = sub || go (i + 1))
  in
  go 0

let test_desktop_entry () =
  let spec = base_spec ~executable:"/bin/echo" () in
  let e = P.desktop_entry spec ~exec:"stubapp" ~icon:(Some "com.devin.stubapp") in
  check bool "has header" true (contains e "[Desktop Entry]\nType=Application\n");
  check bool "name" true (contains e "Name=Stub App\n");
  check bool "exec" true (contains e "Exec=stubapp\n");
  check bool "icon" true (contains e "Icon=com.devin.stubapp\n");
  check bool "terminal" true (contains e "Terminal=false\n");
  check bool "no mime" false (contains e "MimeType=");
  (* handlers: %U appended to Exec, MimeType line emitted *)
  let spec =
    base_spec ~executable:"/bin/echo" ~doc_types:[ doc_stub ]
      ~url_schemes:[ "stubapp" ] ()
  in
  let e = P.desktop_entry spec ~exec:"/opt/stub-app/AppRun" ~icon:None in
  check bool "exec %U" true (contains e "Exec=/opt/stub-app/AppRun %U\n");
  check bool "mime line" true
    (contains e "MimeType=application/x-stub;x-scheme-handler/stubapp;\n");
  check bool "no icon" false (contains e "Icon=")

let test_mime_package () =
  let spec = base_spec ~executable:"/bin/echo" () in
  check string "empty" "" (P.mime_package spec);
  let spec = base_spec ~executable:"/bin/echo" ~doc_types:[ doc_stub ] () in
  let xml = P.mime_package spec in
  check bool "root elem" true
    (contains xml "<mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">");
  check bool "mime type" true
    (contains xml "<mime-type type=\"application/x-stub\">");
  check bool "comment" true (contains xml "<comment>Stub Doc</comment>");
  check bool "glob" true (contains xml "<glob pattern=\"*.stub\"/>")

(** {1 PNG IHDR} *)

let test_png_size () =
  let d = Fs.temp_dir ~prefix:"lui-pkg-linux-test-" () in
  let p = Filename.concat d "icon.png" in
  write_png p ~size:48;
  check (option (pair int int)) "48x48" (Some (48, 48)) (P.png_size p);
  let q = Filename.concat d "junk.png" in
  Fs.write_file q "not a png at all";
  check (option (pair int int)) "garbage" None (P.png_size q);
  check (option (pair int int)) "absent" None
    (P.png_size (Filename.concat d "absent.png"))

(** {1 deb text} *)

let test_deb_arch () =
  check (option string) "amd64" (Some "amd64") (P.deb_arch "x86_64");
  check (option string) "arm64" (Some "arm64") (P.deb_arch "aarch64");
  check (option string) "i386" (Some "i386") (P.deb_arch "i686")

let test_deb_version () =
  check string "semver" "1.2.3" (P.deb_version "1.2.3");
  check string "dash" "1.2.3-rc.1" (P.deb_version "1.2.3-rc.1");
  check string "tilde" "1.0~b1" (P.deb_version "1.0~b1");
  check string "bad chars" "1.0-x" (P.deb_version "1.0_x");
  check string "leading digit" "0-beta" (P.deb_version "beta");
  check string "empty" "0" (P.deb_version "")

let test_control_text () =
  let spec = base_spec ~executable:"/bin/echo" () in
  let c = P.control_text spec ~arch:"amd64" ~installed_kb:7 in
  check bool "package" true (contains c "Package: stub-app\n");
  check bool "version" true (contains c "Version: 1.2.3\n");
  check bool "arch" true (contains c "Architecture: amd64\n");
  check bool "size" true (contains c "Installed-Size: 7\n");
  check bool "desc" true
    (contains c "Description: Stub App\n Stub App is a desktop application.\n")

(** {1 sh_quote and appdir check} *)

let test_sh_quote () =
  check string "simple" "'abc'" (P.sh_quote "abc");
  check string "quote" "'a'\\''b'" (P.sh_quote "a'b")

let test_valid_appdir () =
  let d = Fs.temp_dir ~prefix:"lui-pkg-linux-test-" () in
  check bool "empty" false (P.valid_appdir d);
  check bool "absent" false (P.valid_appdir (Filename.concat d "nope"));
  Fs.mkdir_p (Filename.concat d "usr/bin");
  check bool "no apprun" false (P.valid_appdir d);
  Fs.write_file (Filename.concat d "AppRun") "#!/bin/sh\n";
  check bool "complete" true (P.valid_appdir d)

(** {1 Packager record} *)

let test_packager () =
  let p = X.linux_packager in
  check bool "platform" true (p.L.pkg_platform = L.Linux);
  let spec = base_spec ~executable:"/bin/echo" () in
  (match p.pkg_sign spec "/tmp/x" with
   | L.Unsupported _ -> ()
   | o -> Alcotest.failf "sign: %s" (L.string_of_outcome (fun _ -> "ok") o));
  match p.pkg_notarize spec "/tmp/x" with
  | L.Unsupported _ -> ()
  | o -> Alcotest.failf "notarize: %s" (L.string_of_outcome (fun _ -> "ok") o)

let () =
  Alcotest.run "lui_pkg_linux"
    [
      ( "unit",
        [
          Alcotest.test_case "slugify" `Quick test_slugify;
          Alcotest.test_case "names" `Quick test_names;
          Alcotest.test_case "desktop entry" `Quick test_desktop_entry;
          Alcotest.test_case "mime package" `Quick test_mime_package;
          Alcotest.test_case "png size" `Quick test_png_size;
          Alcotest.test_case "deb arch" `Quick test_deb_arch;
          Alcotest.test_case "deb version" `Quick test_deb_version;
          Alcotest.test_case "control" `Quick test_control_text;
          Alcotest.test_case "sh quote" `Quick test_sh_quote;
          Alcotest.test_case "valid appdir" `Quick test_valid_appdir;
          Alcotest.test_case "packager" `Quick test_packager;
        ] );
    ]
