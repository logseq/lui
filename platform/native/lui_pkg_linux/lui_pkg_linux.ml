(* Linux packaging for LUI native apps: AppDir assembly plus the tar /
   AppImage / .deb package formats, filling the Lui_pkg.packager
   contract. Signing and notarization have no Linux equivalent — those
   slots answer [Unsupported].

   Everything external is shelled out to the platform tools and probed
   first: missing optional tools downgrade to [Skipped], never a fake
   success; [tar] is required for the archive formats. *)

open Lui_pkg

module Fs = Private.Fs
module Proc = Private.Proc

let fmt = Printf.sprintf
let invalid fmt = Printf.ksprintf (fun s -> Failed (Invalid s)) fmt
let missing fmt = Printf.ksprintf (fun s -> Failed (Missing s)) fmt

let tool_failed tool args (r : Proc.ran) =
  Failed
    (Tool_failed
       { tool; args; status = r.status; output = r.stdout ^ r.stderr })

let uname_m () =
  match Proc.check_o "uname" [ "-m" ] with
  | Ok s -> String.trim s
  | _ -> host_arch ()

(** {1 Names} *)

(** Lowercase, keep [a-z0-9._-], fold every other run into one [-], and
    strip leading/trailing punctuation: a string safe for a deb package
    name, a desktop file id, and a path component. *)
let slugify s =
  let b = Buffer.create (String.length s) in
  let pending_dash = ref false in
  String.iter
    (fun c ->
       let c = Char.lowercase_ascii c in
       let ok =
         (c >= 'a' && c <= 'z')
         || (c >= '0' && c <= '9')
         || c = '.' || c = '_' || c = '-'
       in
       if ok then begin
         if !pending_dash && Buffer.length b > 0 then Buffer.add_char b '-';
         pending_dash := false;
         Buffer.add_char b c
       end
       else pending_dash := Buffer.length b > 0)
    s;
  let s = Buffer.contents b in
  let n = String.length s in
  let rec trail i =
    if i > 0 && (s.[i - 1] = '-' || s.[i - 1] = '.') then trail (i - 1)
    else i
  in
  let rec lead i =
    if i < n && (s.[i] = '-' || s.[i] = '.') then lead (i + 1) else i
  in
  let lo = lead 0 and hi = trail n in
  if hi <= lo then "app" else String.sub s lo (hi - lo)

let exe_name spec = Filename.basename spec.executable
let slug spec = slugify spec.name
let appdir_name spec = slug spec ^ ".AppDir"
let desktop_name spec = slugify spec.bundle_id
let icon_name = desktop_name

let archive_name spec ~arch ~ext =
  fmt "%s-%s-linux-%s.%s" (slug spec) spec.version arch ext

let appimage_name spec ~arch = archive_name spec ~arch ~ext:"AppImage"
let deb_name spec ~arch = fmt "%s_%s_%s.deb" (slug spec) spec.version arch

(** Single-quote for POSIX sh: the only escape single quotes need. *)
let sh_quote s =
  "'" ^ String.concat "'\\''" (String.split_on_char '\'' s) ^ "'"

(** {1 Desktop entry and MIME package} *)

