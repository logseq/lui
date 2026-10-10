(* Windows implementation of the Lui_pkg.packager contract.

   The installable unit is a portable app directory — executable,
   generated sidecar manifest, icon and resources side by side — and
   the distributable is that directory zipped by a pure-OCaml writer:
   Lui_pkg already carries the DEFLATE and CRC-32 primitives, so the
   zip writer adds only container framing and needs no external
   archiver, shell or runtime. makeappx (.msix) and makensis (NSIS
   installer) drive the optional formats when the SDK tools are
   installed, answering Skipped otherwise.

   Signing is signtool-only and certificates never pass as raw
   material: a Certificate identity names a .pfx file, a SHA-1
   thumbprint in the user's store, or an environment variable holding
   one of those; the .pfx password is read from the
   LUI_PKG_WINDOWS_CERT_PASSWORD environment variable. There is no
   notarization equivalent on Windows.

   Update deltas reuse Lui_pkg.update_pkg/apply_delta verbatim — the
   wire format is platform-independent. Windows keeps running
   executables locked against overwrite, so apply_delta's
   target-must-not-exist rule is the contract: apply into a staging
   directory beside the install and swap entries with renames (the
   recovery path lui_updater's Dir layout performs), never in place. *)

module L = Lui_pkg
module P = Lui_pkg.Private

let fmt = Printf.sprintf

let missing fmt = Printf.ksprintf (fun s -> L.Failed (L.Missing s)) fmt
let invalid fmt = Printf.ksprintf (fun s -> L.Failed (L.Invalid s)) fmt

let outcome_bind o f =
  match o with
  | L.Ok v -> f v
  | (L.Failed _ | L.Skipped _ | L.Unsupported _) as e -> e

let fs_name = P.Dmg.fs_name

(* PROCESSOR_ARCHITECTURE first: uname does not exist on a
   Windows-native runtime, so L.host_arch reports "" there. *)
let win_arch () =
  match Sys.getenv_opt "PROCESSOR_ARCHITECTURE" with
  | Some a -> (
    match String.uppercase_ascii a with
    | "AMD64" -> "x64"
    | "ARM64" -> "arm64"
    | "X86" -> "x86"
    | _ -> String.lowercase_ascii a)
  | None -> (
    match L.host_arch () with
    | "x86_64" | "amd64" -> "x64"
    | "arm64" | "aarch64" -> "arm64"
    | "" -> "x64"
    | a -> a)

let exe_name spec = fs_name spec.L.name ^ ".exe"

let portable_dir_name spec ~arch =
  fmt "%s-%s-windows-%s" (fs_name spec.L.name) (fs_name spec.version) arch

let zip_name spec ~arch =
  fmt "%s-%s-windows-%s.zip" (fs_name spec.L.name) (fs_name spec.version) arch

(** {1 Private machinery}

    Exposed to the test suite through [Private]; the public API below
    delegates to it. *)

module Private = struct
  module Proc = struct
  type ran = P.Proc.ran

  (* "NUL" is the DOS device name; /dev/null does not exist on a
     Windows-native runtime. *)
  let dev_null = if Sys.win32 then "NUL" else "/dev/null"

  let run ?(stdin = dev_null) prog args = P.Proc.run ~stdin prog args

  let check prog args =
    let r = run prog args in
    if r.status = 0 then Stdlib.Ok r
    else
      Error
        (L.Tool_failed
           { tool = prog; args; status = r.status;
             output = r.stdout ^ r.stderr })

  let check_o prog args =
    match check prog args with
    | Stdlib.Ok r -> L.Ok r.stdout
    | Error e -> L.Failed e

  let path_sep () = match Sys.os_type with "Win32" -> ';' | _ -> ':'

  let pathexts () =
    match Sys.getenv_opt "PATHEXT" with
    | Some s ->
      List.filter_map
        (fun e -> match String.trim e with "" -> None | e -> Some e)
        (String.split_on_char ';' s)
    | None -> [ ".COM"; ".EXE"; ".BAT"; ".CMD" ]

  (** [which name] finds an executable: a name with a path separator or
      an extension is tested as given; a bare name is tried in each PATH
      entry with every PATHEXT extension. *)
  let which name =
    let has_sep =
      String.contains name '/' || String.contains name '\\'
    in
    let candidates dir =
      let base = if dir = "" then name else Filename.concat dir name in
      if Filename.extension name <> "" then [ base ]
      else base :: List.map (fun e -> base ^ e) (pathexts ())
    in
    let in_dir dir =
      List.find_opt
        (fun p ->
           try Sys.file_exists p && not (Sys.is_directory p)
           with _ -> false)
        (candidates dir)
    in
    if has_sep || not (Filename.is_relative name) then in_dir ""
    else
      let path = try Sys.getenv "PATH" with Not_found -> "" in
      let rec search = function
        | [] -> None
        | d :: rest -> (
          match in_dir d with Some p -> Some p | None -> search rest)
      in
      search (String.split_on_char (path_sep ()) path)
end

(** {1 Tool discovery} *)

(* Windows Kit tools live under versioned bin dirs off PATH. *)
let sdk_tool name =
  let arch = match win_arch () with "arm64" -> "arm64" | _ -> "x64" in
  let roots =
    List.filter_map
      (fun v -> try Some (Sys.getenv v) with Not_found -> None)
      [ "ProgramFiles(x86)"; "ProgramW6432"; "ProgramFiles" ]
  in
  let hits = ref [] in
  List.iter
    (fun root ->
       let kits = Filename.concat root "Windows Kits" in
       let bins =
         [ Filename.concat (Filename.concat kits "10") "bin";
           Filename.concat kits "App Certification Kit" ]
       in
       List.iter
         (fun bin ->
            if P.Fs.is_dir bin then
              (* versioned subdirs first, then the bin dir itself *)
              let vers =
                try
                  List.filter
                    (fun e -> P.Fs.is_dir (Filename.concat bin e))
                    (Array.to_list (Sys.readdir bin))
                with Sys_error _ -> []
              in
              List.iter
                (fun v ->
                   let with_arch =
                     Filename.concat
                       (Filename.concat (Filename.concat bin v) arch)
                       name
                   and bare = Filename.concat (Filename.concat bin v) name in
                   if Sys.file_exists with_arch then hits := with_arch :: !hits;
                   if Sys.file_exists bare then hits := bare :: !hits)
                (List.sort compare vers @ [ "" ]))
         bins)
    roots;
  match List.sort compare !hits with
  | [] -> None
  | l -> Some (List.hd (List.rev l))

let powershell () =
  match Proc.which "powershell" with
  | Some p -> Some p
  | None -> (
    (* powershell lives in System32 even when PATH is thin. *)
    let root =
      match Sys.getenv_opt "SystemRoot" with
      | Some r -> r
      | None -> "C:\\Windows"
    in
    let p =
      Filename.concat
        (Filename.concat
           (Filename.concat root "System32")
           "WindowsPowerShell")
        "v1.0\\powershell.exe"
    in
    if Sys.file_exists p then Some p else None)

(* UTF-8 -> UTF-16 code units, surrogate pairs above the BMP, '?' for
   malformed input. Private.Plist keeps its decoder internal, so this
   is the local twin it would expose. *)
let utf16_units s =
  let n = String.length s in
  let i = ref 0 in
  let units = ref [] in
  let next () =
    let c = Char.code s.[!i] in
    if c < 0x80 then begin
      incr i;
      c
    end
    else if c land 0xe0 = 0xc0 && !i + 1 < n then begin
      let v = ((c land 0x1f) lsl 6) lor (Char.code s.[!i + 1] land 0x3f) in
      i := !i + 2;
      v
    end
    else if c land 0xf0 = 0xe0 && !i + 2 < n then begin
      let v =
        ((c land 0x0f) lsl 12)
        lor ((Char.code s.[!i + 1] land 0x3f) lsl 6)
        lor (Char.code s.[!i + 2] land 0x3f)
      in
      i := !i + 3;
      v
    end
    else if c land 0xf8 = 0xf0 && !i + 3 < n then begin
      let v =
        ((c land 0x07) lsl 18)
        lor ((Char.code s.[!i + 1] land 0x3f) lsl 12)
        lor ((Char.code s.[!i + 2] land 0x3f) lsl 6)
        lor (Char.code s.[!i + 3] land 0x3f)
      in
      i := !i + 4;
      v
    end
    else begin
      incr i;
      Char.code '?'
    end
  in
  while !i < n do
    let cp = next () in
    if cp < 0x10000 then units := cp :: !units
    else begin
      let v = cp - 0x10000 in
      units := (0xdc00 lor (v land 0x3ff)) :: (0xd800 lor (v lsr 10)) :: !units
    end
  done;
  List.rev !units

(* PowerShell takes the whole script as UTF-16LE base64, sidestepping
   command-line quoting entirely. *)
let powershell_run script =
  let b = Buffer.create (2 * String.length script) in
  List.iter
    (fun u ->
       Buffer.add_char b (Char.chr (u land 0xff));
       Buffer.add_char b (Char.chr ((u lsr 8) land 0xff)))
    (utf16_units script);
  let utf16 = Buffer.contents b in
  let b64 =
    let tbl =
      "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    in
    let n = String.length utf16 in
    let buf = Buffer.create (((n + 2) / 3) * 4) in
    let byte i = if i < n then Char.code utf16.[i] else 0 in
    for i = 0 to ((n + 2) / 3) - 1 do
      let o = 3 * i in
      let v = (byte o lsl 16) lor (byte (o + 1) lsl 8) lor byte (o + 2) in
      Buffer.add_char buf tbl.[(v lsr 18) land 63];
      Buffer.add_char buf tbl.[(v lsr 12) land 63];
      Buffer.add_char buf
        (if o + 1 < n then tbl.[(v lsr 6) land 63] else '=');
      Buffer.add_char buf
        (if o + 2 < n then tbl.[v land 63] else '=')
    done;
    Buffer.contents buf
  in
  let prog =
    match powershell () with Some p -> p | None -> "powershell.exe"
  in
  Proc.run prog
    [ "-NoProfile"; "-NonInteractive"; "-ExecutionPolicy"; "Bypass";
      "-EncodedCommand"; b64 ]

(** {1 ZIP — minimal archive writer and reader}

    Store-or-DEFLATE entries, central directory, EOCD record. No ZIP64:
    archives past 4 GiB or 65535 entries are refused. Names are always
    written with the UTF-8 flag. *)

module Zip = struct
  exception Bad of string

  type entry = {
    name : string;  (* '/'-separated, directories end in '/' *)
    dir : bool;
    mode : int;
    mtime : float;
    crc : int32;
    data : string;
  }

  let max_size = 0xffff_ffef (* headroom under the 4 GiB zip32 limit *)

  let fail fmt = Printf.ksprintf (fun s -> raise (Bad s)) fmt

  let dos_time t =
    let tm = Unix.localtime t in
    ( (tm.Unix.tm_hour lsl 11) lor (tm.Unix.tm_min lsl 5)
      lor (tm.Unix.tm_sec / 2),
      (max 0 (tm.Unix.tm_year - 80) lsl 9)
      lor ((tm.Unix.tm_mon + 1) lsl 5) lor tm.Unix.tm_mday )

  let u16 buf v =
    Buffer.add_string buf
      (String.init 2 (fun i -> Char.chr ((v lsr (8 * i)) land 0xff)))

  let u32 buf v =
    Buffer.add_string buf
      (String.init 4
         (fun i ->
            Char.chr
              (Int32.to_int
                 (Int32.logand (Int32.shift_right_logical v (8 * i)) 0xffl))))

  let slashify = String.map (fun c -> if c = '\\' then '/' else c)

  (* Local header + data per entry, then the central directory and the
     end record. Method 8 = raw DEFLATE, 0 = stored — used when DEFLATE
     would grow the payload (and for directories). *)
  let write ~entries ~out =
    if List.length entries > 0xfffe then
      fail "zip: %d entries exceeds the format" (List.length entries);
    let names = Hashtbl.create 256 in
    let oc = open_out_bin out in
    (try
       let central = Buffer.create 4096 in
       let offset = ref 0 in
       let put s =
         output_string oc s;
         offset := !offset + String.length s
       in
       List.iter
         (fun e ->
            let name = slashify e.name in
            if Hashtbl.mem names name then fail "zip: duplicate entry %s" name;
            Hashtbl.replace names name ();
            if String.length e.data > max_size then
              fail "zip: %s exceeds the 4 GiB format" name;
            let compressed, method_ =
              if e.dir then ("", 0)
              else
                let c = P.Deflate.deflate e.data in
                if String.length c >= String.length e.data then (e.data, 0)
                else (c, 8)
            in
            let t, d = dos_time e.mtime in
            let head = Buffer.create 64 in
            u32 head 0x04034b50l;
            u16 head 20;
            u16 head 0x800;
            u16 head method_;
            u16 head t;
            u16 head d;
            u32 head e.crc;
            u32 head (Int32.of_int (String.length compressed));
            u32 head (Int32.of_int (String.length e.data));
            u16 head (String.length name);
            u16 head 0;
            put (Buffer.contents head);
            put name;
            let local_off = !offset - 30 - String.length name in
            put compressed;
            u32 central 0x02014b50l;
            u16 central 20;
            u16 central 20;
            u16 central 0x800;
            u16 central method_;
            u16 central t;
            u16 central d;
            u32 central e.crc;
            u32 central (Int32.of_int (String.length compressed));
            u32 central (Int32.of_int (String.length e.data));
            u16 central (String.length name);
            u16 central 0;
            u16 central 0;
            u16 central 0;
            u16 central 0;
            u32 central
              (Int32.of_int
                 ((if e.dir then 0x10 else 0) lor (e.mode lsl 16)));
            u32 central (Int32.of_int local_off);
            Buffer.add_string central name)
         entries;
       let cd_off = !offset in
       put (Buffer.contents central);
       let tail = Buffer.create 32 in
       u32 tail 0x06054b50l;
       u16 tail 0;
       u16 tail 0;
       u16 tail (List.length entries);
       u16 tail (List.length entries);
       u32 tail (Int32.of_int (!offset - cd_off));
       u32 tail (Int32.of_int cd_off);
       u16 tail 0;
       put (Buffer.contents tail);
       close_out oc
     with e ->
       close_out_noerr oc;
       raise e)

  (** [write_dir ~src ~out] archives every file under [src] with
      '/'-separated names, directories included as their own entries. *)
  let write_dir ~src ~out =
    if not (P.Fs.is_dir src) then fail "zip source %s is not a directory" src;
    let entries =
      List.filter_map
        (fun (rel, kind) ->
           let rel = slashify rel in
           let path = Filename.concat src rel in
           match kind with
           | P.Fs.Dir ->
             Some
               { name = rel ^ "/"; dir = true; mode = 0o755;
                 mtime = (Unix.stat path).Unix.st_mtime; crc = 0l;
                 data = "" }
           | P.Fs.File ->
             let st = Unix.stat path in
             Some
               { name = rel; dir = false; mode = st.Unix.st_perm;
                 mtime = st.Unix.st_mtime; crc = 0l;
                 data = P.Fs.read_file path }
           | _ -> None)
        (List.sort compare (P.Fs.walk src))
    in
    write ~out
      ~entries:(List.map (fun e -> { e with crc = P.Crc32.string e.data }) entries)

  let get_u16 s o = Char.code s.[o] lor (Char.code s.[o + 1] lsl 8)

  let get_u32 s o =
    Int32.logor
      (Int32.of_int (get_u16 s o))
      (Int32.shift_left (Int32.of_int (get_u16 s (o + 2))) 16)

  type central = {
    c_name : string;
    c_method : int;
    c_csize : int;
    c_usize : int;
    c_off : int;
  }

  (* The EOCD record sits at the file tail, after a ≤64 KiB comment. *)
  let read_central path =
    let ic = open_in_bin path in
    let size = in_channel_length ic in
    let tail_len = min size (0xffff + 22) in
    seek_in ic (size - tail_len);
    let tail = really_input_string ic tail_len in
    close_in ic;
    let rec scan i =
      if i < 0 then -1
      else if i + 4 <= tail_len && String.sub tail i 4 = "PK\005\006" then i
      else scan (i - 1)
    in
    let eocd = scan (tail_len - 22) in
    if eocd < 0 then fail "zip: no end record in %s" path;
    let count = get_u16 tail (eocd + 10)
    and cd_size = Int32.to_int (get_u32 tail (eocd + 12))
    and cd_off = Int32.to_int (get_u32 tail (eocd + 16)) in
    let ic = open_in_bin path in
    seek_in ic cd_off;
    let cd = really_input_string ic cd_size in
    close_in ic;
    let rec parse o acc =
      if List.length acc = count then List.rev acc
      else if o + 46 > String.length cd || String.sub cd o 4 <> "PK\001\002"
      then fail "zip: central directory of %s is truncated" path
      else
        let name_len = get_u16 cd (o + 28)
        and extra_len = get_u16 cd (o + 30)
        and comment_len = get_u16 cd (o + 32) in
        let c =
          {
            (* zip names are '/'-separated; Compress-Archive emits '\'
               anyway, so normalize on the way in *)
            c_name = slashify (String.sub cd (o + 46) name_len);
            c_method = get_u16 cd (o + 10);
            c_csize = Int32.to_int (get_u32 cd (o + 20));
            c_usize = Int32.to_int (get_u32 cd (o + 24));
            c_off = Int32.to_int (get_u32 cd (o + 42));
          }
        in
        parse (o + 46 + name_len + extra_len + comment_len) (c :: acc)
    in
    parse 0 []

  let list path =
    List.map
      (fun c -> (c.c_name, c.c_usize, c.c_method))
      (read_central path)

  (** [extract path name] returns the member's contents, None when
      absent or undecodable. *)
  let extract path name =
    match
      List.find_opt (fun c -> c.c_name = name) (read_central path)
    with
    | None -> None
    | Some c ->
      let ic = open_in_bin path in
      seek_in ic c.c_off;
      let head = really_input_string ic 30 in
      let name_len = get_u16 head 26 and extra_len = get_u16 head 28 in
      (* the central directory's size is authoritative; a local header
         may carry 0 when a data descriptor follows the data *)
      seek_in ic (c.c_off + 30 + name_len + extra_len);
      let raw = really_input_string ic c.c_csize in
      close_in ic;
      (match c.c_method with
       | 0 -> Some raw
       | 8 -> (
         try Some (P.Deflate.inflate raw)
         with P.Deflate.Bad_stream _ -> None)
       | _ -> None)

  let extract_all ~src ~dst =
    List.iter
      (fun c ->
         let path = Filename.concat dst c.c_name in
         if
           String.length c.c_name > 0
           && c.c_name.[String.length c.c_name - 1] = '/'
         then P.Fs.mkdir_p path
         else
           match extract src c.c_name with
           | Some data -> P.Fs.write_file path data
           | None -> fail "zip: cannot extract %s" c.c_name)
      (read_central src)
end

(** {1 PE images} *)

module Pe = struct
  (* An Authenticode signature lives in the certificate table, the
     fifth entry of the optional header's data directories. *)
  let inspect path =
    let u16le s o = Char.code s.[o] lor (Char.code s.[o + 1] lsl 8) in
    let u32le s o =
      Char.code s.[o] lor (Char.code s.[o + 1] lsl 8)
      lor (Char.code s.[o + 2] lsl 16) lor (Char.code s.[o + 3] lsl 24)
    in
    try
      let ic = open_in_bin path in
      let dos = really_input_string ic (min 64 (in_channel_length ic)) in
      if String.length dos < 64 || String.sub dos 0 2 <> "MZ" then begin
        close_in ic;
        (false, false)
      end
      else begin
        let pe = u32le dos 0x3c in
        seek_in ic pe;
        let head = really_input_string ic 26 in
        if String.length head < 26 || String.sub head 0 4 <> "PE\000\000"
        then begin
          close_in ic;
          (false, false)
        end
        else begin
          let optional_size = u16le head 20 in
          let magic = u16le head 24 in
          let dirs = match magic with 0x10b -> 96 | 0x20b -> 112 | _ -> -1 in
          let result =
            if dirs < 0 then (true, false)
            else
              let security = 4 in
              if optional_size < dirs + ((security + 1) * 8) then (true, false)
              else begin
                seek_in ic (pe + 24 + dirs - 4);
                let d = really_input_string ic (4 + ((security + 1) * 8)) in
                let count = u32le d 0 in
                let size = u32le d (4 + (security * 8) + 4) in
                (true, count > security && size <> 0)
              end
          in
          close_in ic;
          result
        end
      end
    with Sys_error _ | End_of_file -> (false, false)

  let is_pe path = fst (inspect path)
  let is_signed path = snd (inspect path)
end

(** {1 Icons}

    ICO is a container that can hold PNG data directly; every Windows
    version this targets reads PNG-in-ICO. *)

module Ico = struct
  let png_dimensions data =
    if String.length data < 24 || String.sub data 0 8 <> "\137PNG\r\n\026\n"
    then None
    else if String.sub data 12 4 <> "IHDR" then None
    else
      let be o =
        (Char.code data.[o] lsl 24) lor (Char.code data.[o + 1] lsl 16)
        lor (Char.code data.[o + 2] lsl 8) lor Char.code data.[o + 3]
      in
      Some (be 16, be 20)

  let of_png png =
    match png_dimensions png with
    | None -> invalid "icon source is not a PNG"
    | Some (w, h) ->
      let dim v = if v >= 256 then 0 else v in
      let b = Buffer.create (22 + String.length png) in
      Buffer.add_string b "\x00\x00\x01\x00\x01\x00";
      Buffer.add_char b (Char.chr (dim w));
      Buffer.add_char b (Char.chr (dim h));
      Buffer.add_string b "\x00\x00\x01\x00\x20\x00";
      Buffer.add_string b
        (String.init 4
           (fun i -> Char.chr ((String.length png lsr (8 * i)) land 0xff)));
      Buffer.add_string b "\x16\x00\x00\x00";
      Buffer.add_string b png;
      L.Ok (Buffer.contents b)
end

(** {1 Manifests} *)

module Manifest = struct
  (* assemblyIdentity name: identifier characters only. *)
  let identity_name spec =
    let raw =
      if spec.L.bundle_id <> "" then spec.bundle_id else spec.name
    in
    String.map
      (fun c ->
         match c with
         | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '.' | '-' -> c
         | _ -> '-')
      raw

  let version4 v =
    let core =
      match String.index_opt v '-' with
      | Some i -> String.sub v 0 i
      | None -> v
    in
    let parts =
      List.map
        (fun s -> try int_of_string s with _ -> 0)
        (String.split_on_char '.' core)
    in
    match parts with
    | [ a; b; c; d ] -> (a, b, c, d)
    | [ a; b; c ] -> (a, b, c, 0)
    | [ a; b ] -> (a, b, 0, 0)
    | [ a ] -> (a, 0, 0, 0)
    | a :: b :: c :: d :: _ -> (a, b, c, d)
    | [] -> (0, 0, 0, 0)

  let xml_escape s =
    let b = Buffer.create (String.length s) in
    String.iter
      (function
        | '&' -> Buffer.add_string b "&amp;"
        | '<' -> Buffer.add_string b "&lt;"
        | '>' -> Buffer.add_string b "&gt;"
        | '"' -> Buffer.add_string b "&quot;"
        | c -> Buffer.add_char b c)
      s;
    Buffer.contents b

  (* Sidecar <name>.exe.manifest: comctl32 v6 for themed controls,
     Windows 10/11 compatibility, PerMonitorV2 + UTF-8 — what a
     self-drawn app needs when no manifest is embedded. *)
  let app_xml spec =
    let a, b, c, d = version4 spec.L.version in
    fmt
      {|<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<assembly xmlns="urn:schemas-microsoft-com:asm.v1" manifestVersion="1.0">
  <assemblyIdentity type="win32" name="%s" version="%d.%d.%d.%d" processorArchitecture="*"/>
  <dependency>
    <dependentAssembly>
      <assemblyIdentity type="win32" name="Microsoft.Windows.Common-Controls" version="6.0.0.0" processorArchitecture="*" publicKeyToken="6595b64144ccf1df" language="*"/>
    </dependentAssembly>
  </dependency>
  <compatibility xmlns="urn:schemas-microsoft-com:compatibility.v1">
    <application>
      <supportedOS Id="{8e0f7a12-bfb3-4fe8-b9a5-48fd50a15a9a}"/>
    </application>
  </compatibility>
  <application xmlns="urn:schemas-microsoft-com:asm.v3">
    <windowsSettings>
      <dpiAware xmlns="http://schemas.microsoft.com/SMI/2005/WindowsSettings">true/pm</dpiAware>
      <dpiAwareness xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">PerMonitorV2</dpiAwareness>
      <activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">UTF-8</activeCodePage>
      <longPathAware xmlns="http://schemas.microsoft.com/SMI/2016/WindowsSettings">true</longPathAware>
    </windowsSettings>
  </application>
</assembly>
|}
      (xml_escape (identity_name spec)) a b c d

  (* AppxManifest.xml staged for makeappx. The publisher is a
     placeholder identity: signing the finished package with a real
     certificate is what binds the publisher, makeappx only checks
     shape. *)
  let appx_xml spec ~arch =
    let a, b, c, d = version4 spec.L.version in
    let arch =
      match arch with
      | "arm64" -> "arm64"
      | "x86" | "i386" -> "x86"
      | _ -> "x64"
    in
    let name = xml_escape spec.L.name in
    let id = xml_escape (identity_name spec) in
    fmt
      {|<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10" xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10" xmlns:rescap="http://schemas.microsoft.com/appx/manifest/foundation/windows10/restrictedcapabilities">
  <Identity Name="%s" ProcessorArchitecture="%s" Publisher="CN=%s" Version="%d.%d.%d.%d"/>
  <Properties>
    <DisplayName>%s</DisplayName>
    <PublisherDisplayName>%s</PublisherDisplayName>
    <Description>%s</Description>
    <Logo>Assets\Logo.png</Logo>
  </Properties>
  <Resources>
    <Resource Language="en-us"/>
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.17763.0" MaxVersionTested="10.0.22621.0"/>
  </Dependencies>
  <Capabilities>
    <rescap:Capability Name="runFullTrust"/>
  </Capabilities>
  <Applications>
    <Application Id="%s" Executable="%s" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements DisplayName="%s" Description="%s" Square150x150Logo="Assets\Logo.png" Square44x44Logo="Assets\Logo.png" BackgroundColor="transparent"/>
    </Application>
  </Applications>
</Package>
|}
      id arch name a b c d name name name id
      (xml_escape (exe_name spec)) name name
end

(** {1 Bundle assembly — the portable directory} *)

module Bundle = struct
  let exe_name = exe_name

  let validate spec =
    if
      spec.L.name = "" || String.contains spec.name '/'
      || String.contains spec.name '\\'
    then invalid "app name %S" spec.name
    else if spec.bundle_id = "" then invalid "empty bundle id"
    else if P.Fs.kind_of spec.executable <> P.Fs.File then
      missing "executable %s" spec.executable
    else L.Ok ()

  let write spec ~dir =
    outcome_bind (validate spec) @@ fun () ->
    let arch = win_arch () in
    let root = Filename.concat dir (portable_dir_name spec ~arch) in
    P.Fs.rm_rf root;
    P.Fs.mkdir_p root;
    let exe_dst = Filename.concat root (exe_name spec) in
    P.Fs.copy_file ~src:spec.L.executable ~dst:exe_dst;
    P.Fs.write_file (exe_dst ^ ".manifest") (Manifest.app_xml spec);
    (match spec.L.icon with
     | None -> ()
     | Some src -> (
       match Ico.of_png (P.Fs.read_file src) with
       | L.Ok data ->
         P.Fs.write_file
           (Filename.concat root
              (Filename.chop_extension (exe_name spec) ^ ".ico"))
           data
       | (L.Failed _ | L.Skipped _ | L.Unsupported _) -> ()));
    let rec res_loop = function
      | [] -> L.Ok ()
      | r :: rest ->
        if not (P.Delta.valid_rel_path r.L.res_name) then
          invalid "bad resource name %S" r.res_name
        else if P.Fs.kind_of r.res_src = P.Fs.Absent then
          missing "resource %s" r.res_src
        else begin
          P.Fs.install ~src:r.res_src ~dst:(Filename.concat root r.res_name);
          res_loop rest
        end
    in
    outcome_bind (res_loop spec.L.resources) @@ fun () -> L.Ok root
end

(** {1 Signing} *)

module Sign = struct
  let signtool () =
    match Proc.which "signtool" with
    | Some p -> Some p
    | None -> sdk_tool "signtool.exe"

  let is_hex s =
    String.length s = 40
    && String.for_all
         (fun c ->
            (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
            || (c >= 'A' && c <= 'F'))
         s

  (* Certificate resolution: a .pfx path, a 40-hex store thumbprint,
     or an environment variable naming one of those. The .pfx password
     only ever comes from LUI_PKG_WINDOWS_CERT_PASSWORD. *)
  let cert_args = function
    | L.Adhoc -> Error (`Skipped "no ad-hoc signing on Windows")
    | L.Certificate s -> (
      let resolve v =
        if Sys.file_exists v then Some [ "/f"; v ]
        else if is_hex v then Some [ "/sha1"; v ]
        else None
      in
      match resolve s with
      | Some a -> Ok a
      | None -> (
        match Sys.getenv_opt s with
        | Some v when v <> "" -> (
          match resolve v with
          | Some a -> Ok a
          | None ->
            Error
              (`Skipped
                (fmt
                   "env var %s names no readable certificate (expected \
                    a .pfx path or store thumbprint); skipped"
                   s)))
        | _ ->
          Error
            (`Skipped
              (fmt
                 "certificate %S resolves nowhere — expected a .pfx \
                  path, a store thumbprint, or an env var holding one; \
                  skipped"
                 s))))

  let sign spec bundle =
    if not (P.Fs.is_dir bundle) then missing "bundle %s" bundle
    else
      match spec.L.identity with
      | L.Adhoc -> L.Skipped "no ad-hoc signing on Windows"
      | L.Certificate _ as id -> (
        match signtool () with
        | None -> L.Skipped "signtool not found (install the Windows SDK)"
        | Some tool -> (
          match cert_args id with
          | Error (`Skipped s) -> L.Skipped s
          | Stdlib.Ok cert -> (
            let pw =
              match Sys.getenv_opt "LUI_PKG_WINDOWS_CERT_PASSWORD" with
              | Some p when p <> "" -> [ "/p"; p ]
              | _ -> []
            in
            let ts =
              [ "/fd"; "sha256"; "/tr"; "http://timestamp.digicert.com";
                "/td"; "sha256" ]
            in
            let targets =
              List.filter_map
                (fun (rel, kind) ->
                   match kind with
                   | P.Fs.File ->
                     let p = Filename.concat bundle rel in
                     if Pe.is_pe p && not (Pe.is_signed p) then Some (rel, p)
                     else None
                   | _ -> None)
                (P.Fs.walk bundle)
            in
            let rec sign_all acc = function
              | [] -> Stdlib.Ok (List.rev acc)
              | (rel, p) :: rest -> (
                match
                  Proc.check tool ([ "sign" ] @ cert @ ts @ pw @ [ "/v"; p ])
                with
                | Ok _ -> sign_all (rel :: acc) rest
                | Error e -> Error e)
            in
            match sign_all [] targets with
            | Error e -> L.Failed e
            | Stdlib.Ok signed ->
              let verify =
                Proc.run tool
                  [ "verify"; "/pa"; "/v";
                    Filename.concat bundle (exe_name spec) ]
              in
              L.Ok
                {
                  L.signed;
                  codesign_verify =
                    {
                      L.tc_tool = "signtool";
                      tc_ran = true;
                      tc_ok = verify.status = 0;
                      tc_output = verify.stdout ^ verify.stderr;
                    };
                  spctl = None;
                })))
end

(** {1 NSIS installer} *)

module Nsis = struct
  let makensis () =
    match Proc.which "makensis" with
    | Some p -> Some p
    | None -> (
      let cands =
        List.concat_map
          (fun var ->
             match Sys.getenv_opt var with
             | Some root ->
               [ Filename.concat (Filename.concat root "NSIS") "makensis.exe" ]
             | None -> [])
          [ "ProgramFiles(x86)"; "ProgramFiles"; "ProgramW6432" ]
      in
      match List.filter Sys.file_exists cands with
      | [] -> None
      | p :: _ -> Some p)

  (* NSIS quoting: $ and the double quote are the special characters;
     backslashes stay literal since every path is a Windows path. *)
  let esc s =
    let b = Buffer.create (String.length s) in
    String.iter
      (fun c ->
         match c with
         | '$' -> Buffer.add_string b "$$"
         | '"' -> Buffer.add_string b "$\\\""
         | '\n' -> Buffer.add_string b "$\\n"
         | '\r' -> Buffer.add_string b "$\\r"
         | '\t' -> Buffer.add_string b "$\\t"
         | c -> Buffer.add_char b c)
      s;
    Buffer.contents b

  let q s = "\"" ^ esc s ^ "\""

  let installer_name spec ~arch =
    fmt "%s Setup %s %s.exe" (fs_name spec.L.name) (fs_name spec.version)
      arch

  let script spec ~src ~out ~arch:_ =
    (* Install top-level entries: files beside the exe as-is; each
       directory lands under $INSTDIR\<name> via SetOutPath so nested
       resource trees keep their shape. *)
    let files =
      Sys.readdir src
      |> Array.to_list
      |> List.filter_map
           (fun name ->
              let p = Filename.concat src name in
              match P.Fs.kind_of p with
              | P.Fs.Dir ->
                Some
                  (fmt "  SetOutPath \"$INSTDIR\\%s\"\n  File /r %s"
                     (esc name) (q (Filename.concat p "*.*")))
              | P.Fs.File -> Some (fmt "  SetOutPath \"$INSTDIR\"\n  File %s" (q p))
              | _ -> None)
      |> String.concat "\n"
    in
    let exe = exe_name spec in
    let key =
      "Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\"
      ^ spec.L.bundle_id
    in
    let exts =
      List.concat_map (fun (d : L.doc_type) -> d.extensions) spec.L.doc_types
    in
    let assocs =
      List.map
        (fun ext ->
           fmt
             "  WriteRegStr HKCU \"Software\\Classes\\.%s\" \"\" \"%s.%s\"\n\
             \  WriteRegStr HKCU \"Software\\Classes\\%s.%s\\shell\\open\\command\" \"\" '\"$INSTDIR\\%s\" \"%%1\"'"
             ext spec.L.bundle_id ext spec.bundle_id ext exe)
        exts
      |> String.concat "\n"
    in
    let unassocs =
      List.map
        (fun ext ->
           fmt
             "  DeleteRegKey HKCU \"Software\\Classes\\.%s\"\n\
             \  DeleteRegKey HKCU \"Software\\Classes\\%s.%s\""
             ext spec.L.bundle_id ext)
        exts
      |> String.concat "\n"
    in
    fmt
      {|Unicode true
ManifestDPIAware true
SetCompressor /SOLID lzma
Name %s
OutFile %s
InstallDir "$LOCALAPPDATA\Programs\%s"
RequestExecutionLevel user
BrandingText " "
!define MUI_FINISHPAGE_RUN "$INSTDIR\%s"
!include "MUI2.nsh"
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

Section
%s
  WriteUninstaller "$INSTDIR\Uninstall.exe"
  CreateShortCut "$SMPROGRAMS\%s.lnk" "$INSTDIR\%s"
  WriteRegStr HKCU %s "DisplayName" %s
  WriteRegStr HKCU %s "DisplayVersion" %s
  WriteRegStr HKCU %s "DisplayIcon" "$INSTDIR\%s"
  WriteRegStr HKCU %s "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU %s "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU %s "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU %s "NoModify" 1
  WriteRegDWORD HKCU %s "NoRepair" 1
%s
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\%s.lnk"
  DeleteRegKey HKCU %s
%s
  ; Last, once the app's own files can go — the uninstaller runs from a
  ; copy of itself that nothing waits for.
  RMDir /r "$INSTDIR"
SectionEnd
|}
      (q spec.L.name) (q out) (esc spec.name) exe files (esc spec.name) exe
      (q key) (q spec.name) (q key) (q spec.version) (q key) exe (q key)
      (q key) (q key) (q key) (q key) assocs (esc spec.name) (q key)
      unassocs

  let make spec src ~dir ~arch =
    match makensis () with
    | None -> L.Skipped "makensis not found (install NSIS)"
    | Some tool ->
      let out = Filename.concat dir (installer_name spec ~arch) in
      let work = P.Fs.temp_dir ~prefix:"lui_pkg-nsis-" () in
      let nsi = Filename.concat work "installer.nsi" in
      P.Fs.write_file nsi (script spec ~src ~out ~arch);
      (match Proc.check tool [ "-V2"; nsi ] with
       | Stdlib.Ok _ ->
         P.Fs.rm_rf work;
         L.Ok out
       | Error e ->
         P.Fs.rm_rf work;
         L.Failed e)
end

(** {1 MSIX} *)

module Msix = struct
  let makeappx () =
    match Proc.which "makeappx" with
    | Some p -> Some p
    | None -> sdk_tool "makeappx.exe"

  let msix_name spec ~arch =
    fmt "%s-%s-windows-%s.msix" (fs_name spec.L.name)
      (fs_name spec.version) arch

  let make spec src ~dir ~arch =
    match makeappx () with
    | None -> L.Skipped "makeappx not found (install the Windows SDK)"
    | Some tool -> (
      match spec.L.icon with
      | None -> L.Skipped "msix packaging needs spec.icon — a package logo"
      | Some icon ->
        if P.Fs.kind_of icon <> P.Fs.File then missing "icon %s" icon
        else begin
          let stage = P.Fs.temp_dir ~prefix:"lui_pkg-msix-" () in
          let out = Filename.concat dir (msix_name spec ~arch) in
          let result =
            try
              P.Fs.install ~src ~dst:stage;
              P.Fs.mkdir_p (Filename.concat stage "Assets");
              P.Fs.copy_file ~src:icon
                ~dst:(Filename.concat
                        (Filename.concat stage "Assets")
                        "Logo.png");
              P.Fs.write_file
                (Filename.concat stage "AppxManifest.xml")
                (Manifest.appx_xml spec ~arch);
              match
                Proc.check tool [ "pack"; "/d"; stage; "/p"; out; "/l" ]
              with
              | Stdlib.Ok _ -> L.Ok out
              | Error e -> L.Failed e
            with e -> L.Failed (L.Invalid (Printexc.to_string e))
          in
          P.Fs.rm_rf stage;
          result
        end)
end

(** {1 PowerShell Compress-Archive (fallback path)}

    The pure-OCaml writer is the default everywhere — no tool
    dependency, and the tools test verifies its output against the
    platform's own Expand-Archive. This remains as the documented
    fallback for hosts whose policy forbids producing archives from
    unsigned code paths. *)

module Ps_zip = struct
  let psq s =
    (* PowerShell single-quote: inner quotes double up. *)
    let b = Buffer.create (String.length s) in
    String.iter
      (fun c -> if c = '\'' then Buffer.add_string b "''" else Buffer.add_char b c)
      s;
    "'" ^ Buffer.contents b ^ "'"

  let compress_archive ~src ~out =
    match powershell () with
    | None -> L.Skipped "powershell not found"
    | Some _ ->
      if not (P.Fs.is_dir src) then missing "zip source %s" src
      else
        let script =
          fmt
            "Compress-Archive -LiteralPath %s -DestinationPath %s -Force"
            (psq src) (psq out)
        in
        let r = powershell_run script in
        if r.status = 0 then L.Ok out
        else
          L.Failed
            (L.Tool_failed
               { tool = "powershell"; args = [ "Compress-Archive" ];
                 status = r.status; output = r.stdout ^ r.stderr })
end
end

(** {1 Public API} *)

type package_format = Zip | Msix | Nsis

let string_of_package_format = function
  | Zip -> "zip"
  | Msix -> "msix"
  | Nsis -> "nsis"

let find_tool = Private.Proc.which
let sdk_tool = Private.sdk_tool
let powershell = Private.powershell
let powershell_run = Private.powershell_run
let installer_name = Private.Nsis.installer_name
let msix_name = Private.Msix.msix_name
let manifest spec = Private.Manifest.app_xml spec
let appx_manifest spec ~arch = Private.Manifest.appx_xml spec ~arch
let nsis_script spec ~src ~out ~arch =
  Private.Nsis.script spec ~src ~out ~arch
let bundle spec ~dir = Private.Bundle.write spec ~dir
let sign spec bundle = Private.Sign.sign spec bundle

let package ?(fmt = Zip) ?arch spec bundle ~dir =
  let arch =
    match arch with
    | Some a -> a
    | None -> win_arch ()
  in
  let arch =
    match arch with "x86_64" | "amd64" -> "x64" | "aarch64" -> "arm64" | a -> a
  in
  match fmt with
  | Zip -> (
    let out = Filename.concat dir (zip_name spec ~arch) in
    try
      Private.Zip.write_dir ~src:bundle ~out;
      L.Ok out
    with Private.Zip.Bad m -> L.Failed (L.Invalid m))
  | Msix -> Private.Msix.make spec bundle ~dir ~arch
  | Nsis -> Private.Nsis.make spec bundle ~dir ~arch

let notarize _spec _path =
  L.Skipped
    "Windows has no notarization — sign the installer and the app \
     instead; SmartScreen reputation attaches to the signature"

let windows_packager =
  {
    L.pkg_platform = L.Windows;
    pkg_bundle = (fun spec dir -> bundle spec ~dir);
    pkg_sign = sign;
    pkg_notarize = notarize;
    pkg_disk_image = (fun spec app dir -> package ~fmt:Zip spec app ~dir);
  }

(** {1 Delta updates — the shared format}

    Windows file locking makes in-place apply impossible: apply into a
    staging directory beside the install (see the module comment), then
    swap top-level entries with renames as lui_updater's Dir layout
    does. *)

let update_pkg = L.update_pkg
let apply_delta = L.apply_delta

let stage_dir_for install_dir = install_dir ^ ".update"
