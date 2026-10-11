(* Lui_webapp — webview-shell host for web-asset apps. See the .mli
   for the model: a JSON spec drives a webview window, backed by
   {!Lui_webview} through {!Lui_webapp_sdl} when the platform engine is
   available, with a default-browser fallback when it is not.

   The {!WEBVIEW} provider seam remains for tests and custom hosts. *)

open Lui_pkg.Private

let ( / ) = Filename.concat
let ( let* ) = Result.bind

(** {1 Specification} *)

type window = {
  width : int;
  height : int;
  resizable : bool;
  min_width : int;
  min_height : int;
}

type permissions = {
  file_access : bool;
  remote_content : bool;
  dev_tools : bool;
}

type spec = {
  app_id : string;
  name : string;
  version : string;
  web_dir : string;
  entry : string;
  window : window;
  icon : string option;
  permissions : permissions;
}

let default_window =
  { width = 1024; height = 768; resizable = true;
    min_width = 320; min_height = 240 }

let default_permissions =
  { file_access = true; remote_content = false; dev_tools = false }

let spec_file_name = "webapp.json"

(** {1 JSON} *)

let window_to_json (w : window) : Yojson.Safe.t =
  `Assoc
    [ ("width", `Int w.width);
      ("height", `Int w.height);
      ("resizable", `Bool w.resizable);
      ("min_width", `Int w.min_width);
      ("min_height", `Int w.min_height) ]

let permissions_to_json (p : permissions) : Yojson.Safe.t =
  `Assoc
    [ ("file_access", `Bool p.file_access);
      ("remote_content", `Bool p.remote_content);
      ("dev_tools", `Bool p.dev_tools) ]

let spec_to_json (s : spec) : Yojson.Safe.t =
  `Assoc
    [ ("app_id", `String s.app_id);
      ("name", `String s.name);
      ("version", `String s.version);
      ("web_dir", `String s.web_dir);
      ("entry", `String s.entry);
      ("window", window_to_json s.window);
      ( "icon",
        match s.icon with Some i -> `String i | None -> `Null );
      ("permissions", permissions_to_json s.permissions) ]

(* Field readers: every lookup reports which key failed so spec-file
   errors point at the field, not a bare "bad spec". *)

let err field detail = Error (Printf.sprintf "spec %s: %s" field detail)

let req_string j field =
  let open Yojson.Safe.Util in
  match j |> member field with
  | `String s -> Ok s
  | `Null -> err field "missing"
  | _ -> err field "must be a string"

let opt_string j field =
  let open Yojson.Safe.Util in
  match j |> member field with
  | `Null -> Ok None
  | `String s -> Ok (Some s)
  | _ -> err field "must be a string"

let bool_or j field default =
  let open Yojson.Safe.Util in
  match j |> member field with
  | `Bool b -> Ok b
  | `Null -> Ok default
  | _ -> err field "must be a bool"

let int_or j field default =
  let open Yojson.Safe.Util in
  match j |> member field with
  | `Int n -> Ok n
  | `Null -> Ok default
  | _ -> err field "must be an int"

let window_of_json j =
  match j with
  | `Null -> Ok default_window
  | `Assoc _ ->
    let* width = int_or j "width" default_window.width in
    let* height = int_or j "height" default_window.height in
    let* resizable = bool_or j "resizable" default_window.resizable in
    let* min_width = int_or j "min_width" default_window.min_width in
    let* min_height = int_or j "min_height" default_window.min_height in
    Ok { width; height; resizable; min_width; min_height }
  | _ -> err "window" "must be an object"

let permissions_of_json j =
  match j with
  | `Null -> Ok default_permissions
  | `Assoc _ ->
    let* file_access =
      bool_or j "file_access" default_permissions.file_access
    in
    let* remote_content =
      bool_or j "remote_content" default_permissions.remote_content
    in
    let* dev_tools =
      bool_or j "dev_tools" default_permissions.dev_tools
    in
    Ok { file_access; remote_content; dev_tools }
  | _ -> err "permissions" "must be an object"

