module Update = Lui_desktop_update
module Json = Yojson.Basic.Util

external webview_run : string * string * string * int * int * bool * (unit -> bool) -> unit
  = "lui_desktop_webview_run"
external updater_window_run : string * string -> unit = "lui_desktop_updater_window_run"
external scheme_window_run :
  string * string * int * int * bool * (string -> string * string) * (string -> string) -> unit
  = "lui_desktop_scheme_window_run"
external wait_for_process : int -> bool = "lui_desktop_wait_for_process"

let text key json = Json.member key json |> Json.to_string
let integer key json = Json.member key json |> Json.to_int
let json value = Yojson.Basic.to_string value
let object_ fields = `Assoc fields
let string value = `String value
let field key value = key, string value
let under root path = Filename.concat root path

let rec directories path =
  if not (Sys.file_exists path) then (
    directories (Filename.dirname path); Unix.mkdir path 0o700)

let copy_file source destination =
  let input = open_in_bin source in
  Fun.protect ~finally:(fun () -> close_in input) (fun () ->
    let output = open_out_bin destination in
    Fun.protect ~finally:(fun () -> close_out output) (fun () ->
      let buffer = Bytes.create 65536 in
      let rec copy () =
        let count = Stdlib.input input buffer 0 (Bytes.length buffer) in
        if count > 0 then (output_substring output (Bytes.unsafe_to_string buffer) 0 count; copy ()) in
      copy ()))

