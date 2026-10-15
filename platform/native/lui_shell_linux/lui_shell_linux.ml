(* Desktop shell services for the native backend on Linux: session
   probing, the status item, menus, notifications, clipboard, file
   dialogs and open-url handling. The contract is in
   lui_shell_linux.mli; the transport lives in
   lui_shell_linux_stubs.c. Record layouts below are what the C stubs
   consume, in declaration order. *)

(* -------------------------------------------------------- transport *)

type transport = Offline | Session_bus | Indicator

external c_probe : string -> int = "lui_shx_probe"
external c_gui : unit -> bool = "lui_shx_gui"
external c_indicator : unit -> bool = "lui_shx_indicator"
external c_pump : int -> (int * int * string) array = "lui_shx_pump"

(* Well-known session-bus addresses, most specific first: the
   environment, the systemd per-user socket, then the X11 autolaunch
   transport. *)
let session_bus_address () =
  match Sys.getenv_opt "DBUS_SESSION_BUS_ADDRESS" with
  | Some a when a <> "" -> a
  | _ ->
    let p = "/run/user/" ^ string_of_int (Unix.getuid ()) ^ "/bus" in
    if Sys.file_exists p then "unix:path=" ^ p else "autolaunch:"

(* The probe runs once, on first use. *)
let probed = ref false
let caps = ref 0

let probe () =
  if not !probed then begin
    probed := true;
    caps := c_probe (session_bus_address ())
  end

let transport () =
  probe ();
  if !caps land 4 <> 0 && !caps land 2 <> 0 then Indicator
  else if !caps land 1 <> 0 then Session_bus
  else Offline

let gui_available () =
  probe ();
  c_gui ()

let status_item_supported () =
  probe ();
  c_indicator ()

(* ------------------------------------------------------- app identity *)

type activation_policy = Regular | Accessory | Prohibited

let policy = ref Regular
let set_activation_policy p = policy := p; true
let activation_policy () = Some !policy

let app_name_ref = ref "lui"
let set_app_name s =
  if String.length s > 0 then app_name_ref := s
let app_name () = !app_name_ref

let window_title = ref ""
let set_window_title s = window_title := s; false
let window_title () = !window_title

(* --------------------------------------------------------- locations *)

let home_dir () =
  match Sys.getenv_opt "HOME" with
  | Some h when h <> "" -> h
  | _ -> Unix.((getpwuid (getuid ())).pw_dir)

let xdg_dir env fallback =
  match Sys.getenv_opt env with
  | Some d when Filename.is_relative d = false -> d
  | _ -> Filename.concat (home_dir ()) fallback

(* The file to run for a URL: the AppImage rather than the directory
   it is mounted at while running. *)
let executable_path () =
  match Sys.getenv_opt "APPIMAGE" with
  | Some p when p <> "" -> p
  | _ ->
    (try Unix.readlink "/proc/self/exe"
     with Unix.Unix_error _ -> Sys.executable_name)

(* ---------------------------------------------------------- launcher *)

external c_launcher : string -> string -> int -> bool -> bool -> bool
  = "lui_shx_launcher"

(* The desktop entry the launcher keys on: the file this process was
   launched from when the environment says so, else a synthesized
   <exe>.desktop name. *)
let desktop_entry_id () =
  let from_env () =
    match Sys.getenv_opt "GIO_LAUNCHED_DESKTOP_FILE" with
    | Some p when p <> "" -> Some (Filename.basename p)
    | _ ->
      (match Sys.getenv_opt "BAMF_DESKTOP_FILE_HINT" with
       | Some p when p <> "" -> Some (Filename.basename p)
       | _ -> None)
  in
  match from_env () with
  | Some f -> f
  | None ->
    Filename.basename (executable_path ()) ^ ".desktop"

(* fnv-1a 32 over the id, the launcher-entry object path suffix. *)
let fnv1a32 s =
  let h = ref 0x811c9dc5l in
  String.iter
    (fun c ->
      h := Int32.logxor !h (Int32.of_int (Char.code c));
      h := Int32.mul !h 16777619l)
    s;
  Int32.to_int !h land 0x7fffffff

