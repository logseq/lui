(* The runtime self-update client: feed check, delta-first plan,
   verified download, staged apply, rename-dance swap, detached
   relaunch. The contract and the feed format are in lui_updater.mli.

   Fetching is injected (a [fetcher] record); the default shells out to
   curl with hardened flags so the library has no raw HTTP dependency
   and headless tests never touch the network. Delta math and hashing
   come from [Lui_pkg]; nothing here reimplements them. *)

type channel = Stable | Beta | Named of string

type feed = {
  base_url : string;
  channel : channel;
  app_id : string;
  app_name : string;
  version : string;
}

type artifact = {
  url : string;
  size : int;
  sha256 : string;
  signature : string option;
}

type delta = { from : string; artifact : artifact }

type update_info = {
  version : string;
  notes : string;
  date : string;
  archive : artifact;
  deltas : delta list;
}

type install_plan = Full of artifact | Delta of delta

type progress = { received : int; total : int }

(* Reuse the sibling module's fs/process/hash internals rather than
   duplicating them; [outcome] is the shared result vocabulary. *)
module P = Lui_pkg.Private

let fmt = Printf.sprintf
let error fmt = Printf.ksprintf (fun s -> Stdlib.Error s) fmt

(* ------------------------------------------------------------------ *)
(* State machine — pure, drives host UI. *)

type state =
  | Idle
  | Checking
  | Available of update_info
  | Downloading of progress
  | Ready of string
  | Applied
  | Error of string

type event =
  | Begin_check
  | Checked of update_info option
  | Begin_download of update_info
  | Progress of progress
  | Staged of string
  | Applied_to of string
  | Failed of string
  | Dismissed

let step st ev =
  match (st, ev) with
  | Idle, Begin_check -> Checking
  | Checking, Checked (Some i) -> Available i
  | Checking, Checked None -> Idle
  | Available _, Begin_download i ->
    Downloading { received = 0; total = i.archive.size }
  | Downloading _, Progress p -> Downloading p
  | Downloading _, Staged path -> Ready path
  | Ready _, Applied_to _ -> Applied
  | Ready _, Begin_check -> Checking
  | Error _, Begin_check -> Checking
  | (Available _ | Error _), Dismissed -> Idle
  | _, Failed m -> Error m
  | _ -> st

(* ------------------------------------------------------------------ *)
(* Versions: numbers numerically, a pre-release before its release,
   numbers before words; a leading "v" and a "+build" suffix ignored. *)

let compare_fields a b =
  let af = String.split_on_char '.' a
  and bf = String.split_on_char '.' b in
  let rec go = function
    | [], [] -> 0
    | x :: xs, y :: ys when x = y -> go (xs, ys)
    | [], _ :: _ -> -1
    | _ :: _, [] -> 1
    | x :: xs, y :: ys -> (
      match (int_of_string_opt x, int_of_string_opt y) with
      | Some xn, Some yn ->
        if xn < yn then -1 else if xn > yn then 1 else go (xs, ys)
      | Some _, None -> -1
      | None, Some _ -> 1
      | None, None ->
        let c = String.compare x y in
        if c <> 0 then c else go (xs, ys))
  in
  go (af, bf)

let compare_version a b =
  let strip s =
    let s =
      if String.length s > 0 && s.[0] = 'v' then
        String.sub s 1 (String.length s - 1)
      else s
    in
    match String.index_opt s '+' with
    | Some i -> String.sub s 0 i
    | None -> s
  in
  let cut_dash s =
    match String.index_opt s '-' with
    | Some i ->
      (String.sub s 0 i, String.sub s (i + 1) (String.length s - i - 1))
    | None -> (s, "")
  in
  let ar, apre = cut_dash (strip a) and br, bpre = cut_dash (strip b) in
  match compare_fields ar br with
  | 0 ->
    if apre = bpre then 0
    else if apre = "" then 1
    else if bpre = "" then -1
    else compare_fields apre bpre
  | c -> c

(* ------------------------------------------------------------------ *)
(* Check cadence: an interval after the last success; on failure retry
   within an hour at most. Pure for tests. *)

let next_check ~last ~failed ~interval ~now =
  let last = if last > now then now else last in
  let due = last +. interval in
  if failed <> 0. then begin
    let retry = failed +. Float.min interval 3600. in
    Float.min retry due
  end
  else due

(* ------------------------------------------------------------------ *)
(* Fetching. *)

