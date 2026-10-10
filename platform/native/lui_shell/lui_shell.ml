(* Desktop shell: app identity, status item, menus, notifications,
   clipboard, dialogs and open-url handling. The contract is in
   lui_shell.mli; the macOS implementation lives in
   lui_shell_stubs.c. Record layouts below are what the C stubs
   consume, in declaration order. *)

(* Platform handles arrive as custom blocks; nothing in OCaml
   constructs or destructs them. *)
type image = Obj.t

type activation_policy = Regular | Accessory | Prohibited

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

external c_policy_set : int -> bool = "lui_sh_policy_set"
external c_policy_get : unit -> int = "lui_sh_policy_get"
external c_set_app_name : string -> unit = "lui_sh_set_app_name"
external c_dock_badge : string option -> unit = "lui_sh_dock_badge"
external c_attention : bool -> int = "lui_sh_attention"
external c_window_title : string -> bool = "lui_sh_window_title"
external c_image_rgba : int -> int -> bytes -> image option
  = "lui_sh_image_rgba"
external c_image_size : image -> float * float = "lui_sh_image_size"
external c_menubar_insert : string -> menu_row array -> int -> bool
  = "lui_sh_menubar_insert"
external c_menubar_count : unit -> int = "lui_sh_menubar_count"
external c_menubar_remove : int -> bool = "lui_sh_menubar_remove"
external c_status_create : int -> Obj.t = "lui_sh_status_create"
external c_status_remove : Obj.t -> unit = "lui_sh_status_remove"
external c_status_set_title : Obj.t -> string -> unit
  = "lui_sh_status_set_title"
external c_status_set_image : Obj.t -> image option -> unit
  = "lui_sh_status_set_image"
external c_status_set_menu : Obj.t -> string -> menu_row array option
  -> unit = "lui_sh_status_set_menu"
external c_status_set_on_click : Obj.t -> bool -> unit
  = "lui_sh_status_set_on_click"
external c_notify : string -> string -> string -> string ->
  bool * string = "lui_sh_notify"
external c_clip_write : string -> bool = "lui_sh_clip_write"
external c_clip_read : unit -> string option = "lui_sh_clip_read"
external c_clip_clear : unit -> int = "lui_sh_clip_clear"
external c_clip_count : unit -> int = "lui_sh_clip_count"
external c_can_present : unit -> bool = "lui_sh_can_present"
external c_open_panel : bool -> bool -> bool -> string array ->
  string array option = "lui_sh_open_panel"
external c_save_panel : string -> string option = "lui_sh_save_panel"
external c_install_openurl : unit -> bool = "lui_sh_install_openurl"

(* ------------------------------------------------------ app identity *)

let policy_to_int = function
  | Regular -> 0
  | Accessory -> 1
  | Prohibited -> 2

let policy_of_int = function
  | 0 -> Some Regular
  | 1 -> Some Accessory
  | 2 -> Some Prohibited
  | _ -> None

let set_activation_policy p = c_policy_set (policy_to_int p)
let activation_policy () = policy_of_int (c_policy_get ())
let set_app_name = c_set_app_name
let set_dock_badge = c_dock_badge

let request_user_attention ?(critical = false) () =
  c_attention critical

let set_window_title = c_window_title

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

let app_menu_insert m ~at = c_menubar_insert m.title m.rows at
let app_menu_remove ~at = c_menubar_remove at
let app_menu_count = c_menubar_count

(* ------------------------------------------------------- status item *)

let status_item_create ?(tag = 0) () =
  { handle = c_status_create tag; tag }

let status_item_remove item = c_status_remove item.handle
let status_item_set_title item s = c_status_set_title item.handle s
let status_item_set_image item img = c_status_set_image item.handle img

let status_item_set_menu item m =
  c_status_set_menu item.handle
    (match m with
     | Some m -> m.title
     | None -> "")
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

let install_open_url_handler = c_install_openurl

(* ----------------------------------------------------- event handlers *)

(* One handler per event kind, registered under fixed named values for
   the C side. Dispatch always lands on the main thread — see
   lui_shell_stubs.c. *)
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

let () =
  Callback.register "lui_shell_menu_select" (fun id -> !menu_handler id);
  Callback.register "lui_shell_status_click"
    (fun tag -> !status_handler tag);
  Callback.register "lui_shell_notify_click"
    (fun id -> !notification_handler id);
  Callback.register "lui_shell_open_url"
    (fun url -> !open_url_handler url)