let run ~config ~updater_html ~updater_js =
  let config = Yojson.Basic.from_string config in
  let executable = Unix.realpath Sys.executable_name in
  let platform = text "platform" config in
  let macos = String.starts_with ~prefix:"darwin-" platform in
  let updater_mode = macos && Array.length Sys.argv = 3 && Sys.argv.(1) = "--lui-updater" in
  let owner_pid = if updater_mode then int_of_string Sys.argv.(2) else Unix.getpid () in
  let root = if macos then Filename.dirname (Filename.dirname (Filename.dirname executable))
    else Filename.dirname executable in
  let frontend = under root (if macos then "Contents/Resources/frontend" else "frontend") in
  let version = text "version" config in
  let current_build = integer "build" config in
  let app_id = text "identifier" config in
  let updates = Json.member "updates" config in
  let managed = Sys.file_exists (under root ".lui-package-managed") in
  let enabled = updates <> `Null && not managed in
  let storage =
    if Sys.win32 then Sys.getenv "LOCALAPPDATA"
    else if macos then under (Sys.getenv "HOME") "Library/Application Support"
    else Option.value (Sys.getenv_opt "XDG_DATA_HOME") ~default:(under (Sys.getenv "HOME") ".local/share")
  in
  let storage = under storage app_id in
  directories storage;
  let acknowledgement =
    if Array.length Sys.argv = 3 && Sys.argv.(1) = "--lui-updated" then (
      let path = Sys.argv.(2) in
      if Filename.dirname path <> storage || not (String.ends_with ~suffix:".ready" path)
      then failwith "Invalid update acknowledgement path";
      Some path)
    else None in
  Mirage_crypto_rng_unix.use_default ();
  let token = Mirage_crypto_rng.generate 32 |> Ohex.encode in
  let socket = if macos then None else (
    let socket = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
    Unix.set_close_on_exec socket;
    Unix.bind socket (Unix.ADDR_INET (Unix.inet_addr_loopback, 0));
    Unix.listen socket 16; Some socket) in
  let port = match Option.map Unix.getsockname socket with
    | Some (Unix.ADDR_INET (_, port)) -> port
    | Some (Unix.ADDR_UNIX _) -> failwith "Invalid loopback socket"
    | None -> 0 in
  let origin = if macos then "lui://localhost" else Printf.sprintf "http://127.0.0.1:%d" port in
  let base = if macos then origin ^ "/" else origin ^ "/" ^ token ^ "/" in
  let mutex = Mutex.create () in
  let synchronized f = Mutex.lock mutex; Fun.protect ~finally:(fun () -> Mutex.unlock mutex) f in
  let initial_message =
    if managed then "This installation is maintained by your package manager."
    else if not enabled then "Updates have not been configured for this build."
    else "Check for a newer version." in
  let state = ref (object_ [field "status" (if enabled then "idle" else "disabled");
                           field "message" initial_message; field "current" version]) in
  let busy = ref false in
  let release = ref None in
  let staged = ref None in
  let downloading = ref None in
  let updater_process = ref None in
  let quitting = ref false in
  let stop_updater () =
    let process = synchronized (fun () ->
      quitting := true;
      let process = !updater_process in updater_process := None; process) in
    Option.iter (fun pid ->
      (try Unix.kill pid Sys.sigterm with Unix.Unix_error _ -> ());
      (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ())) process in
  let skipped_path = under storage "skipped-build" in
  let skipped () =
    try int_of_string (Update.read_file ~limit:32 skipped_path) with _ -> -1 in
  let set_state status message extra = synchronized (fun () ->
      state := object_ ([field "status" status; field "message" message;
                        field "current" version] @ extra)) in
  let job status f =
    let start = synchronized (fun () ->
        if !busy || !staged <> None || not enabled then false
        else (busy := true; state := object_ [field "status" status; field "current" version]; true)) in
    if start then ignore (Thread.create (fun () ->
      (try f () with error -> set_state "error" (Printexc.to_string error) []);
      synchronized (fun () -> busy := false)) ()) in
  let temporary suffix = under storage (token ^ suffix) in
  let check automatic = job "checking" (fun () ->
    let path = temporary ".feed" in
    Fun.protect ~finally:(fun () -> Update.remove_tree path) (fun () ->
      let url = text "url" updates in
      let parsed = Uri.of_string url in
      if Uri.scheme parsed <> Some "https" || Uri.host parsed = None
         || Uri.userinfo parsed <> None || Uri.fragment parsed <> None
      then failwith "Update feed must use HTTPS";
      let args = [| "curl"; "--fail"; "--silent"; "--show-error"; "--location";
        "--proto"; "=https"; "--proto-redir"; "=https"; "--tlsv1.2";
        "--connect-timeout"; "20"; "--max-time"; "60"; "--max-filesize"; "1048576";
        "--output"; path; "--url"; url |] in
      let pid = Unix.create_process "curl" args Unix.stdin Unix.stdout Unix.stderr in
      if snd (Unix.waitpid [] pid) <> Unix.WEXITED 0 then failwith "Cannot download update feed";
      let found = Update.authenticate ~public_key:(text "public_key" updates)
          ~app_id ~platform ~current_build (Update.read_file ~limit:1_048_576 path) in
      synchronized (fun () -> release := found);
      match found with
      | None -> set_state "current" "You are up to date." []
      | Some found when automatic && skipped () = found.build ->
          set_state "skipped" "This version was skipped." []
      | Some found -> set_state "available" ("Version " ^ found.version ^ " is available.")
          [field "notes" found.notes; field "version" found.version])) in
  let install () = job "downloading" (fun () ->
    let found = synchronized (fun () -> !release) in
    let found = match found with Some found -> found | None -> failwith "Check for an update first" in
    let package = temporary ".package" in
    let destination = root ^ ".lui-stage-" ^ token in
    let prepare artifact =
      synchronized (fun () -> downloading := Some (package, artifact.Update.size));
      set_state "downloading" "Downloading update…" [];
      Update.download artifact package;
      set_state "staging" "Verifying the complete application…" [];
      Update.stage ~package ~installed:root ~destination;
      (try
        let metadata = under destination
            (if macos then "Contents/Resources/lui-desktop.json" else "lui-desktop.json") in
        let metadata = Update.read_file ~limit:1_048_576 metadata |> Yojson.Basic.from_string in
        if text "identifier" metadata <> app_id || text "platform" metadata <> platform
           || integer "build" metadata <> found.build || text "version" metadata <> found.version
           || Json.member "updates" metadata <> updates
        then failwith "The update metadata does not match the signed release";
        let binary = under destination (if macos then "Contents/MacOS/app" else if Sys.win32 then "app.exe" else "app") in
        if (Unix.lstat binary).Unix.st_kind <> Unix.S_REG then failwith "Update executable is missing"
       with error -> Update.remove_tree destination; raise error) in
    Fun.protect ~finally:(fun () -> Update.remove_tree package) (fun () ->
      (match found.Update.delta with
       | None -> prepare found.full
       | Some delta -> (try prepare delta with _ ->
           Update.remove_tree destination;
           prepare found.full));
      synchronized (fun () -> staged := Some destination);
      set_state "ready" "The update is ready. Restart to install it." [])) in
  let restart () =
    let destination = synchronized (fun () ->
      if !busy then None else match !staged with
      | None -> None
      | Some destination -> busy := true; Some destination) in
    match destination with
    | None -> ()
    | Some destination ->
        let helper_directory = temporary ".installer" in
        (try
        directories helper_directory;
        let helper = under helper_directory (if Sys.win32 then "app.exe" else "app") in
        copy_file executable helper;
        if Sys.win32 then Array.iter (fun name ->
          if String.ends_with ~suffix:".dll" (String.lowercase_ascii name) then
            copy_file (under root name) (under helper_directory name)) (Sys.readdir root);
        Unix.chmod helper 0o700;
        let relative_executable = if macos then "Contents/MacOS/app" else if Sys.win32 then "app.exe" else "app" in
        let args = [| helper; "--lui-install"; destination; root;
                      string_of_int owner_pid; relative_executable;
                      string_of_int (match !release with Some found -> found.Update.build
                        | None -> failwith "Missing staged release") |] in
        ignore (Unix.create_process helper args Unix.stdin Unix.stdout Unix.stderr);
        ignore (Thread.create (fun () ->
          Thread.delay 0.3;
          stop_updater ();
          if updater_mode then Unix.kill owner_pid Sys.sigterm;
          exit 0) ())
        with error ->
          synchronized (fun () -> busy := false);
          set_state "ready" ("Unable to restart: " ^ Printexc.to_string error) []) in
  let bridge = Printf.sprintf {|"use strict";
const updater = location.pathname.endsWith("/__lui/update");
const style = document.createElement("link");
style.rel = "stylesheet"; style.href = %s;
document.head.appendChild(style);
const request = window.__lui_request || (async name => {
  const response = await fetch(%s + name, {
    method: name === "state" ? "GET" : "POST",
    headers: {"Content-Type": "application/json"}
  });
  if (!response.ok) throw new Error("Desktop request failed (" + response.status + ")");
  return response.json();
});
Object.defineProperty(window, "luiDesktop", {value: Object.freeze({
  request,
  checkForUpdates: () => window.__lui_check_for_updates(%s)
})});
if (!updater) window.addEventListener("load", () => {
  if (!document.querySelector('[data-error="true"]')) request("ready").catch(() => {});
});
document.addEventListener("keydown", e => {
  if ((e.metaKey || e.ctrlKey) && e.shiftKey && e.code === "KeyU") {
    e.preventDefault(); window.luiDesktop.checkForUpdates();
  }
});
%s
|} (json (string (base ^ "__lui-desktop.css")))
    (json (string (base ^ "__lui/"))) (json (string token))
      (if enabled then {|
if (!updater) {
  const automatic = async () => {
    try {
      await request("automatic");
      const poll = async () => {
        const state = await request("state");
        if (state.status === "checking") setTimeout(() => poll().catch(() => {}), 500);
        else if (state.status === "available") window.luiDesktop.checkForUpdates();
      };
      await poll();
    } catch (_) {}
  };
  setTimeout(automatic, 10000); setInterval(automatic, 86400000);
}
|} else "") in
  let snapshot () = synchronized (fun () ->
    match !state, !downloading with
    | `Assoc fields, Some (path, total) when List.assoc_opt "status" fields = Some (`String "downloading") ->
        let bytes = try (Unix.stat path).Unix.st_size with Unix.Unix_error _ -> 0 in
        `Assoc (("bytes", `Int bytes) :: ("total", `Int total) :: fields)
    | state, _ -> state) in
  let command name =
    match name with
    | "state" -> json (snapshot ())
    | "check" -> check false; "{}"
    | "automatic" -> check true; "{}"
    | "install" -> install (); "{}"
    | "restart" -> restart (); "{}"
    | "ready" -> Option.iter (fun path -> Update.write_file path (string_of_int current_build)) acknowledgement; "{}"
    | "later" -> "null"
    | "skip" ->
        let found = synchronized (fun () -> !release) in
        Option.iter (fun found -> Update.write_file skipped_path (string_of_int found.Update.build)) found;
        set_state "skipped" "This version will not be offered automatically." []; "{}"
    | _ -> invalid_arg "Unknown desktop operation" in
  let asset path =
    let path = if String.starts_with ~prefix:"/" path then
        String.sub path 1 (String.length path - 1) else path in
    let path = Uri.pct_decode path in
    match path with
    | "__lui/update" -> "text/html; charset=utf-8", updater_html
    | "__lui/updater.js" -> "text/javascript; charset=utf-8", updater_js
    | "__lui/bridge.js" -> "text/javascript; charset=utf-8", bridge
    | path ->
        let path = if path = "" then "index.html" else path in
        if not (Filename.is_relative path) || String.contains path '\\'
           || List.exists (fun p -> p = ".." || p = "." || p = "") (String.split_on_char '/' path)
        then failwith "Invalid asset path";
        let resolved = Unix.realpath (under frontend path) in
        if not (String.starts_with ~prefix:(frontend ^ Filename.dir_sep) resolved)
        then failwith "Asset outside frontend";
        let body = Update.read_file ~limit:67_108_864 resolved in
        let kind = match Filename.extension path with
          | ".html" -> "text/html; charset=utf-8" | ".js" | ".mjs" -> "text/javascript; charset=utf-8"
          | ".css" -> "text/css; charset=utf-8" | ".svg" -> "image/svg+xml"
          | ".png" -> "image/png" | ".json" -> "application/json" | ".woff2" -> "font/woff2"
          | _ -> "application/octet-stream" in
        let body = if path = "index.html" then
            let insertion = "<script src=\"./__lui/bridge.js\"></script>" in
            let lower = String.lowercase_ascii body in
            let rec closing_head index =
              if index + 7 > String.length lower then None
              else if String.sub lower index 7 = "</head>" then Some index
              else closing_head (index + 1) in
            (match closing_head 0 with
             | None -> failwith "Invalid index.html"
             | Some index -> String.sub body 0 index ^ insertion
               ^ String.sub body index (String.length body - index))
          else body in
        kind, body in
  let csp = "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; object-src 'none'; frame-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'" in
  let serve client =
    Unix.setsockopt_float client Unix.SO_RCVTIMEO 5.;
    let input = Unix.in_channel_of_descr client in
    let output = Unix.out_channel_of_descr (Unix.dup client) in
    let line () =
      let buffer = Buffer.create 128 in
      let rec read () =
        if Buffer.length buffer > 8192 then failwith "HTTP line too long";
        match input_char input with
        | '\n' -> Buffer.contents buffer |> String.trim
        | c -> Buffer.add_char buffer c; read () in
      read () in
    let respond status kind body =
      Printf.fprintf output "HTTP/1.1 %s\r\nContent-Type: %s\r\nContent-Length: %d\r\nConnection: close\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\nContent-Security-Policy: %s\r\n\r\n%s"
        status kind (String.length body) csp body;
      flush output in
    Fun.protect ~finally:(fun () -> close_in_noerr input; close_out_noerr output) (fun () ->
      try
        let request = line () in
        let headers = Hashtbl.create 12 in
        let rec read_headers size =
          let line = line () in
          if size + String.length line > 16384 then failwith "Headers too large";
          if line <> "" then (
            (match String.index_opt line ':' with
             | Some colon -> Hashtbl.replace headers
                 (String.sub line 0 colon |> String.lowercase_ascii)
                 (String.sub line (colon + 1) (String.length line - colon - 1) |> String.trim)
             | None -> failwith "Invalid header"); read_headers (size + String.length line)) in
        read_headers 0;
        let method_, path = match String.split_on_char ' ' request with
          | [method_; path; protocol] when String.starts_with ~prefix:"HTTP/1." protocol -> method_, path
          | _ -> failwith "Invalid request" in
        let prefix = "/" ^ token ^ "/" in
        if Hashtbl.find_opt headers "host" <> Some ("127.0.0.1:" ^ string_of_int port)
           || not (String.starts_with ~prefix path)
        then respond "404 Not Found" "text/plain" "Not found"
        else
          let path = String.sub path (String.length prefix) (String.length path - String.length prefix) in
          if method_ = "POST" then (
            if Hashtbl.find_opt headers "origin" <> Some origin
               || Hashtbl.find_opt headers "content-type" <> Some "application/json"
            then respond "403 Forbidden" "text/plain" "Invalid origin"
            else if String.starts_with ~prefix:"__lui/" path then
              respond "200 OK" "application/json" (command (String.sub path 6 (String.length path - 6)))
            else respond "404 Not Found" "text/plain" "Not found")
          else if method_ <> "GET" then respond "405 Method Not Allowed" "text/plain" "GET or POST required"
          else if path = "__lui/state" then respond "200 OK" "application/json" (command "state")
          else let kind, body = asset path in respond "200 OK" kind body
      with _ -> (try respond "400 Bad Request" "text/plain" "Invalid request" with _ -> ())) in
  let stopped = Atomic.make false in
  let server = Option.map (fun socket -> Thread.create (fun () ->
      try while not (Atomic.get stopped) do
        let client, _ = Unix.accept socket in Unix.set_close_on_exec client; serve client
      done with Unix.Unix_error ((Unix.EBADF | Unix.EINVAL), _, _) -> ()) ()) socket in
  let open_updater () = synchronized (fun () ->
    if !quitting then false else if updater_mode then true else
    let live = match !updater_process with
      | None -> false
      | Some pid ->
          (try fst (Unix.waitpid [Unix.WNOHANG] pid) = 0
           with Unix.Unix_error (Unix.ECHILD, _, _) -> false) in
    if live then true
    else (
      let arguments = if macos then [|executable; "--lui-updater"; string_of_int owner_pid|]
        else [| executable; "--lui-updater"; text "name" config ^ " Updates"; base ^ "__lui/update" |] in
      let pid = Unix.create_process executable arguments Unix.stdin Unix.stdout Unix.stderr in
      updater_process := Some pid;
      true)) in
  Fun.protect ~finally:(fun () ->
      stop_updater ();
      Atomic.set stopped true;
      Option.iter (fun socket ->
        (try Unix.shutdown socket Unix.SHUTDOWN_ALL with Unix.Unix_error _ -> ());
        Unix.close socket) socket;
      Option.iter Thread.join server)
    (fun () ->
      if macos then
        let callback name = if name = "check_for_updates" then json (`Bool (open_updater ())) else command name in
        scheme_window_run (text "name" config ^ (if updater_mode then " Updates" else ""),
          base ^ (if updater_mode then "__lui/update" else ""),
          (if updater_mode then 520 else integer "width" config),
          (if updater_mode then 440 else integer "height" config), updater_mode, asset, callback)
      else webview_run (text "name" config, base, token,
          integer "width" config, integer "height" config, false, open_updater))

let () =
  if Array.length Sys.argv = 4 && Sys.argv.(1) = "--lui-updater" then (
    let url = Uri.of_string Sys.argv.(3) in
    if Uri.scheme url <> Some "http" || Uri.host url <> Some "127.0.0.1"
       || Uri.userinfo url <> None
    then failwith "The update window must use the local application server";
    updater_window_run (Sys.argv.(2), Sys.argv.(3));
    exit 0);
  if Array.length Sys.argv = 7 && Sys.argv.(1) = "--lui-install" then (
    let staged = Sys.argv.(2) and target = Sys.argv.(3) in
    let log = Filename.concat (Filename.dirname staged) "lui-update-install.log" in
    try
      if not (wait_for_process (int_of_string Sys.argv.(4))) then
        failwith "Application did not exit within 60 seconds";
      if not (Filename.is_relative staged) && not (Filename.is_relative target)
         && String.starts_with ~prefix:(target ^ ".lui-stage-") staged
         && List.mem Sys.argv.(5) ["app"; "app.exe"; "Contents/MacOS/app"]
      then () else failwith "Invalid update installation plan";
      let installation = Update.install ~staged ~target in
      let executable = Filename.concat target Sys.argv.(5) in
      let helper_directory = Filename.dirname Sys.executable_name in
      let acknowledgement = Filename.concat (Filename.dirname helper_directory)
          (Filename.basename helper_directory ^ ".ready") in
      Update.remove_tree acknowledgement;
      let child = ref None in
      (try
        let pid = Unix.create_process executable [|executable; "--lui-updated"; acknowledgement|]
            Unix.stdin Unix.stdout Unix.stderr in
        child := Some pid;
        let rec wait count =
          if Sys.file_exists acknowledgement then (
            if Update.read_file ~limit:32 acknowledgement <> Sys.argv.(6)
            then failwith "The updated application started a different build")
          else if count = 0 then failwith "The updated Web frontend did not start within 30 seconds"
          else (Thread.delay 0.1; wait (count - 1)) in
        wait 300
       with error ->
        Option.iter (fun pid ->
          (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ());
          (try ignore (Unix.waitpid [] pid) with Unix.Unix_error _ -> ())) !child;
        Update.rollback installation;
        (try ignore (Unix.create_process executable [|executable|] Unix.stdin Unix.stdout Unix.stderr)
         with Unix.Unix_error _ -> ());
        raise error);
      Update.confirm installation;
      Update.remove_tree acknowledgement;
      exit 0
    with error -> Update.write_file log (Printexc.to_string error); exit 1)
