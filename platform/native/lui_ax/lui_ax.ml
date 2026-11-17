(* macOS accessibility bridge: mirrors a [Lui_a11y] semantic tree as
   NSAccessibilityElement objects so assistive technology sees a
   self-drawn app.

   The ObjC side keeps a flat node-id -> element table; [sync] pushes an
   attribute set for every node Lui_a11y reports changed and posts the
   matching AX notifications. VoiceOver actions are enqueued on the ObjC
   side and polled here via [drain_actions] — no ObjC code ever calls
   back into the runtime.

   Call everything on the host's UI thread, the same discipline AppKit
   expects. *)

type rect = { x : float; y : float; w : float; h : float }
(** A rect in the host view's coordinate space (points). *)

type native_view = nativeint
(** A raw NSView pointer. *)

(* Descriptor pushed to the ObjC side per changed node, as a tuple: the
   C stub reads fields positionally, so the order is fixed with
   lui_ax_objc.m —
   0 role, 1 subrole, 2 title, 3 label, 4 value tag (0 none/1 num/2 str),
   5 value num, 6 value str, 7 has min, 8 min, 9 has max, 10 max,
   11 enabled, 12 expanded (-1/0/1), 13 orientation (0/1 vert/2 horiz),
   14 index (-1 none), 15 selected (-1/0/1), 16 placeholder, 17 help,
   18 num chars (-1 none), 19 sel loc, 20 sel len, 21 disclosed (-1/0/1),
   22 disclosure level (-1), 23 mark char, 24 invalid,
   25 action mask, 26 textual, 27 value settable, 28 outline item. *)
type ax_desc =
  string * string * string * string * int * float * string * bool *
  float * bool * float * bool * int * int * int * int * string *
  string * int * int * int * int * int * string * bool * int * bool *
  bool * bool

(* Row sets pushed for list/table/outline containers; fields read
   positionally by the C stub: 0 row ids, 1 visible row ids,
   2 selected row ids, 3 total row count. *)
type rows_desc = int array * int array * int array * int

type t = {
  id : int;
  a11y : Lui_a11y.t;
  view : native_view;
  frame_of : int -> rect option;
  pushed : (int, Lui_a11y.node_a11y) Hashtbl.t;
}

external c_attach : native_view -> int = "lui_ax_attach"
external c_detach : int -> unit = "lui_ax_detach"
external c_apply : int -> int -> ax_desc -> unit = "lui_ax_apply"
external c_link : int -> int -> int -> int array -> unit = "lui_ax_link"
external c_set_rows : int -> int -> rows_desc -> unit = "lui_ax_set_rows"
external c_set_frame : int -> int -> rect -> unit = "lui_ax_set_frame"
external c_remove : int -> int -> unit = "lui_ax_remove"
external c_finish : int -> int array -> bool -> unit = "lui_ax_finish"
external c_post : int -> int -> string -> unit = "lui_ax_post"
external c_set_focus : int -> int -> unit = "lui_ax_set_focus"
external c_drain : int -> (int * int * string) array = "lui_ax_drain"

(* ---------- notification names ---------- *)

let notif_destroyed = "AXUIElementDestroyed"
let notif_value = "AXValueChanged"
let notif_title = "AXTitleChanged"
let notif_focused = "AXFocusedUIElementChanged"
let notif_selected_rows = "AXSelectedRowsChanged"
let notif_expanded = "AXExpandedChanged"
(* AXLayoutChanged is posted by the C side from [finish], not per node. *)

(* ---------- role mapping ---------- *)

(* Lui_a11y role -> (AX role, AX subrole); "" = no subrole. *)
let ax_role_table =
  Lui_a11y.
    [ (Window, ("AXWindow", ""));
      (Group, ("AXGroup", ""));
      (Static_text, ("AXStaticText", ""));
      (Heading, ("AXHeading", ""));
      (Text_field, ("AXTextField", ""));
      (Text_area, ("AXTextArea", ""));
      (Search_field, ("AXTextField", "AXSearchField"));
      (Button, ("AXButton", ""));
      (Toggle_button, ("AXCheckBox", "AXToggle"));
      (Check_box, ("AXCheckBox", ""));
      (Radio_button, ("AXRadioButton", ""));
      (Radio_group, ("AXRadioGroup", ""));
      (Switch, ("AXCheckBox", "AXSwitch"));
      (Slider, ("AXSlider", ""));
      (Spin_button, ("AXIncrementor", ""));
      (Progress_indicator, ("AXProgressIndicator", ""));
      (Link, ("AXLink", ""));
      (Image, ("AXImage", ""));
      (* lists expose row semantics to VoiceOver like native tables *)
      (List, ("AXTable", ""));
      (List_item, ("AXRow", "AXTableRow"));
      (Outline, ("AXOutline", ""));
      (Outline_item, ("AXRow", "AXOutlineRow"));
      (Tab_group, ("AXTabGroup", ""));
      (Tab, ("AXRadioButton", "AXTabButton"));
      (Menu, ("AXMenu", ""));
      (Menu_item, ("AXMenuItem", ""));
      (Combo_box, ("AXComboBox", ""));
      (Dialog, ("AXGroup", "AXDialog"));
      (Sheet, ("AXSheet", ""));
      (Tooltip, ("AXHelpTag", ""));
      (Table, ("AXTable", ""));
      (Table_row, ("AXRow", "AXTableRow"));
      (Table_cell, ("AXCell", ""));
      (Separator, ("AXGroup", ""));
      (Toolbar, ("AXToolbar", ""));
      (Status_bar, ("AXGroup", "AXApplicationStatus"));
      (Navigation, ("AXGroup", "AXLandmarkNavigation"));
      (Split_group, ("AXSplitGroup", ""));
      (Extension, ("AXGroup", "")) ]

let ax_role_of (n : Lui_a11y.node_a11y) =
  let role, sub = List.assoc n.Lui_a11y.role ax_role_table in
  (* a password field is a secure text field *)
  if n.Lui_a11y.state.password && n.Lui_a11y.role = Lui_a11y.Text_field
  then (role, "AXSecureTextField")
  else (role, sub)

(* ---------- role predicates ---------- *)

(* Controls show their name as the title; other elements are described
   by it (AXLabel). *)
let titled_role = function
  | Lui_a11y.Button | Lui_a11y.Toggle_button | Lui_a11y.Check_box
  | Lui_a11y.Radio_button | Lui_a11y.Switch | Lui_a11y.Tab
  | Lui_a11y.Menu_item | Lui_a11y.Link -> true
  | _ -> false

(* Roles that edit or carry a text value. *)
let textual_role = function
  | Lui_a11y.Text_field | Lui_a11y.Text_area | Lui_a11y.Search_field
  | Lui_a11y.Combo_box -> true
  | _ -> false

(* Containers whose children are rows for VoiceOver. *)
let container_role = function
  | Lui_a11y.List | Lui_a11y.Table | Lui_a11y.Outline -> true
  | _ -> false

let row_role = function
  | Lui_a11y.List_item | Lui_a11y.Table_row | Lui_a11y.Outline_item ->
    true
  | _ -> false

(* ---------- pure helpers ---------- *)

(* Flips a rect between a top-left-origin space and a bottom-left-origin
   space of the same height — what a non-flipped NSView needs from a
   y-down layout space: y' = height - y - h. *)
let y_flip ~container_height r =
  { r with y = container_height -. r.y -. r.h }

(* Length of a UTF-8 string in UTF-16 code units, which is what
   AXNumberOfCharacters counts. Astral code points take 2 units; stray
   bytes count 1 each. *)
let utf16_length s =
  let n = String.length s in
  let i = ref 0 and u = ref 0 in
  while !i < n do
    let c = Char.code (String.unsafe_get s !i) in
    let w =
      if c < 0x80 then 1
      else if c < 0xE0 then 2
      else if c < 0xF0 then 3
      else 4
    in
    u := !u + (if w = 4 then 2 else 1);
    i := !i + w
  done;
  !u

(* ---------- action mask ---------- *)

(* Bit values shared with lui_ax_objc.m. *)
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
  (match n.role with
   | Outline_item ->
     (match n.state.expanded with
      | Some _ -> m := !m lor bit_disclose
      | None -> ())
   | _ -> ());
  !m

(* ---------- notification selection ---------- *)

type notify_target = On_element | On_parent | On_view

let notifications_of ~old ~cur =
  match old, cur with
  | Some _, None -> [ (notif_destroyed, On_element) ]
  | None, _ -> []
  | Some o, Some n ->
    let l = ref [] in
    let add c = l := c :: !l in
    (* the state of a toggle is part of its AX value *)
    if o.Lui_a11y.value <> n.Lui_a11y.value
       || o.state.checked <> n.state.checked
    then add (notif_value, On_element);
    if o.name <> n.name then add (notif_title, On_element);
    if n.state.focused && not o.state.focused then
      add (notif_focused, On_element);
    if row_role n.role
       && (o.state.selected <> n.state.selected
           || o.state.checked <> n.state.checked)
    then add (notif_selected_rows, On_parent);
    if o.state.expanded <> n.state.expanded then
      add (notif_expanded, On_element);
    List.rev !l

(* Whether the change alters the tree — feeds the single
   AXLayoutChanged on the view. *)
let structure_changed ~old ~cur =
  match old, cur with
  | Some _, None | None, Some _ -> true
  | Some o, Some n ->
    o.Lui_a11y.parent <> n.Lui_a11y.parent
    || o.children <> n.children || o.role <> n.role
  | None, None -> false

(* ---------- node -> descriptor ---------- *)

let opt = function Some s -> s | None -> ""

(* Position of a row node among the row-role children of its parent —
   the "row N of M" VoiceOver reports. *)
let row_index t (n : Lui_a11y.node_a11y) =
  if not (row_role n.Lui_a11y.role) then -1
  else
    match n.Lui_a11y.parent with
    | None -> -1
    | Some p ->
      (match Lui_a11y.find t.a11y p with
       | None -> -1
       | Some pn ->
         let rec go i = function
           | [] -> -1
           | c :: rest ->
             if c = n.Lui_a11y.id then i
             else
               (match Lui_a11y.find t.a11y c with
                | Some cn when row_role cn.Lui_a11y.role ->
                  go (i + 1) rest
                | _ -> go i rest)
         in
         go 0 pn.Lui_a11y.children)

(* Nesting level of an outline row, from 0. *)
let disclosure_level t (n : Lui_a11y.node_a11y) =
  if n.Lui_a11y.role <> Lui_a11y.Outline_item then -1
  else
    let rec up acc id =
      match Lui_a11y.find t.a11y id with
      | Some { Lui_a11y.role = Lui_a11y.Outline_item;
               Lui_a11y.parent = Some p; _ } -> up (acc + 1) p
      | _ -> acc
    in
    match n.Lui_a11y.parent with Some p -> up 0 p | None -> 0

(* The check mark a menu item shows for its state. *)
let mark_of (n : Lui_a11y.node_a11y) =
  match n.Lui_a11y.state.checked with
  | Some Lui_a11y.Checked -> "\xE2\x9C\x93" (* ✓ *)
  | Some Lui_a11y.Mixed -> "-"
  | _ -> ""

let desc_of t (n : Lui_a11y.node_a11y) : ax_desc =
  let open Lui_a11y in
  let role, subrole = ax_role_of n in
  let name = opt n.name in
  let titled = titled_role n.role in
  let sel = n.state.selected || n.state.checked = Some Checked in
  let vtag, vnum, vstr =
    match n.role with
    | Check_box | Radio_button | Switch | Toggle_button ->
      let v =
        match n.state.checked with
        | Some Checked -> 1. | Some Mixed -> 2. | _ -> 0.
      in
      (1, v, "")
    | Tab -> (1, (if sel then 1. else 0.), "")
    | Slider | Spin_button | Progress_indicator ->
      (match n.value with
       | Some { numeric = Some f; _ } -> (1, f, "")
       | _ -> (0, 0., ""))
    | Text_field | Text_area | Search_field | Combo_box ->
      (2, 0., (match n.value with
               | Some { text = Some s; _ } -> s | _ -> ""))
    | Static_text -> (2, 0., name)
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
  let textual = textual_role n.role in
  let expanded =
    match n.state.expanded with Some b -> if b then 1 else 0 | None -> -1
  in
  ( role,
    subrole,
    (if titled then name else ""),
    (if titled then "" else name),
    vtag,
    vnum,
    vstr,
    has_min,
    min_,
    has_max,
    max_,
    not n.state.disabled,
    expanded,
    0,
    row_index t n,
    (if row_role n.role then (if sel then 1 else 0) else -1),
    "",
    opt n.description,
    (if textual && vtag = 2 then utf16_length vstr else -1),
    0,
    0,
    (if n.role = Outline_item then expanded else -1),
    disclosure_level t n,
    (if n.role = Menu_item then mark_of n else ""),
    false,
    actions_of n,
    textual,
    textual && (not n.state.read_only) && not n.state.disabled,
    n.role = Outline_item )

(* ---------- bridge ---------- *)

let rows_of t (n : Lui_a11y.node_a11y) : rows_desc =
  let rows =
    List.filter
      (fun c ->
        match Lui_a11y.find t.a11y c with
        | Some cn -> row_role cn.Lui_a11y.role
        | None -> false)
      n.Lui_a11y.children
  in
  let selected =
    List.filter
      (fun c ->
        match Lui_a11y.find t.a11y c with
        | Some cn ->
          cn.Lui_a11y.state.selected
          || cn.Lui_a11y.state.checked = Some Lui_a11y.Checked
        | None -> false)
      rows
  in
  ( Array.of_list rows,
    Array.of_list rows,
    Array.of_list selected,
    List.length rows )

let push_changed t changed =
  let layout = ref false in
  let snapshot =
    List.map
      (fun id ->
        (id, Hashtbl.find_opt t.pushed id, Lui_a11y.find t.a11y id))
      changed
  in
  (* removals first: the destroyed notification posts on the dying
     element while it still resolves *)
  List.iter
    (fun (id, old, cur) ->
      match old, cur with
      | Some _, None ->
        c_post t.id id notif_destroyed;
        c_remove t.id id;
        Hashtbl.remove t.pushed id;
        layout := true
      | _ -> ())
    snapshot;
  (* attribute sets + frames for present nodes *)
  List.iter
    (fun (id, old, cur) ->
      match cur with
      | Some n ->
        if structure_changed ~old ~cur:(Some n) then layout := true;
        c_apply t.id id (desc_of t n);
        (match t.frame_of id with
         | Some r -> c_set_frame t.id id r
         | None -> ());
        Hashtbl.replace t.pushed id n
      | None -> ())
    snapshot;
  (* links + container rows once every element exists *)
  List.iter
    (fun (_, _, cur) ->
      match cur with
      | Some n ->
        c_link t.id n.Lui_a11y.id
          (Option.value n.parent ~default:(-1))
          (Array.of_list n.Lui_a11y.children);
        if container_role n.Lui_a11y.role then
          c_set_rows t.id n.Lui_a11y.id (rows_of t n)
      | None -> ())
    snapshot;
  (* per-element notifications *)
  List.iter
    (fun (id, old, cur) ->
      match cur with
      | Some n ->
        List.iter
          (fun (name, tgt) ->
            let tid =
              match tgt with
              | On_element -> id
              | On_parent -> (match n.Lui_a11y.parent with
                              | Some p -> p | None -> -1)
              | On_view -> -1
            in
            c_post t.id tid name)
          (notifications_of ~old ~cur)
      | None -> ())
    snapshot;
  c_set_focus t.id
    (Option.value (Lui_a11y.focused t.a11y) ~default:(-1));
  c_finish t.id
    (Array.of_list (Lui_a11y.root_ids t.a11y))
    !layout

let attach ~frame_of a11y view =
  let id = c_attach view in
  let t = { id; a11y; view; frame_of; pushed = Hashtbl.create 64 } in
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
let view t = t.view
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