let launcher_path id =
  Printf.sprintf "/com/canonical/unity/launcherentry/%d" (fnv1a32 id)

let emit_launcher_entry ~count ~count_visible ~urgent =
  probe ();
  c_launcher (launcher_path (desktop_entry_id ()))
    ("application://" ^ desktop_entry_id ()) count count_visible urgent

let set_dock_badge opt =
  let count, visible =
    match opt with
    | None -> (0, false)
    | Some s ->
      ( (match int_of_string_opt (String.trim s) with
         | Some n -> n
         | None -> 0),
        true )
  in
  ignore (emit_launcher_entry ~count ~count_visible:visible ~urgent:false)

let attention_seq = ref 0

let request_user_attention ?(critical = false) () =
  ignore critical;
  if emit_launcher_entry ~count:0 ~count_visible:false ~urgent:true
  then begin
    incr attention_seq;
    !attention_seq
  end
  else -1

(* ------------------------------------------------------------ image *)

type image = { img_w : int; img_h : int; img_px : bytes }

let image_of_rgba ~width ~height px =
  if width <= 0 || height <= 0
     || Bytes.length px <> width * height * 4
  then None
  else Some { img_w = width; img_h = height; img_px = px }

let image_size i = (float_of_int i.img_w, float_of_int i.img_h)

(* PNG encoding via imagelib: the RGBA buffer becomes an RGBA8
   Image.image and its PNG writer owns chunks, CRCs and the DEFLATE
   stream — the hand-rolled encoder is gone. *)
module Png = struct
  let encode ~width ~height px =
    let im = Image.create_rgb ~alpha:true ~max_val:255 width height in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let i = ((y * width) + x) * 4 in
        Image.write_rgba im x y
          (Bytes.get_uint8 px i) (Bytes.get_uint8 px (i + 1))
          (Bytes.get_uint8 px (i + 2)) (Bytes.get_uint8 px (i + 3))
      done
    done;
    let buf = Buffer.create 256 in
    ImageLib.PNG.write (ImageUtil.chunk_writer_of_buffer buf) im;
    Buffer.to_bytes buf
end

let image_png i = Png.encode ~width:i.img_w ~height:i.img_h i.img_px

(* ------------------------------------------------------------ menus *)

type item_spec = {
  label : string;
  id : int;
  enabled : bool;
  checked : bool;
}

type menu_item =
  | Item of item_spec
  | Separator
  | Submenu of submenu_spec

and submenu_spec = {
  label : string;
  enabled : bool;
  items : menu_item list;
}

type menu_row_kind = Row_item | Row_separator | Row_submenu

type menu_row = {
  depth : int;
  kind : menu_row_kind;
  label : string;
  id : int;
  enabled : bool;
  checked : bool;
}

type menu = { title : string; rows : menu_row array }

(* Depth-first flatten: a [Submenu] row is emitted first, then its
   children at [depth + 1]; separators carry no label and id -1. *)
let menu ?(title = "") items =
  let acc = ref [] in
  let push row = acc := row :: !acc in
  let rec go depth = function
    | Item { label; id; enabled; checked } ->
      push { depth; kind = Row_item; label; id; enabled; checked }
    | Separator ->
      push { depth; kind = Row_separator; label = ""; id = -1;
             enabled = false; checked = false }
    | Submenu { label; enabled; items } ->
      push { depth; kind = Row_submenu; label; id = -1; enabled;
             checked = false };
      List.iter (go (depth + 1)) items
  in
  List.iter (go 0) items;
  { title; rows = Array.of_list (List.rev !acc) }

let menu_rows m = m.rows

(* The app menu model: Linux has no global app menu bar, so the model
   is authoritative — the host renders it and tray surfaces realize
   it. *)
let app_menu = ref [||]

let app_menu_insert m ~at =
  let n = Array.length !app_menu in
  let at = if at < 0 then n + at else at in
  let at = max 0 (min at n) in
  let next = Array.make (n + 1) m in
  Array.blit !app_menu 0 next 0 at;
  Array.blit !app_menu at next (at + 1) (n - at);
  app_menu := next;
  true

