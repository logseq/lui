module Json = Yojson.Basic.Util

type artifact = { url : string; size : int; sha256 : string }
type release = {
  version : string;
  build : int;
  notes : string;
  full : artifact;
  delta : artifact option;
}

let fail message = failwith ("Desktop update: " ^ message)
let max_package = 2_000_000_000

let read_file ~limit path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      let length = in_channel_length channel in
      if length > limit then fail "file exceeds its size limit";
      really_input_string channel length)

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
      output_string channel contents)

let rec remove_tree path =
  match Unix.lstat path with
  | { Unix.st_kind = Unix.S_DIR; _ } ->
      Array.iter (fun name -> remove_tree (Filename.concat path name))
        (Sys.readdir path);
      Unix.rmdir path
  | _ -> Unix.unlink path
  | exception Unix.Unix_error (Unix.ENOENT, _, _) -> ()

let field name json = Json.member name json
let text name json = field name json |> Json.to_string
let integer name json = field name json |> Json.to_int

let unhex value =
  let digit = function
    | '0' .. '9' as c -> Char.code c - Char.code '0'
    | 'a' .. 'f' as c -> Char.code c - Char.code 'a' + 10
    | _ -> fail "invalid lowercase hex encoding"
  in
  if String.length value mod 2 <> 0 then fail "invalid hex length";
  String.init (String.length value / 2) (fun i ->
      Char.chr ((digit value.[2 * i] lsl 4) lor digit value.[2 * i + 1]))

let https url =
  let parsed = Uri.of_string url in
  if Uri.scheme parsed <> Some "https" || Uri.host parsed = None
     || Uri.userinfo parsed <> None || Uri.fragment parsed <> None
  then fail "download URL must use HTTPS without credentials or a fragment";
  url

let artifact json =
  let url = text "url" json |> https in
  let size = integer "size" json in
  let sha256 = text "sha256" json in
  if size <= 0 || size > max_package then fail "invalid artifact size";
  if String.length sha256 <> 64 then fail "invalid SHA-256 length";
  ignore (unhex sha256);
  { url; size; sha256 }

let authenticate ~public_key ~app_id ~platform ~current_build envelope =
  if String.length envelope > 1_048_576 then fail "manifest exceeds size limit";
  let envelope = Yojson.Basic.from_string envelope in
  let payload = text "payload" envelope in
  let signature = text "signature" envelope |> unhex in
  let key =
    match Mirage_crypto_ec.Ed25519.pub_of_octets (unhex public_key) with
    | Ok key -> key
    | Error _ -> fail "invalid Ed25519 public key"
  in
  if String.length signature <> 64
     || not (Mirage_crypto_ec.Ed25519.verify ~key signature
               ~msg:("lui desktop update v1\n" ^ payload))
  then fail "invalid manifest signature";
  let release = Yojson.Basic.from_string payload in
  if integer "schema" release <> 1 || text "app_id" release <> app_id
     || text "platform" release <> platform
  then fail "manifest belongs to a different application or platform";
  let build = integer "build" release in
  if build <= current_build then None
  else
    let deltas = field "deltas" release |> Json.to_list in
    let delta = List.find_opt
        (fun delta -> integer "from_build" delta = current_build) deltas in
    Some { version = text "version" release; build; notes = text "notes" release;
           full = artifact (field "full" release);
           delta = Option.map (fun delta -> artifact (field "artifact" delta)) delta }

let sha256_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      let buffer = Bytes.create 65536 in
      let rec loop hash =
        let count = input channel buffer 0 (Bytes.length buffer) in
        if count = 0 then Digestif.SHA256.(to_hex (get hash))
        else loop (Digestif.SHA256.feed_bytes hash ~len:count buffer)
      in
      loop Digestif.SHA256.empty)

let verify_file artifact path =
  if (Unix.stat path).Unix.st_size <> artifact.size
     || sha256_file path <> artifact.sha256
  then fail "artifact size or SHA-256 mismatch"

let download artifact destination =
  ignore (https artifact.url);
  let arguments = [| "curl"; "--fail"; "--silent"; "--show-error";
    "--location"; "--proto"; "=https"; "--proto-redir"; "=https";
    "--tlsv1.2"; "--connect-timeout"; "20"; "--max-time"; "600";
    "--max-filesize"; string_of_int artifact.size;
    "--output"; destination; "--url"; artifact.url |] in
  let process = Unix.create_process "curl" arguments Unix.stdin Unix.stdout Unix.stderr in
  match snd (Unix.waitpid [] process) with
  | Unix.WEXITED 0 -> verify_file artifact destination
  | Unix.WEXITED _ | Unix.WSIGNALED _ | Unix.WSTOPPED _ -> fail "download failed"

let safe_path path =
  let invalid_part part =
    let stem = String.split_on_char '.' part |> List.hd |> String.uppercase_ascii in
    part = "" || part = "." || part = ".."
    || String.ends_with ~suffix:"." part || String.ends_with ~suffix:" " part
    || List.mem stem ["CON"; "PRN"; "AUX"; "NUL"; "COM1"; "COM2"; "COM3";
                      "COM4"; "COM5"; "COM6"; "COM7"; "COM8"; "COM9";
                      "LPT1"; "LPT2"; "LPT3"; "LPT4"; "LPT5"; "LPT6"; "LPT7"; "LPT8"; "LPT9"]
  in
  if path = "" || String.length path > 4096 || not (Filename.is_relative path)
     || String.contains path '\\' || String.contains path ':'
     || String.exists (fun c -> Char.code c < 32) path
     || List.exists invalid_part (String.split_on_char '/' path)
  then fail "unsafe package path";
  path

