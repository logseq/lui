(* AT-SPI accessibility bridge for the native backend on Linux.

   Architecture: all protocol semantics are pure OCaml (role/state
   mapping, served-object bookkeeping, diff -> event translation,
   method-call dispatch); the C stubs are a transport that binds the
   platform's D-Bus client library at runtime and carries the
   marshalled messages.  See the .mli for the contract. *)

(* ---------- AT-SPI role numbers (the enum's wire values) ---------- *)

let role_invalid = 0
let role_check_box = 7
let role_combo_box = 11
let role_dialog = 16
let role_frame = 23
let role_image = 27
let role_list = 31
let role_list_item = 32
let role_menu_item = 35
let role_page_tab = 37
let role_page_tab_list = 38
let role_panel = 39
let role_password_text = 40
let role_popup_menu = 41
let role_progress_bar = 42
let role_push_button = 43
let role_radio_button = 44
let role_separator = 50
let role_slider = 51
let role_spin_button = 52
let role_split_pane = 53
let role_status_bar = 54
let role_table = 55
let role_table_cell = 56
let role_text = 61
let role_toggle_button = 62
let role_tool_bar = 63
let role_tool_tip = 64
let role_tree = 65
let role_unknown = 67
let role_application = 75
let role_entry = 79
let role_heading = 83
let role_link = 88
let role_table_row = 90
let role_tree_item = 91
let role_grouping = 99
let role_landmark = 110
let role_static = 116
let role_switch = 130

(* ---------- role mapping ----------

   Full coverage of every [Lui_a11y.role].  Where AT-SPI has no direct
   counterpart the mapping picks the closest semantic role:

   - Search_field -> ENTRY: AT-SPI has no search role; a search input is
     a single-line entry (clients see an editable text field).
   - Radio_group -> GROUPING: a labelled group of related widgets.
   - Menu -> POPUP_MENU: LUI menus are transient popups (dropdown and
     context menus), not a persistent menu bar.
   - Sheet -> DIALOG: sheets slide over content as modal-ish surfaces;
     there is no dedicated role.
   - Navigation -> LANDMARK: navigation regions (breadcrumbs,
     pagination) are navigation landmarks.
   - Extension -> UNKNOWN: custom widgets carry their identity in
     AccessibleId/ext_id; their semantics are extension-defined.
   - Window -> FRAME: a top-level window with a title (the WINDOW role
     is for borderless toplevels).
   - Switch -> SWITCH: the dedicated role; clients that do not know it
     still receive a consistent role number. *)

let role_map : (Lui_a11y.role * int * string) list =
  [ (Lui_a11y.Window, role_frame, "frame");
    (Group, role_panel, "panel");
    (Static_text, role_static, "static");
    (Heading, role_heading, "heading");
    (Text_field, role_entry, "entry");
    (Text_area, role_text, "text");
    (Search_field, role_entry, "entry");
    (Button, role_push_button, "push button");
    (Toggle_button, role_toggle_button, "toggle button");
    (Check_box, role_check_box, "check box");
    (Radio_button, role_radio_button, "radio button");
    (Radio_group, role_grouping, "grouping");
    (Switch, role_switch, "switch");
    (Slider, role_slider, "slider");
    (Spin_button, role_spin_button, "spin button");
    (Progress_indicator, role_progress_bar, "progress bar");
    (Link, role_link, "link");
    (Image, role_image, "image");
    (List, role_list, "list");
    (List_item, role_list_item, "list item");
    (Outline, role_tree, "tree");
    (Outline_item, role_tree_item, "tree item");
    (Tab_group, role_page_tab_list, "page tab list");
    (Tab, role_page_tab, "page tab");
    (Menu, role_popup_menu, "popup menu");
    (Menu_item, role_menu_item, "menu item");
    (Combo_box, role_combo_box, "combo box");
    (Dialog, role_dialog, "dialog");
    (Sheet, role_dialog, "dialog");
    (Tooltip, role_tool_tip, "tool tip");
    (Table, role_table, "table");
    (Table_row, role_table_row, "table row");
    (Table_cell, role_table_cell, "table cell");
    (Separator, role_separator, "separator");
    (Toolbar, role_tool_bar, "tool bar");
    (Status_bar, role_status_bar, "status bar");
    (Navigation, role_landmark, "landmark");
    (Split_group, role_split_pane, "split pane");
    (Extension, role_unknown, "unknown") ]

let atspi_role_of r =
  match
    List.find_map (fun (r', n, _) -> if r' = r then Some n else None)
      role_map
  with
  | Some n -> n
  | None -> role_invalid

let atspi_role_name r =
  match
    List.find_map (fun (r', _, n) -> if r' = r then Some n else None)
      role_map
  with
  | Some n -> n
  | None -> "unknown"

(* ---------- AT-SPI state numbers + detail names ---------- *)

let state_active = 1
let state_checked = 4
let state_collapsed = 5
let state_editable = 7
let state_enabled = 8
let state_expandable = 9
let state_expanded = 10
let state_focusable = 11
let state_focused = 12
let state_multi_line = 17
let state_opaque = 19
let state_selectable = 22
let state_selected = 23
let state_sensitive = 24
let state_showing = 25
let state_single_line = 26
let state_visible = 30
let state_indeterminate = 32
let state_required = 33
let state_checkable = 41
let state_has_popup = 42
let state_read_only = 43

(* State number -> the detail string StateChanged events carry. *)
let state_names =
  [ (0, "invalid"); (1, "active"); (2, "armed"); (3, "busy");
    (4, "checked"); (5, "collapsed"); (6, "defunct"); (7, "editable");
    (8, "enabled"); (9, "expandable"); (10, "expanded");
    (11, "focusable"); (12, "focused"); (13, "has-tooltip");
    (14, "horizontal"); (15, "iconified"); (16, "modal");
    (17, "multi-line"); (18, "multiselectable"); (19, "opaque");
    (20, "pressed"); (21, "resizable"); (22, "selectable");
    (23, "selected"); (24, "sensitive"); (25, "showing");
    (26, "single-line"); (27, "stale"); (28, "transient");
    (29, "vertical"); (30, "visible"); (31, "manages-descendants");
    (32, "indeterminate"); (33, "required"); (34, "truncated");
    (35, "animated"); (36, "invalid-entry");
    (37, "supports-autocompletion"); (38, "selectable-text");
    (39, "is-default"); (40, "visited"); (41, "checkable");
    (42, "has-popup"); (43, "read-only") ]

let state_name n =
  match List.assoc_opt n state_names with
  | Some s -> s
  | None -> "unknown"

(* ---------- interface names ---------- *)

let itf_accessible = "org.a11y.atspi.Accessible"
let itf_component = "org.a11y.atspi.Component"
let itf_action = "org.a11y.atspi.Action"
let itf_text = "org.a11y.atspi.Text"
let itf_value = "org.a11y.atspi.Value"
let itf_application = "org.a11y.atspi.Application"
let itf_cache = "org.a11y.atspi.Cache"
let itf_socket = "org.a11y.atspi.Socket"
let itf_properties = "org.freedesktop.DBus.Properties"
let itf_introspectable = "org.freedesktop.DBus.Introspectable"
let itf_peer = "org.freedesktop.DBus.Peer"
let evt_object = "org.a11y.atspi.Event.Object"
let evt_focus = "org.a11y.atspi.Event.Focus"
let evt_window = "org.a11y.atspi.Event.Window"

(* ---------- paths ---------- *)

let null_ref = ("", "/org/a11y/atspi/null")
let root_path = "/org/a11y/atspi/accessible/root"
let cache_path = "/org/a11y/atspi/cache"
let path_prefix = "/org/a11y/atspi/accessible/"

let path_of id = path_prefix ^ string_of_int id

let id_of_path p =
  let lp = String.length path_prefix in
  if String.length p > lp && String.sub p 0 lp = path_prefix then
    int_of_string_opt (String.sub p lp (String.length p - lp))
  else None

(* ---------- role-derived helpers ---------- *)

let interactive_role = function
  | Lui_a11y.Button | Toggle_button | Check_box | Radio_button | Switch
  | Slider | Spin_button | Text_field | Text_area | Search_field
  | Combo_box | Menu_item | Link | Tab | Outline_item | List_item -> true
  | _ -> false

let text_role = function
  | Lui_a11y.Static_text | Heading | Text_field | Text_area
  | Search_field -> true
  | _ -> false

let multiline_role = function
  | Lui_a11y.Text_area -> true
  | _ -> false

(* Roles whose children are selectable items — the child's SELECTABLE
   state is set when its a11y parent has one of these roles. *)
let selectable_parent_role = function
  | Lui_a11y.List | Outline | Menu | Tab_group | Radio_group | Table
  | Table_row | Combo_box -> true
  | _ -> false

let popup_role = function
  | Lui_a11y.Combo_box | Menu -> true
  | _ -> false

(* ---------- state translation ---------- *)

let stateset_of parent_role (n : Lui_a11y.node_a11y) =
  let s = n.Lui_a11y.state in
  let set = ref [] in
  let add b st = if b then set := st :: !set in
  (* Only unhidden nodes are served, so both visibility states hold.
     The backend self-draws fully opaque surfaces. *)
  add true state_visible;
  add true state_showing;
  add true state_opaque;
  add (not s.disabled) state_enabled;
  add (not s.disabled) state_sensitive;
  add s.focusable state_focusable;
  add s.focused state_focused;
  add
    (match parent_role with
     | Some p -> selectable_parent_role p
     | None -> false)
    state_selectable;
  add s.selected state_selected;
  (match s.checked with
   | Some Lui_a11y.Checked ->
     set := state_checked :: state_checkable :: !set
   | Some Lui_a11y.Unchecked -> set := state_checkable :: !set
   | Some Lui_a11y.Mixed ->
     set := state_indeterminate :: state_checkable :: !set
   | None -> ());
  (match s.expanded with
   | Some true -> set := state_expanded :: state_expandable :: !set
   | Some false -> set := state_collapsed :: state_expandable :: !set
   | None -> ());
  add s.required state_required;
  add s.read_only state_read_only;
  add
    (text_role n.role && (not s.read_only) && not s.disabled)
    state_editable;
  add (multiline_role n.role) state_multi_line;
  add
    (text_role n.role && not (multiline_role n.role))
    state_single_line;
  add (popup_role n.role) state_has_popup;
  add (n.role = Lui_a11y.Window) state_active;
  List.sort_uniq compare !set

(* ---------- interfaces / actions / text ---------- *)

let interfaces_of (n : Lui_a11y.node_a11y) =
  let ifs = ref [] in
  if interactive_role n.role || n.state.expanded <> None then
    ifs := !ifs @ [ "Action" ];
  if text_role n.role then ifs := !ifs @ [ "Text" ];
  (match n.value with
   | Some v when v.Lui_a11y.numeric <> None ->
     ifs := !ifs @ [ "Value" ]
   | _ -> ());
  [ "Accessible"; "Component" ] @ !ifs

type action = { name : string; description : string }

let actions_of (n : Lui_a11y.node_a11y) =
  let acts = ref [] in
  (match n.Lui_a11y.role with
   | Lui_a11y.Button | Link | Tab | Menu_item | Outline_item | List_item
   | Combo_box ->
     acts := !acts @ [ { name = "press"; description = "Activate the control" } ]
   | Toggle_button | Check_box | Radio_button | Switch ->
     acts := !acts @ [ { name = "toggle"; description = "Toggle the checked state" } ]
   | _ -> ());
  (match n.state.expanded with
   | Some true ->
     acts := !acts @ [ { name = "contract"; description = "Collapse the expanded item" } ]
   | Some false ->
     acts := !acts @ [ { name = "expand"; description = "Expand the collapsed item" } ]
   | None -> ());
  !acts

let text_of (n : Lui_a11y.node_a11y) =
  if not (text_role n.role) then None
  else
    match n.value with
    | Some { Lui_a11y.text = Some s; _ } -> Some s
    | _ -> n.name

let attributes_of (n : Lui_a11y.node_a11y) =
  let a = [ ("toolkit-kind", n.Lui_a11y.kind) ] in
  match n.ext_id with
  | Some e -> a @ [ ("extension-id", e) ]
  | None -> a

(* ---------- UTF-8 / character-offset helpers ----------

   AT-SPI text offsets are Unicode code-point offsets (the atk/glib
   convention); LUI strings are UTF-8 bytes, so every boundary crossing
   translates. *)

let is_continuation b =
  let c = Char.code b in
  c land 0b11000000 = 0b10000000

let char_offset_of_byte s byte =
  let n = min (String.length s) (max 0 byte) in
  let cnt = ref 0 in
  for i = 0 to n - 1 do
    if not (is_continuation s.[i]) then incr cnt
  done;
  !cnt

let decode_at s i =
  (* Decodes one UTF-8 code point at byte [i]; returns (cp, width). *)
  let len = String.length s in
  if i >= len then (-1, 0)
  else begin
    let b0 = Char.code s.[i] in
    if b0 < 0x80 then (b0, 1)
    else if b0 land 0xE0 = 0xC0 && i + 1 < len then
      (((b0 land 0x1F) lsl 6) lor (Char.code s.[i + 1] land 0x3F), 2)
    else if b0 land 0xF0 = 0xE0 && i + 2 < len then
      ( (b0 land 0x0F) lsl 12
        lor (Char.code s.[i + 1] land 0x3F) lsl 6
        lor (Char.code s.[i + 2] land 0x3F),
        3 )
    else if b0 land 0xF8 = 0xF0 && i + 3 < len then
      ( (b0 land 0x07) lsl 18
        lor (Char.code s.[i + 1] land 0x3F) lsl 12
        lor (Char.code s.[i + 2] land 0x3F) lsl 6
        lor (Char.code s.[i + 3] land 0x3F),
        4 )
    else (b0, 1)
  end

let next_boundary s i =
  (* Next code-point boundary strictly after byte offset i. *)
  let len = String.length s in
  let j = ref (i + 1) in
  while !j < len && is_continuation s.[!j] do
    incr j
  done;
  min !j len

let prev_boundary s i =
  let j = ref (i - 1) in
  while !j > 0 && is_continuation s.[!j] do
    decr j
  done;
  max !j 0

let byte_of_char_offset s n =
  (* Byte offset of the [n]th code point's first byte. *)
  if n <= 0 then 0
  else begin
    let pos = ref 0 and cnt = ref 0 in
    let len = String.length s in
    while !pos < len && !cnt < n do
      pos := next_boundary s !pos;
      incr cnt
    done;
    !pos
  end

let char_at s n =
  let b = byte_of_char_offset s n in
  if b >= String.length s then -1 else fst (decode_at s b)

let char_count s = char_offset_of_byte s (String.length s)

(* ---------- text granularity ----------

   AT-SPI boundary types: 0 char, 1 word-start, 2 word-end,
   3 sentence-start, 4 sentence-end, 5 line-start, 6 line-end. *)

let cp_of_byte s i = fst (decode_at s i)

let is_word_char cp =
  (cp >= Char.code 'a' && cp <= Char.code 'z')
  || (cp >= Char.code 'A' && cp <= Char.code 'Z')
  || (cp >= Char.code '0' && cp <= Char.code '9')
  || cp = Char.code '_' || cp > 0x7F

let word_start s i =
  let len = String.length s in
  if len = 0 then 0
  else begin
    let i = min i len in
    let rec back j =
      if j <= 0 then 0
      else
        let p = prev_boundary s j in
        if is_word_char (cp_of_byte s p) then back p else j
    in
    let rec fwd j =
      if j >= len then len
      else if is_word_char (cp_of_byte s j) then j
      else fwd (next_boundary s j)
    in
    if i >= len then back len
    else if is_word_char (cp_of_byte s i) then back i
    else fwd i (* not inside a word: next word start *)
  end

let word_end s i =
  let len = String.length s in
  let rec fwd j =
    if j >= len then len
    else if is_word_char (cp_of_byte s j) then fwd (next_boundary s j)
    else j
  in
  fwd (word_start s i)

let is_sentence_end cp =
  cp = Char.code '.' || cp = Char.code '!' || cp = Char.code '?'
  || cp = 0x3002 || cp = 0xFF01 || cp = 0xFF1F

let sentence_start s i =
  let len = String.length s in
  if len = 0 then 0
  else begin
    let rec back j =
      if j <= 0 then 0
      else
        let p = prev_boundary s j in
        if is_sentence_end (cp_of_byte s p) then begin
          (* Sentence starts after the terminator's trailing spaces. *)
          let rec skip k =
            if k < len
               && (cp_of_byte s k = Char.code ' '
                   || cp_of_byte s k = Char.code '\t')
            then skip (next_boundary s k)
            else k
          in
          skip j
        end
        else back p
    in
    back (min i len)
  end

let sentence_end s i =
  let len = String.length s in
  let rec fwd j =
    if j >= len then len
    else if is_sentence_end (cp_of_byte s j) then next_boundary s j
    else fwd (next_boundary s j)
  in
  fwd (min i len)

let line_start s i =
  let rec back j =
    if j <= 0 then 0
    else if s.[j - 1] = '\n' then j
    else back (j - 1)
  in
  back (min i (String.length s))

let line_end s i =
  let len = String.length s in
  let rec fwd j =
    if j >= len then len
    else if s.[j] = '\n' then j + 1 (* include the newline *)
    else fwd (j + 1)
  in
  fwd (min i len)

(* One "at offset" range for a granularity kind, in byte offsets. *)
let at_range s kind i =
  match kind with
  | 0 ->
    if i >= String.length s then (String.length s, String.length s)
    else (i, next_boundary s i)
  | 1 | 2 -> (word_start s i, word_end s i)
  | 3 | 4 -> (sentence_start s i, sentence_end s i)
  | 5 | 6 -> (line_start s i, line_end s i)
  | _ -> (0, 0)

(* At/before/after resolution.  [dir]: 0 at, <0 before, >0 after. *)
let text_range ?(offset = 0) s kind dir =
  let b0 = byte_of_char_offset s offset in
  let bs, be =
    if dir = 0 then at_range s kind b0
    else if dir < 0 then
      let a, _ = at_range s kind b0 in
      if a <= 0 then (0, 0)
      else begin
        (* Walk back from the current unit's start, skipping bytes that
           cannot contain a unit: non-word bytes for word granularity,
           the inter-sentence whitespace gap for sentences. *)
        let rec back j =
          if j <= 0 then -1
          else
            let p = prev_boundary s j in
            let cp = cp_of_byte s p in
            if (kind = 1 || kind = 2) && not (is_word_char cp) then back p
            else if
              (kind = 3 || kind = 4)
              && (cp = Char.code ' ' || cp = Char.code '\t')
            then back p
            else p
        in
        match back a with
        | -1 -> (0, 0)
        | p -> at_range s kind p
      end
    else
      let _, b = at_range s kind b0 in
      if b >= String.length s then (String.length s, String.length s)
      else at_range s kind b
  in
  (bs, be, char_offset_of_byte s bs)

(* ---------- wire values ---------- *)

type dvalue =
  | DStr of string
  | DInt of int
  | DUInt of int
  | DN16 of int
  | DBool of bool
  | DDbl of float
  | DObj of string
  | DVar of string * dvalue
  | DArr of string * dvalue list
  | DStruct of dvalue list
  | DDict of string * (string * dvalue) list

type obj_ref = string * string

(* ---------- events ---------- *)

type event_data =
  | D_unit
  | D_int of int
  | D_str of string
  | D_ref of string

type cache_item = {
  path : string;
  parent_path : string option;
  index_in_parent : int;
  child_count : int;
  interfaces : string list;
  name : string;
  role : int;
  description : string;
  states : int list;
}

type object_event = {
  path : string;
  iface : string;
  member : string;
  detail : string;
  detail1 : int;
  detail2 : int;
  any : event_data;
}

type event =
  | Object_event of object_event
  | Cache_add of cache_item
  | Cache_remove of string
  | Cache_ready
  | Focus_event of string
  | Window_event of string * string

(* ---------- served objects ---------- *)

type served = {
  id : int;
  path : string;
  mutable node : Lui_a11y.node_a11y;
  mutable atspi_role : int;
  mutable states : int list;
  mutable interfaces : string list;
  mutable actions : action list;
  mutable text : string option;
  mutable caret : int;
  mutable children : int list;
  mutable parent : int option;
}

type transport = Offline | Session_bus | A11y_bus

type call = {
  serial : int;
  path : string;
  iface : string;
  member : string;
  iargs : int array;
  fargs : float array;
  sargs : string array;
}

type reply = Value of dvalue list | Error of string * string

type t = {
  toolkit_name : string;
  toolkit_version : string;
  mutable a11y : Lui_a11y.t option;
  objs : (int, served) Hashtbl.t;
  mutable roots : int list;
  mutable app_id : int;
  mutable bus_name : string;
  mutable desktop : obj_ref option;
  mutable trans : transport;
  conn : int ref;
  pending : event Queue.t;
  mutable cb_action : int -> string -> unit;
  mutable cb_focus : int -> unit;
  mutable cb_caret : int -> int -> bool;
  mutable cb_value : int -> float -> bool;
}

(* ---------- externals (transport) ---------- *)

external c_dbus_probe : unit -> int = "lui_ax_dbus_probe"
external c_dbus_open : string -> int = "lui_ax_dbus_open"
external c_dbus_close : int -> unit = "lui_ax_dbus_close"
external c_dbus_name : int -> string = "lui_ax_dbus_name"
external c_dbus_a11y_address : int -> string = "lui_ax_dbus_a11y_address"
external c_dbus_embed : int -> string -> string * string
  = "lui_ax_dbus_embed"
external c_dbus_poll : int -> int ->
  (int * string * string * string * int array * float array *
   string array) array = "lui_ax_dbus_poll"
external c_reply : int -> int -> dvalue array -> unit = "lui_ax_reply"
external c_reply_error : int -> int -> string -> string -> unit
  = "lui_ax_reply_error"
external c_emit_num : int -> string -> string -> string -> string ->
  int -> int -> int -> unit = "lui_ax_emit_num_bc" "lui_ax_emit_num"
external c_emit_str : int -> string -> string -> string -> string ->
  int -> int -> string -> unit = "lui_ax_emit_str_bc" "lui_ax_emit_str"
external c_emit_ref : int -> string -> string -> string -> string ->
  int -> int -> string -> unit = "lui_ax_emit_ref_bc" "lui_ax_emit_ref"
external c_emit_sig : int -> string -> string -> string -> unit
  = "lui_ax_emit_sig"
external c_emit_cache_add : int -> string -> string -> int -> int ->
  string array -> string -> int -> string -> int array -> unit
  = "lui_ax_emit_cache_add_bc" "lui_ax_emit_cache_add"
external c_emit_cache_remove : int -> string -> unit
  = "lui_ax_emit_cache_remove"

(* ---------- create / attach ---------- *)

let create ?(toolkit_name = "lui") ?(toolkit_version = "") () =
  { toolkit_name;
    toolkit_version;
    a11y = None;
    objs = Hashtbl.create 64;
    roots = [];
    app_id = 0;
    bus_name = "";
    desktop = None;
    trans = Offline;
    conn = ref 0;
    pending = Queue.create ();
    cb_action = (fun _ _ -> ());
    cb_focus = (fun _ -> ());
    cb_caret = (fun _ _ -> false);
    cb_value = (fun _ _ -> false) }

let a11y t = t.a11y

let parent_role_of t (n : Lui_a11y.node_a11y) =
  match n.parent with
  | Some p ->
    (match Hashtbl.find_opt t.objs p with
     | Some s -> Some s.node.role
     | None ->
       (match t.a11y with
        | Some a ->
          (match Lui_a11y.find a p with
           | Some pn -> Some pn.role
           | None -> None)
        | None -> None))
  | None -> None

let served_role (n : Lui_a11y.node_a11y) =
  (* Password fields report PASSWORD_TEXT: the role comes from state,
     not kind. *)
  if n.Lui_a11y.state.password then role_password_text
  else atspi_role_of n.role

let mk_served t (n : Lui_a11y.node_a11y) =
  let id = n.id in
  { id;
    path = path_of id;
    node = n;
    atspi_role = served_role n;
    states = stateset_of (parent_role_of t n) n;
    interfaces = interfaces_of n;
    actions = actions_of n;
    text = text_of n;
    caret = 0;
    children = n.children;
    parent = n.parent }

let index_of lst x =
  let rec go i = function
    | [] -> -1
    | c :: tl -> if c = x then i else go (i + 1) tl
  in
  go 0 lst

let index_in_parent t id =
  match Hashtbl.find_opt t.objs id with
  | Some s ->
    (match s.parent with
     | Some p ->
       (match Hashtbl.find_opt t.objs p with
        | Some sp -> index_of sp.children id
        | None -> index_of t.roots id)
     | None -> index_of t.roots id)
  | None -> -1

let ref_of t path =
  if path = "" then null_ref else (t.bus_name, path)

let ref_of_id t id =
  match Hashtbl.find_opt t.objs id with
  | Some s -> ref_of t s.path
  | None -> null_ref

let cache_item_of t s =
  let parent_path =
    (* Every served non-root object's a11y parent, or the application
       root for forest-top objects. *)
    match s.parent with
    | Some p ->
      (match Hashtbl.find_opt t.objs p with
       | Some sp -> Some sp.path
       | None -> Some root_path)
    | None -> Some root_path
  in
  { path = s.path;
    parent_path;
    index_in_parent = index_in_parent t s.id;
    child_count = List.length s.children;
    interfaces = s.interfaces;
    name = Option.value ~default:"" s.node.name;
    role = s.atspi_role;
    description = Option.value ~default:"" s.node.description;
    states = s.states }

let push t ev = Queue.add ev t.pending

let window_events_for t s =
  if s.node.Lui_a11y.role = Lui_a11y.Window then begin
    push t (Window_event (s.path, "Create"));
    push t (Window_event (s.path, "Activate"))
  end

let attach t a =
  Hashtbl.reset t.objs;
  t.a11y <- Some a;
  t.roots <- Lui_a11y.root_ids a;
  let nodes = Lui_a11y.flatten a in
  List.iter
    (fun n ->
      let s = mk_served t n in
      Hashtbl.replace t.objs s.id s)
    nodes;
  (* Announce the whole tree through the cache (preorder), mark it
     ready, and emit window lifecycle events for toplevels. *)
  List.iter
    (fun id ->
      match Hashtbl.find_opt t.objs id with
      | Some s ->
        push t (Cache_add (cache_item_of t s));
        window_events_for t s
      | None -> ())
    (List.map (fun (n : Lui_a11y.node_a11y) -> n.Lui_a11y.id) nodes);
  push t Cache_ready

(* ---------- diff -> events ---------- *)

let emit_children_delta t (s : served) ~old_children ~new_children =
  let removed =
    List.filter
      (fun c ->
        not (List.mem c new_children)
        || index_of old_children c <> index_of new_children c)
      old_children
  and added =
    List.filter
      (fun c ->
        not (List.mem c old_children)
        || index_of old_children c <> index_of new_children c)
      new_children
  in
  List.iter
    (fun c ->
      push t
        (Object_event
           { path = s.path;
             iface = evt_object;
             member = "ChildrenChanged";
             detail = "remove";
             detail1 = index_of old_children c;
             detail2 = 0;
             any = D_ref (path_of c) }))
    removed;
  List.iter
    (fun c ->
      push t
        (Object_event
           { path = s.path;
             iface = evt_object;
             member = "ChildrenChanged";
             detail = "add";
             detail1 = index_of new_children c;
             detail2 = 0;
             any = D_ref (path_of c) }))
    added

let prop_change t (s : served) detail =
  push t
    (Object_event
       { path = s.path;
         iface = evt_object;
         member = "PropertyChange";
         detail;
         detail1 = 0;
         detail2 = 0;
         any = D_unit })

let text_change t (s : served) ~old ~new_ =
  (* Replace-style change: delete the old text, insert the new one. *)
  if old <> "" then
    push t
      (Object_event
         { path = s.path;
           iface = evt_object;
           member = "TextChanged";
           detail = "delete";
           detail1 = 0;
           detail2 = char_count old;
           any = D_str old });
  if new_ <> "" then
    push t
      (Object_event
         { path = s.path;
           iface = evt_object;
           member = "TextChanged";
           detail = "insert";
           detail1 = 0;
           detail2 = char_count new_;
           any = D_str new_ })

let diff_served t s (n : Lui_a11y.node_a11y) =
  let o = s.node in
  if o.Lui_a11y.name <> n.name then prop_change t s "accessible-name";
  if o.description <> n.description then
    prop_change t s "accessible-description";
  if o.role <> n.role || o.state.password <> n.state.password then
    prop_change t s "accessible-role";
  if o.parent <> n.parent then prop_change t s "accessible-parent";
  let old_v = o.value and new_v = n.value in
  if
    (match old_v, new_v with
     | Some a, Some b ->
       a.Lui_a11y.numeric <> b.numeric
       || a.minimum <> b.minimum || a.maximum <> b.maximum
     | None, None -> false
     | _ -> true)
  then prop_change t s "accessible-value";
  if o.children <> n.children then
    emit_children_delta t s ~old_children:s.children
      ~new_children:n.children;
  let new_states = stateset_of (parent_role_of t n) n in
  List.iter
    (fun st ->
      let in_old = List.mem st s.states in
      let in_new = List.mem st new_states in
      if in_old <> in_new then
        push t
          (Object_event
             { path = s.path;
               iface = evt_object;
               member = "StateChanged";
               detail = state_name st;
               detail1 = (if in_new then 1 else 0);
               detail2 = 0;
               any = D_unit }))
    (List.sort_uniq compare (s.states @ new_states));
  let new_text = text_of n in
  (match s.text, new_text with
   | Some a, Some b when a <> b -> text_change t s ~old:a ~new_:b
   | None, Some b -> text_change t s ~old:"" ~new_:b
   | Some a, None -> text_change t s ~old:a ~new_:""
   | _ -> ());
  (* commit *)
  s.node <- n;
  s.atspi_role <- served_role n;
  s.states <- new_states;
  s.interfaces <- interfaces_of n;
  s.actions <- actions_of n;
  s.text <- new_text;
  s.children <- n.children;
  s.parent <- n.parent

let update t changed =
  let a =
    match t.a11y with
    | Some a -> a
    | None -> invalid_arg "Lui_ax_linux.update: not attached"
  in
  (* Classify each changed id against the served set. *)
  let removed, added, modified =
    List.fold_left
      (fun (r, ad, md) id ->
        match Hashtbl.find_opt t.objs id, Lui_a11y.find a id with
        | Some s, None -> (s :: r, ad, md)
        | None, Some n -> (r, n :: ad, md)
        | Some s, Some n -> (r, ad, (s, n) :: md)
        | None, None -> (r, ad, md))
      ([], [], []) changed
  in
  (* Removals: cache notification per object; the parent's
     children-changed event comes from its own membership diff. *)
  List.iter
    (fun (s : served) ->
      push t (Cache_remove s.path);
      Hashtbl.remove t.objs s.id)
    (List.rev removed);
  List.iter
    (fun (n : Lui_a11y.node_a11y) ->
      let s = mk_served t n in
      Hashtbl.replace t.objs s.id s;
      push t (Cache_add (cache_item_of t s));
      window_events_for t s)
    (List.rev added);
  List.iter (fun (s, n) -> diff_served t s n) (List.rev modified);
  (* Root membership changes are children-changed on the synthetic
     application object. *)
  let new_roots = Lui_a11y.root_ids a in
  if t.roots <> new_roots then begin
    let removed =
      List.filter (fun c -> not (List.mem c new_roots)) t.roots
    and added =
      List.filter (fun c -> not (List.mem c t.roots)) new_roots
    in
    List.iter
      (fun c ->
        push t
          (Object_event
             { path = root_path;
               iface = evt_object;
               member = "ChildrenChanged";
               detail = "remove";
               detail1 = index_of t.roots c;
               detail2 = 0;
               any = D_ref (path_of c) }))
      removed;
    List.iter
      (fun c ->
        push t
          (Object_event
             { path = root_path;
               iface = evt_object;
               member = "ChildrenChanged";
               detail = "add";
               detail1 = index_of new_roots c;
               detail2 = 0;
               any = D_ref (path_of c) }))
      added;
    t.roots <- new_roots
  end

let sync t =
  match t.a11y with
  | Some a -> update t (Lui_a11y.sync a)
  | None -> ()

(* ---------- focus ---------- *)

let set_focus t id =
  match t.a11y with
  | None -> ()
  | Some a ->
    let changed = Lui_a11y.set_focused a id in
    update t changed;
    if Lui_a11y.focused a = Some id then
      push t (Focus_event (path_of id))

let clear_focus t =
  match t.a11y with
  | None -> ()
  | Some a -> update t (Lui_a11y.clear_focused a)

let focused t =
  match t.a11y with
  | Some a -> Lui_a11y.focused a
  | None -> None

(* ---------- events out ---------- *)

let drain_events t =
  let l = Queue.fold (fun acc e -> e :: acc) [] t.pending in
  Queue.clear t.pending;
  List.rev l

let pending_count t = Queue.length t.pending

(* ---------- callbacks ---------- *)

let on_action t f = t.cb_action <- f
let on_focus_request t f = t.cb_focus <- f
let on_caret_request t f = t.cb_caret <- f
let on_value_request t f = t.cb_value <- f

(* ---------- misc helpers ---------- *)

let obj_by_id t id = Hashtbl.find_opt t.objs id

let locale () =
  match Sys.getenv_opt "LC_ALL" with
  | Some l when l <> "" -> l
  | _ -> Option.value ~default:"" (Sys.getenv_opt "LANG")

let machine_id () =
  (* /etc/machine-id is the conventional stable id; empty when absent
     (containers). *)
  match
    (let ic = open_in "/etc/machine-id" in
     let s = input_line ic in
     close_in ic;
     String.trim s)
  with
  | s -> s
  | exception _ -> ""

let obj_ref_dvalue t (s : served) =
  DStruct [ DStr t.bus_name; DObj s.path ]

let children_dvalue t (s : served) =
  DArr
    ( "(so)",
      List.filter_map
        (fun c ->
          match obj_by_id t c with
          | Some cs -> Some (obj_ref_dvalue t cs)
          | None -> None)
        s.children )

(* ---------- incoming calls: properties ---------- *)

let get_prop t s iface prop =
  let n = s.node in
  if iface = itf_accessible then begin
    match prop with
    | "version" -> Some ("u", DUInt 1)
    | "Name" ->
      Some ("s", DStr (Option.value ~default:"" n.Lui_a11y.name))
    | "Description" ->
      Some ("s", DStr (Option.value ~default:"" n.description))
    | "Parent" ->
      let r =
        match s.parent with
        | Some p -> ref_of_id t p
        | None -> ref_of t root_path
      in
      Some ("(so)", DStruct [ DStr (fst r); DObj (snd r) ])
    | "ChildCount" -> Some ("i", DInt (List.length s.children))
    | "Locale" -> Some ("s", DStr (locale ()))
    | "AccessibleId" ->
      Some
        ( "s",
          DStr
            (match n.ext_id with
             | Some e -> "extension:" ^ e
             | None -> n.kind ^ ":" ^ string_of_int n.id) )
    | "HelpText" -> Some ("s", DStr "")
    | _ -> None
  end
  else if iface = itf_component then begin
    match prop with
    | "version" -> Some ("u", DUInt 1)
    | _ -> None
  end
  else if iface = itf_action then begin
    match prop with
    | "version" -> Some ("u", DUInt 1)
    | "NActions" -> Some ("i", DInt (List.length s.actions))
    | _ -> None
  end
  else if iface = itf_text then begin
    match prop with
    | "version" -> Some ("u", DUInt 1)
    | "CharacterCount" ->
      Some ("i", DInt (char_count (Option.value ~default:"" s.text)))
    | "CaretOffset" -> Some ("i", DInt s.caret)
    | "NSelections" -> Some ("i", DInt 0)
    | _ -> None
  end
  else if iface = itf_value then begin
    match n.value with
    | Some v ->
      (match prop with
       | "version" -> Some ("u", DUInt 1)
       | "CurrentValue" ->
         Some ("d", DDbl (Option.value ~default:0. v.Lui_a11y.numeric))
       | "MinimumValue" ->
         Some ("d", DDbl (Option.value ~default:0. v.minimum))
       | "MaximumValue" ->
         Some ("d", DDbl (Option.value ~default:0. v.maximum))
       | "MinimumIncrement" -> Some ("d", DDbl 0.)
       | _ -> None)
    | None -> None
  end
  else if iface = itf_application then begin
    match prop with
    | "InterfaceVersion" -> Some ("u", DUInt 1)
    | "ToolkitName" -> Some ("s", DStr t.toolkit_name)
    | "Version" -> Some ("s", DStr t.toolkit_version)
    | "ToolkitVersion" -> Some ("s", DStr t.toolkit_version)
    | "AtspiVersion" -> Some ("s", DStr "2.1")
    | "Id" -> Some ("i", DInt t.app_id)
    | _ -> None
  end
  else None

let all_props t s iface =
  let names =
    if iface = itf_accessible then
      [ "version"; "Name"; "Description"; "Parent"; "ChildCount";
        "Locale"; "AccessibleId"; "HelpText" ]
    else if iface = itf_action then [ "version"; "NActions" ]
    else if iface = itf_text then
      [ "version"; "CharacterCount"; "CaretOffset"; "NSelections" ]
    else if iface = itf_value then
      [ "version"; "CurrentValue"; "MinimumValue"; "MaximumValue";
        "MinimumIncrement" ]
    else if iface = itf_application then
      [ "InterfaceVersion"; "ToolkitName"; "Version"; "ToolkitVersion";
        "AtspiVersion"; "Id" ]
    else if iface = itf_component then [ "version" ]
    else []
  in
  List.filter_map
    (fun p ->
      match get_prop t s iface p with
      | Some (sig_, v) -> Some (p, DVar (sig_, v))
      | None -> None)
    names

let set_prop t iface prop v =
  if iface = itf_application && prop = "Id" then begin
    match v with
    | DInt i | DUInt i | DN16 i ->
      t.app_id <- i;
      true
    | _ -> false
  end
  else false

(* ---------- introspection ---------- *)

type ifprop = { pname : string; ptype : string; paccess : string }
type ifmeth = {
  mname : string;
  mins : (string * string) list;
  mouts : (string * string) list;
}
type ififace = { iname : string; iprops : ifprop list; imeths : ifmeth list }

(* Short-name -> served interface declaration (member tables cover only
   what [handle_call] actually answers). *)
let iface_table : (string * ififace) list =
  [ ( "Accessible",
      { iname = itf_accessible;
        iprops =
          [ { pname = "version"; ptype = "u"; paccess = "read" };
            { pname = "Name"; ptype = "s"; paccess = "read" };
            { pname = "Description"; ptype = "s"; paccess = "read" };
            { pname = "Parent"; ptype = "(so)"; paccess = "read" };
            { pname = "ChildCount"; ptype = "i"; paccess = "read" };
            { pname = "Locale"; ptype = "s"; paccess = "read" };
            { pname = "AccessibleId"; ptype = "s"; paccess = "read" };
            { pname = "HelpText"; ptype = "s"; paccess = "read" } ];
        imeths =
          [ { mname = "GetChildAtIndex"; mins = [ ("index", "i") ];
              mouts = [ ("", "(so)") ] };
            { mname = "GetChildren"; mins = [];
              mouts = [ ("", "a(so)") ] };
            { mname = "GetIndexInParent"; mins = [];
              mouts = [ ("", "i") ] };
            { mname = "GetRelationSet"; mins = [];
              mouts = [ ("", "a(ua(so))") ] };
            { mname = "GetRole"; mins = []; mouts = [ ("", "u") ] };
            { mname = "GetRoleName"; mins = []; mouts = [ ("", "s") ] };
            { mname = "GetLocalizedRoleName"; mins = [];
              mouts = [ ("", "s") ] };
            { mname = "GetState"; mins = []; mouts = [ ("", "au") ] };
            { mname = "GetAttributes"; mins = [];
              mouts = [ ("", "a{ss}") ] };
            { mname = "GetApplication"; mins = [];
              mouts = [ ("", "(so)") ] };
            { mname = "GetInterfaces"; mins = [];
              mouts = [ ("", "as") ] } ] } );
    ( "Component",
      { iname = itf_component;
        iprops = [ { pname = "version"; ptype = "u"; paccess = "read" } ];
        imeths =
          [ { mname = "GetExtents"; mins = [ ("coordType", "u") ];
              mouts = [ ("", "(iiii)") ] };
            { mname = "GetPosition"; mins = [ ("coordType", "u") ];
              mouts = [ ("", "(ii)") ] };
            { mname = "GetSize"; mins = []; mouts = [ ("", "(ii)") ] };
            { mname = "GetLayer"; mins = []; mouts = [ ("", "u") ] };
            { mname = "GetMDIZOrder"; mins = []; mouts = [ ("", "n") ] };
            { mname = "GetAlpha"; mins = []; mouts = [ ("", "d") ] };
            { mname = "Contains";
              mins = [ ("x", "i"); ("y", "i"); ("coordType", "u") ];
              mouts = [ ("", "b") ] };
            { mname = "GetAccessibleAtPoint";
              mins = [ ("x", "i"); ("y", "i"); ("coordType", "u") ];
              mouts = [ ("", "(so)") ] };
            { mname = "GetAccessible"; mins = [ ("point", "(ii)") ];
              mouts = [ ("", "(so)") ] };
            { mname = "GrabFocus"; mins = []; mouts = [ ("", "b") ] };
            { mname = "ScrollTo"; mins = []; mouts = [ ("", "b") ] };
            { mname = "ScrollToPoint";
              mins = [ ("x", "i"); ("y", "i"); ("coordType", "u") ];
              mouts = [ ("", "b") ] };
            { mname = "ScrollSubviewTo";
              mins = [ ("child", "(so)"); ("x", "i"); ("y", "i") ];
              mouts = [ ("", "b") ] } ] } );
    ( "Action",
      { iname = itf_action;
        iprops =
          [ { pname = "version"; ptype = "u"; paccess = "read" };
            { pname = "NActions"; ptype = "i"; paccess = "read" } ];
        imeths =
          [ { mname = "GetName"; mins = [ ("index", "i") ];
              mouts = [ ("", "s") ] };
            { mname = "GetDescription"; mins = [ ("index", "i") ];
              mouts = [ ("", "s") ] };
            { mname = "GetLocalizedName"; mins = [ ("index", "i") ];
              mouts = [ ("", "s") ] };
            { mname = "GetKeyBinding"; mins = [ ("index", "i") ];
              mouts = [ ("", "s") ] };
            { mname = "DoAction"; mins = [ ("index", "i") ];
              mouts = [] } ] } );
    ( "Text",
      { iname = itf_text;
        iprops =
          [ { pname = "version"; ptype = "u"; paccess = "read" };
            { pname = "CharacterCount"; ptype = "i"; paccess = "read" };
            { pname = "CaretOffset"; ptype = "i"; paccess = "read" };
            { pname = "NSelections"; ptype = "i"; paccess = "read" } ];
        imeths =
          [ { mname = "GetText";
              mins = [ ("startOffset", "i"); ("endOffset", "i") ];
              mouts = [ ("", "s") ] };
            { mname = "GetStringAtOffset";
              mins = [ ("offset", "i"); ("granularity", "u") ];
              mouts =
                [ ("", "s"); ("startOffset", "i"); ("endOffset", "i") ] };
            { mname = "GetTextAtOffset";
              mins = [ ("offset", "i"); ("type", "u") ];
              mouts =
                [ ("", "s"); ("startOffset", "i"); ("endOffset", "i") ] };
            { mname = "GetTextBeforeOffset";
              mins = [ ("offset", "i"); ("type", "u") ];
              mouts =
                [ ("", "s"); ("startOffset", "i"); ("endOffset", "i") ] };
            { mname = "GetTextAfterOffset";
              mins = [ ("offset", "i"); ("type", "u") ];
              mouts =
                [ ("", "s"); ("startOffset", "i"); ("endOffset", "i") ] };
            { mname = "GetCharacterAtOffset";
              mins = [ ("offset", "i") ]; mouts = [ ("", "i") ] };
            { mname = "GetAttributes"; mins = [ ("offset", "i") ];
              mouts =
                [ ("", "a{ss}"); ("startOffset", "i");
                  ("endOffset", "i") ] };
            { mname = "GetAttributeValue";
              mins = [ ("offset", "i"); ("attributeName", "s") ];
              mouts = [ ("", "s") ] };
            { mname = "GetDefaultAttributeSet"; mins = [];
              mouts = [ ("", "a{ss}") ] };
            { mname = "GetDefaultAttributes"; mins = [];
              mouts = [ ("", "a{ss}") ] };
            { mname = "GetCharacterExtents";
              mins = [ ("offset", "i"); ("coordType", "u") ];
              mouts =
                [ ("x", "i"); ("y", "i"); ("width", "i");
                  ("height", "i") ] };
            { mname = "GetOffsetAtPoint";
              mins = [ ("x", "i"); ("y", "i"); ("coordType", "u") ];
              mouts = [ ("", "i") ] };
            { mname = "GetRangeExtents";
              mins =
                [ ("startOffset", "i"); ("endOffset", "i");
                  ("coordType", "u") ];
              mouts = [ ("", "(iiii)") ] };
            { mname = "GetBoundedRanges";
              mins =
                [ ("x", "i"); ("y", "i"); ("width", "i");
                  ("height", "i"); ("coordType", "u"); ("clipType", "u") ];
              mouts = [ ("", "a(iisv)") ] };
            { mname = "GetCharacterCount"; mins = [];
              mouts = [ ("", "i") ] };
            { mname = "GetCaretOffset"; mins = [];
              mouts = [ ("", "i") ] };
            { mname = "SetCaretOffset"; mins = [ ("offset", "i") ];
              mouts = [ ("", "b") ] };
            { mname = "GetNSelections"; mins = [];
              mouts = [ ("", "i") ] };
            { mname = "GetSelection";
              mins = [ ("selectionNum", "i") ];
              mouts = [ ("startOffset", "i"); ("endOffset", "i") ] };
            { mname = "AddSelection";
              mins = [ ("startOffset", "i"); ("endOffset", "i") ];
              mouts = [ ("", "b") ] };
            { mname = "RemoveSelection";
              mins = [ ("selectionNum", "i") ]; mouts = [ ("", "b") ] };
            { mname = "SetSelection";
              mins =
                [ ("selectionNum", "i"); ("startOffset", "i");
                  ("endOffset", "i") ];
              mouts = [ ("", "b") ] } ] } );
    ( "Value",
      { iname = itf_value;
        iprops =
          [ { pname = "version"; ptype = "u"; paccess = "read" };
            { pname = "CurrentValue"; ptype = "d"; paccess = "read" };
            { pname = "MinimumValue"; ptype = "d"; paccess = "read" };
            { pname = "MaximumValue"; ptype = "d"; paccess = "read" };
            { pname = "MinimumIncrement"; ptype = "d"; paccess = "read" } ];
        imeths =
          [ { mname = "SetCurrentValue"; mins = [ ("value", "d") ];
              mouts = [ ("", "b") ] } ] } );
    ( "Application",
      { iname = itf_application;
        iprops =
          [ { pname = "InterfaceVersion"; ptype = "u"; paccess = "read" };
            { pname = "ToolkitName"; ptype = "s"; paccess = "read" };
            { pname = "Version"; ptype = "s"; paccess = "read" };
            { pname = "ToolkitVersion"; ptype = "s"; paccess = "read" };
            { pname = "AtspiVersion"; ptype = "s"; paccess = "read" };
            { pname = "Id"; ptype = "i"; paccess = "readwrite" } ];
        imeths =
          [ { mname = "GetLocale"; mins = [ ("lctype", "u") ];
              mouts = [ ("", "s") ] };
            { mname = "GetApplicationBusAddress"; mins = [];
              mouts = [ ("", "s") ] } ] } );
    ( "Cache",
      { iname = itf_cache;
        iprops = [ { pname = "version"; ptype = "u"; paccess = "read" } ];
        imeths =
          [ { mname = "GetItems"; mins = [];
              mouts = [ ("nodes", "a((so)(so)(so)iiassusau)") ] } ] } );
    ( "Socket",
      { iname = itf_socket; iprops = [];
        imeths =
          [ { mname = "Embedded"; mins = [ ("path", "s") ]; mouts = [] };
            { mname = "Unembed"; mins = [ ("plug", "(so)") ];
              mouts = [] } ] } ) ]

let xml_escape s =
  let b = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let introspection_xml ~app_name short_names =
  let b = Buffer.create 1024 in
  Buffer.add_string b
    "<!DOCTYPE node PUBLIC \"-//freedesktop//DTD D-BUS Object \
     Introspection 1.0//EN\"\n\
     \"http://www.freedesktop.org/standards/dbus/1.0/introspect.dtd\">\n\
     <node name=\"";
  Buffer.add_string b (xml_escape app_name);
  Buffer.add_string b "\">\n";
  let emit_iface i =
    Buffer.add_string b "  <interface name=\"";
    Buffer.add_string b i.iname;
    Buffer.add_string b "\">\n";
    List.iter
      (fun p ->
        Buffer.add_string b "    <property name=\"";
        Buffer.add_string b p.pname;
        Buffer.add_string b "\" type=\"";
        Buffer.add_string b p.ptype;
        Buffer.add_string b "\" access=\"";
        Buffer.add_string b p.paccess;
        Buffer.add_string b "\"/>\n")
      i.iprops;
    List.iter
      (fun m ->
        Buffer.add_string b "    <method name=\"";
        Buffer.add_string b m.mname;
        Buffer.add_string b "\">\n";
        List.iter
          (fun (n, ty) ->
            Buffer.add_string b "      <arg direction=\"in\" name=\"";
            Buffer.add_string b n;
            Buffer.add_string b "\" type=\"";
            Buffer.add_string b ty;
            Buffer.add_string b "\"/>\n")
          m.mins;
        List.iter
          (fun (n, ty) ->
            Buffer.add_string b "      <arg direction=\"out\"";
            if n <> "" then begin
              Buffer.add_string b " name=\"";
              Buffer.add_string b n;
              Buffer.add_string b "\"";
            end;
            Buffer.add_string b " type=\"";
            Buffer.add_string b ty;
            Buffer.add_string b "\"/>\n")
          m.mouts;
        Buffer.add_string b "    </method>\n")
      i.imeths;
    Buffer.add_string b "  </interface>\n"
  in
  Buffer.add_string b
    "  <interface name=\"";
  Buffer.add_string b itf_introspectable;
  Buffer.add_string b
    "\">\n    <method name=\"Introspect\">\n      <arg direction=\"out\" type=\"s\"/>\n    </method>\n  </interface>\n";
  Buffer.add_string b "  <interface name=\"";
  Buffer.add_string b itf_peer;
  Buffer.add_string b
    "\">\n    <method name=\"Ping\"/>\n    <method name=\"GetMachineId\">\n      <arg direction=\"out\" type=\"s\"/>\n    </method>\n  </interface>\n";
  Buffer.add_string b "  <interface name=\"";
  Buffer.add_string b itf_properties;
  Buffer.add_string b
    "\">\n    <method name=\"Get\">\n      <arg direction=\"in\" name=\"interface_name\" type=\"s\"/>\n      <arg direction=\"in\" name=\"property_name\" type=\"s\"/>\n      <arg direction=\"out\" type=\"v\"/>\n    </method>\n    <method name=\"GetAll\">\n      <arg direction=\"in\" name=\"interface_name\" type=\"s\"/>\n      <arg direction=\"out\" type=\"a{sv}\"/>\n    </method>\n    <method name=\"Set\">\n      <arg direction=\"in\" name=\"interface_name\" type=\"s\"/>\n      <arg direction=\"in\" name=\"property_name\" type=\"s\"/>\n      <arg direction=\"in\" name=\"value\" type=\"v\"/>\n    </method>\n    <signal name=\"PropertiesChanged\">\n      <arg name=\"interface_name\" type=\"s\"/>\n      <arg name=\"changed_properties\" type=\"a{sv}\"/>\n      <arg name=\"invalidated_properties\" type=\"as\"/>\n    </signal>\n  </interface>\n";
  List.iter
    (fun sn ->
      match List.assoc_opt sn iface_table with
      | Some i -> emit_iface i
      | None -> ())
    short_names;
  Buffer.add_string b "</node>\n";
  Buffer.contents b

(* ---------- incoming calls: method dispatch ---------- *)

let action_at s i =
  if i >= 0 && i < List.length s.actions then
    Some (List.nth s.actions i)
  else None

let text_string s = Option.value ~default:"" s.text

let text_range_reply s c dir =
  let text = text_string s in
  let offset =
    if Array.length c.iargs > 0 then c.iargs.(0) else 0
  and kind =
    if Array.length c.iargs > 1 then c.iargs.(1) else 0
  in
  let bs, be, _ = text_range ~offset text kind dir in
  Value
    [ DStr (String.sub text bs (be - bs));
      DInt (char_offset_of_byte text bs);
      DInt (char_offset_of_byte text be) ]

let invalid_args what =
  Error ("org.freedesktop.DBus.Error.InvalidArgs", what)

let unknown_member c =
  Error
    ( "org.freedesktop.DBus.Error.UnknownMethod",
      c.iface ^ "." ^ c.member )

let obj_call t s (c : call) : reply =
  let n = s.node in
  match c.iface, c.member with
  (* --- Introspectable / Peer --- *)
  | i, "Introspect" when i = itf_introspectable ->
    Value
      [ DStr
          (introspection_xml ~app_name:t.toolkit_name s.interfaces) ]
  | i, "Ping" when i = itf_peer -> Value []
  | i, "GetMachineId" when i = itf_peer -> Value [ DStr (machine_id ()) ]
  (* --- Properties --- *)
  | i, "Get" when i = itf_properties ->
    if Array.length c.sargs >= 2 then
      let piface, pname = (c.sargs.(0), c.sargs.(1)) in
      (match get_prop t s piface pname with
       | Some (sig_, v) -> Value [ DVar (sig_, v) ]
       | None -> invalid_args ("no such property: " ^ piface ^ "." ^ pname))
    else invalid_args "Get"
  | i, "GetAll" when i = itf_properties ->
    let piface =
      if Array.length c.sargs > 0 then c.sargs.(0) else ""
    in
    Value [ DDict ("{sv}", all_props t s piface) ]
  | i, "Set" when i = itf_properties ->
    if Array.length c.sargs >= 2 then begin
      let v =
        if Array.length c.iargs > 0 then DInt c.iargs.(0)
        else if Array.length c.fargs > 0 then DDbl c.fargs.(0)
        else if Array.length c.sargs > 2 then DStr c.sargs.(2)
        else DInt 0
      in
      if set_prop t c.sargs.(0) c.sargs.(1) v then Value []
      else
        Error
          ( "org.freedesktop.DBus.Error.PropertyReadOnly",
            "read-only property" )
    end
    else invalid_args "Set"
  (* --- Accessible --- *)
  | i, "GetRole" when i = itf_accessible ->
    Value [ DUInt s.atspi_role ]
  | i, ("GetRoleName" | "GetLocalizedRoleName")
    when i = itf_accessible ->
    Value [ DStr (atspi_role_name n.Lui_a11y.role) ]
  | i, "GetName" when i = itf_accessible ->
    Value [ DStr (Option.value ~default:"" n.name) ]
  | i, "GetDescription" when i = itf_accessible ->
    Value [ DStr (Option.value ~default:"" n.description) ]
  | i, "GetParent" when i = itf_accessible ->
    let r =
      match s.parent with
      | Some p -> ref_of_id t p
      | None -> ref_of t root_path
    in
    Value [ DStruct [ DStr (fst r); DObj (snd r) ] ]
  | i, "GetChildCount" when i = itf_accessible ->
    Value [ DInt (List.length s.children) ]
  | i, "GetChildren" when i = itf_accessible ->
    Value [ children_dvalue t s ]
  | i, "GetChildAtIndex" when i = itf_accessible ->
    let i = if Array.length c.iargs > 0 then c.iargs.(0) else -1 in
    (match List.nth_opt s.children i with
     | Some cid ->
       (match obj_by_id t cid with
        | Some cs -> Value [ obj_ref_dvalue t cs ]
        | None -> invalid_args "child index out of range")
     | None -> invalid_args "child index out of range")
  | i, "GetIndexInParent" when i = itf_accessible ->
    Value [ DInt (index_in_parent t s.id) ]
  | i, "GetRelationSet" when i = itf_accessible ->
    Value [ DArr ("(ua(so))", []) ]
  | i, "GetState" when i = itf_accessible ->
    Value [ DArr ("u", List.map (fun st -> DUInt st) s.states) ]
  | i, "GetAttributes" when i = itf_accessible ->
    Value
      [ DDict
          ( "{ss}",
            List.map (fun (k, v) -> (k, DStr v)) (attributes_of n)) ]
  | i, "GetApplication" when i = itf_accessible ->
    Value [ DStruct [ DStr t.bus_name; DObj root_path ] ]
  | i, "GetInterfaces" when i = itf_accessible ->
    Value [ DArr ("s", List.map (fun x -> DStr x) s.interfaces) ]
  (* --- Action --- *)
  | i, ("GetName" | "GetDescription" | "GetLocalizedName")
    when i = itf_action ->
    let idx = if Array.length c.iargs > 0 then c.iargs.(0) else -1 in
    (match action_at s idx with
     | Some a ->
       Value
         [ DStr
             (if c.member = "GetDescription" then a.description
              else a.name) ]
     | None -> invalid_args "action index out of range")
  | i, "GetKeyBinding" when i = itf_action -> Value [ DStr "" ]
  | i, "DoAction" when i = itf_action ->
    let idx = if Array.length c.iargs > 0 then c.iargs.(0) else -1 in
    (match action_at s idx with
     | Some a ->
       t.cb_action s.id a.name;
       Value []
     | None -> invalid_args "action index out of range")
  (* --- Component --- *)
  | i, "GetExtents" when i = itf_component ->
    (* On-screen geometry needs the layout tree, which the a11y model
       does not carry yet; zeros are the honest answer until bounds are
       plumbed through. *)
    Value [ DStruct [ DInt 0; DInt 0; DInt 0; DInt 0 ] ]
  | i, "GetPosition" when i = itf_component ->
    Value [ DStruct [ DInt 0; DInt 0 ] ]
  | i, "GetSize" when i = itf_component ->
    Value [ DStruct [ DInt 0; DInt 0 ] ]
  | i, "GetLayer" when i = itf_component -> Value [ DUInt 3 ]
  | i, "GetMDIZOrder" when i = itf_component -> Value [ DN16 0 ]
  | i, "GetAlpha" when i = itf_component -> Value [ DDbl 1.0 ]
  | i, "Contains" when i = itf_component -> Value [ DBool false ]
  | i, "GetAccessibleAtPoint" when i = itf_component ->
    Value [ DStruct [ DStr ""; DObj "/org/a11y/atspi/null" ] ]
  | i, "GetAccessible" when i = itf_component ->
    Value [ obj_ref_dvalue t s ]
  | i, "GrabFocus" when i = itf_component ->
    if s.node.state.focusable then begin
      t.cb_focus s.id;
      Value [ DBool true ]
    end
    else Value [ DBool false ]
  | i, ("ScrollTo" | "ScrollToPoint" | "ScrollSubviewTo")
    when i = itf_component -> Value [ DBool false ]
  (* --- Text --- *)
  | i, "GetCharacterCount" when i = itf_text ->
    Value [ DInt (char_count (text_string s)) ]
  | i, "GetText" when i = itf_text ->
    let text = text_string s in
    let nchars = char_count text in
    let a = if Array.length c.iargs > 0 then c.iargs.(0) else 0 in
    let b = if Array.length c.iargs > 1 then c.iargs.(1) else -1 in
    let b = if b < 0 || b > nchars then nchars else b in
    let a = max 0 (min a nchars) in
    let bs = byte_of_char_offset text a
    and be = byte_of_char_offset text (max a b) in
    Value [ DStr (String.sub text bs (be - bs)) ]
  | i, "GetCaretOffset" when i = itf_text -> Value [ DInt s.caret ]
  | i, "SetCaretOffset" when i = itf_text ->
    let off = if Array.length c.iargs > 0 then c.iargs.(0) else 0 in
    if t.cb_caret s.id off then begin
      s.caret <- off;
      push t
        (Object_event
           { path = s.path;
             iface = evt_object;
             member = "TextCaretMoved";
             detail = "";
             detail1 = off;
             detail2 = 0;
             any = D_unit });
      Value [ DBool true ]
    end
    else Value [ DBool false ]
  | i, "GetTextAtOffset" when i = itf_text -> text_range_reply s c 0
  | i, "GetTextBeforeOffset" when i = itf_text ->
    text_range_reply s c (-1)
  | i, "GetTextAfterOffset" when i = itf_text -> text_range_reply s c 1
  | i, "GetCharacterAtOffset" when i = itf_text ->
    let off = if Array.length c.iargs > 0 then c.iargs.(0) else 0 in
    Value [ DInt (char_at (text_string s) off) ]
  | i, "GetAttributes" when i = itf_text ->
    Value
      [ DDict ("{ss}", []);
        DInt 0;
        DInt (char_count (text_string s)) ]
  | i, ("GetDefaultAttributeSet" | "GetDefaultAttributes")
    when i = itf_text -> Value [ DDict ("{ss}", []) ]
  | i, "GetAttributeValue" when i = itf_text -> Value [ DStr "" ]
  | i, "GetStringAtOffset" when i = itf_text -> text_range_reply s c 0
  | i, "GetCharacterExtents" when i = itf_text ->
    Value [ DInt 0; DInt 0; DInt 0; DInt 0 ]
  | i, "GetOffsetAtPoint" when i = itf_text -> Value [ DInt (-1) ]
  | i, "GetRangeExtents" when i = itf_text ->
    Value [ DStruct [ DInt 0; DInt 0; DInt 0; DInt 0 ] ]
  | i, "GetBoundedRanges" when i = itf_text ->
    Value [ DArr ("(iisv)", []) ]
  | i, "GetNSelections" when i = itf_text -> Value [ DInt 0 ]
  | i, "GetSelection" when i = itf_text ->
    Value [ DInt (-1); DInt (-1) ]
  | i, ("AddSelection" | "RemoveSelection" | "SetSelection")
    when i = itf_text -> Value [ DBool false ]
  (* --- Value --- *)
  | i, "SetCurrentValue" when i = itf_value ->
    let v = if Array.length c.fargs > 0 then c.fargs.(0) else 0. in
    Value [ DBool (t.cb_value s.id v) ]
  (* --- Application --- *)
  | i, "GetLocale" when i = itf_application ->
    Value [ DStr (locale ()) ]
  | i, "GetApplicationBusAddress" when i = itf_application ->
    Value [ DStr "" ]
  (* --- Socket handshake on the application root --- *)
  | i, "Embedded" when i = itf_socket ->
    (if Array.length c.sargs > 0 then
       match t.desktop with
       | Some (name, _) -> t.desktop <- Some (name, c.sargs.(0))
       | None -> t.desktop <- Some ("", c.sargs.(0)));
    Value []
  | i, "Unembed" when i = itf_socket ->
    t.desktop <- None;
    Value []
  | _ -> unknown_member c

(* The synthetic application object at root_path: role APPLICATION,
   children are the a11y forest roots, Parent is the desktop reference
   learned during embedding. *)

let root_obj t : served =
  { id = -1;
    path = root_path;
    node =
      { Lui_a11y.id = -1;
        kind = "application";
        role = Lui_a11y.Window;
        name = Some t.toolkit_name;
        description = None;
        state =
          { focusable = false;
            focused = false;
            selected = false;
            checked = None;
            disabled = false;
            expanded = None;
            required = false;
            read_only = true;
            password = false };
        value = None;
        parent = None;
        children = t.roots;
        ext_id = None };
    atspi_role = role_application;
    states = [ state_enabled; state_active ];
    interfaces = [ "Accessible"; "Component"; "Application"; "Socket" ];
    actions = [];
    text = None;
    caret = 0;
    children = t.roots;
    parent = None }

let root_parent_dvalue t =
  let r = match t.desktop with Some d -> d | None -> null_ref in
  DStruct [ DStr (fst r); DObj (snd r) ]

let root_call t (c : call) : reply =
  let s = root_obj t in
  match c.iface, c.member with
  | i, "Introspect" when i = itf_introspectable ->
    Value
      [ DStr
          (introspection_xml ~app_name:t.toolkit_name s.interfaces) ]
  | i, "GetParent" when i = itf_accessible ->
    Value [ root_parent_dvalue t ]
  | i, "Get" when i = itf_properties ->
    if Array.length c.sargs >= 2 then
      let piface, pname = (c.sargs.(0), c.sargs.(1)) in
      if piface = itf_accessible && pname = "Parent" then
        Value [ DVar ("(so)", root_parent_dvalue t) ]
      else
        (match get_prop t s piface pname with
         | Some (sig_, v) -> Value [ DVar (sig_, v) ]
         | None -> invalid_args ("no such property: " ^ piface ^ "." ^ pname))
    else invalid_args "Get"
  | i, "GetAll" when i = itf_properties ->
    let piface =
      if Array.length c.sargs > 0 then c.sargs.(0) else ""
    in
    let props = all_props t s piface in
    let props =
      if piface = itf_accessible then
        List.map
          (fun (k, v) ->
            if k = "Parent" then (k, DVar ("(so)", root_parent_dvalue t))
            else (k, v))
          props
      else props
    in
    Value [ DDict ("{sv}", props) ]
  | i, "GetIndexInParent" when i = itf_accessible ->
    Value [ DInt 0 ]
  | i, "GetApplication" when i = itf_accessible ->
    Value [ DStruct [ DStr t.bus_name; DObj root_path ] ]
  | _ -> obj_call t s c

(* The cache pseudo-object at cache_path. *)

let cache_get_items t =
  let a = Option.get t.a11y in
  let items =
    Lui_a11y.flatten a
    |> List.filter_map (fun n -> Hashtbl.find_opt t.objs n.Lui_a11y.id)
  in
  let ref_struct name path = DStruct [ DStr name; DObj path ] in
  let item_of s =
    let ci = cache_item_of t s in
    let parent_ref_struct =
      match ci.parent_path with
      | Some p -> ref_struct t.bus_name p
      | None -> ref_struct "" (snd null_ref)
    in
    DStruct
      [ ref_struct t.bus_name ci.path;
        ref_struct t.bus_name root_path;
        parent_ref_struct;
        DInt ci.index_in_parent;
        DInt ci.child_count;
        DArr ("s", List.map (fun x -> DStr x) ci.interfaces);
        DStr ci.name;
        DUInt ci.role;
        DStr ci.description;
        DArr ("u", List.map (fun st -> DUInt st) ci.states) ]
  in
  let s = root_obj t in
  let app_item =
    DStruct
      [ ref_struct t.bus_name root_path;
        ref_struct t.bus_name root_path;
        root_parent_dvalue t;
        DInt 0;
        DInt (List.length t.roots);
        DArr ("s", List.map (fun x -> DStr x) s.interfaces);
        DStr t.toolkit_name;
        DUInt role_application;
        DStr "";
        DArr ("u", List.map (fun st -> DUInt st) s.states) ]
  in
  DArr ("((so)(so)(so)iiassusau)", app_item :: List.map item_of items)

let cache_call t (c : call) : reply =
  match c.iface, c.member with
  | i, "GetItems" when i = itf_cache ->
    (match t.a11y with
     | Some _ -> Value [ cache_get_items t ]
     | None -> Value [ DArr ("((so)(so)(so)iiassusau)", []) ])
  | i, "Introspect" when i = itf_introspectable ->
    Value
      [ DStr (introspection_xml ~app_name:t.toolkit_name [ "Cache" ]) ]
  | i, "Get" when i = itf_properties ->
    if Array.length c.sargs >= 2 && c.sargs.(1) = "version" then
      Value [ DVar ("u", DUInt 2) ]
    else invalid_args "no such property"
  | i, "GetAll" when i = itf_properties ->
    Value [ DDict ("{sv}", [ ("version", DVar ("u", DUInt 2)) ]) ]
  | i, "Ping" when i = itf_peer -> Value []
  | _ -> unknown_member c

let handle_call t (c : call) : reply =
  if c.path = cache_path then cache_call t c
  else if c.path = root_path then root_call t c
  else
    match id_of_path c.path with
    | Some id ->
      (match obj_by_id t id with
       | Some s -> obj_call t s c
       | None ->
         Error
           ( "org.freedesktop.DBus.Error.UnknownObject",
             "no such accessible object: " ^ c.path ))
    | None ->
      Error
        ( "org.freedesktop.DBus.Error.UnknownObject",
          "no such accessible object: " ^ c.path )

(* ---------- transport ---------- *)

let set_bus_name t n = t.bus_name <- n
let desktop_ref t = t.desktop
let set_desktop_ref t r = t.desktop <- Some r
let app_id t = t.app_id
let transport t = t.trans

let session_bus_address () =
  match Sys.getenv_opt "DBUS_SESSION_BUS_ADDRESS" with
  | Some a when a <> "" -> a
  | _ ->
    (* The per-user bus socket lives at the well-known systemd path. *)
    let p = "/run/user/" ^ string_of_int (Unix.getuid ()) ^ "/bus" in
    if Sys.file_exists p then "unix:path=" ^ p else ""

let connect t =
  if !(t.conn) <> 0 then t.trans
  else if c_dbus_probe () = 0 then begin
    t.trans <- Offline;
    t.trans
  end
  else begin
    let session_addr = session_bus_address () in
    let session_conn =
      if session_addr = "" then 0 else c_dbus_open session_addr
    in
    let a11y_addr =
      if session_conn <> 0 then c_dbus_a11y_address session_conn else ""
    in
    if a11y_addr <> "" then begin
      (* The a11y bus is separate: open it, register, and embed the
         application root with the registry. *)
      let conn = c_dbus_open a11y_addr in
      if conn <> 0 then begin
        t.conn := conn;
        t.bus_name <- c_dbus_name conn;
        let dname, dpath = c_dbus_embed conn root_path in
        if dpath <> "" then t.desktop <- Some (dname, dpath);
        t.trans <- A11y_bus
      end
      else begin
        t.conn := session_conn;
        t.bus_name <-
          (if session_conn <> 0 then c_dbus_name session_conn else "");
        t.trans <- (if session_conn <> 0 then Session_bus else Offline)
      end
    end
    else begin
      (* No a11y service on the session bus: serve on the session bus
         itself (developer/test setups), same wire format even though
         no AT will discover the objects there. *)
      t.conn := session_conn;
      t.bus_name <-
        (if session_conn <> 0 then c_dbus_name session_conn else "");
      t.trans <- (if session_conn <> 0 then Session_bus else Offline)
    end;
    if session_conn <> 0 && !(t.conn) <> session_conn then
      c_dbus_close session_conn;
    t.trans
  end

let disconnect t =
  if !(t.conn) <> 0 then begin
    c_dbus_close !(t.conn);
    t.conn := 0
  end;
  t.trans <- Offline

let emit_event t = function
  | Object_event
      { path; iface; member; detail; detail1; detail2; any } ->
    (match any with
     | D_unit ->
       c_emit_num !(t.conn) path iface member detail detail1 detail2 0
     | D_int i ->
       c_emit_num !(t.conn) path iface member detail detail1 detail2 i
     | D_str s ->
       c_emit_str !(t.conn) path iface member detail detail1 detail2 s
     | D_ref p ->
       c_emit_ref !(t.conn) path iface member detail detail1 detail2 p)
  | Cache_add ci ->
    c_emit_cache_add !(t.conn) ci.path
      (Option.value ~default:"" ci.parent_path)
      ci.index_in_parent ci.child_count
      (Array.of_list ci.interfaces) ci.name ci.role ci.description
      (Array.of_list ci.states)
  | Cache_remove p -> c_emit_cache_remove !(t.conn) p
  | Cache_ready -> c_emit_sig !(t.conn) cache_path itf_cache "Ready"
  | Focus_event p -> c_emit_num !(t.conn) p evt_focus "Focus" "" 0 0 0
  | Window_event (p, name) ->
    c_emit_num !(t.conn) p evt_window name "" 0 0 0

let flush t =
  if !(t.conn) = 0 then 0
  else begin
    let n = ref 0 in
    while not (Queue.is_empty t.pending) do
      emit_event t (Queue.pop t.pending);
      incr n
    done;
    !n
  end

let dispatch t =
  if !(t.conn) = 0 then 0
  else begin
    let calls = c_dbus_poll !(t.conn) 0 in
    Array.iter
      (fun (serial, path, iface, member, iargs, fargs, sargs) ->
        let c = { serial; path; iface; member; iargs; fargs; sargs } in
        match handle_call t c with
        | Value args -> c_reply !(t.conn) serial (Array.of_list args)
        | Error (name, msg) -> c_reply_error !(t.conn) serial name msg)
      calls;
    Array.length calls
  end

let destroy t =
  disconnect t;
  Hashtbl.reset t.objs;
  t.a11y <- None;
  t.roots <- []
