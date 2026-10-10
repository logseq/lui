(* Windows accessibility bridge: mirrors a [Lui_a11y] semantic tree as
   UI Automation provider objects so assistive technology sees a
   self-drawn app.

   The C side keeps one COM object per a11y node — children implement
   IRawElementProviderSimple + IRawElementProviderFragment plus the
   control patterns their role offers, the root adds
   IRawElementProviderFragmentRoot — and a flat node-id -> element
   table the OCaml side updates per [sync]. The window's WM_GETOBJECT
   hands the root's simple provider to UI Automation, which navigates
   the fragment tree from there.

   Assistive-technology actions are enqueued on the C side and polled
   here via [drain_actions] — no platform code ever calls back into
   the runtime.

   Call everything on the host's UI thread, the same discipline the
   window procedure expects. *)

type rect = { x : float; y : float; w : float; h : float }
(** A rect in the host window's client coordinate space (points). *)

type native_window = nativeint
(** A raw HWND. *)

(* Descriptor pushed to the C side per changed node, as a tuple: the
   C stub reads fields positionally, so the order is fixed with
   lui_ax_windows_stubs.c —
   0 control type, 1 patterns mask, 2 name, 3 localized type override,
   4 description, 5 value tag (0 none/1 num/2 str), 6 value num,
   7 value str, 8 has min, 9 min, 10 has max, 11 max, 12 enabled,
   13 expanded (-1/0/1), 14 focusable, 15 focused, 16 selected
   (-1/0/1), 17 toggle state (-1/0/1/2), 18 password, 19 position in
   set (1-based, -1 none), 20 size of set (-1 none), 21 level
   (1-based, -1 none), 22 required, 23 live setting, 24 action mask,
   25 is dialog, 26 read only. *)
type uia_desc =
  int * int * string * string * string * int * float * string * bool *
  float * bool * float * bool * int * bool * bool * int * int * bool *
  int * int * int * bool * int * int * bool * bool

(* A VARIANT pushed to C, as (tag, num, str): 0 empty, 1 int,
   2 double, 3 bool (num 0/1), 4 string. *)
type uia_v = int * float * string

type t = {
  id : int;
  a11y : Lui_a11y.t;
  win : native_window;
  frame_of : int -> rect option;
  pushed : (int, Lui_a11y.node_a11y) Hashtbl.t;
}

external c_attach : native_window -> int = "lui_axw_attach"
external c_detach : int -> unit = "lui_axw_detach"
external c_apply : int -> int -> uia_desc -> unit = "lui_axw_apply"
external c_link : int -> int -> int -> int array -> unit =
  "lui_axw_link"
external c_set_frame : int -> int -> rect -> unit =
  "lui_axw_set_frame"
external c_remove : int -> int -> unit = "lui_axw_remove"
external c_finish : int -> int array -> unit = "lui_axw_finish"
external c_raise_prop : int -> int -> int -> uia_v -> uia_v -> unit =
  "lui_axw_raise_prop"
external c_raise_event : int -> int -> int -> unit =
  "lui_axw_raise_event"
external c_raise_struct : int -> int -> unit = "lui_axw_raise_struct"
external c_set_focus : int -> int -> unit = "lui_axw_set_focus"
external c_drain : int -> (int * int * string) array = "lui_axw_drain"
external c_get_object : native_window -> nativeint -> nativeint ->
  nativeint = "lui_axw_get_object"
external c_probe_has_provider : int -> bool =
  "lui_axw_probe_has_provider"
external c_probe_root : int -> nativeint = "lui_axw_probe_root"
external c_probe_find : int -> int -> nativeint = "lui_axw_probe_find"
external c_probe_free : nativeint -> unit = "lui_axw_probe_free"
external c_probe_children : nativeint -> int array =
  "lui_axw_probe_children"
external c_probe_runtime_id : nativeint -> int =
  "lui_axw_probe_runtime_id"
external c_probe_prop_int : nativeint -> int -> int =
  "lui_axw_probe_prop_int"
external c_probe_prop_bool : nativeint -> int -> bool =
  "lui_axw_probe_prop_bool"
external c_probe_prop_str : nativeint -> int -> string =
  "lui_axw_probe_prop_str"
external c_probe_prop_num : nativeint -> int -> float =
  "lui_axw_probe_prop_num"
external c_probe_pattern : int -> int -> int -> bool =
  "lui_axw_probe_pattern"
external c_probe_invoke : int -> int -> unit = "lui_axw_probe_invoke"
external c_probe_toggle : int -> int -> unit = "lui_axw_probe_toggle"
external c_probe_select : int -> int -> unit = "lui_axw_probe_select"
external c_probe_set_range : int -> int -> float -> unit =
  "lui_axw_probe_set_range"
external c_probe_set_value : int -> int -> string -> unit =
  "lui_axw_probe_set_value"
external c_probe_expand : int -> int -> unit = "lui_axw_probe_expand"
external c_probe_collapse : int -> int -> unit =
  "lui_axw_probe_collapse"
external c_probe_scroll : int -> int -> unit = "lui_axw_probe_scroll"
external c_probe_hit : int -> float -> float -> int =
  "lui_axw_probe_hit"
external c_probe_focused : int -> int = "lui_axw_probe_focused"

(* ---------- UIA constants ---------- *)

let prop_control_type = 30003
let prop_localized_type = 30004
let prop_name = 30005
let prop_has_keyboard_focus = 30008
let prop_is_keyboard_focusable = 30009
let prop_is_enabled = 30010
let prop_help_text = 30013
let prop_is_password = 30019
let prop_is_required_for_form = 30025
let prop_live_setting = 30135
let prop_position_in_set = 30152
let prop_size_of_set = 30153
let prop_level = 30154
let prop_full_description = 30159
let prop_is_dialog = 30174
let prop_value = 30045
let prop_range_value = 30047
let prop_expand_state = 30070
let prop_is_selected = 30079
let prop_toggle_state = 30086

let event_focus_changed = 20005
let event_element_selected = 20012
let event_added_to_selection = 20010
let event_removed_from_selection = 20011

let pattern_invoke = 10000
let pattern_selection = 10001
let pattern_value = 10002
let pattern_range_value = 10003
let pattern_expand_collapse = 10005
let pattern_selection_item = 10010
let pattern_toggle = 10015
let pattern_scroll_item = 10017

(* ---------- control type mapping ---------- *)

(* Lui_a11y role -> UIA_ControlTypeId. *)
let control_type_table =
  Lui_a11y.
    [ (Window, 50032);
      (Group, 50026);
      (Static_text, 50020);
      (* a heading is text with a heading level when we had one *)
      (Heading, 50020);
      (Text_field, 50004);
      (Text_area, 50004);
      (Search_field, 50004);
      (Button, 50000);
      (* a toggle button is a button with the Toggle pattern *)
      (Toggle_button, 50000);
      (Check_box, 50002);
      (Radio_button, 50013);
      (Radio_group, 50026);
      (Switch, 50000);
      (Slider, 50015);
      (Spin_button, 50016);
      (Progress_indicator, 50012);
      (Link, 50005);
      (Image, 50006);
      (List, 50008);
      (List_item, 50007);
      (Outline, 50023);
      (Outline_item, 50024);
      (Tab_group, 50018);
      (Tab, 50019);
      (Menu, 50009);
      (Menu_item, 50011);
      (Combo_box, 50003);
      (* dialogs and sheets surface as panes; IsDialog marks the true
         dialog *)
      (Dialog, 50033);
      (Sheet, 50033);
      (Tooltip, 50022);
      (Table, 50036);
      (Table_row, 50029);
      (Table_cell, 50025);
      (Separator, 50038);
      (Toolbar, 50021);
      (Status_bar, 50017);
      (Navigation, 50026);
      (Split_group, 50026);
      (Extension, 50026) ]

let control_type_of (n : Lui_a11y.node_a11y) =
  List.assoc n.Lui_a11y.role control_type_table

(* LocalizedControlType reads better than a bare control type for
   roles UIA has no distinct type for. "" = the type's own name. *)
let localized_type_of (n : Lui_a11y.node_a11y) =
  match n.Lui_a11y.role with
  | Lui_a11y.Switch -> "toggle switch"
  | Lui_a11y.Toggle_button -> "toggle button"
  | Lui_a11y.Radio_group -> "radio group"
  | Lui_a11y.Dialog -> "dialog"
  | Lui_a11y.Sheet -> "sheet"
  | Lui_a11y.Heading -> "heading"
  | Lui_a11y.Navigation -> "navigation"
  | Lui_a11y.Combo_box -> "combo box"
  | _ -> ""

(* ---------- role predicates ---------- *)

(* Checkable roles: the Toggle pattern replaces Invoke. *)
let toggle_role = function
  | Lui_a11y.Check_box | Lui_a11y.Switch | Lui_a11y.Toggle_button ->
    true
  | _ -> false

(* Roles that edit or carry a text value. *)
let textual_role = function
  | Lui_a11y.Text_field | Lui_a11y.Text_area | Lui_a11y.Search_field
  | Lui_a11y.Combo_box -> true
  | _ -> false

(* Children selectable through the SelectionItem pattern. Radio
   buttons and tabs are selectable per role; rows and tree items when
   the node is marked selectable or selected (Lui_a11y carries no
   separate "selectable" flag — focusable marks the node
   interactive). *)
let selectable_role (n : Lui_a11y.node_a11y) =
  match n.Lui_a11y.role with
  | Lui_a11y.Radio_button | Lui_a11y.Tab -> true
  | Lui_a11y.List_item | Lui_a11y.Table_row | Lui_a11y.Outline_item ->
    n.Lui_a11y.state.focusable || n.Lui_a11y.state.selected
    || n.Lui_a11y.state.checked <> None
  | _ -> false

(* Containers whose children form a Selection. *)
let selection_role = function
  | Lui_a11y.List | Lui_a11y.Table | Lui_a11y.Outline
  | Lui_a11y.Tab_group | Lui_a11y.Radio_group -> true
  | _ -> false

let row_role = function
  | Lui_a11y.List_item | Lui_a11y.Table_row | Lui_a11y.Outline_item ->
    true
  | _ -> false

let range_role = function
  | Lui_a11y.Slider | Lui_a11y.Spin_button | Lui_a11y.Progress_indicator ->
    true
  | _ -> false

(* ---------- patterns ---------- *)

let bit_invoke = 1
let bit_toggle = 2
let bit_selection_item = 4
let bit_selection = 8
let bit_range_value = 16
let bit_value = 32
let bit_expand_collapse = 64
let bit_scroll_item = 128

let patterns_of (n : Lui_a11y.node_a11y) =
  let open Lui_a11y in
  let m = ref bit_scroll_item in
  (* every element may sit inside a scroll container *)
  let checkable_menu_item =
    n.role = Menu_item && n.state.checked <> None
  in
  if toggle_role n.role || checkable_menu_item then
    m := !m lor bit_toggle;
  if selectable_role n then m := !m lor bit_selection_item;
  (* Invoke presses what the other patterns don't claim. A checkable
     menu item still invokes, like a checkable WPF item; tree and
     list items invoke their click action too. *)
  (match n.role with
   | Button | Link | Menu_item | List_item | Outline_item ->
     m := !m lor bit_invoke
   | _ -> ());
  if selection_role n.role then m := !m lor bit_selection;
  if range_role n.role then m := !m lor bit_range_value;
  if textual_role n.role then m := !m lor bit_value;
  (match n.state.expanded with
   | Some _ -> m := !m lor bit_expand_collapse
   | None ->
     (match n.role with
      | Combo_box | Outline_item ->
        m := !m lor bit_expand_collapse
      | _ -> ()));
  !m

(* ---------- state helpers ---------- *)

(* ToggleState: -1 n/a, 0 off, 1 on, 2 indeterminate. *)
let toggle_state_of (n : Lui_a11y.node_a11y) =
  let checkable =
    toggle_role n.Lui_a11y.role
    || (n.Lui_a11y.role = Lui_a11y.Menu_item
        && n.Lui_a11y.state.checked <> None)
  in
  if not checkable then -1
  else
    match n.Lui_a11y.state.checked with
    | Some Lui_a11y.Checked -> 1
    | Some Lui_a11y.Mixed -> 2
    | _ -> 0

(* ExpandCollapseState: -1 n/a, 0 collapsed, 1 expanded, 3 leaf. *)
let expand_state_of (n : Lui_a11y.node_a11y) =
  if patterns_of n land bit_expand_collapse = 0 then -1
  else
    match n.Lui_a11y.state.expanded with
    | Some true -> 1
    | Some false -> 0
    (* a tree item without an expanded flag is a leaf *)
    | None -> if n.Lui_a11y.role = Lui_a11y.Outline_item then 3 else 0

(* ---------- action mask ---------- *)

(* Bit values shared with lui_ax_windows_stubs.c — same codes as the
   macOS bridge's action queue. *)
let bit_press = 1
let bit_increment = 2
let bit_decrement = 4
let bit_focus = 8
let bit_set_value = 16
let bit_scroll = 32
let bit_disclose = 64

let actions_of (n : Lui_a11y.node_a11y) =
  let open Lui_a11y in
  (* every element may sit inside a scroll container *)
  let m = ref bit_scroll in
  if n.state.focusable then m := !m lor bit_focus;
  (match n.role with
   | Button | Toggle_button | Check_box | Radio_button | Switch
   | Menu_item | Link | Tab | Combo_box | List_item | Outline_item ->
     m := !m lor bit_press
   | _ -> ());
  (match n.role with
   | Slider | Spin_button ->
     m := !m lor bit_increment lor bit_decrement
   | _ -> ());
  (match n.role with
   | Text_field | Text_area | Search_field | Combo_box ->
     if (not n.state.read_only) && not n.state.disabled then
       m := !m lor bit_set_value
   | _ -> ());
  (* expandable nodes of any role offer expand/collapse *)
  (match n.state.expanded with
   | Some _ -> m := !m lor bit_disclose
   | None -> ());
  !m

(* ---------- event selection ---------- *)

type variant =
  | V_empty
  | V_int of int
  | V_num of float
  | V_bool of bool
  | V_str of string

let enc = function
  | V_empty -> (0, 0., "")
  | V_int i -> (1, Float.of_int i, "")
  | V_num f -> (2, f, "")
  | V_bool b -> (3, (if b then 1. else 0.), "")
  | V_str s -> (4, 0., s)

type notify =
  | Prop of int * variant * variant
  | Event of int

type notify_target = On_element | On_parent | On_root

let sopt = function Some s -> V_str s | None -> V_str ""

(* The selection event a container item raising; multi-select
   containers are not distinguished in Lui_a11y, so selected->true
   reports a single-element selection and true->false a removal. *)
let selection_events ~before ~after =
  match before, after with
  | false, true -> [ event_element_selected ]
  | true, false -> [ event_removed_from_selection ]
  | _ -> []

let notifications_of ~old ~cur =
  match old, cur with
  | Some _, None -> []
  | None, _ -> []
  | Some o, Some n ->
    let l = ref [] in
    let add x = l := x :: !l in
    let open Lui_a11y in
    if o.name <> n.name then
      add (Prop (prop_name, sopt o.name, sopt n.name), On_element);
    if o.description <> n.description then
      add
        (Prop (prop_help_text, sopt o.description, sopt n.description),
         On_element);
    if o.state.disabled <> n.state.disabled then
      add
        (Prop
           ( prop_is_enabled,
             V_bool (not o.state.disabled),
             V_bool (not n.state.disabled) ),
         On_element);
    (match o.value, n.value with
     | Some ov, Some nv when ov.numeric <> nv.numeric ->
       (match range_role n.role with
        | true ->
          let num = function
            | Some { numeric = Some f; _ } -> V_num f
            | _ -> V_empty
          in
          add (Prop (prop_range_value, num o.value, num n.value),
               On_element)
        | false -> ())
     | _ -> ());
    (match o.value, n.value with
     | Some ov, Some nv when ov.text <> nv.text && textual_role n.role ->
       let txt = function
         | Some { text = Some s; _ } -> V_str s
         | _ -> V_empty
       in
       add (Prop (prop_value, txt o.value, txt n.value), On_element)
     | _ -> ());
    (* toggle state is a checkable's value *)
    if toggle_state_of o <> toggle_state_of n
       && toggle_state_of n >= 0
    then
      add
        (Prop
           ( prop_toggle_state,
             V_int (max 0 (toggle_state_of o)),
             V_int (toggle_state_of n) ),
         On_element);
    (* selection: IsSelected on selectable nodes, plus the event *)
    let sel_of (x : Lui_a11y.node_a11y) =
      x.state.selected || x.state.checked = Some Checked
    in
    if selectable_role n && sel_of o <> sel_of n then begin
      add
        (Prop (prop_is_selected, V_bool (sel_of o), V_bool (sel_of n)),
         On_element);
      List.iter
        (fun e -> add (Event e, On_element))
        (selection_events ~before:(sel_of o) ~after:(sel_of n))
    end;
    if o.state.focused <> n.state.focused && n.state.focused then
      add (Event event_focus_changed, On_element);
    if o.state.expanded <> n.state.expanded
       && expand_state_of n >= 0
    then
      add
        (Prop
           ( prop_expand_state,
             V_int (max 0 (expand_state_of o)),
             V_int (expand_state_of n) ),
         On_element);
    List.rev !l

(* Whether the change alters the tree — feeds StructureChanged. *)
let structure_changed ~old ~cur =
  match old, cur with
  | Some _, None | None, Some _ -> true
  | Some o, Some n ->
    o.Lui_a11y.parent <> n.Lui_a11y.parent
    || o.children <> n.children || o.role <> n.role
  | None, None -> false

(* The providers whose children a change invalidated; -1 = root. *)
let struct_invalidations ~old ~cur =
  let pid = function Some p -> p | None -> -1 in
  match old, cur with
  | Some o, None -> [ pid o.Lui_a11y.parent ]
  | None, Some n -> [ pid n.Lui_a11y.parent ]
  | Some o, Some n ->
    let l = ref [] in
    let add id = if not (List.mem id !l) then l := id :: !l in
    if o.Lui_a11y.children <> n.Lui_a11y.children then add n.id;
    if o.Lui_a11y.parent <> n.Lui_a11y.parent then begin
      add (pid o.Lui_a11y.parent);
      add (pid n.Lui_a11y.parent)
    end;
    if o.Lui_a11y.role <> n.Lui_a11y.role then
      add (pid n.Lui_a11y.parent);
    !l
  | None, None -> []

(* ---------- pure helpers ---------- *)

(* UTF-16 code units of a UTF-8 string: astral code points become
   surrogate pairs, invalid bytes decode as U+FFFD. *)
let utf16_encode s =
  let n = String.length s in
  let buf = Buffer.create n in
  let emit u =
    Buffer.add_char buf (Char.unsafe_chr (u land 0xFF));
    Buffer.add_char buf (Char.unsafe_chr ((u lsr 8) land 0xFF))
  in
  let i = ref 0 in
  while !i < n do
    let c = Char.code (String.unsafe_get s !i) in
    let cp, w =
      if c < 0x80 then (c, 1)
      else if c < 0xC2 then (0xFFFD, 1)
      (* lone continuation byte or overlong lead — invalid *)
      else if c < 0xE0 then
        if !i + 1 < n
           && Char.code (String.unsafe_get s (!i + 1)) land 0xC0 = 0x80
        then
          ( ((c land 0x1F) lsl 6)
            lor (Char.code (String.unsafe_get s (!i + 1)) land 0x3F),
            2 )
        else (0xFFFD, 1)
      else if c < 0xF0 then
        if
          !i + 2 < n
          && Char.code (String.unsafe_get s (!i + 1)) land 0xC0 = 0x80
          && Char.code (String.unsafe_get s (!i + 2)) land 0xC0 = 0x80
        then
          let u =
            ((c land 0x0F) lsl 12)
            lor ((Char.code (String.unsafe_get s (!i + 1)) land 0x3F)
                 lsl 6)
            lor (Char.code (String.unsafe_get s (!i + 2)) land 0x3F)
          in
          (if u < 0x800 || (u >= 0xD800 && u <= 0xDFFF) then (0xFFFD, 3)
           else (u, 3))
        else (0xFFFD, 1)
      else if
        !i + 3 < n
        && Char.code (String.unsafe_get s (!i + 1)) land 0xC0 = 0x80
        && Char.code (String.unsafe_get s (!i + 2)) land 0xC0 = 0x80
        && Char.code (String.unsafe_get s (!i + 3)) land 0xC0 = 0x80
      then
        let u =
          ((c land 0x07) lsl 18)
          lor ((Char.code (String.unsafe_get s (!i + 1)) land 0x3F)
               lsl 12)
          lor ((Char.code (String.unsafe_get s (!i + 2)) land 0x3F)
               lsl 6)
          lor (Char.code (String.unsafe_get s (!i + 3)) land 0x3F)
        in
        (if u < 0x10000 || u > 0x10FFFF then (0xFFFD, 4) else (u, 4))
      else (0xFFFD, 1)
    in
    if cp < 0x10000 then emit cp
    else begin
      let u = cp - 0x10000 in
      emit (0xD800 lor (u lsr 10));
      emit (0xDC00 lor (u land 0x3FF))
    end;
    i := !i + w
  done;
  let b = Buffer.to_bytes buf in
  Array.init (Bytes.length b / 2)
    (fun i ->
      Char.code (Bytes.unsafe_get b (2 * i))
      lor (Char.code (Bytes.unsafe_get b ((2 * i) + 1)) lsl 8))

(* Length of a UTF-8 string in UTF-16 code units — what UIA text
   properties count. Astral code points take 2 units; invalid bytes
   decode as one U+FFFD unit each. Sharing the encoder keeps the two
   consistent. *)
let utf16_length s = Array.length (utf16_encode s)

(* ---------- node -> descriptor ---------- *)

let opt = function Some s -> s | None -> ""

(* Position of a row node among the row-role children of its parent —
   UIA's 1-based PositionInSet, with the row count as SizeOfSet. *)
let row_index t (n : Lui_a11y.node_a11y) =
  if not (row_role n.Lui_a11y.role) then (-1, -1)
  else
    match n.Lui_a11y.parent with
    | None -> (-1, -1)
    | Some p ->
      (match Lui_a11y.find t.a11y p with
       | None -> (-1, -1)
       | Some pn ->
         let total =
           List.fold_left
             (fun acc c ->
               match Lui_a11y.find t.a11y c with
               | Some cn when row_role cn.Lui_a11y.role -> acc + 1
               | _ -> acc)
             0 pn.Lui_a11y.children
         in
         let rec go i = function
           | [] -> (-1, total)
           | c :: rest ->
             if c = n.Lui_a11y.id then (i + 1, total)
             else
               (match Lui_a11y.find t.a11y c with
                | Some cn when row_role cn.Lui_a11y.role ->
                  go (i + 1) rest
                | _ -> go i rest)
         in
         go 0 pn.Lui_a11y.children)

(* Nesting level of an outline row — 1-based for UIA_LevelPropertyId. *)
let level_of t (n : Lui_a11y.node_a11y) =
  if n.Lui_a11y.role <> Lui_a11y.Outline_item then -1
  else
    let rec up acc id =
      match Lui_a11y.find t.a11y id with
      | Some { Lui_a11y.role = Lui_a11y.Outline_item;
               Lui_a11y.parent = Some p; _ } -> up (acc + 1) p
      | _ -> acc
    in
    (match n.Lui_a11y.parent with Some p -> up 1 p | None -> 1)

let desc_of t (n : Lui_a11y.node_a11y) : uia_desc =
  let open Lui_a11y in
  let vtag, vnum, vstr =
    match n.role with
    | Slider | Spin_button | Progress_indicator ->
      (match n.value with
       | Some { numeric = Some f; _ } -> (1, f, "")
       | _ -> (1, 0., ""))
    | Text_field | Text_area | Search_field | Combo_box ->
      (2, 0., (match n.value with
               | Some { text = Some s; _ } -> s
               | Some { numeric = Some f; _ } -> string_of_float f
               | _ -> ""))
    | _ ->
      (match n.value with
       | Some { text = Some s; _ } -> (2, 0., s)
       | Some { numeric = Some f; _ } -> (1, f, "")
       | _ -> (0, 0., ""))
  in
  let has_min, min_, has_max, max_ =
    match n.value with
    | Some v ->
      (v.minimum <> None, Option.value v.minimum ~default:0.,
       v.maximum <> None, Option.value v.maximum ~default:0.)
    | None -> (false, 0., false, 0.)
  in
  let expanded =
    match n.state.expanded with Some b -> if b then 1 else 0 | None -> -1
  in
  let pos, size = row_index t n in
  ( control_type_of n,
    patterns_of n,
    opt n.name,
    localized_type_of n,
    opt n.description,
    vtag,
    vnum,
    vstr,
    has_min,
    min_,
    has_max,
    max_,
    not n.state.disabled,
    expanded,
    n.state.focusable,
    n.state.focused,
    (if selectable_role n then
       (if n.state.selected || n.state.checked = Some Checked then 1
        else 0)
     else -1),
    toggle_state_of n,
    n.state.password,
    pos,
    size,
    level_of t n,
    n.state.required,
    (if n.role = Status_bar then 1 else 0),
    actions_of n,
    n.role = Dialog,
    n.state.read_only )

(* ---------- bridge ---------- *)

let raise_one t id (ntf, tgt) =
  let target =
    match tgt with
    | On_element -> id
    | On_root -> -1
    | On_parent ->
      (match Lui_a11y.find t.a11y id with
       | Some { Lui_a11y.parent = Some p; _ } -> p
       | _ -> -1)
  in
  match ntf with
  | Prop (prop, ov, nv) -> c_raise_prop t.id target prop (enc ov) (enc nv)
  | Event ev -> c_raise_event t.id target ev

let push_changed t changed =
  let snapshot =
    List.map
      (fun id ->
        (id, Hashtbl.find_opt t.pushed id, Lui_a11y.find t.a11y id))
      changed
  in
  (* removals first: the disconnect happens while the element still
     resolves *)
  List.iter
    (fun (id, old, cur) ->
      match old, cur with
      | Some _, None ->
        c_remove t.id id;
        Hashtbl.remove t.pushed id
      | _ -> ())
    snapshot;
  (* attribute sets + frames for present nodes *)
  List.iter
    (fun (id, _, cur) ->
      match cur with
      | Some n ->
        c_apply t.id id (desc_of t n);
        (match t.frame_of id with
         | Some r -> c_set_frame t.id id r
         | None -> ());
        Hashtbl.replace t.pushed id n
      | None -> ())
    snapshot;
  (* links once every element exists *)
  List.iter
    (fun (_, _, cur) ->
      match cur with
      | Some n ->
        c_link t.id n.Lui_a11y.id
          (Option.value n.Lui_a11y.parent ~default:(-1))
          (Array.of_list n.Lui_a11y.children)
      | None -> ())
    snapshot;
  (* structure invalidations on the providers whose children list the
     change touched; -1 targets the fragment root *)
  List.iter
    (fun (_, old, cur) ->
      List.iter
        (fun pid -> c_raise_struct t.id pid)
        (struct_invalidations ~old ~cur))
    snapshot;
  (* per-element notifications *)
  List.iter
    (fun (id, old, cur) ->
      List.iter (raise_one t id)
        (notifications_of ~old ~cur))
    snapshot;
  c_set_focus t.id
    (Option.value (Lui_a11y.focused t.a11y) ~default:(-1));
  c_finish t.id (Array.of_list (Lui_a11y.root_ids t.a11y))

let attach ~frame_of a11y win =
  let id = c_attach win in
  let t = { id; a11y; win; frame_of; pushed = Hashtbl.create 64 } in
  let ids =
    List.map (fun (n : Lui_a11y.node_a11y) -> n.Lui_a11y.id)
      (Lui_a11y.flatten a11y)
  in
  push_changed t ids;
  t

let detach t =
  c_detach t.id;
  Hashtbl.reset t.pushed

let a11y t = t.a11y
let window t = t.win
let bridge_id t = t.id

let sync t =
  let changed = Lui_a11y.sync t.a11y in
  push_changed t changed;
  changed

let refresh_frames t =
  List.iter
    (fun (n : Lui_a11y.node_a11y) ->
      match t.frame_of n.Lui_a11y.id with
      | Some r -> c_set_frame t.id n.Lui_a11y.id r
      | None -> ())
    (Lui_a11y.flatten t.a11y)

let set_focused t id = push_changed t (Lui_a11y.set_focused t.a11y id)
let clear_focused t = push_changed t (Lui_a11y.clear_focused t.a11y)

let wm_getobject win wp lp = c_get_object win wp lp

(* ---------- actions ---------- *)

type action =
  | Press
  | Increment
  | Decrement
  | Focus
  | Set_value of string
  | Scroll_to_visible
  | Expand
  | Collapse

let action_of_code = function
  | 0 -> Press
  | 1 -> Increment
  | 2 -> Decrement
  | 3 -> Focus
  | 5 -> Scroll_to_visible
  | 6 -> Expand
  | 7 -> Collapse
  | _ -> Set_value ""

let drain_actions t =
  List.map
    (fun (id, code, text) ->
      (id, (match code with
           | 4 -> Set_value text
           | c -> action_of_code c)))
    (Array.to_list (c_drain t.id))

(* ---------- probes ---------- *)

let probe_has_provider t = c_probe_has_provider t.id
let probe_node_of_root t = c_probe_root t.id
let probe_find t id = c_probe_find t.id id
let probe_free h = c_probe_free h
let probe_children h = c_probe_children h
let probe_runtime_id h = c_probe_runtime_id h
let probe_prop_int h p = c_probe_prop_int h p
let probe_prop_bool h p = c_probe_prop_bool h p
let probe_prop_str h p = c_probe_prop_str h p
let probe_prop_num h p = c_probe_prop_num h p
let probe_pattern t id pat = c_probe_pattern t.id id pat
let probe_invoke t id = c_probe_invoke t.id id
let probe_toggle t id = c_probe_toggle t.id id
let probe_select t id = c_probe_select t.id id
let probe_set_range t id v = c_probe_set_range t.id id v
let probe_set_value t id s = c_probe_set_value t.id id s
let probe_expand t id = c_probe_expand t.id id
let probe_collapse t id = c_probe_collapse t.id id
let probe_scroll_into_view t id = c_probe_scroll t.id id
let probe_hit_test t x y = c_probe_hit t.id x y
let probe_focused t = c_probe_focused t.id