type fetcher = { get : url:string -> dest:string -> (unit, string) result }

let is_loopback host =
  host = "localhost"
  || (String.length host >= 4 && String.sub host 0 4 = "127.")
  || host = "::1" || host = "[::1]"

let url_scheme url =
  match String.index_opt url ':' with
  | Some i -> String.sub url 0 i
  | None -> ""

let url_host url =
  (* The host of scheme://host/...; "" when not an authority URL. *)
  match String.index_opt url ':' with
  | Some i when i + 3 <= String.length url
               && String.sub url (i + 1) 2 = "//" ->
    let rest = String.sub url (i + 3) (String.length url - i - 3) in
    let host =
      match String.index_opt rest '/' with
      | Some j -> String.sub rest 0 j
      | None -> rest
    in
    let host =
      match String.rindex_opt host '@' with
      | Some k -> String.sub host (k + 1) (String.length host - k - 1)
      | None -> host
    in
    (match String.index_opt host ':' with
     | Some _ when host.[0] = '[' ->
       (* [v6]:port — keep the brackets for is_loopback. *)
       (match String.index_opt host ']' with
        | Some j -> String.sub host 0 (j + 1)
        | None -> host)
     | Some k -> String.sub host 0 k
     | None -> host)
  | _ -> ""

let url_allowed url =
  match url_scheme url with
  | "https" | "file" -> true
  | "http" -> is_loopback (url_host url)
  | _ -> false

let user_agent f = fmt "Lui_updater/1 %s/%s" f.app_name f.version

(* curl flags: fail on HTTP errors, quiet but for errors, follow
   redirects (to https only), bounded connect and total time. The
   downloaded file is verified afterwards, so partial bodies can never
   stand in for real content. *)
let curl_fetcher ?(user_agent = "Lui_updater/1") () =
  {
    get =
      (fun ~url ~dest ->
        if not (url_allowed url) then error "refusing to fetch %s" url
        else
          match
            P.Proc.check "curl"
              [
                "-fsSL";
                "--proto-redir"; "=https";
                "--connect-timeout"; "15";
                "--max-time"; "600";
                "-A"; user_agent;
                "-o"; dest;
                url;
              ]
          with
          | Stdlib.Ok _ -> Stdlib.Ok ()
          | Stdlib.Error e -> Error (Lui_pkg.string_of_failure e));
  }

(* Fetch to a temp file then read it: one mechanism for manifests and
   packages alike. *)
let fetch_text fetch url =
  let tmp = P.Fs.temp_dir ~prefix:"lui_upd-" () in
  let dest = Filename.concat tmp "body" in
  match fetch.get ~url ~dest with
  | Stdlib.Error m ->
    P.Fs.rm_rf tmp;
    Stdlib.Error m
  | Stdlib.Ok () ->
    let s = P.Fs.read_file dest in
    P.Fs.rm_rf tmp;
    Stdlib.Ok s

(* ------------------------------------------------------------------ *)
(* Feed and manifest. *)

let channel_name = function
  | Stable -> "stable"
  | Beta -> "beta"
  | Named n -> n

let feed_url f = fmt "%s/%s.json" f.base_url (channel_name f.channel)

let max_manifest = 1 lsl 20
let max_package = 1 lsl 30

let hex64 s =
  String.length s = 64
  && String.for_all
       (fun c ->
          (c >= '0' && c <= '9')
          || (c >= 'a' && c <= 'f')
          || (c >= 'A' && c <= 'F'))
       s

let artifact_of_json j =
  let open Yojson.Safe.Util in
  let url = j |> member "url" |> to_string_option |> Option.value ~default:"" in
  let size = j |> member "size" |> to_int_option |> Option.value ~default:0 in
  let sha256 =
    j |> member "sha256" |> to_string_option |> Option.value ~default:""
  in
  let signature = j |> member "signature" |> to_string_option in
  if url = "" || size <= 0 || not (hex64 sha256) then None
  else Some { url; size; sha256; signature }

let manifest_of_string s =
  try
    let j = Yojson.Safe.from_string s in
    let open Yojson.Safe.Util in
    let version =
      j |> member "version" |> to_string_option |> Option.value ~default:""
    in
    if version = "" then error "incomplete manifest: no version"
    else
      match artifact_of_json j with
      | None -> error "incomplete manifest: no usable archive entry"
      | Some archive ->
        let deltas =
          (match j |> member "deltas" with
           | `List l -> l
           | _ -> [])
          |> List.filter_map (fun d ->
                 match
                   ( d |> member "from" |> to_string_option,
                     artifact_of_json d )
                 with
                 | Some from, Some artifact -> Some { from; artifact }
                 | _ -> None)
        in
        let notes =
          j |> member "notes" |> to_string_option |> Option.value ~default:""
        and date =
          j |> member "date" |> to_string_option |> Option.value ~default:""
        in
        Stdlib.Ok { version; notes; date; archive; deltas }
  with Yojson.Json_error m -> error "manifest is not valid JSON: %s" m

let check ?fetch f =
  let fetch =
    match fetch with
    | Some fc -> fc
    | None -> curl_fetcher ~user_agent:(user_agent f) ()
  in
  let url = feed_url f in
  if not (url_allowed url) then error "refusing to fetch %s" url
  else
    match fetch_text fetch url with
    | Stdlib.Error m -> Stdlib.Error m
    | Stdlib.Ok body ->
      if String.length body > max_manifest then
        error "manifest too large (%d bytes)" (String.length body)
      else
        match manifest_of_string body with
        | Stdlib.Error m -> Stdlib.Error m
        | Stdlib.Ok info ->
          if compare_version info.version f.version > 0 then
            Stdlib.Ok (Some info)
          else Stdlib.Ok None

(* ------------------------------------------------------------------ *)
(* Plan: delta-first. *)

let plan i ~current =
  match List.find_opt (fun d -> d.from = current) i.deltas with
  | Some d -> Delta d
  | None -> Full i.archive

(* ------------------------------------------------------------------ *)
(* Download: size + sha256 always, signature via the injected hook. *)

let download ?(fetch = curl_fetcher ()) ?verify_sig ?progress a ~dest =
  if a.size <= 0 || a.size > max_package then error "invalid size %d" a.size
  else if not (url_allowed a.url) then error "refusing to fetch %s" a.url
  else begin
    Option.iter (fun p -> p ~received:0 ~total:a.size) progress;
    match fetch.get ~url:a.url ~dest with
    | Stdlib.Error m -> Stdlib.Error m
    | Stdlib.Ok () -> (
      let n = Option.value ~default:0 (P.Fs.file_size dest) in
      if n <> a.size then error "downloaded %d bytes, want %d" n a.size
      else
        let sum = P.Sha256.file dest in
        if String.compare sum a.sha256 <> 0 then
          error "downloaded file has sha256 %s, want %s" sum a.sha256
        else
          match (a.signature, verify_sig) with
          | Some sig_, Some verify
            when not (verify ~sha256:sum ~signature:sig_) ->
            error "signature check failed for %s" a.url
          | _ ->
            Option.iter (fun p -> p ~received:a.size ~total:a.size) progress;
            Stdlib.Ok ())
  end

(* ------------------------------------------------------------------ *)
(* Staging, apply, swap. *)

type layout = App_bundle | Dir

type staged = { stage_dir : string; new_root : string; layout : layout }

let stage_dir_of bundle = bundle ^ ".update"

let layout_of target =
  if Filename.check_suffix target ".app" then App_bundle else Dir

(* The one entry an App_bundle stage holds. *)
let staged_bundle stage_dir =
  match
    Sys.readdir stage_dir
    |> Array.to_list
    |> List.filter (fun n -> Filename.check_suffix n ".app")
  with
  | [ name ] -> Stdlib.Ok (Filename.concat stage_dir name)
  | [] -> error "the update holds no app bundle"
  | _ -> error "the update holds more than one app bundle"

(* Untar a full package into [into]. *)
let untar ~package ~into =
  P.Fs.mkdir_p into;
  match P.Proc.check "tar" [ "-xzf"; package; "-C"; into ] with
  | Stdlib.Ok _ -> Stdlib.Ok ()
  | Stdlib.Error e -> Error (Lui_pkg.string_of_failure e)

let outcome_to_result = function
  | Lui_pkg.Ok v -> Stdlib.Ok v
  | Lui_pkg.Skipped m -> Stdlib.Error m
  | Lui_pkg.Unsupported m -> Stdlib.Error m
  | Lui_pkg.Failed e -> Stdlib.Error (Lui_pkg.string_of_failure e)

let apply ?verify ~info ~plan ~package ~bundle ~stage_dir () =
  let layout = layout_of bundle in
  if P.Fs.exists stage_dir then P.Fs.rm_rf stage_dir;
  let build =
    match plan with
    | Delta d -> (
      P.Fs.mkdir_p stage_dir;
      (* The new tree lands in the stage dir named after the target,
         so the swap can rename it into place. *)
      let new_root =
        match layout with
        | App_bundle ->
          Filename.concat stage_dir (Filename.basename bundle)
        | Dir -> Filename.concat stage_dir "app"
      in
      match
        outcome_to_result
          (Lui_pkg.apply_delta ~delta:package ~from:d.from ~to_:info.version
             ~old_dir:bundle ~new_dir:new_root)
      with
      | Stdlib.Ok () -> Stdlib.Ok new_root
      | Stdlib.Error m -> Stdlib.Error m)
    | Full _ -> (
      match untar ~package ~into:stage_dir with
      | Stdlib.Error m -> Stdlib.Error m
      | Stdlib.Ok () -> (
        match layout with
        | App_bundle -> staged_bundle stage_dir
        | Dir -> Stdlib.Ok stage_dir))
  in
  match build with
  | Stdlib.Error m ->
    P.Fs.rm_rf stage_dir;
    Stdlib.Error m
  | Stdlib.Ok new_root -> (
    match verify with
    | None -> Stdlib.Ok { stage_dir; new_root; layout }
    | Some v -> (
      match outcome_to_result (v new_root) with
      | Stdlib.Ok () -> Stdlib.Ok { stage_dir; new_root; layout }
      | Stdlib.Error m ->
        P.Fs.rm_rf stage_dir;
        Stdlib.Error (fmt "staged update failed verification: %s" m)))

(* Renames stay inside one filesystem: the stage dir and the backup
   live next to the target. *)
let rename = Unix.rename

let swap_bundle ~new_root ~target =
  let backup =
    Filename.concat (Filename.dirname target)
      (fmt ".%s.old-%d" (Filename.basename target) (Unix.getpid ()))
  in
  rename target backup;
  match
    (try
       rename new_root target;
       Stdlib.Ok ()
     with Unix.Unix_error (e, _, _) -> Stdlib.Error (Unix.error_message e))
  with
  | Stdlib.Ok () -> Stdlib.Ok backup
  | Stdlib.Error m ->
    (try rename backup target with Unix.Unix_error _ -> ());
    Stdlib.Error m

(* Directory installs: swap each top-level entry, undo on mid-failure,
   drop the asides on success — per-entry renames absorb an OS that
   keeps running executables open. *)
let swap_dir ~new_root ~target =
  let entries = Sys.readdir new_root in
  if Array.length entries = 0 then error "the update is empty"
  else begin
    let suffix = fmt ".old-%d" (Unix.getpid ()) in
    let moved = ref [] in
    let ok = ref true in
    let err = ref "" in
    let undo () =
      List.iter
        (fun (dst, aside) ->
          P.Fs.rm_rf dst;
          try rename aside dst with Unix.Unix_error _ -> ())
        !moved
    in
    Array.iter
      (fun name ->
         if !ok then begin
           let dst = Filename.concat target name in
           let src = Filename.concat new_root name in
           try
             if P.Fs.exists dst then begin
               let aside = Filename.concat target ("." ^ name ^ suffix) in
               rename dst aside;
               moved := (dst, aside) :: !moved
             end;
             rename src dst
           with Unix.Unix_error (e, _, _) ->
             ok := false;
             err := Unix.error_message e
         end)
      entries;
    if !ok then begin
      List.iter (fun (_, aside) -> P.Fs.rm_rf aside) !moved;
      Stdlib.Ok ""
    end
    else begin
      undo ();
      Stdlib.Error !err
    end
  end

let swap st ~target =
  match st.layout with
  | App_bundle -> swap_bundle ~new_root:st.new_root ~target
  | Dir -> swap_dir ~new_root:st.new_root ~target

let rollback ~backup ~target =
  if not (P.Fs.exists backup) then error "no backup at %s" backup
  else begin
    if P.Fs.exists target then begin
      let aside =
        Filename.concat (Filename.dirname target)
          (fmt ".%s.bad-%d" (Filename.basename target) (Unix.getpid ()))
      in
      (try rename target aside with Unix.Unix_error _ -> ())
    end;
    try
      rename backup target;
      Stdlib.Ok ()
    with Unix.Unix_error (e, _, _) ->
      error "rollback failed: %s" (Unix.error_message e)
  end

let cleanup_backup backup = P.Fs.rm_rf backup

(* ------------------------------------------------------------------ *)
(* Install orchestration. *)

type install_report =
  | Up_to_date
  | Installed of { version : string; backup : string; exe : string }
  | Install_failed of string

(* ------------------------------------------------------------ relaunch *)

(* A detached spawn: stdin is /dev/null, stdout/stderr are inherited,
   and the pid is never waited on, so the child is reparented once the
   caller exits. *)
let spawn_detached path args =
  let devnull = Unix.openfile P.Proc.devnull [ Unix.O_RDWR ] 0 in
  let pid =
    Unix.create_process path
      (Array.of_list (path :: args))
      devnull Unix.stdout Unix.stderr
  in
  Unix.close devnull;
  pid

let relaunch ~exe ~args () =
  ignore (spawn_detached exe args);
  exit 0

(* What an update replaces: on macOS the .app bundle holding the
   executable, elsewhere the executable's directory. *)
let install_target_of ~exe =
  let real =
    match P.Fs.kind_of exe with
    | P.Fs.Link -> (try Unix.readlink exe with Unix.Unix_error _ -> exe)
    | _ -> exe
  in
  if Lui_pkg.host_platform () = Lui_pkg.Macos then begin
    let bundle =
      Filename.dirname (Filename.dirname (Filename.dirname real))
    in
    if Filename.check_suffix bundle ".app" then Stdlib.Ok bundle
    else error "only app bundles can update themselves"
  end
  else Stdlib.Ok (Filename.dirname real)

(* ------------------------------------------------------- orchestration *)

let install ?fetch ?verify ?verify_sig ?progress ?on_state ?stage_dir f
    ~bundle ~exe =
  let fetch =
    match fetch with
    | Some fc -> fc
    | None -> curl_fetcher ~user_agent:(user_agent f) ()
  in
  let emit st = Option.iter (fun g -> g st) on_state in
  let fail m =
    emit (Error m);
    Install_failed m
  in
  let stage_dir = Option.value stage_dir ~default:(stage_dir_of bundle) in
  emit Checking;
  match check ~fetch f with
  | Error m -> fail m
  | Stdlib.Ok None ->
    emit Idle;
    Up_to_date
  | Stdlib.Ok (Some i) -> (
    emit (Available i);
    (* Downloads land next to the app so the staged rename is atomic
       within one filesystem — and so an unwritable install fails
       before any bytes move. *)
    let work =
      P.Fs.temp_dir ~prefix:"lui_upd-dl-"
        ~parent:(Filename.dirname bundle ^ Filename.dir_sep)
        ()
    in
    let run pl =
      let a = match pl with Full a -> a | Delta d -> d.artifact in
      emit (Downloading { received = 0; total = a.size });
      let pkg = Filename.concat work "pkg" in
      match download ~fetch ?verify_sig ?progress a ~dest:pkg with
      | Stdlib.Error m -> Stdlib.Error m
      | Stdlib.Ok () ->
        apply ?verify ~info:i ~plan:pl ~package:pkg ~bundle ~stage_dir ()
    in
    let finish = function
      | Stdlib.Error m ->
        P.Fs.rm_rf work;
        fail m
      | Stdlib.Ok staged -> (
        emit (Ready staged.new_root);
        match swap staged ~target:bundle with
        | Stdlib.Error m ->
          P.Fs.rm_rf work;
          P.Fs.rm_rf stage_dir;
          fail m
        | Stdlib.Ok backup ->
          P.Fs.rm_rf work;
          if P.Fs.exists stage_dir then P.Fs.rm_rf stage_dir;
          emit Applied;
          Installed
            { version = i.version; backup;
              exe = Filename.concat bundle exe })
    in
    match run (plan i ~current:f.version) with
    | Stdlib.Ok _ as ok -> finish ok
    | Stdlib.Error m -> (
      (* A delta that cannot rebuild the app falls back to the full
         package once: the running tree may not be the one the delta
         was made from. *)
      match plan i ~current:f.version with
      | Full _ -> finish (Stdlib.Error m)
      | Delta _ -> finish (run (Full i.archive))))

let install_and_relaunch ?fetch ?verify ?verify_sig ?progress ?on_state
    ?stage_dir f ~bundle ~exe ~args =
  match
    install ?fetch ?verify ?verify_sig ?progress ?on_state ?stage_dir f
      ~bundle ~exe
  with
  | Installed { exe; _ } ->
    ignore (spawn_detached exe args);
    exit 0
  | report -> report