let app_menu_remove ~at =
  let n = Array.length !app_menu in
  if at < 0 || at >= n then false
  else begin
    let next = Array.make (n - 1) !app_menu.(0) in
    Array.blit !app_menu 0 next 0 at;
    Array.blit !app_menu (at + 1) next at (n - at - 1);
    app_menu := next;
    true
  end

let app_menu_count () = Array.length !app_menu
let app_menus () = !app_menu

(* ------------------------------------------------------- status item *)

type status_item = { handle : Obj.t; tag : int }

external c_status_create : int -> Obj.t = "lui_shx_status_create"
external c_status_remove : Obj.t -> unit = "lui_shx_status_remove"
external c_status_live : Obj.t -> bool = "lui_shx_status_live"
external c_status_set_title : Obj.t -> string -> unit
  = "lui_shx_status_set_title"
external c_status_set_image : Obj.t -> int -> bytes -> unit
  = "lui_shx_status_set_image"
external c_status_set_menu : Obj.t -> string -> menu_row array option
  -> unit = "lui_shx_status_set_menu"
external c_status_set_on_click : Obj.t -> bool -> unit
  = "lui_shx_status_set_on_click"

let status_item_create ?(tag = 0) () =
  { handle = c_status_create tag; tag }

let status_item_live i = c_status_live i.handle
let status_item_remove i = c_status_remove i.handle
let status_item_set_title i s = c_status_set_title i.handle s

let status_icon_seq = ref 0

let status_item_set_image i img =
  match img with
  | None -> c_status_set_image i.handle (-1) Bytes.empty
  | Some img ->
    incr status_icon_seq;
    c_status_set_image i.handle !status_icon_seq (image_png img)

let status_item_set_menu i m =
  c_status_set_menu i.handle
    (match m with
     | Some m -> m.title
     | None -> "")
    (match m with
     | Some m -> Some m.rows
     | None -> None)

let status_item_set_on_click i on = c_status_set_on_click i.handle on

(* ------------------------------------------------------- notifications *)

external c_notify : string -> string -> string -> int * string
  = "lui_shx_notify"

(* dbus notification id -> caller id: the activation signal resolves
   back through this table. *)
let notify_ids : (int, string) Hashtbl.t = Hashtbl.create 16

let notify ~id ~title ?(subtitle = "") ~body () =
  probe ();
  let body =
    if subtitle = "" then body else subtitle ^ "\n" ^ body
  in
  let dbus_id, detail = c_notify !app_name_ref title body in
  if dbus_id > 0 then Hashtbl.replace notify_ids dbus_id id;
  (dbus_id > 0, detail)

(* ---------------------------------------------------------- clipboard *)

external c_clip_write : string -> bool = "lui_shx_clip_write"
external c_clip_read : unit -> string option = "lui_shx_clip_read"
external c_clip_clear : unit -> int = "lui_shx_clip_clear"
external c_clip_count : unit -> int = "lui_shx_clip_count"

let clipboard_write s =
  probe ();
  c_clip_write s

let clipboard_read () =
  probe ();
  c_clip_read ()

let clipboard_clear () =
  probe ();
  c_clip_clear ()

let clipboard_change_count () =
  probe ();
  c_clip_count ()

(* ------------------------------------------------------------ dialogs *)

external c_can_present : unit -> bool = "lui_shx_can_present"
external c_open_panel : bool -> bool -> bool -> string array ->
  string array option = "lui_shx_open_panel"
external c_save_panel : string -> string option = "lui_shx_save_panel"

let can_present_dialogs () =
  probe ();
  c_can_present ()

let open_dialog ?(dirs = false) ?(files = true) ?(multi = false)
    ?(filters = []) () =
  let filters =
    filters
    |> List.map (fun f ->
           (* Extensions, not "*.ext" patterns. *)
           if String.length f > 0 && f.[0] = '.' then
             String.sub f 1 (String.length f - 1)
           else f)
    |> List.filter (fun f -> f <> "")
  in
  match c_open_panel files dirs multi (Array.of_list filters) with
  | Some paths -> Some (Array.to_list paths)
  | None -> None