let spec_of_json (j : Yojson.Safe.t) : (spec, string) result =
  let open Yojson.Safe.Util in
  match j with
  | `Assoc _ ->
    let* app_id = req_string j "app_id" in
    let* name = req_string j "name" in
    let* version = req_string j "version" in
    let* web_dir = req_string j "web_dir" in
    let* entry = req_string j "entry" in
    let* window = window_of_json (j |> member "window") in
    let* icon = opt_string j "icon" in
    let* permissions =
      permissions_of_json (j |> member "permissions")
    in
    Ok { app_id; name; version; web_dir; entry; window; icon;
         permissions }
  | _ -> Error "spec: must be a JSON object"

let spec_to_string s = Yojson.Safe.pretty_to_string (spec_to_json s)

let spec_of_string s =
  try spec_of_json (Yojson.Safe.from_string s)
  with Yojson.Json_error m ->
    Error (Printf.sprintf "spec is not valid JSON: %s" m)

let read_spec path =
  match Fs.kind_of path with
  | Fs.Absent -> Error (Printf.sprintf "spec file %s does not exist" path)
  | Fs.Dir -> Error (Printf.sprintf "spec file %s is a directory" path)
  | _ ->
    (try spec_of_string (Fs.read_file path)
     with Sys_error m -> Error m)

let write_spec spec path =
  try Ok (Fs.write_file path (spec_to_string spec ^ "\n"))
  with Sys_error m -> Error m

(** {1 Paths} *)

let is_abs p = not (Filename.is_relative p)

(* A relative path escapes its base when a [..] segment climbs above
   it — normalized lexically, so it holds on every platform and never
   needs the filesystem. *)
let escapes_base p =
  if is_abs p then false
  else
    let segs =
      p
      |> String.split_on_char '\\'
      |> String.concat "/"
      |> String.split_on_char '/'
    in
    let rec depth n = function
      | [] -> n < 0
      | seg :: rest ->
        if seg = ".." then
          if n <= 0 then true else depth (n - 1) rest
        else if seg = "." || seg = "" then depth n rest
        else depth (n + 1) rest
    in
    depth 0 segs

let validate (s : spec) : (unit, string) result =
  if s.app_id = "" then err "app_id" "must not be empty"
  else if s.name = "" then err "name" "must not be empty"
  else if s.version = "" then err "version" "must not be empty"
  else if s.web_dir = "" then err "web_dir" "must not be empty"
  else if s.entry = "" then err "entry" "must not be empty"
  else if is_abs s.entry then
    err "entry" "must be relative to web_dir"
  else if escapes_base s.entry then
    err "entry" "must not escape web_dir (\"..\" segment)"
  else if s.window.width <= 0 || s.window.height <= 0 then
    err "window" "width/height must be positive"
  else if s.window.min_width < 0 || s.window.min_height < 0 then
    err "window" "min_width/min_height must not be negative"
  else Ok ()

let resolve ~base (s : spec) : spec =
  let abs p = if p = "" || is_abs p then p else base / p in
  { s with
    web_dir = abs s.web_dir;
    icon = (match s.icon with Some i -> Some (abs i) | None -> None) }

let entry_path s = s.web_dir / s.entry

(* file:// URL: forward slashes, every byte outside RFC 3986
   unreserved + a small path-safe set is percent-escaped. *)
let file_url path =
  let safe = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9'
    | '/' | '-' | '_' | '.' | '~' -> true
    | _ -> false
  in
  let b = Buffer.create (String.length path + 16) in
  Buffer.add_string b "file://";
  String.iter
    (fun c ->
       let c = if c = '\\' then '/' else c in
       if safe c then Buffer.add_char b c
       else Buffer.add_string b (Printf.sprintf "%%%02X" (Char.code c)))
    path;
  Buffer.contents b

(** {1 Webview provider} *)

module type WEBVIEW = sig
  type t

  val create :
    window:window -> title:string -> permissions:permissions ->
    (t, string) result
  val load_url : t -> string -> (unit, string) result
  val eval : t -> string -> unit
  val set_message_handler : t -> (string -> unit) -> unit
  val set_close_handler : t -> (unit -> unit) -> unit
  val run : t -> unit
  val close : t -> unit
end

let provider : (module WEBVIEW) option ref = ref None
let set_webview w = provider := w
let webview () = !provider

(* The built-in shell, re-exported: the wrapped library only exposes
   this main module, so the SDL+Lui_webview backend surfaces here. *)
module Sdl_shell = Lui_webapp_sdl

(** {1 Prepare and boot} *)

type prepared = {
  prep_spec : spec;
  entry_file : string;
  url : string;
}

let prepare ?(base = Sys.getcwd ()) (s : spec) : (prepared, string) result =
  match validate s with
  | Error _ as e -> e
  | Ok () ->
    let s = resolve ~base s in
    (match Fs.kind_of s.web_dir with
     | Fs.Dir ->
       (* the entry must be absolute: the native shell hands it to the
          platform view as a file URL and the browser fallback needs a
          file:// URL that resolves from any cwd *)
       let entry_file = entry_path s in
       let entry_file =
         if is_abs entry_file then entry_file
         else Sys.getcwd () / entry_file
       in
       (match Fs.kind_of entry_file with
        | Fs.File ->
          Ok { prep_spec = s; entry_file; url = file_url entry_file }
        | _ ->
          Error
            (Printf.sprintf "entry %s not found in web_dir %s"
               s.entry s.web_dir))
     | Fs.Absent ->
       Error (Printf.sprintf "web_dir %s does not exist" s.web_dir)
     | _ -> Error (Printf.sprintf "web_dir %s is not a directory" s.web_dir))

let open_in_browser url : (unit, string) result =
  let tool, args =
    match Lui_pkg.host_platform () with
    | Lui_pkg.Macos -> ("open", [ url ])
    | Lui_pkg.Linux -> ("xdg-open", [ url ])
    | Lui_pkg.Windows -> ("cmd", [ "/c"; "start"; ""; url ])
    | Lui_pkg.Unknown s ->
      ("", [ Printf.sprintf "no browser opener for platform %s" s ])
  in
  if tool = "" then Error (List.hd args)
  else
    match Proc.which tool with
    | None ->
      Error (Printf.sprintf "no %s on PATH to open the browser" tool)
    | Some _ ->
      let r = Proc.run tool args in
      if r.Proc.status = 0 then Ok ()
      else
        Error
          (Printf.sprintf "%s exited %d: %s" tool r.Proc.status
             (String.trim (r.Proc.stdout ^ r.Proc.stderr)))

let boot ?base ?(webview : (module WEBVIEW) option)
    ?(native_shell = true) ?(fallback_browser = true)
    ?(on_message = fun _ -> ())
    ?(on_ready = fun ~eval:(_ : string -> unit) -> ()) (s : spec) :
    unit =
  match prepare ?base s with
  | Error e -> failwith ("lui_webapp: " ^ e)
  | Ok prep ->
    let backend =
      match webview with Some _ -> webview | None -> !provider
    in
    (match backend with
     | Some (module W) ->
       (match
          W.create ~window:prep.prep_spec.window
            ~title:prep.prep_spec.name
            ~permissions:prep.prep_spec.permissions
        with
        | Error e -> failwith ("lui_webapp: webview create: " ^ e)
        | Ok t ->
          (match W.load_url t prep.url with
           | Error e -> failwith ("lui_webapp: webview load: " ^ e)
           | Ok () ->
             W.set_message_handler t on_message;
             on_ready ~eval:(fun js -> W.eval t js);
             W.run t))
     | None ->
       let browser_or_fail why =
         if fallback_browser then
           match open_in_browser prep.url with
           | Ok () ->
             Printf.eprintf
               "lui_webapp: %s — opened %s in the default browser\n%!"
               why prep.url
           | Error e ->
             failwith
               (Printf.sprintf
                  "lui_webapp: %s and the default browser could not \
                   be opened: %s"
                  why e)
         else
           failwith
             (Printf.sprintf
                "lui_webapp: %s and the browser fallback is disabled"
                why)
       in
       if native_shell && Lui_webapp_sdl.available () then
         match
           let (w : window) = prep.prep_spec.window in
           Lui_webapp_sdl.run
             ~window:
               { Lui_webapp_sdl.width = w.width; height = w.height;
                 resizable = w.resizable; min_width = w.min_width;
                 min_height = w.min_height }
             ~title:prep.prep_spec.name ~entry_file:prep.entry_file
             ~on_message ~on_ready
         with
         | Ok () -> ()
         | Error e -> browser_or_fail ("native shell: " ^ e)
       else
         browser_or_fail "no webview backend installed")

(** {1 Packaged-spec discovery} *)

(* Linux AppDir layout: the exe sits in usr/bin while the spec lands
   in usr/share/<app>/ — discover it by scanning the share dir. *)
let share_candidates ~exe =
  let share = Filename.dirname (Filename.dirname exe) / "share" in
  match Sys.readdir share with
  | entries ->
    Array.sort compare entries;
    Array.to_list entries
    |> List.filter_map (fun d ->
           let p = share / d / spec_file_name in
           if Fs.kind_of (share / d) = Fs.Dir && Fs.exists p then Some p
           else None)
  | exception Sys_error _ -> []

let embedded_spec_candidates ~exe =
  let d = Filename.dirname exe in
  [ d / spec_file_name; d / ".." / "Resources" / spec_file_name ]
  @ share_candidates ~exe

let find_embedded_spec ~exe =
  List.find_opt Sys.file_exists (embedded_spec_candidates ~exe)