(** MIME types the entry registers: declared file types plus scheme
    handlers for the app's URL schemes. *)
let mime_entries spec =
  let add l v = if List.mem v l then l else l @ [ v ] in
  let mimes =
    List.fold_left
      (fun acc d -> List.fold_left add acc d.mime)
      [] spec.doc_types
  in
  List.fold_left
    (fun acc s -> add acc ("x-scheme-handler/" ^ s))
    mimes spec.url_schemes

(** [desktop_entry spec ~exec ~icon] renders the .desktop file. [exec]
    is the Exec line verbatim — the exe name inside an AppDir, an
    absolute path once installed; [%U] is appended when the app takes
    files or URLs. *)
let desktop_entry spec ~exec ~icon =
  let mimes = mime_entries spec in
  let exec = if mimes = [] then exec else exec ^ " %U" in
  let b = Buffer.create 256 in
  Buffer.add_string b "[Desktop Entry]\nType=Application\n";
  Buffer.add_string b ("Name=" ^ spec.name ^ "\n");
  Buffer.add_string b ("Exec=" ^ exec ^ "\n");
  (match icon with
   | Some i -> Buffer.add_string b ("Icon=" ^ i ^ "\n")
   | None -> ());
  Buffer.add_string b "Categories=Utility;\nTerminal=false\n";
  (match mimes with
   | [] -> ()
   | _ ->
     Buffer.add_string b ("MimeType=" ^ String.concat ";" mimes ^ ";\n"));
  Buffer.contents b

(** shared-mime-info XML for the file types the spec declares with a
    custom mime type, or [""] when there are none. *)
let mime_package spec =
  let b = Buffer.create 256 in
  List.iter
    (fun d ->
       List.iter
         (fun t ->
            Buffer.add_string b (fmt "  <mime-type type=\"%s\">\n" t);
            (match d.doc_name with
             | Some n ->
               Buffer.add_string b (fmt "    <comment>%s</comment>\n" n)
             | None -> ());
            List.iter
              (fun e ->
                 Buffer.add_string b (fmt "    <glob pattern=\"*.%s\"/>\n" e))
              d.extensions;
            Buffer.add_string b "  </mime-type>\n")
         d.mime)
    spec.doc_types;
  if Buffer.length b = 0 then ""
  else
    "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n\
     <mime-info xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\">\n"
    ^ Buffer.contents b ^ "</mime-info>\n"

(** {1 Icons} *)

(** [png_size path] reads the IHDR of a PNG file. *)
let png_size path =
  match Fs.kind_of path with
  | Fs.File -> (
    try
      let ic = open_in_bin path in
      let hdr = really_input_string ic 24 in
      close_in ic;
      let be32 off =
        (Char.code hdr.[off] lsl 24)
        lor (Char.code hdr.[off + 1] lsl 16)
        lor (Char.code hdr.[off + 2] lsl 8)
        lor Char.code hdr.[off + 3]
      in
      if String.sub hdr 0 8 = "\137PNG\r\n\026\n" && String.sub hdr 12 4 = "IHDR"
      then Some (be32 16, be32 20)
      else None
    with End_of_file | Sys_error _ -> None)
  | _ -> None

(** {1 Bundle: the AppDir} *)

let validate_spec spec =
  if spec.name = "" || String.contains spec.name '/' then
    invalid "app name %S" spec.name
  else if spec.bundle_id = "" then invalid "empty bundle id"
  else if Fs.kind_of spec.executable <> Fs.File then
    missing "executable %s" spec.executable
  else Ok ()

(** An AppDir has an AppRun and a usr/bin payload. *)
let valid_appdir dir =
  Fs.is_dir dir
  && Fs.kind_of (Filename.concat dir "AppRun") <> Fs.Absent
  && Fs.is_dir (Filename.concat dir (Filename.concat "usr" "bin"))

let bundle spec ~dir =
  match validate_spec spec with
  | (Failed _ | Skipped _ | Unsupported _) as e -> e
  | Ok () -> (
    let appdir = Filename.concat dir (appdir_name spec) in
    let exe = exe_name spec and id = desktop_name spec in
    Fs.rm_rf appdir;
    let at rel = Filename.concat appdir rel in
    Fs.mkdir_p (at "usr/bin");
    Fs.mkdir_p (at "usr/share/applications");
    let dst_exe = at ("usr/bin/" ^ exe) in
    Fs.copy_file ~src:spec.executable ~dst:dst_exe;
    (try Unix.chmod dst_exe ((Unix.stat dst_exe).Unix.st_perm lor 0o111)
     with Unix.Unix_error _ -> ());
    (* Icon: PNG into the hicolor tree at its real size, plus the
       AppDir-root copy the AppImage tooling expects next to the
       desktop entry. *)
    let icon_o =
      match spec.icon with
      | None -> Ok None
      | Some src -> (
        match (Fs.kind_of src, png_size src) with
        | Fs.Absent, _ -> missing "icon %s" src
        | Fs.File, None -> invalid "icon %s is not a PNG" src
        | Fs.File, Some (w, h) ->
          let hicolor = at (fmt "usr/share/icons/hicolor/%dx%d/apps" w h) in
          Fs.mkdir_p hicolor;
          Fs.copy_file ~src ~dst:(Filename.concat hicolor (id ^ ".png"));
          Fs.copy_file ~src ~dst:(at (id ^ ".png"));
          Ok (Some id)
        | _ -> invalid "icon %s is not a PNG" src)
    in
    match icon_o with
    | (Failed _ | Skipped _ | Unsupported _) as e -> e
    | Ok icon -> (
      let entry = desktop_entry spec ~exec:exe ~icon in
      Fs.write_file (at ("usr/share/applications/" ^ id ^ ".desktop")) entry;
      Fs.write_file (at (id ^ ".desktop")) entry;
      let xml = mime_package spec in
      if xml <> "" then begin
        Fs.mkdir_p (at "usr/share/mime/packages");
        Fs.write_file (at ("usr/share/mime/packages/" ^ id ^ ".xml")) xml
      end;
      (* Resources ride along under usr/share/<app>. *)
      let rec res_loop = function
        | [] -> Stdlib.Ok ()
        | r :: rest ->
          if r.res_name = "" || String.contains r.res_name '\x00' then
            Error (Invalid (fmt "bad resource name %S" r.res_name))
          else if Fs.kind_of r.res_src = Fs.Absent then
            Error (Missing (fmt "resource %s" r.res_src))
          else begin
            Fs.install ~src:r.res_src
              ~dst:(at ("usr/share/" ^ slug spec ^ "/" ^ r.res_name));
            res_loop rest
          end
      in
      match res_loop spec.resources with
      | Error f -> Failed f
      | Ok () -> (
        (* AppRun is a real file, not a symlink: the shared delta
           format rejects a root link whose relative target resolves
           through "." — a script also fixes the working directory. *)
        Fs.write_file ~perm:0o755 (at "AppRun")
          (fmt "#!/bin/sh\nexec \"$(dirname \"$0\")/usr/bin/%s\" \"$@\"\n"
             exe);
        match Proc.which "desktop-file-validate" with
        | Some tool -> (
          match Proc.check tool [ at (id ^ ".desktop") ] with
          | Stdlib.Ok _ -> Ok appdir
          | Error f -> Failed f)
        | None -> Ok appdir)))

(** {1 Package formats} *)

(** [tarball spec appdir ~dir] archives the AppDir through the first
    compressor of the zstd/gzip chain that is installed, falling back
    to a plain tar. *)
let tarball spec appdir ~dir =
  if not (valid_appdir appdir) then invalid "%s is not an AppDir" appdir
  else
    match Proc.which "tar" with
    | None -> missing "tar"
    | Some tar ->
      Fs.mkdir_p dir;
      let arch = host_arch () in
      let parent = Filename.dirname appdir
      and base = Filename.basename appdir in
      let run_out ext compress =
        let out = Filename.concat dir (archive_name spec ~arch ~ext) in
        let cmd =
          match compress with
          | Some comp ->
            fmt "%s -C %s -cf - %s | %s > %s" tar (sh_quote parent)
              (sh_quote base) comp (sh_quote out)
          | None ->
            fmt "%s -C %s -cf %s %s" tar (sh_quote parent) (sh_quote out)
              (sh_quote base)
        in
        let r = Proc.run "sh" [ "-c"; cmd ] in
        if r.status = 0 then Ok out
        else tool_failed "tar" [ "-C"; parent; "-cf"; out; base ] r
      in
      (match Proc.which "zstd" with
       | Some z -> run_out "tar.zst" (Some (fmt "%s -q" z))
       | None -> (
         match Proc.which "gzip" with
         | Some g -> run_out "tar.gz" (Some (fmt "%s -9" g))
         | None -> run_out "tar" None))

let appimage spec appdir ~dir =
  if not (valid_appdir appdir) then invalid "%s is not an AppDir" appdir
  else
    match Proc.which "appimagetool" with
    | None ->
      Skipped "appimagetool not in PATH; cannot build an AppImage"
    | Some tool ->
      Fs.mkdir_p dir;
      let arch = host_arch () in
      let out = Filename.concat dir (appimage_name spec ~arch) in
      (* appimagetool picks the runtime per ARCH, as uname -m names it. *)
      let cmd =
        fmt "ARCH=%s %s %s %s" (sh_quote (uname_m ())) (sh_quote tool)
          (sh_quote appdir) (sh_quote out)
      in
      let r = Proc.run "sh" [ "-c"; cmd ] in
      if r.status = 0 then Ok out
      else tool_failed "appimagetool" [ appdir; out ] r

(** {1 Debian package} *)

let deb_arch = function
  | "x86_64" | "amd64" -> Some "amd64"
  | "arm64" | "aarch64" -> Some "arm64"
  | "i386" | "i486" | "i586" | "i686" -> Some "i386"
  | "armv7l" | "armhf" -> Some "armhf"
  | "riscv64" -> Some "riscv64"
  | "ppc64le" -> Some "ppc64le"
  | "s390x" -> Some "s390x"
  | _ -> (
    match Proc.check_o "dpkg" [ "--print-architecture" ] with
    | Ok s -> (
      match String.trim s with "" -> None | a -> Some a)
    | _ -> None)

(** Debian upstream-version characters: digits, letters, [. + - : ~];
    the version must start with a digit. *)
let deb_version v =
  let b = Buffer.create (String.length v) in
  String.iter
    (fun c ->
       let ok =
         (c >= '0' && c <= '9')
         || (c >= 'a' && c <= 'z')
         || (c >= 'A' && c <= 'Z')
         || c = '.' || c = '+' || c = '-' || c = ':' || c = '~'
       in
       Buffer.add_char b (if ok then c else '-'))
    v;
  let s = Buffer.contents b in
  if s = "" then "0"
  else if s.[0] >= '0' && s.[0] <= '9' then s
  else "0-" ^ s

let control_text spec ~arch ~installed_kb =
  fmt
    "Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: %s\n\
     Installed-Size: %d\nSection: utils\nPriority: optional\n\
     Description: %s\n %s is a desktop application.\n"
    (slug spec) (deb_version spec.version) arch spec.name installed_kb
    spec.name spec.name

(** [deb spec appdir ~dir] stages a dpkg tree — the AppDir payload under
    /opt/<app>, a /usr/bin launcher link, the desktop entry with an
    absolute Exec, icons and the MIME package under /usr/share — and
    runs dpkg-deb on it. *)
let deb spec appdir ~dir =
  if not (valid_appdir appdir) then invalid "%s is not an AppDir" appdir
  else
    match Proc.which "dpkg-deb" with
    | None -> Skipped "dpkg-deb not in PATH; cannot build a .deb"
    | Some tool -> (
      match deb_arch (host_arch ()) with
      | None -> invalid "no Debian architecture for %s" (host_arch ())
      | Some arch ->
        Fs.mkdir_p dir;
        let stage = Fs.temp_dir ~prefix:"lui-pkg-deb-" () in
        let root = Filename.concat stage "root" in
        let app = slug spec and id = desktop_name spec in
        Fs.mkdir_p (Filename.concat root "usr/bin");
        Fs.mkdir_p (Filename.concat root "usr/share/applications");
        (* Payload: the whole AppDir; AppRun stays the entry point. *)
        Fs.install ~src:appdir ~dst:(Filename.concat root ("opt/" ^ app));
        (try
           Unix.symlink
             ("../../opt/" ^ app ^ "/AppRun")
             (Filename.concat root ("usr/bin/" ^ exe_name spec))
         with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
        (* Registered files: absolute Exec once installed. *)
        let icon = match spec.icon with Some _ -> Some id | None -> None in
        Fs.write_file
          (Filename.concat root ("usr/share/applications/" ^ id ^ ".desktop"))
          (desktop_entry spec ~exec:("/opt/" ^ app ^ "/AppRun") ~icon);
        (match (spec.icon, Option.bind spec.icon png_size) with
         | Some src, Some (w, h) ->
           let hd =
             Filename.concat root
               (fmt "usr/share/icons/hicolor/%dx%d/apps" w h)
           in
           Fs.mkdir_p hd;
           Fs.copy_file ~src ~dst:(Filename.concat hd (id ^ ".png"))
         | _ -> ());
        let xml = mime_package spec in
        if xml <> "" then begin
          Fs.mkdir_p (Filename.concat root "usr/share/mime/packages");
          Fs.write_file
            (Filename.concat root ("usr/share/mime/packages/" ^ id ^ ".xml"))
            xml
        end;
        (* Sizes and checksums over the payload, DEBIAN excluded. *)
        let bytes = ref 0 and md5 = Buffer.create 512 in
        List.iter
          (fun (rel, kind) ->
             match kind with
             | Fs.File ->
               let p = Filename.concat root rel in
               bytes := !bytes + Option.value ~default:0 (Fs.file_size p);
               Buffer.add_string md5
                 (fmt "%s  %s\n" (Digest.to_hex (Digest.file p)) rel)
             | _ -> ())
          (Fs.walk root);
        let debian = Filename.concat root "DEBIAN" in
        Fs.mkdir_p debian;
        Fs.write_file (Filename.concat debian "control")
          (control_text spec ~arch ~installed_kb:((!bytes + 1023) / 1024));
        Fs.write_file (Filename.concat debian "md5sums")
          (Buffer.contents md5);
        let out = Filename.concat dir (deb_name spec ~arch) in
        let build args =
          let r = Proc.run tool args in
          (r, r.status)
        in
        let r, st = build [ "--root-owner-group"; "--build"; root; out ] in
        let r, st =
          (* Older dpkg-deb has no --root-owner-group. *)
          if st = 0 then (r, st) else build [ "--build"; root; out ]
        in
        Fs.rm_rf stage;
        if st = 0 then Ok out
        else tool_failed "dpkg-deb" [ "--build"; root; out ] r)

let linux_packager =
  {
    pkg_platform = Linux;
    pkg_bundle = (fun spec dir -> bundle spec ~dir);
    pkg_sign =
      (fun _ _ ->
        Unsupported "linux has no system code-signing step");
    pkg_notarize =
      (fun _ _ -> Unsupported "linux has no notarization step");
    pkg_disk_image = (fun spec appdir dir -> tarball spec appdir ~dir);
  }

let probe () =
  List.map
    (fun t -> (t, Proc.which t))
    [ "tar"; "zstd"; "gzip"; "appimagetool"; "dpkg-deb";
      "desktop-file-validate" ]

(** {1 Delta updates — the shared format over AppDir trees} *)

let update_pkg ~from ~to_ ~old_dir ~new_dir out =
  Lui_pkg.update_pkg ~from ~to_ ~old_dir ~new_dir out

let apply_delta ~delta ~from ~to_ ~old_dir ~new_dir =
  Lui_pkg.apply_delta ~delta ~from ~to_ ~old_dir ~new_dir

let delta_info = Lui_pkg.delta_info

module Private = struct
  let slugify = slugify
  let exe_name = exe_name
  let appdir_name = appdir_name
  let desktop_name = desktop_name
  let icon_name = icon_name
  let mime_entries = mime_entries
  let desktop_entry = desktop_entry
  let mime_package = mime_package
  let png_size = png_size
  let deb_arch = deb_arch
  let deb_version = deb_version
  let archive_name = archive_name
  let appimage_name = appimage_name
  let deb_name = deb_name
  let control_text = control_text
  let sh_quote = sh_quote
  let valid_appdir = valid_appdir
end
