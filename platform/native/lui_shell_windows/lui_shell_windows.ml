(* Desktop shell for Windows: tray icon, popup menus, notifications,
   clipboard, dialogs and open-url handling. The contract is in
   lui_shell_windows.mli; the Windows implementation lives in
   lui_shell_windows_stubs.c. Record layouts below are what the C
   stubs consume, in declaration order. *)

(* Platform handles arrive as custom blocks; nothing in OCaml
   constructs or destructs them. *)
type image = Obj.t

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

type status_item = { handle : Obj.t; tag : int }

external c_image_rgba : int -> int -> bytes -> image option
  = "lui_shw_image_rgba"
external c_image_size : image -> float * float = "lui_shw_image_size"
external c_popup_menu : menu_row array -> int = "lui_shw_popup_menu"
external c_status_create : int -> Obj.t = "lui_shw_status_create"
external c_status_remove : Obj.t -> unit = "lui_shw_status_remove"
external c_status_set_title : Obj.t -> string -> unit
  = "lui_shw_status_set_title"
external c_status_set_image : Obj.t -> image option -> unit
  = "lui_shw_status_set_image"
external c_status_set_menu : Obj.t -> menu_row array option -> unit
  = "lui_shw_status_set_menu"
external c_status_set_on_click : Obj.t -> bool -> unit
  = "lui_shw_status_set_on_click"
external c_notify : string -> string -> string -> string ->
  bool * string = "lui_shw_notify"
external c_clip_write : string -> bool = "lui_shw_clip_write"
external c_clip_read : unit -> string option = "lui_shw_clip_read"
external c_clip_clear : unit -> int = "lui_shw_clip_clear"
external c_clip_count : unit -> int = "lui_shw_clip_count"
external c_clip_write_format : string -> bytes -> bool
  = "lui_shw_clip_write_format"
external c_clip_read_format : string -> bytes option
  = "lui_shw_clip_read_format"
external c_can_present : unit -> bool = "lui_shw_can_present"
external c_open_panel : bool -> bool -> bool -> string array ->
  string array option = "lui_shw_open_panel"
external c_save_panel : string -> string option = "lui_shw_save_panel"
external c_open_url : string -> bool = "lui_shw_open_url"
external c_register_scheme : string -> string -> bool
  = "lui_shw_register_scheme"
external c_unregister_scheme : string -> bool
  = "lui_shw_unregister_scheme"
external c_pump : unit -> int = "lui_shw_pump"

(* One handler per event kind, registered under fixed named values for
   the C side. Dispatch runs on the thread that owns the library's
   hidden window, while it pumps — see lui_shell_windows_stubs.c. *)
let menu_handler = ref (fun (_ : int) -> ())
let status_handler = ref (fun (_ : int) -> ())
let notification_handler = ref (fun (_ : string) -> ())
let open_url_handler = ref (fun (_ : string) -> ())

(* ------------------------------------------------------------ images *)

let image_of_rgba ~width ~height px =
  if width <= 0 || height <= 0
     || Bytes.length px <> width * height * 4
  then None
  else c_image_rgba width height px

let image_size = c_image_size

(* ------------------------------------------------------------- menus *)

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

let popup_menu m = c_popup_menu m.rows

(* ------------------------------------------------------- status item *)

let status_item_create ?(tag = 0) () =
  { handle = c_status_create tag; tag }

let status_item_remove item = c_status_remove item.handle
let status_item_set_title item s = c_status_set_title item.handle s
let status_item_set_image item img = c_status_set_image item.handle img

let status_item_set_menu item m =
  c_status_set_menu item.handle
    (match m with
     | Some m -> Some m.rows
     | None -> None)

let status_item_set_on_click item on = c_status_set_on_click item.handle on

(* ------------------------------------------------------- notifications *)

let notify ~id ~title ?(subtitle = "") ~body () =
  c_notify id title subtitle body

(* ---------------------------------------------------------- clipboard *)

let clipboard_write = c_clip_write
let clipboard_read = c_clip_read
let clipboard_clear = c_clip_clear
let clipboard_change_count = c_clip_count

let valid_format_name name =
  let n = String.length name in
  n > 0 && not (String.contains name '\000')

let clipboard_write_format name data =
  valid_format_name name && c_clip_write_format name data

let clipboard_read_format name =
  if valid_format_name name then c_clip_read_format name else None

(* ------------------------------------------------------------ dialogs *)

let can_present_dialogs = c_can_present

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

let open_url url =
  String.length url > 0 && not (String.contains url '\000')
  && c_open_url url

(* The schemes registered by [register_url_scheme]; only their URLs are
   delivered to the handler. Scheme names are case-insensitive per
   RFC 3986. *)
let registered_schemes : string list ref = ref []

(* RFC 3986: ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ). *)
let valid_scheme scheme =
  let n = String.length scheme in
  let is_letter c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
  in
  let rec go i =
    i = n
    || ((let c = scheme.[i] in
         is_letter c || (c >= '0' && c <= '9')
         || c = '+' || c = '-' || c = '.')
        && go (i + 1))
  in
  n > 0 && is_letter scheme.[0] && go 1

let register_url_scheme ~scheme ?(name = "") () =
  if not (valid_scheme scheme) then false
  else if c_register_scheme scheme
            (if name = "" then scheme ^ " URL" else name)
  then begin
    let lc = String.lowercase_ascii scheme in
    if not (List.mem lc !registered_schemes) then
      registered_schemes := lc :: !registered_schemes;
    true
  end else false

let unregister_url_scheme ~scheme () =
  if valid_scheme scheme then begin
    registered_schemes :=
      List.filter
        (fun s -> s <> String.lowercase_ascii scheme)
        !registered_schemes;
    c_unregister_scheme scheme
  end else false

let scheme_of_url url =
  match String.index_opt url ':' with
  | None | Some 0 -> None
  | Some i -> Some (String.lowercase_ascii (String.sub url 0 i))

let dispatch_open_url url =
  match scheme_of_url url with
  | Some s when List.mem s !registered_schemes ->
    !open_url_handler url;
    true
  | _ -> false

let install_open_url_handler () =
  for i = 1 to Array.length Sys.argv - 1 do
    ignore (dispatch_open_url Sys.argv.(i))
  done;
  true

(* ------------------------------------------------------------ pump *)

let pump_pending = c_pump

(* ----------------------------------------------------- event handlers *)

let set_menu_handler f =
  menu_handler := (match f with Some f -> f | None -> fun _ -> ())

let set_status_handler f =
  status_handler := (match f with Some f -> f | None -> fun _ -> ())

let set_notification_handler f =
  notification_handler :=
    (match f with Some f -> f | None -> fun _ -> ())

let set_open_url_handler f =
  open_url_handler := (match f with Some f -> f | None -> fun _ -> ())

let () =
  Callback.register "lui_shellw_menu_select"
    (fun id -> !menu_handler id);
  Callback.register "lui_shellw_status_click"
    (fun tag -> !status_handler tag);
  Callback.register "lui_shellw_notify_click"
    (fun id -> !notification_handler id);
  Callback.register "lui_shellw_open_url"
    (fun url -> !open_url_handler url)