let rec ensure_directory path =
  if Sys.file_exists path then (
    if (Unix.lstat path).Unix.st_kind <> Unix.S_DIR then fail "non-directory parent")
  else (ensure_directory (Filename.dirname path); Unix.mkdir path 0o700)

let safe_installed_file installed path =
  let parts = String.split_on_char '/' (safe_path path) in
  let rec walk parent = function
    | [] -> fail "empty source path"
    | [name] ->
        let path = Filename.concat parent name in
        if (Unix.lstat path).Unix.st_kind <> Unix.S_REG then fail "invalid delta source";
        path
    | name :: rest ->
        let parent = Filename.concat parent name in
        if (Unix.lstat parent).Unix.st_kind <> Unix.S_DIR then fail "linked delta parent";
        walk parent rest
  in
  walk installed parts

let copy_exact input output size =
  let buffer = Bytes.create 65536 in
  let rec loop remaining =
    if remaining > 0 then (
      let count = min remaining (Bytes.length buffer) in
      really_input input buffer 0 count;
      output_bytes output (if count = Bytes.length buffer then buffer else Bytes.sub buffer 0 count);
      loop (remaining - count))
  in
  loop size

let stage ~package ~installed ~destination =
  if Sys.file_exists destination then fail "staging directory already exists";
  let input = open_in_bin package in
  Fun.protect ~finally:(fun () -> close_in input) (fun () ->
    if really_input_string input 8 <> "LUIUPD1\n" then fail "invalid package header";
    let length = input_binary_int input in
    if length <= 0 || length > 8_388_608 then fail "invalid package index length";
    let index = Yojson.Basic.from_string (really_input_string input length) in
    let entries = field "files" index |> Json.to_list in
    if integer "schema" index <> 1 || List.length entries > 100_000
    then fail "invalid package index";
    let payload_start = pos_in input in
    let package_size = in_channel_length input in
    let seen = Hashtbl.create (List.length entries) in
    let next_offset = ref 0 in
    let total_size = ref 0 in
    Unix.mkdir destination 0o700;
    try
      List.iter (fun entry ->
        let path = text "path" entry |> safe_path in
        let folded = String.lowercase_ascii path in
        if Hashtbl.mem seen folded then fail "duplicate or case-colliding package path";
        Hashtbl.add seen folded ();
        let size = integer "size" entry in
        let mode = integer "mode" entry in
        let sha256 = text "sha256" entry in
        if size < 0 || size > max_package - !total_size
           || not (mode = 0o644 || mode = 0o755)
           || String.length sha256 <> 64
        then fail "invalid package entry";
        ignore (unhex sha256);
        total_size := !total_size + size;
        let output_path = Filename.concat destination path in
        ensure_directory (Filename.dirname output_path);
        let output = Unix.openfile output_path [Unix.O_WRONLY; Unix.O_CREAT; Unix.O_EXCL] 0o600
                     |> Unix.out_channel_of_descr in
        Fun.protect ~finally:(fun () -> close_out output) (fun () ->
          match field "offset" entry with
          | `Int offset ->
              if offset <> !next_offset || size > package_size - payload_start - offset
              then fail "overlapping or out-of-bounds package payload";
              seek_in input (payload_start + offset);
              copy_exact input output size;
              next_offset := offset + size
          | `Null ->
              let source = safe_installed_file installed path |> open_in_bin in
              Fun.protect ~finally:(fun () -> close_in source) (fun () ->
                if in_channel_length source <> size then fail "delta source size mismatch";
                copy_exact source output size)
          | _ -> fail "invalid payload offset");
        Unix.chmod output_path mode;
        if sha256_file output_path <> sha256 then fail "reconstructed file hash mismatch"
      ) entries;
      if payload_start + !next_offset <> package_size then fail "unreferenced package payload"
    with error -> remove_tree destination; raise error)

type installation = { target : string; backup : string }

let install ~staged ~target =
  if Filename.dirname staged <> Filename.dirname target || staged = target
     || (Unix.lstat staged).Unix.st_kind <> Unix.S_DIR
     || (Unix.lstat target).Unix.st_kind <> Unix.S_DIR
  then fail "replacement requires sibling directories";
  let backup = target ^ ".lui-previous" in
  if Sys.file_exists backup then fail "previous update needs recovery";
  Unix.rename target backup;
  (try Unix.rename staged target
   with error -> Unix.rename backup target; raise error);
  { target; backup }

let confirm installation = remove_tree installation.backup

let rollback installation =
  let failed = installation.target ^ ".lui-failed" in
  if Sys.file_exists failed then fail "failed update directory already exists";
  Unix.rename installation.target failed;
  (try Unix.rename installation.backup installation.target
   with error -> Unix.rename failed installation.target; raise error);
  remove_tree failed