let save_dialog ?(default_name = "") () = c_save_panel default_name

(* ----------------------------------------------------------- open-url *)

external c_open_url : string -> bool = "lui_shx_open_url"
external c_openurl_bus : string -> string -> bool = "lui_shx_openurl_bus"

let open_url url =
  probe ();
  c_open_url url

(* XDG plumbing — pure, runs anywhere. *)

(* A desktop file name is [A-Za-z0-9._-]; anything else becomes '-'. *)
let desktop_name id =
  String.map
    (fun c ->
      if
        (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c = '.' || c = '-' || c = '_'
      then c
      else '-')
    id

(* Desktop entry string values cannot hold control characters. *)
let entry_string s =
  String.map (fun c -> if Char.code c < 0x20 then ' ' else c) s

(* An Exec argument in a desktop entry: wrapped in double quotes with
   the reserved characters (quote, backtick, dollar) escaped by a
   backslash, a backslash itself doubled, and percent doubled for
   field codes. *)
let exec_arg arg =
  let b = Buffer.create (String.length arg + 8) in
  Buffer.add_char b '"';
  String.iter
    (fun c ->
      match c with
      | '"' | '`' | '$' ->
        Buffer.add_char b '\\';
        Buffer.add_char b c
      | '\\' -> Buffer.add_string b "\\\\"
      | '%' -> Buffer.add_string b "%%"
      | _ -> Buffer.add_char b c)
    arg;
  Buffer.add_char b '"';
  Buffer.contents b

(* The hidden handler entry: DBusActivatable so the running instance
   gets Open over the bus, an Exec fallback so a cold start still
   receives the URL on argv. *)
let handler_desktop_entry ~name ~exe schemes =
  let mime =
    String.concat "" (List.map (fun s -> "x-scheme-handler/" ^ s ^ ";") schemes)
  in
  Printf.sprintf
    "[Desktop Entry]\n\
     Type=Application\n\
     Name=%s\n\
     Exec=%s %%u\n\
     Terminal=false\n\
     NoDisplay=true\n\
     DBusActivatable=true\n\
     MimeType=%s\n"
    (entry_string name) (exec_arg exe) mime

let handler_entry id =
  ( Filename.concat (xdg_dir "XDG_DATA_HOME" ".local/share")
      "applications",
    desktop_name id ^ ".url-handler.desktop" )

(* The schemes a handler entry already declares. *)
let handler_schemes path =
  let schemes = ref [] in
  (try
     let ic = open_in path in
     (try
        while true do
          let line = input_line ic in
          let line = String.trim line in
          if String.length line > 9
             && String.sub line 0 9 = "MimeType="
          then
            String.split_on_char ';' (String.sub line 9
                                        (String.length line - 9))
            |> List.iter (fun m ->
                   let prefix = "x-scheme-handler/" in
                   if
                     String.length m > String.length prefix
                     && String.sub m 0 (String.length prefix) = prefix
                   then
                     schemes :=
                       String.sub m (String.length prefix)
                         (String.length m - String.length prefix)
                       :: !schemes)
        done
      with End_of_file -> close_in ic)
   with Sys_error _ -> ());
  List.rev !schemes

let default_apps_section = "[Default Applications]"

let mimeapps_list () =
  Filename.concat (xdg_dir "XDG_CONFIG_HOME" ".config") "mimeapps.list"

let read_lines path =
  try
    let ic = open_in path in
    let lines = ref [] in
    (try
       while true do
         lines := input_line ic :: !lines
       done
     with End_of_file -> close_in ic);
    List.rev !lines
  with Sys_error _ -> []

let rec mkdir_p dir =
  if dir <> "" && dir <> "/" && not (Sys.file_exists dir) then begin
    mkdir_p (Filename.dirname dir);
    Unix.mkdir dir 0o755
  end

let write_file_atomic path data =
  let dir = Filename.dirname path in
  (try mkdir_p dir
   with Unix.Unix_error _ | Sys_error _ -> ());
  let tmp = path ^ ".tmp" in
  let oc = open_out_bin tmp in
  output_string oc data;
  close_out oc;
  Unix.rename tmp path

(* The default application for a mime type per the user's
   mimeapps.list. *)
let mime_default mime =
  let lines = read_lines (mimeapps_list ()) in
  let section = ref "" in
  List.find_map
    (fun line ->
      let line = String.trim line in
      if String.length line > 0 && line.[0] = '[' then section := line;
      match String.index_opt line '=' with
      | Some i
        when !section = default_apps_section
             && String.trim (String.sub line 0 i) = mime ->
        let v = String.sub line (i + 1) (String.length line - i - 1) in
        let v = String.trim v in
        (match String.index_opt v ';' with
         | Some j -> Some (String.sub v 0 j)
         | None -> Some v)
      | _ -> None)
    lines

(* [set_mime_default mime file owner] makes [file] the default for
   [mime]; an empty [file] removes the default only when it is
   [owner]'s. *)
let set_mime_default mime file owner =
  let path = mimeapps_list () in
  let lines = read_lines path in
  (* Locate the [Default Applications] section span. *)
  let start, stop =
    let s = ref (-1) and e = ref (List.length lines) in
    List.iteri
      (fun i line ->
        let t = String.trim line in
        if !s >= 0 && !e = List.length lines
           && String.length t > 0 && t.[0] = '['
        then e := i;
        if t = default_apps_section then s := i)
      lines;
    (!s, !e)
  in
  let arr = Array.of_list lines in
  let found = ref (-1) in
  if start >= 0 then
    for i = start + 1 to stop - 1 do
      match String.index_opt arr.(i) '=' with
      | Some j
        when String.trim (String.sub arr.(i) 0 j) = mime ->
        found := i
      | _ -> ()
    done;
  let next =
    if file = "" then begin
      match !found with
      | i when i < 0 -> lines
      | i ->
        let v =
          match String.index_opt arr.(i) '=' with
          | Some j ->
            String.trim
              (String.sub arr.(i) (j + 1)
                 (String.length arr.(i) - j - 1))
          | None -> ""
        in
        (* Only remove when the current default is ours. *)
        if
          (match String.index_opt v ';' with
           | Some j -> String.sub v 0 j
           | None -> v)
          = owner
        then List.filteri (fun k _ -> k <> i) lines
        else lines
    end
    else begin
      let entry = mime ^ "=" ^ file in
      match !found with
      | i when i >= 0 ->
        List.mapi (fun k l -> if k = i then entry else l) lines
      | _ when start >= 0 ->
        List.mapi (fun k l -> if k = start then l ^ "\n" ^ entry else l)
          lines
        |> List.concat_map (String.split_on_char '\n')
      | _ ->
        lines
        @ (if List.length lines > 0 then [ "" ] else [])
        @ [ default_apps_section; entry ]
    end
  in
  write_file_atomic path (String.concat "\n" next ^ "\n")

(* Bus name for a handler desktop file: the file's basename minus
   .desktop, kept valid (elements of [A-Za-z0-9_-] joined by dots, no
   leading digit). *)
let bus_name_of_desktop_id file =
  let base =
    if Filename.check_suffix file ".desktop" then
      Filename.chop_suffix file ".desktop"
    else file
  in
  let parts =
    String.split_on_char '.' base
    |> List.map (fun p ->
           String.map
             (fun c ->
               if
                 (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
                 || (c >= '0' && c <= '9') || c = '_' || c = '-'
               then c
               else '_')
             p)
    |> List.filter (fun p -> p <> "")
  in
  let parts =
    match parts with
    | [] -> [ "lui"; "app" ]
    | p :: _ when p <> "" && p.[0] >= '0' && p.[0] <= '9' ->
      "lui" :: parts
    | _ -> parts
  in
  String.concat "." parts

(* The org.freedesktop.Application object path for a bus name. *)
let object_path_of_bus_name name =
  "/"
  ^ String.map
      (fun c ->
        if c = '.' then '/'
        else if
          (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
          || (c >= '0' && c <= '9') || c = '_'
        then c
        else '_')
      name

let install_open_url_handler ~scheme ?id ?name () =
  let id = match id with
    | Some i when i <> "" -> i
    | _ -> Filename.basename (executable_path ())
  in
  let name = match name with
    | Some n when n <> "" -> n
    | _ -> !app_name_ref
  in
  let dir, file = handler_entry id in
  let path = Filename.concat dir file in
  let schemes =
    let have = handler_schemes path in
    if List.mem scheme have then have else have @ [ scheme ]
  in
  let file_ok =
    try
      write_file_atomic path
        (handler_desktop_entry ~name ~exe:(executable_path ()) schemes);
      true
    with Sys_error _ | Unix.Unix_error _ -> false
  in
  let mime_ok =
    (try set_mime_default ("x-scheme-handler/" ^ scheme) file file
     with _ -> ());
    (match mime_default ("x-scheme-handler/" ^ scheme) with
     | Some f -> f = file
     | None -> false)
  in
  (* With a session bus, claim the activatable name and serve the
     org.freedesktop.Application object; without one the Exec line is
     the only delivery path. *)
  probe ();
  let bus = bus_name_of_desktop_id file in
  let bus_ok = c_openurl_bus bus (object_path_of_bus_name bus) in
  file_ok && mime_ok && (bus_ok || transport () = Offline)

(* ----------------------------------------------------- event handlers *)

(* One handler per event kind, registered under fixed named values for
   the C side. Dispatch runs inside [pump] on the calling thread. *)
let menu_handler = ref (fun (_ : int) -> ())
let status_handler = ref (fun (_ : int) -> ())
let notification_handler = ref (fun (_ : string) -> ())
let open_url_handler = ref (fun (_ : string) -> ())

let set_menu_handler f =
  menu_handler := (match f with Some f -> f | None -> fun _ -> ())

let set_status_handler f =
  status_handler := (match f with Some f -> f | None -> fun _ -> ())

let set_notification_handler f =
  notification_handler :=
    (match f with Some f -> f | None -> fun _ -> ())

let set_open_url_handler f =
  open_url_handler := (match f with Some f -> f | None -> fun _ -> ())

(* Event kinds carried in the pump queue: *)
let ev_notify_invoked = 0
let ev_notify_closed = 1
let ev_open_url = 2
let ev_menu_select = 3
let ev_status_click = 4

(* One queued event, translated — the wire (kind, int, string) triple
   the stubs deliver. *)
let dispatch_event (kind, iarg, sarg) =
  if kind = ev_notify_invoked then
    (match Hashtbl.find_opt notify_ids iarg with
     | Some id -> !notification_handler id
     | None -> ())
  else if kind = ev_notify_closed then
    Hashtbl.remove notify_ids iarg
  else if kind = ev_open_url then
    !open_url_handler sarg
  else if kind = ev_menu_select then
    !menu_handler iarg
  else if kind = ev_status_click then
    !status_handler iarg

let pump ?(timeout_ms = 0) () =
  probe ();
  let events = c_pump (max 0 timeout_ms) in
  Array.iter dispatch_event events;
  Array.length events

(* ------------------------------------------------------ for tests *)

module Private = struct
  let png_of_rgba ~width ~height px = Png.encode ~width ~height px
  let desktop_name = desktop_name
  let entry_string = entry_string
  let exec_arg = exec_arg
  let handler_desktop_entry = handler_desktop_entry
  let handler_schemes = handler_schemes
  let handler_entry = handler_entry
  let mime_default = mime_default
  let set_mime_default = set_mime_default
  let mimeapps_list = mimeapps_list
  let bus_name_of_desktop_id = bus_name_of_desktop_id
  let object_path_of_bus_name = object_path_of_bus_name
  let fnv1a32 = fnv1a32
  let launcher_path = launcher_path
  let session_bus_address = session_bus_address
  let desktop_entry_id = desktop_entry_id
  let dispatch_event = dispatch_event
  let window_title = window_title
end
